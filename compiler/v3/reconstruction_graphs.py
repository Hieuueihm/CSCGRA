#!/usr/bin/env python3
"""Canonical paper-phase CFGs and array-routine DDGs for the v3 CGRA.

This module is deliberately independent from RTL and from the v2 controller.
It is the machine-readable bridge from paper algorithms to future MRRG mapping.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from functools import lru_cache
import json
from pathlib import Path
from typing import Iterable

from compiler.v3 import architecture_configuration as architecture


PAPER_DOI = {
    "OMP": "10.1109/TIT.2007.909108",
    "CoSaMP": "10.1016/j.acha.2008.07.002",
    "IHT": "10.1016/j.acha.2009.04.002",
    "HTP": "10.1137/100806278",
    "SP": "10.1109/TIT.2009.2016006",
    "GP": "10.1109/TSP.2007.916124",
    "GOMP": "10.1109/TSP.2012.2218810",
    "MP": "10.1109/78.258082",
}


@dataclass(frozen=True)
class PhaseNode:
    name: str
    routine: str
    reads: tuple[str, ...]
    writes: tuple[str, ...]
    array_usage: str = "tiles_and_resources"


@dataclass(frozen=True)
class PhaseEdge:
    source: str
    target: str
    condition: str = "always"


@dataclass(frozen=True)
class AlgorithmCFG:
    algorithm: str
    paper_doi: str
    entry: str
    terminals: tuple[str, ...]
    nodes: tuple[PhaseNode, ...]
    edges: tuple[PhaseEdge, ...]


@dataclass(frozen=True)
class OperationNode:
    name: str
    operation: str
    resource_class: str
    latency: int
    initiation_interval: int
    occupancy: int
    variable_latency: bool
    instances_required: int = 1
    preferred_instance: int | None = None


@dataclass(frozen=True)
class DependencyEdge:
    source: str
    target: str
    value: str
    iteration_distance: int = 0
    route: str = "direct_plane"


@dataclass(frozen=True)
class ArrayRoutineDDG:
    name: str
    loop_axis: str
    partition_mode: str
    operations: tuple[OperationNode, ...]
    dependencies: tuple[DependencyEdge, ...]
    mapping_domain: str = "resource_transaction"


def _node(name: str, routine: str, reads: Iterable[str], writes: Iterable[str],
          array_usage: str = "tiles_and_resources") -> PhaseNode:
    return PhaseNode(name, routine, tuple(reads), tuple(writes), array_usage)


def _linear_edges(names: list[str]) -> list[PhaseEdge]:
    return [PhaseEdge(a, b) for a, b in zip(names, names[1:])]


def _iterative_cfg(algorithm: str, phases: list[PhaseNode],
                   loop_target: str | None = None) -> AlgorithmCFG:
    node_names = [node.name for node in phases]
    stop_name = "STOP"
    done_name = "DONE"
    nodes = phases + [
        _node(stop_name, "residual_stop", ("residual", "iteration"), ("stop_event",), "resources_only"),
        _node(done_name, "commit_result", ("support", "x", "residual"), ("result",), "resources_only"),
    ]
    edges = _linear_edges(node_names)
    edges.append(PhaseEdge(node_names[-1], stop_name))
    edges.append(PhaseEdge(stop_name, done_name, "stop_or_iteration_limit"))
    edges.append(PhaseEdge(stop_name, loop_target or node_names[0], "continue"))
    return AlgorithmCFG(algorithm, PAPER_DOI[algorithm], node_names[0], (done_name,),
                        tuple(nodes), tuple(edges))


def build_phase_cfgs() -> dict[str, AlgorithmCFG]:
    cfgs: dict[str, AlgorithmCFG] = {}
    cfgs["OMP"] = _iterative_cfg("OMP", [
        _node("CORR", "correlation", ("phi", "residual"), ("proxy",)),
        _node("SELECT", "argmax_excluding_support", ("proxy", "support"), ("candidate",)),
        _node("APPEND", "support_append", ("support", "candidate"), ("support",), "resources_only"),
        _node("LS", "restricted_refinement", ("phi", "y", "support", "proxy"), ("x", "residual")),
        _node("RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
    ])
    cfgs["CoSaMP"] = _iterative_cfg("CoSaMP", [
        _node("CORR", "correlation", ("phi", "residual"), ("proxy",)),
        _node("IDENTIFY_2K", "topk_stream", ("proxy",), ("candidate_2k",)),
        _node("UNION_3K", "support_union", ("support_k", "candidate_2k"), ("work_support_3k",), "resources_only"),
        _node("LS_3K", "restricted_refinement", ("phi", "y", "work_support_3k", "proxy"), ("work_x", "work_residual")),
        _node("PRUNE_K", "coefficient_topk", ("work_x",), ("support_k", "x"), "resources_only"),
        _node("RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
    ])
    cfgs["IHT"] = _iterative_cfg("IHT", [
        _node("CORR", "correlation", ("phi", "residual"), ("gradient",)),
        _node("GRADIENT_STEP", "vector_axpy", ("x", "gradient", "mu"), ("tentative_x",)),
        _node("TOP_K", "coefficient_topk", ("tentative_x",), ("support", "x"), "resources_only"),
        _node("RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
    ])
    cfgs["HTP"] = _iterative_cfg("HTP", [
        _node("CORR", "correlation", ("phi", "residual"), ("gradient",)),
        _node("TENTATIVE", "vector_axpy", ("x", "gradient", "mu"), ("tentative_x",)),
        _node("TOP_K", "coefficient_topk", ("tentative_x",), ("support",), "resources_only"),
        _node("LS_K", "restricted_refinement", ("phi", "y", "support"), ("x", "residual")),
        _node("RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
    ])

    sp_nodes = [
        _node("INIT_CORR", "correlation", ("phi", "y"), ("proxy",)),
        _node("INIT_TOP_K", "topk_stream", ("proxy",), ("support_k",), "resources_only"),
        _node("INIT_LS_K", "restricted_refinement", ("phi", "y", "support_k", "proxy"), ("x", "residual")),
        _node("INIT_RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
        _node("CORR", "correlation", ("phi", "residual"), ("proxy",)),
        _node("TOP_K", "topk_stream", ("proxy",), ("candidate_k",)),
        _node("UNION_2K", "support_union", ("support_k", "candidate_k"), ("work_support_2k",), "resources_only"),
        _node("LS_2K", "restricted_refinement", ("phi", "y", "work_support_2k", "proxy"), ("work_x", "work_residual")),
        _node("PRUNE_K", "coefficient_topk", ("work_x",), ("proposed_support_k",), "resources_only"),
        _node("LS_K", "restricted_refinement", ("phi", "y", "proposed_support_k", "work_x"), ("proposed_x", "proposed_residual")),
        _node("RESIDUAL_CHECK", "residual_update", ("phi", "y", "proposed_x"), ("proposed_residual",)),
        _node("NON_DECREASE", "sp_accept_or_rollback", ("residual", "proposed_residual"), ("support_k", "x", "residual"), "resources_only"),
        _node("STOP", "residual_stop", ("residual", "iteration"), ("stop_event",), "resources_only"),
        _node("DONE", "commit_result", ("support_k", "x", "residual"), ("result",), "resources_only"),
    ]
    sp_names = [node.name for node in sp_nodes]
    sp_edges = _linear_edges(sp_names[:-2]) + [
        PhaseEdge("NON_DECREASE", "STOP"),
        PhaseEdge("STOP", "DONE", "stop_non_decrease_or_limit"),
        PhaseEdge("STOP", "CORR", "continue"),
    ]
    cfgs["SP"] = AlgorithmCFG("SP", PAPER_DOI["SP"], "INIT_CORR", ("DONE",),
                               tuple(sp_nodes), tuple(sp_edges))

    cfgs["GP"] = _iterative_cfg("GP", [
        _node("CORR", "correlation", ("phi", "residual"), ("gradient",)),
        _node("SUPPORT", "gp_support_policy", ("gradient", "support"), ("support",), "resources_only"),
        _node("DIRECTION", "restricted_gradient", ("gradient", "support"), ("direction",)),
        _node("PHI_DIRECTION", "phi_support_forward", ("phi", "support", "direction"), ("projected_direction",)),
        _node("LINE_SEARCH", "gp_line_search", ("residual", "projected_direction"), ("step",), "resources_only"),
        _node("UPDATE", "vector_axpy", ("x", "direction", "step"), ("x",)),
        _node("RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
    ])
    cfgs["GOMP"] = _iterative_cfg("GOMP", [
        _node("CORR", "correlation", ("phi", "residual"), ("proxy",)),
        _node("TOP_L", "topk_excluding_support", ("proxy", "support"), ("candidate_l",)),
        _node("APPEND", "support_append", ("support", "candidate_l"), ("support",), "resources_only"),
        _node("LS", "restricted_refinement", ("phi", "y", "support", "proxy"), ("x", "residual")),
        _node("RESIDUAL", "residual_update", ("phi", "y", "x"), ("residual",)),
    ])
    cfgs["MP"] = _iterative_cfg("MP", [
        _node("CORR", "normalized_correlation", ("phi", "residual"), ("proxy",)),
        _node("ARGMAX", "argmax_stream", ("proxy",), ("candidate",), "resources_only"),
        _node("RANK1_UPDATE", "mp_rank1_update", ("x", "candidate", "proxy"), ("x",)),
        _node("RESIDUAL", "mp_residual_projection", ("phi", "residual", "candidate"), ("residual",)),
    ])
    return cfgs


@lru_cache(maxsize=1)
def _architecture_configuration() -> dict:
    return architecture.load()


def _op(name: str, operation: str, resource_class: str,
        instances_required: int = 1,
        preferred_instance: int | None = None) -> OperationNode:
    configuration = _architecture_configuration()
    timing = architecture.operation_timing(configuration)
    resources = architecture.physical_resource_map(configuration)
    if resource_class not in resources:
        raise ValueError(f"{name}: unknown physical resource {resource_class}")
    if operation not in resources[resource_class]["operations"]:
        raise ValueError(
            f"{name}: {operation} is not supported by {resource_class}")
    record = timing[operation]
    return OperationNode(
        name=name,
        operation=operation,
        resource_class=resource_class,
        latency=record["latency"],
        initiation_interval=record["initiation_interval"],
        occupancy=record["initiation_interval"],
        variable_latency=record["variable_latency"],
        instances_required=instances_required,
        preferred_instance=preferred_instance,
    )


def _dep(source: str, target: str, value: str, iteration_distance: int = 0,
         route: str = "direct_plane") -> DependencyEdge:
    return DependencyEdge(source, target, value, iteration_distance, route)


def build_array_routine_ddgs() -> dict[str, ArrayRoutineDDG]:
    return {
        "correlation": ArrayRoutineDDG("correlation", "signal_column", "split_measurement_rows", (
            _op("load_r", "LOAD_VECTOR", "vector_read_port", preferred_instance=0),
            _op("phi", "PHI_SIGN_WORD", "phi_generator"),
            _op("phi_accumulate", "PHI_DATA_ACCUMULATE", "paired_context_tile", 16),
            _op("reduce", "REDUCE_SUM", "reduction_pipeline"),
            _op("collect", "TOPK_PUSH", "selection_unit"),
        ), (
            _dep("load_r", "phi_accumulate", "residual", route="memory_row"),
            _dep("phi", "phi_accumulate", "phi_sign", route="phi_broadcast"),
            _dep("phi_accumulate", "phi_accumulate", "partial_sum", 1,
                 "local_feedback"),
            _dep("phi_accumulate", "reduce", "lane_partial", route="reduction_up"),
            _dep("reduce", "collect", "proxy_candidate",
                 route="normalized_result"),
        ), "modulo_array"),
        "residual_update": ArrayRoutineDDG("residual_update", "measurement", "split_measurement_tiles", (
            _op("load_x", "LOAD_VECTOR", "vector_read_port", preferred_instance=0),
            _op("phi", "PHI_SIGN_WORD", "phi_generator"),
            _op("phi_accumulate", "PHI_ACCUMULATE", "paired_context_tile", 16),
            _op("load_y", "LOAD_VECTOR", "vector_read_port", preferred_instance=1),
            _op("subtract", "PHI_RESIDUAL_CAPTURE", "paired_context_tile", 16),
            _op("store_r", "STORE_VECTOR", "vector_write_port"),
        ), (
            _dep("load_x", "phi_accumulate", "coefficient", route="memory_row"),
            _dep("phi", "phi_accumulate", "phi_sign", route="phi_broadcast"),
            _dep("phi_accumulate", "phi_accumulate", "partial_sum", 1,
                 "local_feedback"),
            _dep("phi_accumulate", "subtract", "fitted_y", route="local_feedback"),
            _dep("load_y", "subtract", "measurement", route="memory_row"),
            _dep("subtract", "store_r", "residual", route="memory_row"),
        ), "modulo_array"),
        "vector_axpy": ArrayRoutineDDG("vector_axpy", "vector_index", "split_vector_tiles", (
            _op("load_x", "LOAD_VECTOR", "vector_read_port"),
            _op("load_p", "LOAD_VECTOR", "vector_read_port", preferred_instance=0),
            _op("scale", "SHARED_VECTOR_SCALE", "shared_vector_arithmetic_unit"),
            _op("add", "SHARED_VECTOR_AXPY", "shared_vector_arithmetic_unit"),
            _op("narrow", "SHARED_VECTOR_COPY", "shared_vector_arithmetic_unit"),
            _op("store", "STORE_VECTOR", "vector_write_port"),
        ), (
            _dep("load_p", "scale", "p"),
            _dep("scale", "add", "scaled_p"),
            _dep("load_x", "add", "x"),
            _dep("add", "narrow", "sum"),
            _dep("narrow", "store", "result"),
        )),
        "dot_norm": ArrayRoutineDDG("dot_norm", "vector_index", "split_then_reduce_clusters", (
            _op("load_a", "LOAD_VECTOR", "vector_read_port"),
            _op("load_b", "LOAD_VECTOR", "vector_read_port"),
            _op("dot", "SHARED_VECTOR_DOT", "shared_vector_arithmetic_unit"),
        ), (
            _dep("load_a", "dot", "a"),
            _dep("load_b", "dot", "b"),
            _dep("dot", "dot", "partial_sum", 1, "local_feedback"),
        )),
        "phi_support_forward": ArrayRoutineDDG("phi_support_forward", "support_index", "split_measurement_tiles", (
            _op("load_p", "LOAD_VECTOR", "vector_read_port"),
            _op("phi", "PHI_SIGN_WORD", "phi_generator"),
            _op("phi_accumulate", "PHI_ACCUMULATE", "paired_context_tile", 16),
            _op("read_accumulator", "PHI_ACCUMULATOR_CAPTURE", "paired_context_tile", 16),
            _op("store_t", "STORE_VECTOR", "vector_write_port"),
        ), (
            _dep("load_p", "phi_accumulate", "support_coefficient", route="memory_row"),
            _dep("phi", "phi_accumulate", "phi_sign", route="phi_broadcast"),
            _dep("phi_accumulate", "phi_accumulate", "partial_sum", 1,
                 "local_feedback"),
            _dep("phi_accumulate", "read_accumulator", "lane_partial", route="local_feedback"),
            _dep("read_accumulator", "store_t", "measurement_projection",
                 route="memory_row"),
        ), "modulo_array"),
        "phi_support_transpose": ArrayRoutineDDG("phi_support_transpose", "measurement", "split_support_tiles", (
            _op("load_t", "LOAD_VECTOR", "vector_read_port", preferred_instance=0),
            _op("phi", "PHI_SIGN_WORD", "phi_generator"),
            _op("phi_accumulate", "PHI_ACCUMULATE", "paired_context_tile", 16),
            _op("reduce", "REDUCE_SUM", "reduction_pipeline"),
            _op("store_q", "STORE_VECTOR", "vector_write_port"),
        ), (
            _dep("load_t", "phi_accumulate", "t", route="memory_row"),
            _dep("phi", "phi_accumulate", "phi_sign", route="phi_broadcast"),
            _dep("phi_accumulate", "phi_accumulate", "partial_sum", 1,
                 "local_feedback"),
            _dep("phi_accumulate", "reduce", "lane_partial", route="reduction_up"),
            _dep("reduce", "store_q", "normal_operator_result",
                 route="normalized_memory"),
        ), "modulo_array"),
        "topk_stream": ArrayRoutineDDG("topk_stream", "score_index", "global_exact_backpressured", (
            _op("load_score", "LOAD_VECTOR", "vector_read_port"),
            _op("absolute", "ABS", "paired_context_tile", 16),
            _op("candidate_fifo", "TOPK_PUSH", "selection_unit"),
            _op("worst_scan", "ARGMAX", "selection_unit"),
            _op("commit", "TOPK_COMMIT", "selection_unit"),
        ), (
            _dep("load_score", "absolute", "score"),
            _dep("absolute", "candidate_fifo", "absolute_score"),
            _dep("candidate_fifo", "worst_scan", "candidate"),
            _dep("worst_scan", "worst_scan", "best_set", 1),
            _dep("worst_scan", "commit", "global_topk"),
        )),
        "support_union": ArrayRoutineDDG("support_union", "support_index", "single_shared_resource", (
            _op("read_existing", "SUPPORT_GATHER", "support_set_unit"),
            _op("read_candidate", "SUPPORT_GATHER", "support_set_unit"),
            _op("membership", "SUPPORT_MEMBERSHIP", "support_set_unit"),
            _op("append_unique", "SUPPORT_APPEND", "support_set_unit"),
            _op("commit", "SUPPORT_COMMIT", "support_set_unit"),
        ), (
            _dep("read_existing", "membership", "existing_index"),
            _dep("read_candidate", "membership", "candidate_index"),
            _dep("membership", "append_unique", "is_new"),
            _dep("append_unique", "append_unique", "work_list", 1),
            _dep("append_unique", "commit", "complete_work_support"),
        )),
        "restricted_refinement": ArrayRoutineDDG(
            "restricted_refinement", "refinement_iteration",
            "array_operators_plus_scheduled_shared_resources", (
                _op("forward", "PHI_ACCUMULATE", "paired_context_tile", 16),
                _op("delta", "SHARED_VECTOR_NORM_SQ", "shared_vector_arithmetic_unit"),
                _op("alpha", "SCALAR_DIVIDE", "scalar_function_unit"),
                _op("update_x", "SHARED_VECTOR_AXPY", "shared_vector_arithmetic_unit"),
                _op("update_r", "SHARED_VECTOR_AXPY", "shared_vector_arithmetic_unit"),
                _op("transpose", "PHI_ACCUMULATE", "paired_context_tile", 16),
                _op("gamma", "SHARED_VECTOR_NORM_SQ", "shared_vector_arithmetic_unit"),
                _op("beta", "SCALAR_DIVIDE", "scalar_function_unit"),
                _op("update_p", "SHARED_VECTOR_AXPY", "shared_vector_arithmetic_unit"),
                _op("check", "REFINEMENT_CHECK", "refinement_checker"),
            ), (
                _dep("forward", "delta", "d"),
                _dep("delta", "alpha", "delta"),
                _dep("alpha", "update_x", "alpha"),
                _dep("alpha", "update_r", "alpha"),
                _dep("update_r", "transpose", "r"),
                _dep("transpose", "gamma", "g"),
                _dep("gamma", "beta", "gamma"),
                _dep("beta", "update_p", "beta"),
                _dep("update_x", "check", "x"),
                _dep("gamma", "check", "normal_residual"),
                _dep("update_p", "forward", "p", 1),
            ), "hierarchical_control"),
    }


TRACE_PATTERNS = {
    "OMP": ("PROXY", "SELECT", "LS", "RESIDUAL"),
    "CoSaMP": ("PROXY", "IDENTIFY", "MERGE", "LS", "PRUNE", "RESIDUAL"),
    "IHT": ("PROXY", "UPDATE", "PRUNE", "RESIDUAL"),
    "HTP": ("PROXY", "SELECT", "LS", "RESIDUAL"),
    "GP": ("PROXY", "SELECT", "DIRECTION", "UPDATE", "RESIDUAL"),
    "GOMP": ("PROXY", "SELECT_GROUP", "LS", "RESIDUAL"),
    "MP": ("PROXY", "UPDATE", "RESIDUAL"),
}
SP_TRACE_INIT = ("INIT_PROXY", "INIT_SELECT", "INIT_LS", "INIT_RESIDUAL")
SP_TRACE_ITERATION = ("PROXY", "MERGE", "LS_WORK", "PRUNE", "LS_FINAL", "RESIDUAL_CHECK")


# Every paper-level routine is deliberately classified.  Only modulo_array
# entries are legal MMG inputs; variable-latency and hierarchical routines
# remain explicit resource/event transactions controlled by the phase CFG.
ROUTINE_LOWERING = {
    "correlation": {"kind": "array_ddg", "target": "correlation"},
    "normalized_correlation": {
        "kind": "hierarchical", "targets": ["correlation", "dot_norm"]},
    "residual_update": {"kind": "array_ddg", "target": "residual_update"},
    "phi_support_forward": {"kind": "array_ddg", "target": "phi_support_forward"},
    "restricted_refinement": {
        "kind": "hierarchical",
        "targets": ["phi_support_forward", "dot_norm", "vector_axpy",
                    "phi_support_transpose"],
    },
    "vector_axpy": {"kind": "resource_transaction", "target": "vector_axpy"},
    "restricted_gradient": {
        "kind": "resource_transaction", "target": "vector_axpy"},
    "argmax_excluding_support": {
        "kind": "resource_transaction", "target": "topk_stream"},
    "argmax_stream": {"kind": "resource_transaction", "target": "topk_stream"},
    "coefficient_topk": {
        "kind": "resource_transaction", "target": "topk_stream"},
    "topk_excluding_support": {
        "kind": "resource_transaction", "target": "topk_stream"},
    "topk_stream": {"kind": "resource_transaction", "target": "topk_stream"},
    "support_append": {
        "kind": "resource_transaction", "target": "support_union",
        "mode": "append"},
    "support_union": {
        "kind": "resource_transaction", "target": "support_union",
        "mode": "union"},
    "gp_support_policy": {
        "kind": "resource_transaction", "target": "support_union",
        "mode": "policy"},
    "gp_line_search": {
        "kind": "hierarchical", "targets": ["dot_norm", "vector_axpy"]},
    "mp_rank1_update": {
        "kind": "hierarchical", "targets": ["vector_axpy"]},
    "mp_residual_projection": {
        "kind": "hierarchical", "targets": ["phi_support_forward", "vector_axpy"]},
    "sp_accept_or_rollback": {"kind": "control_only"},
    "residual_stop": {"kind": "control_only"},
    "commit_result": {"kind": "control_only"},
}


def validate_phase_cfg(cfg: AlgorithmCFG) -> None:
    names = {node.name for node in cfg.nodes}
    if len(names) != len(cfg.nodes):
        raise ValueError(f"{cfg.algorithm}: duplicate phase node")
    if cfg.entry not in names or not set(cfg.terminals) <= names:
        raise ValueError(f"{cfg.algorithm}: invalid entry/terminal")
    allowed_usage = {"tiles_and_resources", "resources_only"}
    if any(node.array_usage not in allowed_usage for node in cfg.nodes):
        raise ValueError(f"{cfg.algorithm}: invalid synchronous-array usage")
    for edge in cfg.edges:
        if edge.source not in names or edge.target not in names:
            raise ValueError(f"{cfg.algorithm}: dangling edge {edge}")
    reachable = {cfg.entry}
    changed = True
    while changed:
        changed = False
        for edge in cfg.edges:
            if edge.source in reachable and edge.target not in reachable:
                reachable.add(edge.target)
                changed = True
    if reachable != names:
        raise ValueError(f"{cfg.algorithm}: unreachable nodes {sorted(names - reachable)}")


def validate_array_routine_ddg(ddg: ArrayRoutineDDG) -> None:
    configuration = _architecture_configuration()
    timing = architecture.operation_timing(configuration)
    resources = architecture.physical_resource_map(configuration)
    names = {node.name for node in ddg.operations}
    if len(names) != len(ddg.operations):
        raise ValueError(f"{ddg.name}: duplicate operation")
    if ddg.mapping_domain not in {
            "modulo_array", "resource_transaction", "hierarchical_control"}:
        raise ValueError(f"{ddg.name}: invalid mapping domain")
    for node in ddg.operations:
        if node.resource_class not in resources:
            raise ValueError(f"{ddg.name}: unknown resource class {node.resource_class}")
        if node.operation not in resources[node.resource_class]["operations"]:
            raise ValueError(f"{ddg.name}: illegal operation/resource binding {node}")
        authoritative = timing[node.operation]
        if ((node.latency, node.initiation_interval, node.variable_latency) !=
                (authoritative["latency"], authoritative["initiation_interval"],
                 authoritative["variable_latency"])):
            raise ValueError(f"{ddg.name}: stale timing for {node.name}")
        if not 1 <= node.instances_required <= resources[node.resource_class]["count"]:
            raise ValueError(f"{ddg.name}: illegal instance bundle for {node.name}")
        if (node.preferred_instance is not None and
                not 0 <= node.preferred_instance < resources[node.resource_class]["count"]):
            raise ValueError(f"{ddg.name}: illegal preferred instance for {node.name}")
        if ddg.mapping_domain == "modulo_array" and node.variable_latency:
            raise ValueError(f"{ddg.name}: variable-latency operation inside MMG kernel")
    for edge in ddg.dependencies:
        if edge.source not in names or edge.target not in names:
            raise ValueError(f"{ddg.name}: dangling dependency {edge}")
        if edge.iteration_distance < 0:
            raise ValueError(f"{ddg.name}: negative iteration distance")
        if edge.route not in {
                "direct_plane", "memory_row", "phi_broadcast",
                "same_tile_bundle", "local_feedback", "reduction_up",
                "scalar_broadcast", "resource_result", "normalized_result",
                "normalized_memory", "registered_mesh",
                "intercluster_column_connector"}:
            raise ValueError(f"{ddg.name}: unknown route class {edge.route}")

    # Removing loop-carried edges must leave an acyclic per-iteration graph.
    indegree = {name: 0 for name in names}
    successors = {name: [] for name in names}
    for edge in ddg.dependencies:
        if edge.iteration_distance == 0:
            successors[edge.source].append(edge.target)
            indegree[edge.target] += 1
    ready = [name for name, degree in indegree.items() if degree == 0]
    visited = 0
    while ready:
        source = ready.pop()
        visited += 1
        for target in successors[source]:
            indegree[target] -= 1
            if indegree[target] == 0:
                ready.append(target)
    if visited != len(names):
        raise ValueError(f"{ddg.name}: zero-distance dependency cycle")


def validate_all() -> tuple[dict[str, AlgorithmCFG], dict[str, ArrayRoutineDDG]]:
    cfgs = build_phase_cfgs()
    ddgs = build_array_routine_ddgs()
    if set(cfgs) != set(PAPER_DOI):
        raise ValueError("algorithm/source set mismatch")
    for cfg in cfgs.values():
        validate_phase_cfg(cfg)
    for ddg in ddgs.values():
        validate_array_routine_ddg(ddg)
    referenced = {node.routine for cfg in cfgs.values() for node in cfg.nodes}
    if referenced != set(ROUTINE_LOWERING):
        raise ValueError(
            "paper routine lowering mismatch: "
            f"missing={sorted(referenced - set(ROUTINE_LOWERING))}, "
            f"unused={sorted(set(ROUTINE_LOWERING) - referenced)}")
    for routine, lowering in ROUTINE_LOWERING.items():
        targets = ([lowering["target"]] if "target" in lowering
                   else lowering.get("targets", []))
        if any(target not in ddgs for target in targets):
            raise ValueError(f"{routine}: lowering references an unknown DDG")
    return cfgs, ddgs


def payload() -> dict:
    cfgs, ddgs = validate_all()
    configuration = _architecture_configuration()
    topology = configuration["topology"]
    storage = configuration["context_storage"]
    memory = configuration["memory"]
    return {
        "schema": "cscgra-v3-reconstruction-graphs-v7",
        "architecture_hash": architecture.configuration_hash(configuration),
        "architecture": {
            "macroblocks": [
                "reconstruction_control",
                "context_programmed_cgra",
                "generated_phi_stream",
                "reconstruction_memory",
                "sparse_selection_support",
                "reconstruction_result_writer",
            ],
            "cluster_count": topology["cluster_count"],
            "rows_per_cluster": topology["rows_per_cluster"],
            "columns_per_cluster": topology["columns_per_cluster"],
            "cluster_execution": "shared_synchronous_context",
            "scheduling": "static_per_cycle",
            "routing_model": "time_expanded_mrrg",
            "context_format": {
                "revision": configuration["context_format_revision"],
                "tile_count": topology["rows_per_cluster"] * topology["columns_per_cluster"],
                "tile_width": storage["tile_context_width"],
                "array_control_width": storage["array_control_context_width"],
                "stream_width": storage["stream_context_width"],
                "resource_width": storage["resource_context_width"],
                "cycle_width": (topology["rows_per_cluster"] *
                                topology["columns_per_cluster"] *
                                storage["tile_context_width"] +
                                storage["array_control_context_width"] +
                                storage["stream_context_width"] +
                                storage["resource_context_width"]),
                "phase_width": storage["phase_instruction_width"],
                "physical_ramb36": 10,
                "image_banks": storage["image_banks"],
            },
            "physical_resources": configuration["physical_resources"],
            "memory": {
                "vector_banks": memory["vector_bank_count"],
                "phi_banks": 0,
                "bank_word_width": memory["vector_bank_word_width"],
                "data_lanes": 32,
                "shared_vector_arithmetic_lanes": 16,
                "ports_per_bank": 2,
                "axi_data_width": memory["axi_data_width"],
                "mapping": "compiler_static_configuration_banking",
            },
            "intercluster_pe_links": (
                topology["intercluster_column_connectors"] *
                topology["intercluster_connector_lanes"] * 2
            ),
            "intercluster_routing": (
                "bidirectional_registered_column_connector"
            ),
        },
        "phase_cfgs": {name: asdict(cfg) for name, cfg in cfgs.items()},
        "array_routine_ddgs": {name: asdict(ddg) for name, ddg in ddgs.items()},
        "routine_lowering": ROUTINE_LOWERING,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = payload()
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
