#!/usr/bin/env python3
"""Candidate-II MRRG expansion and Modulo Mapping Graph construction.

The MMG is the finite product between one canonical array-routine DDG and the
physical resources available in a candidate modulo schedule.  It keeps
placement candidates explicit while route/resource constraints remain compact;
the emitted baseline mapping is independently revalidated before collateral is
accepted.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict
from math import ceil
import json
from pathlib import Path
from typing import Any

from compiler.v3 import architecture_configuration as architecture
from compiler.v3 import reconstruction_graphs as graphs


ROOT = Path(__file__).resolve().parents[2]
MODULO_KERNELS = (
    "correlation",
    "residual_update",
    "phi_support_forward",
    "phi_support_transpose",
)
ROUTE_DELAY = {
    "direct_plane": 1,
    "memory_row": 1,
    "phi_broadcast": 1,
    "same_tile_bundle": 0,
    "local_feedback": 0,
    "reduction_up": 1,
    "scalar_broadcast": 1,
    "resource_result": 2,
    "normalized_result": 5,
    "normalized_memory": 5,
    "registered_mesh": 1,
    "intercluster_column_connector": 1,
}


def _ceil_div(numerator: int, denominator: int) -> int:
    return (numerator + denominator - 1) // denominator


def _operation_map(ddg: graphs.ArrayRoutineDDG) -> dict[str, graphs.OperationNode]:
    return {operation.name: operation for operation in ddg.operations}


def _zero_distance_order(ddg: graphs.ArrayRoutineDDG) -> list[str]:
    names = [operation.name for operation in ddg.operations]
    indegree = {name: 0 for name in names}
    successors = {name: [] for name in names}
    for edge in ddg.dependencies:
        if edge.iteration_distance == 0:
            indegree[edge.target] += 1
            successors[edge.source].append(edge.target)
    ready = sorted(name for name, degree in indegree.items() if degree == 0)
    order: list[str] = []
    while ready:
        source = ready.pop(0)
        order.append(source)
        for target in sorted(successors[source]):
            indegree[target] -= 1
            if indegree[target] == 0:
                ready.append(target)
                ready.sort()
    if len(order) != len(names):
        raise ValueError(f"{ddg.name}: zero-distance graph is cyclic")
    return order


def asap_times(ddg: graphs.ArrayRoutineDDG) -> dict[str, int]:
    operations = _operation_map(ddg)
    result = {name: 0 for name in operations}
    incoming: dict[str, list[graphs.DependencyEdge]] = {
        name: [] for name in operations}
    for edge in ddg.dependencies:
        if edge.iteration_distance == 0:
            incoming[edge.target].append(edge)
    for name in _zero_distance_order(ddg):
        if incoming[name]:
            result[name] = max(
                result[edge.source] + operations[edge.source].latency +
                ROUTE_DELAY[edge.route]
                for edge in incoming[name]
            )
    return result


def resource_mii(ddg: graphs.ArrayRoutineDDG,
                 configuration: dict[str, Any]) -> tuple[int, dict[str, int]]:
    resources = architecture.physical_resource_map(configuration)
    demand: dict[str, int] = {}
    bounds: dict[str, int] = {}
    for operation in ddg.operations:
        demand[operation.resource_class] = (
            demand.get(operation.resource_class, 0) +
            operation.occupancy * operation.instances_required
        )
    for resource_class, total in demand.items():
        bounds[resource_class] = _ceil_div(total, resources[resource_class]["count"])
    resource_word_demand = sum(
        operation.occupancy for operation in ddg.operations
        if resources[operation.resource_class]["kind"] == "shared_resource"
    )
    if resource_word_demand:
        bounds["resource_context_issue"] = resource_word_demand
    return max(bounds.values(), default=1), bounds


def _recurrence_cycles(ddg: graphs.ArrayRoutineDDG) -> list[dict[str, Any]]:
    operations = _operation_map(ddg)
    outgoing: dict[str, list[graphs.DependencyEdge]] = {
        name: [] for name in operations}
    for edge in ddg.dependencies:
        outgoing[edge.source].append(edge)
    cycles: dict[tuple[tuple[str, str, int], ...], dict[str, Any]] = {}
    names = sorted(operations)

    def visit(start: str, current: str, path_nodes: list[str],
              path_edges: list[graphs.DependencyEdge]) -> None:
        for edge in outgoing[current]:
            if edge.target == start:
                cycle_edges = path_edges + [edge]
                distance = sum(item.iteration_distance for item in cycle_edges)
                if distance <= 0:
                    continue
                key_items = [(item.source, item.target, item.iteration_distance)
                             for item in cycle_edges]
                rotations = [tuple(key_items[index:] + key_items[:index])
                             for index in range(len(key_items))]
                key = min(rotations)
                delay = sum(operations[item.source].latency +
                            ROUTE_DELAY[item.route] for item in cycle_edges)
                cycles[key] = {
                    "nodes": path_nodes + [start],
                    "delay": delay,
                    "iteration_distance": distance,
                    "bound": ceil(delay / distance),
                }
            elif edge.target not in path_nodes and len(path_nodes) < len(names):
                visit(start, edge.target, path_nodes + [edge.target],
                      path_edges + [edge])

    for name in names:
        visit(name, name, [name], [])
    return [cycles[key] for key in sorted(cycles)]


def recurrence_mii(ddg: graphs.ArrayRoutineDDG) -> tuple[int, list[dict[str, Any]]]:
    cycles = _recurrence_cycles(ddg)
    return max((cycle["bound"] for cycle in cycles), default=1), cycles


def mii(ddg: graphs.ArrayRoutineDDG,
        configuration: dict[str, Any]) -> dict[str, Any]:
    res_mii, resource_bounds = resource_mii(ddg, configuration)
    rec_mii, recurrence_cycles = recurrence_mii(ddg)
    return {
        "res_mii": res_mii,
        "rec_mii": rec_mii,
        "minimum_ii": max(res_mii, rec_mii),
        "resource_bounds": resource_bounds,
        "recurrence_cycles": recurrence_cycles,
    }


def _base_resource_instances(configuration: dict[str, Any]) -> dict[str, list[str]]:
    topology = configuration["topology"]
    result: dict[str, list[str]] = {}
    for resource in configuration["physical_resources"]:
        if resource["id"] == "paired_context_tile":
            result[resource["id"]] = [
                f"paired_tile_r{row}_c{column}"
                for row in range(topology["rows_per_cluster"])
                for column in range(topology["columns_per_cluster"])
            ]
        else:
            result[resource["id"]] = [
                f"{resource['id']}_{index}" for index in range(resource["count"])
            ]
    return result


def time_expanded_mrrg(configuration: dict[str, Any], ii: int) -> dict[str, Any]:
    if ii < 1:
        raise ValueError("candidate II must be positive")
    base = architecture.mrrg_payload(configuration)
    nodes = []
    links = []
    for slot in range(ii):
        for node in base["nodes"]:
            expanded = dict(node)
            expanded["base_id"] = node["id"]
            expanded["id"] = f"{node['id']}@{slot}"
            expanded["modulo_slot"] = slot
            nodes.append(expanded)
        for link in base["links"]:
            sink_time = slot + link["latency"]
            expanded = dict(link)
            expanded["base_id"] = link["id"]
            expanded["id"] = f"{link['id']}@{slot}"
            expanded["source"] = f"{link['source']}@{slot}"
            expanded["sink"] = f"{link['sink']}@{sink_time % ii}"
            expanded["source_slot"] = slot
            expanded["sink_slot"] = sink_time % ii
            expanded["iteration_wrap"] = sink_time // ii
            links.append(expanded)
    return {
        "schema": "cscgra-v3-time-expanded-mrrg-v1",
        "architecture_hash": architecture.configuration_hash(configuration),
        "candidate_ii": ii,
        "nodes": nodes,
        "links": links,
    }


def _candidate_resources(operation: graphs.OperationNode,
                         instances: dict[str, list[str]]) -> list[tuple[str, ...]]:
    available = instances[operation.resource_class]
    if operation.preferred_instance is not None:
        if operation.instances_required != 1:
            raise ValueError(
                f"{operation.name}: preferred instance requires singleton placement")
        return [(available[operation.preferred_instance],)]
    if operation.instances_required == len(available):
        return [tuple(available)]
    if operation.instances_required == 1:
        return [(item,) for item in available]
    # The current machine only uses singleton resources or the full paired-tile
    # SIMD bundle.  Rejecting arbitrary combinations keeps context coupling
    # explicit instead of silently inventing independent cluster schedules.
    raise ValueError(
        f"{operation.name}: unsupported partial resource bundle "
        f"{operation.instances_required}/{len(available)}")


def build_mmg(ddg: graphs.ArrayRoutineDDG, configuration: dict[str, Any], ii: int,
              stage_budget: int = 3) -> dict[str, Any]:
    if ddg.mapping_domain != "modulo_array":
        raise ValueError(f"{ddg.name} is not a modulo-array kernel")
    lower_bound = mii(ddg, configuration)
    if ii < lower_bound["minimum_ii"]:
        raise ValueError(
            f"{ddg.name}: II {ii} is below MII {lower_bound['minimum_ii']}")
    if stage_budget < 1:
        raise ValueError("stage budget must be positive")
    instances = _base_resource_instances(configuration)
    resource_records = architecture.physical_resource_map(configuration)
    asap = asap_times(ddg)
    candidates: list[dict[str, Any]] = []
    one_of: dict[str, list[str]] = {}
    for operation in ddg.operations:
        if operation.occupancy > ii:
            raise ValueError(
                f"{ddg.name}: {operation.name} occupancy exceeds candidate II")
        one_of[operation.name] = []
        stop = asap[operation.name] + stage_budget * ii
        for resources in _candidate_resources(operation, instances):
            for schedule_time in range(asap[operation.name], stop + 1):
                candidate_id = (
                    f"{operation.name}:{'+'.join(resources)}:t{schedule_time}")
                slots = sorted({(schedule_time + offset) % ii
                                for offset in range(operation.occupancy)})
                candidate = {
                    "id": candidate_id,
                    "operation_node": operation.name,
                    "operation": operation.operation,
                    "resource_class": operation.resource_class,
                    "resources": list(resources),
                    "schedule_time": schedule_time,
                    "modulo_slot": schedule_time % ii,
                    "stage": schedule_time // ii,
                    "latency": operation.latency,
                    "occupancy_slots": slots,
                    "issue_domains": (["resource_context"]
                                      if resource_records[operation.resource_class]["kind"] ==
                                      "shared_resource" else []),
                }
                if operation.resource_class == "paired_context_tile":
                    candidate["physical_lane_replicas"] = {
                        resource: [
                            f"pe_c{cluster}_r{_tile_coordinates(resource)[0]}_c"
                            f"{_tile_coordinates(resource)[1]}"
                            for cluster in range(configuration["topology"]["cluster_count"])
                        ]
                        for resource in resources
                    }
                candidates.append(candidate)
                one_of[operation.name].append(candidate_id)
    dependencies = []
    for edge in ddg.dependencies:
        dependencies.append({
            **asdict(edge),
            "route_delay": ROUTE_DELAY[edge.route],
            "timing_constraint": (
                "T(target)+distance*II >= T(source)+latency(source)+route_delay"),
        })
    expanded = time_expanded_mrrg(configuration, ii)
    return {
        "schema": "cscgra-v3-modulo-mapping-graph-v1",
        "architecture_hash": architecture.configuration_hash(configuration),
        "kernel": ddg.name,
        "candidate_ii": ii,
        "stage_budget": stage_budget,
        "mii": lower_bound,
        "asap_times": asap,
        "time_expanded_mrrg_summary": {
            "schema": expanded["schema"],
            "node_count": len(expanded["nodes"]),
            "link_count": len(expanded["links"]),
        },
        "candidates": candidates,
        "one_of_candidate_groups": one_of,
        "constraints": {
            "resource_rule": "no overlapping occupancy on a physical resource modulo II",
            "context_rule": "all 16 paired tiles share one opcode/route schedule across clusters",
            "route_rule": "registered mesh/dedicated-plane capacity is reserved modulo II",
            "dependencies": dependencies,
        },
    }


def _slots_overlap(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return bool(set(left["occupancy_slots"]) & set(right["occupancy_slots"]))


def _resource_conflict(left: dict[str, Any], right: dict[str, Any]) -> bool:
    physical_overlap = bool(set(left["resources"]) & set(right["resources"]))
    issue_overlap = bool(set(left.get("issue_domains", ())) &
                         set(right.get("issue_domains", ())))
    return (physical_overlap or issue_overlap) and _slots_overlap(left, right)


def _dependency_legal(edge: graphs.DependencyEdge,
                      source: dict[str, Any], target: dict[str, Any], ii: int,
                      operations: dict[str, graphs.OperationNode]) -> bool:
    route_delay = ROUTE_DELAY[edge.route]
    if edge.route in {"same_tile_bundle", "local_feedback"}:
        if set(source["resources"]) != set(target["resources"]):
            return False
    if edge.route == "phi_broadcast" and (
            source["modulo_slot"] != target["modulo_slot"]):
        return False
    if edge.route == "intercluster_column_connector":
        if len(source["resources"]) != 1 or len(target["resources"]) != 1:
            return False
        if _intercluster_connector(
                source["resources"][0], target["resources"][0]) is None:
            return False
    if edge.route == "memory_row" and (
            source["resource_class"] in {"vector_read_port", "vector_write_port"} or
            target["resource_class"] in {"vector_read_port", "vector_write_port"}):
        if source["modulo_slot"] != target["modulo_slot"]:
            return False
    return (target["schedule_time"] + edge.iteration_distance * ii >=
            source["schedule_time"] + operations[edge.source].latency + route_delay)


def _tile_coordinates(resource: str) -> tuple[int, int]:
    # paired_tile_r<row>_c<column>
    parts = resource.split("_")
    return int(parts[-2][1:]), int(parts[-1][1:])


def _registered_mesh_path(source: str, target: str) -> list[str]:
    source_row, source_column = _tile_coordinates(source)
    target_row, target_column = _tile_coordinates(target)
    current = source
    result: list[str] = []
    while source_column != target_column:
        direction = "east" if target_column > source_column else "west"
        result.append(f"{current}_{direction}")
        source_column += 1 if direction == "east" else -1
        current = f"paired_tile_r{source_row}_c{source_column}"
    while source_row != target_row:
        direction = "south" if target_row > source_row else "north"
        result.append(f"{current}_{direction}")
        source_row += 1 if direction == "south" else -1
        current = f"paired_tile_r{source_row}_c{source_column}"
    return result


def _intercluster_connector(source: str, target: str) -> dict[str, str] | None:
    source_row, source_column = _tile_coordinates(source)
    target_row, target_column = _tile_coordinates(target)
    if source_column != target_column:
        return None
    if source_row == 3 and target_row == 0:
        return {
            "link": f"intercluster_c{source_column}_upper_to_lower",
            "physical_source": f"pe_c0_r3_c{source_column}",
            "physical_sink": f"pe_c1_r0_c{source_column}",
        }
    if source_row == 0 and target_row == 3:
        return {
            "link": f"intercluster_c{source_column}_lower_to_upper",
            "physical_source": f"pe_c1_r0_c{source_column}",
            "physical_sink": f"pe_c0_r3_c{source_column}",
        }
    return None


def _route_reservations(edge: graphs.DependencyEdge,
                        source: dict[str, Any], target: dict[str, Any],
                        ii: int) -> list[tuple[str, int]]:
    if edge.route in {"same_tile_bundle", "local_feedback"}:
        return []
    start = source["schedule_time"] + source["latency"]
    source_resources = source["resources"]
    target_resources = target["resources"]
    if edge.route == "memory_row":
        if source["resource_class"] == "vector_read_port":
            return [(f"{source_resources[0]}_to_{tile}", start % ii)
                    for tile in target_resources]
        if target["resource_class"] == "vector_write_port":
            return [(f"{tile}_to_{target_resources[0]}", start % ii)
                    for tile in source_resources]
    if edge.route == "phi_broadcast":
        return [(f"{source_resources[0]}_to_{tile}", start % ii)
                for tile in target_resources]
    if edge.route == "reduction_up":
        return [(f"{tile}_to_{target_resources[0]}", start % ii)
                for tile in source_resources]
    if edge.route == "scalar_broadcast":
        return [(f"{source_resources[0]}_to_{tile}", start % ii)
                for tile in target_resources]
    if edge.route == "resource_result":
        # The reduction result descends on scalar_broadcast and is then captured
        # by the memory-row write gateway one registered cycle later.
        first = [(f"{source_resources[0]}_to_{tile}", start % ii)
                 for tile in _base_paired_tile_names()]
        second = [(f"{tile}_to_{target_resources[0]}", (start + 1) % ii)
                  for tile in _base_paired_tile_names()]
        return first + second
    if edge.route == "normalized_result":
        return [
            ("reduction_pipeline_0_to_phi_operator_normalizer_0", start % ii),
            ("phi_operator_normalizer_0_to_selection_unit_0", (start + 1) % ii),
        ]
    if edge.route == "normalized_memory":
        return [
            ("reduction_pipeline_0_to_phi_operator_normalizer_0", start % ii),
            ("phi_operator_normalizer_0_to_vector_write_port_0", (start + 1) % ii),
        ]
    if edge.route == "registered_mesh":
        if len(source_resources) != 1 or len(target_resources) != 1:
            raise ValueError("registered mesh route requires singleton tile placements")
        path = _registered_mesh_path(source_resources[0], target_resources[0])
        return [(link, (start + index) % ii) for index, link in enumerate(path)]
    if edge.route == "intercluster_column_connector":
        if len(source_resources) != 1 or len(target_resources) != 1:
            raise ValueError("intercluster connector requires singleton tile placements")
        connector = _intercluster_connector(source_resources[0], target_resources[0])
        if connector is None:
            raise ValueError("illegal intercluster connector endpoints")
        return [(connector["link"], start % ii)]
    return [(f"{edge.route}:{source_resources[0]}->{target_resources[0]}",
             start % ii)]


def _base_paired_tile_names() -> tuple[str, ...]:
    return tuple(f"paired_tile_r{row}_c{column}"
                 for row in range(4) for column in range(4))


def _route_capacity_legal(ddg: graphs.ArrayRoutineDDG,
                          placements: dict[str, dict[str, Any]], ii: int) -> bool:
    reservations: set[tuple[str, int]] = set()
    for edge in ddg.dependencies:
        if edge.source not in placements or edge.target not in placements:
            continue
        for reservation in _route_reservations(
                edge, placements[edge.source], placements[edge.target], ii):
            if reservation in reservations:
                return False
            reservations.add(reservation)
    return True


def _mapping_route_payload(ddg: graphs.ArrayRoutineDDG,
                           placements: dict[str, dict[str, Any]],
                           ii: int) -> list[dict[str, Any]]:
    result = []
    for edge in ddg.dependencies:
        reservations = _route_reservations(
            edge, placements[edge.source], placements[edge.target], ii)
        route_payload = {
            "source": edge.source,
            "target": edge.target,
            "route": edge.route,
            "reservations": [
                {"link": link, "modulo_slot": slot}
                for link, slot in reservations
            ],
        }
        if edge.route == "intercluster_column_connector":
            connector = _intercluster_connector(
                placements[edge.source]["resources"][0],
                placements[edge.target]["resources"][0])
            if connector is None:
                raise ValueError("illegal intercluster connector endpoints")
            route_payload["physical_source"] = connector["physical_source"]
            route_payload["physical_sink"] = connector["physical_sink"]
        result.append(route_payload)
    return result


def solve_mmg(ddg: graphs.ArrayRoutineDDG, mmg: dict[str, Any]) -> dict[str, Any] | None:
    ii = mmg["candidate_ii"]
    operations = _operation_map(ddg)
    by_id = {candidate["id"]: candidate for candidate in mmg["candidates"]}
    groups = {
        name: [by_id[candidate_id] for candidate_id in ids]
        for name, ids in mmg["one_of_candidate_groups"].items()
    }
    incident: dict[str, list[graphs.DependencyEdge]] = {
        name: [] for name in operations}
    for edge in ddg.dependencies:
        incident[edge.source].append(edge)
        if edge.target != edge.source:
            incident[edge.target].append(edge)
    order = sorted(operations, key=lambda name: (len(groups[name]), -len(incident[name]), name))
    selected: dict[str, dict[str, Any]] = {}

    def legal(name: str, candidate: dict[str, Any]) -> bool:
        if any(_resource_conflict(candidate, other) for other in selected.values()):
            return False
        for edge in incident[name]:
            if edge.source == edge.target == name:
                if not _dependency_legal(edge, candidate, candidate, ii, operations):
                    return False
            elif edge.source == name and edge.target in selected:
                if not _dependency_legal(edge, candidate, selected[edge.target], ii,
                                         operations):
                    return False
            elif edge.target == name and edge.source in selected:
                if not _dependency_legal(edge, selected[edge.source], candidate, ii,
                                         operations):
                    return False
        tentative = dict(selected)
        tentative[name] = candidate
        return _route_capacity_legal(ddg, tentative, ii)

    def search(index: int) -> bool:
        if index == len(order):
            return True
        name = order[index]
        for candidate in groups[name]:
            if legal(name, candidate):
                selected[name] = candidate
                if search(index + 1):
                    return True
                selected.pop(name)
        return False

    if not search(0):
        return None
    placement_payload = {
        name: {
            key: value for key, value in candidate.items()
            if key != "id"
        }
        for name, candidate in sorted(selected.items())
    }
    routes = _mapping_route_payload(ddg, selected, ii)
    for route in routes:
        if route["route"] == "intercluster_column_connector":
            placement_payload[route["source"]]["physical_replica"] = (
                route["physical_source"])
            placement_payload[route["target"]]["physical_replica"] = (
                route["physical_sink"])
    mapping = {
        "schema": "cscgra-v3-modulo-mapping-v1",
        "architecture_hash": mmg["architecture_hash"],
        "kernel": ddg.name,
        "candidate_ii": ii,
        "placements": placement_payload,
        "routes": routes,
    }
    validate_mapping(ddg, mmg, mapping)
    return mapping


def validate_mapping(ddg: graphs.ArrayRoutineDDG, mmg: dict[str, Any],
                     mapping: dict[str, Any]) -> None:
    configuration = architecture.load()
    expected_hash = architecture.configuration_hash(configuration)
    if mmg["architecture_hash"] != expected_hash or mapping["architecture_hash"] != expected_hash:
        raise ValueError(f"{ddg.name}: stale architecture hash in MMG/mapping")
    placements = mapping["placements"]
    operations = _operation_map(ddg)
    if set(placements) != set(operations):
        raise ValueError(f"{ddg.name}: mapping does not place every operation exactly once")
    values = list(placements.values())
    for index, left in enumerate(values):
        for right in values[index + 1:]:
            if _resource_conflict(left, right):
                raise ValueError(f"{ddg.name}: physical resource collision")
    for edge in ddg.dependencies:
        if not _dependency_legal(edge, placements[edge.source], placements[edge.target],
                                 mmg["candidate_ii"], operations):
            raise ValueError(f"{ddg.name}: dependency timing/route violation {edge}")
        if edge.route == "intercluster_column_connector":
            connector = _intercluster_connector(
                placements[edge.source]["resources"][0],
                placements[edge.target]["resources"][0])
            if connector is None or (
                    placements[edge.source].get("physical_replica") !=
                    connector["physical_source"]) or (
                    placements[edge.target].get("physical_replica") !=
                    connector["physical_sink"]):
                raise ValueError(
                    f"{ddg.name}: connector physical-replica binding violation {edge}")
    if not _route_capacity_legal(ddg, placements, mmg["candidate_ii"]):
        raise ValueError(f"{ddg.name}: modulo route-capacity collision")
    base_links = {link["id"] for link in architecture.mrrg_payload(configuration)["links"]}
    for route in _mapping_route_payload(ddg, placements, mmg["candidate_ii"]):
        for reservation in route["reservations"]:
            if reservation["link"] not in base_links:
                raise ValueError(
                    f"{ddg.name}: route uses absent MRRG link {reservation['link']}")


def map_kernel(ddg: graphs.ArrayRoutineDDG, configuration: dict[str, Any],
               maximum_extra_ii: int = 8) -> dict[str, Any]:
    lower_bound = mii(ddg, configuration)
    for ii in range(lower_bound["minimum_ii"],
                    lower_bound["minimum_ii"] + maximum_extra_ii + 1):
        mmg = build_mmg(ddg, configuration, ii)
        mapping = solve_mmg(ddg, mmg)
        if mapping is not None:
            return {"mmg": mmg, "mapping": mapping}
    raise ValueError(f"{ddg.name}: no mapping found in bounded II search")


def payload() -> dict[str, Any]:
    configuration = architecture.load()
    _, ddgs = graphs.validate_all()
    kernels = {
        name: map_kernel(ddgs[name], configuration)
        for name in MODULO_KERNELS
    }
    return {
        "schema": "cscgra-v3-modulo-mapping-library-v1",
        "architecture_hash": architecture.configuration_hash(configuration),
        "context_revision": configuration["context_format_revision"],
        "kernel_order": list(MODULO_KERNELS),
        "kernels": kernels,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = payload()
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out:
        path = args.out if args.out.is_absolute() else ROOT / args.out
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
