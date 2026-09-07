#!/usr/bin/env python3
"""Strict loader and collateral builder for the v3 architecture configuration."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from compiler.v3 import architecture_scaling as scaling
from compiler.v3 import context_isa as isa

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PATH = ROOT / "compiler" / "v3" / "architecture_configuration.json"

TOP_LEVEL_KEYS = {
    "schema", "architecture_revision", "rtl_minor_revision",
    "context_format_revision", "numeric_profiles", "topology", "context_storage", "memory",
    "execution_context", "matrix_modes", "tile_operations", "resource_operations",
    "compiler_operations", "physical_resources", "reservation_guard",
}
NUMERIC_PROFILES_KEYS = {"active", "closure_candidate", "profiles"}
NUMERIC_PROFILE_KEYS = {
    "id", "name", "data_width", "data_fraction_bits", "solver_width",
    "solver_fraction_bits", "accumulator_width",
    "scalar_divide_latency", "strict_normal_residual_shift", "status",
}
TOPOLOGY_KEYS = {
    "cluster_count", "rows_per_cluster", "columns_per_cluster",
    "shared_array_context_pc", "interconnect", "wraparound",
    "express_links_enabled", "route_capacity_per_direction",
    "intercluster_column_connectors", "intercluster_connector_lanes",
    "intercluster_connector_latency",
}
CONTEXT_STORAGE_KEYS = {
    "context_depth", "image_banks", "tile_context_width",
    "array_control_context_width", "stream_context_width",
    "resource_context_width", "phase_instruction_width",
    "tile_pair_plane_count", "array_stream_plane_count",
    "resource_phase_plane_count", "array_context_commit_plane",
    "phase_instruction_commit_plane", "require_contiguous_plane_programming",
    "array_context_programming_order",
}
MEMORY_KEYS = {
    "vector_bank_count", "vector_bank_depth", "vector_bank_word_width",
    "memory_configuration_count", "memory_configuration_width",
    "memory_configuration_read_ports", "memory_configuration_read_latency",
    "memory_configuration_ram_copies", "memory_configuration_bram36_count",
    "axi_data_width",
}
EXECUTION_CONTEXT_KEYS = {
    "selection", "phase_entry_pc", "hardware_algorithm_decode",
    "software_defines_context", "status", "rtl_owner", "evidence",
}
MATRIX_MODE_KEYS = {"code", "name", "status", "rtl_owner", "evidence"}
TIMING_KEYS = {"timing_status", "timing_evidence"}
TILE_OPERATION_KEYS = {
    "code", "name", "latency", "initiation_interval", "status",
    "rtl_owner", "evidence", *TIMING_KEYS,
}
RESOURCE_OPERATION_KEYS = {
    "code", "name", "latency", "initiation_interval", "variable_latency",
    "status", "rtl_owner", "evidence", *TIMING_KEYS,
}
COMPILER_OPERATION_KEYS = {
    "name", "latency", "initiation_interval", "variable_latency", "status",
    "rtl_owner", "evidence", *TIMING_KEYS,
}
PHYSICAL_RESOURCE_KEYS = {
    "id", "kind", "count", "operations", "connection_planes",
    "context_coupling",
}
GUARD_KEYS = {
    "enabled", "reject_express_route", "reject_active_bank_write", "error_codes",
}
ERROR_NAMES = {
    "array_control", "tile_operation", "route_capacity", "stream_contract",
    "resource_contract", "guaranteed_commit", "phase_instruction",
    "memory_configuration", "image_unavailable", "image_write",
}


def _require_exact_keys(value: dict[str, Any], expected: set[str], where: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        raise ValueError(f"{where} key mismatch: missing={missing}, unknown={unknown}")


def _positive_int(value: Any, where: str, allow_zero: bool = False) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{where} must be an integer")
    if value < (0 if allow_zero else 1):
        raise ValueError(f"{where} is outside its legal range")
    return value


def _evidence_exists(value: Any, where: str) -> None:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{where} evidence must be a non-empty path")
    path = ROOT / value
    if not path.is_file():
        raise ValueError(f"{where} evidence does not exist: {value}")


def _rtl_module_names() -> set[str]:
    filelist = ROOT / "rtl" / "v3" / "files.f"
    names: set[str] = set()
    for relative in filelist.read_text(encoding="utf-8").splitlines():
        relative = relative.strip()
        if not relative or relative.startswith("#") or relative.startswith("+"):
            continue
        text = (ROOT / relative).read_text(encoding="utf-8")
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("module "):
                names.add(stripped.split()[1].split("#")[0].split("(")[0])
    return names


def _validate_capability(record: dict[str, Any], where: str,
                         allowed_status: set[str]) -> None:
    status = record["status"]
    if status not in allowed_status:
        raise ValueError(f"{where} has invalid capability status")
    owner, evidence = record["rtl_owner"], record["evidence"]
    if status in {"implemented", "verification"}:
        if not isinstance(owner, str) or not owner:
            raise ValueError(f"{where} implemented capability lacks rtl_owner")
        _evidence_exists(evidence, where)
    elif owner is not None or evidence is not None:
        raise ValueError(f"{where} inactive capability must not claim owner/evidence")


def _validate_timing(record: dict[str, Any], where: str) -> None:
    status, evidence = record["timing_status"], record["timing_evidence"]
    if status not in {"measured", "modeled", "unimplemented"}:
        raise ValueError(f"{where} has invalid timing status")
    if status == "measured":
        _evidence_exists(evidence, f"{where} timing")
    elif evidence is not None:
        raise ValueError(f"{where} non-measured timing cannot claim evidence")


def canonical_bytes(configuration: dict[str, Any]) -> bytes:
    return (json.dumps(configuration, sort_keys=True, separators=(",", ":")) + "\n").encode()


def configuration_hash(configuration: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_bytes(configuration)).hexdigest()


def validate(configuration: dict[str, Any]) -> dict[str, Any]:
    _require_exact_keys(configuration, TOP_LEVEL_KEYS, "architecture configuration")
    if configuration["schema"] != "cscgra-v3-architecture-configuration-v5":
        raise ValueError("unsupported architecture configuration schema")
    if configuration["architecture_revision"] != 3:
        raise ValueError("architecture revision must remain 3 for the active build")
    if configuration["context_format_revision"] != isa.CONTEXT_FORMAT_REVISION:
        raise ValueError("context revision differs from context_isa.py")

    numeric = configuration["numeric_profiles"]
    _require_exact_keys(numeric, NUMERIC_PROFILES_KEYS, "numeric profiles")
    profiles = numeric["profiles"]
    if not isinstance(profiles, list) or len(profiles) != 2:
        raise ValueError("numeric profile table must contain production and closure candidate")
    by_name = {}
    identifiers = set()
    for profile in profiles:
        _require_exact_keys(profile, NUMERIC_PROFILE_KEYS, "numeric profile")
        name = profile["name"]
        if not isinstance(name, str) or not name or name in by_name:
            raise ValueError("numeric profile names must be unique non-empty strings")
        identifier = _positive_int(profile["id"], f"{name} numeric profile id")
        if identifier in identifiers:
            raise ValueError("numeric profile ids must be unique")
        identifiers.add(identifier)
        for field in ("data_width", "data_fraction_bits", "solver_width",
                      "solver_fraction_bits", "accumulator_width",
                      "scalar_divide_latency", "strict_normal_residual_shift"):
            _positive_int(profile[field], f"{name} {field}")
        if profile["data_fraction_bits"] >= profile["data_width"]:
            raise ValueError(f"{name} data fraction does not fit its width")
        if profile["solver_fraction_bits"] >= profile["solver_width"]:
            raise ValueError(f"{name} solver fraction does not fit its width")
        if profile["status"] not in {"active", "closure_candidate"}:
            raise ValueError(f"{name} numeric status is invalid")
        by_name[name] = profile
    if numeric["active"] != "production" or numeric["closure_candidate"] != "quality_d22":
        raise ValueError("numeric active/candidate bindings differ from the P1 contract")
    production = by_name[numeric["active"]]
    candidate = by_name[numeric["closure_candidate"]]
    if production != {
        "id": 1, "name": "production", "data_width": scaling.DATA_W,
        "data_fraction_bits": 14, "solver_width": scaling.SOLVER_W,
        "solver_fraction_bits": 19, "accumulator_width": scaling.ACC_W,
        "scalar_divide_latency": 15,
        "strict_normal_residual_shift": 14, "status": "active",
    }:
        raise ValueError("active production numeric profile differs from B0")
    if candidate != {
        "id": 2, "name": "quality_d22", "data_width": 22,
        "data_fraction_bits": 18, "solver_width": 31,
        "solver_fraction_bits": 23, "accumulator_width": 70,
        "scalar_divide_latency": 17,
        "strict_normal_residual_shift": 16, "status": "closure_candidate",
    }:
        raise ValueError("closure candidate differs from the qualified D22 model")

    topology = configuration["topology"]
    _require_exact_keys(topology, TOPOLOGY_KEYS, "topology")
    if topology["cluster_count"] != scaling.CLUSTER_COUNT:
        raise ValueError("cluster count differs from scaling authority")
    if topology["rows_per_cluster"] != 4 or topology["columns_per_cluster"] != 4:
        raise ValueError("active architecture must contain two 4x4 clusters")
    if topology["shared_array_context_pc"] is not True:
        raise ValueError("per-cluster or per-column PCs are forbidden")
    if topology["interconnect"] != "registered_nearest_neighbor_mesh":
        raise ValueError("only the registered nearest-neighbour mesh is enabled")
    if topology["wraparound"] or topology["express_links_enabled"]:
        raise ValueError("wraparound and express links are disabled in the baseline")
    if topology["route_capacity_per_direction"] != 1:
        raise ValueError("each directed route has exactly one slot per context cycle")
    if topology["intercluster_column_connectors"] != 1:
        raise ValueError("active architecture must contain one column connector")
    if topology["intercluster_connector_lanes"] != topology["columns_per_cluster"]:
        raise ValueError("column connector must contain one lane per PE column")
    if topology["intercluster_connector_latency"] != 1:
        raise ValueError("column connector latency must equal one registered routing hop")

    storage = configuration["context_storage"]
    _require_exact_keys(storage, CONTEXT_STORAGE_KEYS, "context storage")
    expected_storage = {
        "context_depth": scaling.CONTEXT_DEPTH,
        "image_banks": 2,
        "tile_context_width": isa.TILE_CONTEXT_WIDTH,
        "array_control_context_width": isa.ARRAY_CONTROL_CONTEXT_WIDTH,
        "stream_context_width": isa.STREAM_CONTEXT_WIDTH,
        "resource_context_width": isa.RESOURCE_CONTEXT_WIDTH,
        "phase_instruction_width": isa.PHASE_INSTRUCTION_WIDTH,
        "tile_pair_plane_count": 8,
        "array_stream_plane_count": 1,
        "resource_phase_plane_count": 1,
        "array_context_commit_plane": 8,
        "phase_instruction_commit_plane": 10,
        "require_contiguous_plane_programming": True,
        "array_context_programming_order": [0, 1, 2, 3, 4, 5, 6, 7, 9, 8],
    }
    if storage != expected_storage:
        raise ValueError(f"context storage differs from the active physical plan: {storage}")

    memory = configuration["memory"]
    _require_exact_keys(memory, MEMORY_KEYS, "memory")
    expected_memory = {
        "vector_bank_count": scaling.MEMORY_LANES,
        "vector_bank_depth": 512,
        "vector_bank_word_width": scaling.MEMORY_WORD_W,
        "memory_configuration_count": 64,
        "memory_configuration_width": isa.MEMORY_CONFIGURATION_WIDTH,
        "memory_configuration_read_ports": 4,
        "memory_configuration_read_latency": 1,
        "memory_configuration_ram_copies": 2,
        "memory_configuration_bram36_count": 4,
        "axi_data_width": scaling.AXI_DATA_W,
    }
    if memory != expected_memory:
        raise ValueError("memory organization differs from the active K32 build")

    execution = configuration["execution_context"]
    _require_exact_keys(execution, EXECUTION_CONTEXT_KEYS, "execution context")
    if execution["selection"] != "active_finalized_image":
        raise ValueError("hardware must launch the active finalized context image")
    if execution["phase_entry_pc"] != 0:
        raise ValueError("context images must expose phase entry PC zero")
    if execution["hardware_algorithm_decode"] is not False:
        raise ValueError("hardware algorithm decode is forbidden")
    if execution["software_defines_context"] is not True:
        raise ValueError("software must own algorithm-to-context compilation")
    _validate_capability(execution, "execution context", {"implemented"})

    matrix_modes = configuration["matrix_modes"]
    if not isinstance(matrix_modes, list) or len(matrix_modes) != 2:
        raise ValueError("matrix capability table must contain two encoded modes")
    expected_modes = ("DENSE_RADEMACHER", "FIXED_COLUMN_WEIGHT_EXPERIMENTAL")
    for expected_code, (mode, expected_name) in enumerate(zip(matrix_modes, expected_modes)):
        _require_exact_keys(mode, MATRIX_MODE_KEYS, f"matrix mode {expected_code}")
        if mode["code"] != expected_code or mode["name"] != expected_name:
            raise ValueError("matrix capability table differs from run ABI")
        _validate_capability(mode, f"matrix mode {expected_code}", {"implemented", "planned"})

    enum_groups = (
        (configuration["tile_operations"], TILE_OPERATION_KEYS, isa.TileOperation, False),
        (configuration["resource_operations"], RESOURCE_OPERATION_KEYS,
         isa.ResourceOperation, True),
    )
    for records, keys, enum_type, has_variable in enum_groups:
        if not isinstance(records, list):
            raise ValueError("operation table must be a list")
        by_code: dict[int, dict[str, Any]] = {}
        for record in records:
            _require_exact_keys(record, keys, f"{enum_type.__name__} record")
            code = _positive_int(record["code"], "operation code", allow_zero=True)
            if code in by_code:
                raise ValueError("duplicate operation code")
            _positive_int(record["latency"], "operation latency", allow_zero=has_variable)
            _positive_int(record["initiation_interval"], "operation initiation interval")
            if has_variable and not isinstance(record["variable_latency"], bool):
                raise ValueError("variable_latency must be boolean")
            allowed_status = {"implemented", "planned", "reserved"} if has_variable else {"implemented"}
            _validate_capability(record, record["name"], allowed_status)
            _validate_timing(record, record["name"])
            if has_variable and record["status"] == "reserved" and (
                    record["latency"] != 1 or
                    record["initiation_interval"] != 1 or
                    record["variable_latency"]):
                raise ValueError(
                    f"{record['name']} reserved fault must be fixed one-cycle")
            by_code[code] = record
        if set(by_code) != {int(item) for item in enum_type}:
            raise ValueError(f"{enum_type.__name__} operation set is incomplete")
        for item in enum_type:
            if by_code[int(item)]["name"] != item.name:
                raise ValueError(f"operation {int(item)} name differs from ISA enum")

    compiler_operations = configuration["compiler_operations"]
    if not isinstance(compiler_operations, list) or not compiler_operations:
        raise ValueError("compiler operation table must be a non-empty list")
    compiler_by_name: dict[str, dict[str, Any]] = {}
    for record in compiler_operations:
        _require_exact_keys(record, COMPILER_OPERATION_KEYS, "compiler operation")
        name = record["name"]
        if not isinstance(name, str) or not name or name in compiler_by_name:
            raise ValueError("compiler operation names must be unique non-empty strings")
        _positive_int(record["latency"], f"{name} latency")
        _positive_int(record["initiation_interval"], f"{name} initiation interval")
        if not isinstance(record["variable_latency"], bool):
            raise ValueError("compiler variable_latency must be boolean")
        _validate_capability(record, name, {"implemented", "planned"})
        _validate_timing(record, name)
        compiler_by_name[name] = record

    tile_names = {record["name"] for record in configuration["tile_operations"]}
    resource_names = {record["name"] for record in configuration["resource_operations"]
                      if record["name"] != "NOP"}
    implemented_resource_names = {
        record["name"] for record in configuration["resource_operations"]
        if record["name"] != "NOP" and record["status"] == "implemented"
    }
    reserved_resource_names = {
        record["name"] for record in configuration["resource_operations"]
        if record["status"] == "reserved"
    }
    if (tile_names & resource_names) or (set(compiler_by_name) &
                                         (tile_names | resource_names)):
        raise ValueError("operation names must be unique across timing tables")

    physical_resources = configuration["physical_resources"]
    if not isinstance(physical_resources, list) or not physical_resources:
        raise ValueError("physical resource table must be a non-empty list")
    resource_ids: set[str] = set()
    operation_owners: dict[str, str] = {}
    legal_operations = tile_names | (resource_names - reserved_resource_names) | set(compiler_by_name)
    for record in physical_resources:
        _require_exact_keys(record, PHYSICAL_RESOURCE_KEYS, "physical resource")
        resource_id = record["id"]
        if not isinstance(resource_id, str) or not resource_id or resource_id in resource_ids:
            raise ValueError("physical resource IDs must be unique non-empty strings")
        resource_ids.add(resource_id)
        _positive_int(record["count"], f"{resource_id} count")
        if not isinstance(record["kind"], str) or not record["kind"]:
            raise ValueError(f"{resource_id} kind is malformed")
        if not isinstance(record["context_coupling"], str) or not record["context_coupling"]:
            raise ValueError(f"{resource_id} context coupling is malformed")
        planes = record["connection_planes"]
        if (not isinstance(planes, list) or not planes or
                any(not isinstance(plane, str) or not plane for plane in planes)):
            raise ValueError(f"{resource_id} connection planes are malformed")
        operations = record["operations"]
        if not isinstance(operations, list) or not operations:
            raise ValueError(f"{resource_id} must own at least one operation")
        for operation in operations:
            if operation in reserved_resource_names:
                raise ValueError(
                    f"{resource_id} cannot own reserved operation {operation}")
            if operation not in legal_operations:
                raise ValueError(f"{resource_id} owns unknown operation {operation}")
            if operation in operation_owners:
                raise ValueError(
                    f"operation {operation} has multiple physical owners: "
                    f"{operation_owners[operation]}, {resource_id}")
            operation_owners[operation] = resource_id
    if set(operation_owners) != legal_operations:
        raise ValueError(
            "physical resource operation coverage mismatch: "
            f"missing={sorted(legal_operations - set(operation_owners))}")
    paired = next((item for item in physical_resources
                   if item["id"] == "paired_context_tile"), None)
    if paired is None or paired["count"] != topology["rows_per_cluster"] * topology["columns_per_cluster"]:
        raise ValueError("paired context tile count differs from shared-context topology")

    guard = configuration["reservation_guard"]
    _require_exact_keys(guard, GUARD_KEYS, "reservation guard")
    if guard["enabled"] is not True or guard["reject_express_route"] is not True:
        raise ValueError("M3 production configuration must enable N2 guards")
    if guard["reject_active_bank_write"] is not True:
        raise ValueError("active context image writes must be rejected")
    if set(guard["error_codes"]) != ERROR_NAMES:
        raise ValueError("reservation guard error-code table is incomplete")
    codes = list(guard["error_codes"].values())
    if len(set(codes)) != len(codes) or any(not isinstance(x, int) or not 0 <= x < 256
                                            for x in codes):
        raise ValueError("reservation guard error codes must be unique bytes")
    module_names = _rtl_module_names()
    for table in ("tile_operations", "resource_operations", "compiler_operations"):
        for record in configuration[table]:
            if record["status"] == "implemented" and record["rtl_owner"] not in module_names:
                raise ValueError(
                    f"{record['name']} implemented owner {record['rtl_owner']} is absent from files.f")
    for record in [execution, *matrix_modes]:
        if record["status"] == "implemented" and record["rtl_owner"] not in module_names:
            raise ValueError(f"{record.get('name', 'execution context')} owner is absent from files.f")
    return configuration


def load(path: Path = DEFAULT_PATH) -> dict[str, Any]:
    return validate(json.loads(path.read_text(encoding="utf-8")))


def latency_ii_payload(configuration: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema": "cscgra-v3-latency-ii-v2",
        "architecture_hash": configuration_hash(configuration),
        "status": "mixed measured/modeled authority; unimplemented operations are unschedulable",
        "tile_operations": configuration["tile_operations"],
        "resource_operations": configuration["resource_operations"],
        "compiler_operations": configuration["compiler_operations"],
        "physical_resources": configuration["physical_resources"],
    }


def operation_timing(configuration: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Return the single timing authority indexed by compiler operation name."""
    result: dict[str, dict[str, Any]] = {}
    for table in ("tile_operations", "resource_operations", "compiler_operations"):
        for record in configuration[table]:
            if table == "resource_operations" and record["name"] == "NOP":
                continue
            result[record["name"]] = {
                "latency": record["latency"],
                "initiation_interval": record["initiation_interval"],
                "variable_latency": record.get("variable_latency", False),
                "status": record.get("status", "implemented"),
                "rtl_owner": record.get("rtl_owner"),
                "evidence": record.get("evidence"),
                "timing_status": record.get("timing_status", "modeled"),
                "timing_evidence": record.get("timing_evidence"),
            }
    return result


def resource_operation_is_schedulable(configuration: dict[str, Any],
                                      operation: str) -> bool:
    """Return true only for resource opcodes backed by current-build datapath."""
    for record in configuration["resource_operations"]:
        if record["name"] == operation:
            return record["status"] == "implemented"
    raise ValueError(f"unknown resource operation {operation}")


def physical_resource_map(configuration: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {record["id"]: record for record in configuration["physical_resources"]}


def mrrg_payload(configuration: dict[str, Any]) -> dict[str, Any]:
    topology = configuration["topology"]
    nodes: list[dict[str, Any]] = []
    links: list[dict[str, Any]] = []
    rows, columns = topology["rows_per_cluster"], topology["columns_per_cluster"]
    timing = operation_timing(configuration)
    resources = physical_resource_map(configuration)
    paired = resources["paired_context_tile"]
    for row in range(rows):
        for column in range(columns):
            node = f"paired_tile_r{row}_c{column}"
            nodes.append({
                "id": node,
                "kind": paired["kind"],
                "resource_class": paired["id"],
                "capacity": 1,
                "row": row,
                "column": column,
                "physical_lane_replicas": [
                    f"pe_c{cluster}_r{row}_c{column}"
                    for cluster in range(topology["cluster_count"])
                ],
                "operations": paired["operations"],
                "operation_timing": {
                    name: timing[name] for name in paired["operations"]
                },
                "connection_planes": paired["connection_planes"],
                "context_coupling": paired["context_coupling"],
            })
            for direction, dr, dc in (
                ("north", -1, 0), ("east", 0, 1),
                ("south", 1, 0), ("west", 0, -1),
            ):
                rr, cc = row + dr, column + dc
                if 0 <= rr < rows and 0 <= cc < columns:
                    links.append({
                        "id": f"{node}_{direction}",
                        "source": node,
                        "sink": f"paired_tile_r{rr}_c{cc}",
                        "latency": 1,
                        "capacity": topology["route_capacity_per_direction"],
                        "plane": "registered_mesh",
                        "physical_replicas": topology["cluster_count"],
                    })
    for column in range(columns):
        upper = f"paired_tile_r{rows - 1}_c{column}"
        lower = f"paired_tile_r0_c{column}"
        links.extend((
            {
                "id": f"intercluster_c{column}_upper_to_lower",
                "source": upper,
                "sink": lower,
                "latency": topology["intercluster_connector_latency"],
                "capacity": topology["route_capacity_per_direction"],
                "plane": "intercluster_column_connector",
                "physical_replicas": 1,
                "physical_source": f"pe_c0_r{rows - 1}_c{column}",
                "physical_sink": f"pe_c1_r0_c{column}",
            },
            {
                "id": f"intercluster_c{column}_lower_to_upper",
                "source": lower,
                "sink": upper,
                "latency": topology["intercluster_connector_latency"],
                "capacity": topology["route_capacity_per_direction"],
                "plane": "intercluster_column_connector",
                "physical_replicas": 1,
                "physical_source": f"pe_c1_r0_c{column}",
                "physical_sink": f"pe_c0_r{rows - 1}_c{column}",
            },
        ))
    for resource in configuration["physical_resources"]:
        if resource["id"] == "paired_context_tile":
            continue
        for instance in range(resource["count"]):
            nodes.append({
                "id": f"{resource['id']}_{instance}",
                "kind": resource["kind"],
                "resource_class": resource["id"],
                "capacity": 1,
                "operations": resource["operations"],
                "operation_timing": {
                    name: timing[name] for name in resource["operations"]
                },
                "connection_planes": resource["connection_planes"],
                "context_coupling": resource["context_coupling"],
            })
    for bank in range(configuration["memory"]["vector_bank_count"]):
        nodes.append({
            "id": f"vector_bank_{bank}", "kind": "memory_bank", "ports": 2,
            "cluster": bank // rows, "row": bank % rows,
        })
    paired_nodes = [node["id"] for node in nodes
                    if node["kind"] == "paired_context_tile"]
    for node in paired_nodes:
        for source in ("vector_read_port_0", "vector_read_port_1"):
            links.append({"id": f"{source}_to_{node}", "source": source,
                          "sink": node, "latency": 1, "capacity": 1,
                          "plane": "memory_row", "physical_replicas": 2})
        links.append({"id": f"phi_generator_0_to_{node}",
                      "source": "phi_generator_0", "sink": node,
                      "latency": 1, "capacity": 1,
                      "plane": "phi_broadcast", "physical_replicas": 2})
        links.append({"id": f"{node}_to_reduction_pipeline_0",
                      "source": node, "sink": "reduction_pipeline_0",
                      "latency": 1, "capacity": 1,
                      "plane": "reduction_up", "physical_replicas": 2})
        links.append({"id": f"reduction_pipeline_0_to_{node}",
                      "source": "reduction_pipeline_0", "sink": node,
                      "latency": 1, "capacity": 1,
                      "plane": "scalar_broadcast", "physical_replicas": 2})
        links.append({"id": f"{node}_to_vector_write_port_0",
                      "source": node, "sink": "vector_write_port_0",
                      "latency": 1, "capacity": 1,
                      "plane": "memory_row", "physical_replicas": 2})
    links.extend([
        {
            "id": "reduction_pipeline_0_to_phi_operator_normalizer_0",
            "source": "reduction_pipeline_0",
            "sink": "phi_operator_normalizer_0",
            "latency": 1,
            "capacity": 1,
            "plane": "normalized_result",
            "physical_replicas": 1,
        },
        {
            "id": "phi_operator_normalizer_0_to_selection_unit_0",
            "source": "phi_operator_normalizer_0",
            "sink": "selection_unit_0",
            "latency": 4,
            "capacity": 1,
            "plane": "normalized_result",
            "physical_replicas": 1,
        },
        {
            "id": "phi_operator_normalizer_0_to_vector_write_port_0",
            "source": "phi_operator_normalizer_0",
            "sink": "vector_write_port_0",
            "latency": 4,
            "capacity": 1,
            "plane": "normalized_result",
            "physical_replicas": 1,
        },
    ])
    return {
        "schema": "cscgra-v3-base-mrrg-v2",
        "architecture_hash": configuration_hash(configuration),
        "time_expansion": "base graph; modulo_mapping_graph.py expands candidate II",
        "configuration_resources": 16,
        "physical_pe_lanes": 32,
        "nodes": nodes,
        "links": links,
    }


if __name__ == "__main__":
    value = load()
    print(json.dumps({"architecture_hash": configuration_hash(value)}, indent=2))
