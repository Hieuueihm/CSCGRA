#!/usr/bin/env python3
"""Typed SSA, RF/bank allocation and context emission for v3 array kernels.

This compiler stage consumes only validated M3.5 mappings.  It deliberately
emits kernel templates rather than paper-algorithm phase programs: phase CFG
composition remains software-owned, while every emitted array word is already
a bit-exact revision-9 ISA word suitable for the M3 context store.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from math import ceil
from typing import Any

from compiler.v3 import architecture_configuration as architecture
from compiler.v3 import context_isa as isa
from compiler.v3 import modulo_mapping_graph as mmg
from compiler.v3 import reconstruction_graphs as graphs


@dataclass(frozen=True)
class ValueType:
    name: str
    width: int
    fraction: int
    signed: bool
    aggregate: bool = False


VALUE_TYPES = {
    "D18F14": ValueType("D18F14", 18, 14, True),
    "S27F19": ValueType("S27F19", 27, 19, True),
    "L48F19": ValueType("L48F19", 48, 19, True),
    "A62F19": ValueType("A62F19", 62, 19, True),
    "A62F38": ValueType("A62F38", 62, 38, True),
    "PHI_SYMBOL2": ValueType("PHI_SYMBOL2", 2, 0, False),
    "INDEX10": ValueType("INDEX10", 10, 0, False),
    "PREDICATE1": ValueType("PREDICATE1", 1, 0, False),
    "TOPK_RECORD37": ValueType("TOPK_RECORD37", 37, 19, False),
    "TOPK_STATE": ValueType("TOPK_STATE", 64 * 37, 0, False, True),
    "SUPPORT_LIST": ValueType("SUPPORT_LIST", 96 * 10, 0, False, True),
}

_NUMERIC_CONFIGURATION = architecture.load()["numeric_profiles"]
_CLOSURE_PROFILE = next(
    profile for profile in _NUMERIC_CONFIGURATION["profiles"]
    if profile["name"] == _NUMERIC_CONFIGURATION["closure_candidate"]
)
CLOSURE_VALUE_TYPES = {
    "D22F18": ValueType(
        "D22F18", _CLOSURE_PROFILE["data_width"],
        _CLOSURE_PROFILE["data_fraction_bits"], True),
    "S31F23": ValueType(
        "S31F23", _CLOSURE_PROFILE["solver_width"],
        _CLOSURE_PROFILE["solver_fraction_bits"], True),
    "A70F23": ValueType(
        "A70F23", _CLOSURE_PROFILE["accumulator_width"],
        _CLOSURE_PROFILE["solver_fraction_bits"], True),
    "A70F46": ValueType(
        "A70F46", _CLOSURE_PROFILE["accumulator_width"],
        2 * _CLOSURE_PROFILE["solver_fraction_bits"], True),
    "TOPK_RECORD41": ValueType(
        "TOPK_RECORD41", _CLOSURE_PROFILE["solver_width"] + 10,
        _CLOSURE_PROFILE["solver_fraction_bits"], False),
}

PHI_ONLY_TILE_START = 4
PHI_ONLY_OPERATIONS = frozenset({
    isa.TileOperation.NOP,
    isa.TileOperation.PHI_ACCUMULATE,
    isa.TileOperation.ACCUMULATOR_READ,
    isa.TileOperation.ACCUMULATOR_CLEAR,
    isa.TileOperation.PHI_ACCUMULATOR_CAPTURE,
    isa.TileOperation.PHI_RESIDUAL_CAPTURE,
    isa.TileOperation.PHI_DATA_ACCUMULATE,
})


def _validate_production_tile_capabilities(
        kernel_name: str, pc: int, tiles: list[isa.TileContext]) -> None:
    for tile_id, tile in enumerate(tiles):
        if tile_id < PHI_ONLY_TILE_START:
            continue
        operation = isa.TileOperation(tile.operation)
        if operation not in PHI_ONLY_OPERATIONS:
            raise ValueError(
                f"{kernel_name} PC {pc} tile {tile_id}: operation "
                f"{operation.name} is unavailable on a Phi-only PE")
        if tile.rf_write_enable:
            raise ValueError(
                f"{kernel_name} PC {pc} tile {tile_id}: RF write is "
                "unavailable on a Phi-only PE")
        routes = (
            tile.route_north_select, tile.route_east_select,
            tile.route_south_select, tile.route_west_select,
        )
        if any(route != isa.RouteSource.HOLD for route in routes):
            raise ValueError(
                f"{kernel_name} PC {pc} tile {tile_id}: routing is "
                "unavailable on a Phi-only PE")


EDGE_TYPES: dict[str, dict[str, str]] = {
    "correlation": {
        "residual": "D18F14", "phi_sign": "PHI_SYMBOL2",
        "partial_sum": "L48F19",
        "lane_partial": "L48F19", "proxy_candidate": "S27F19",
    },
    "residual_update": {
        "coefficient": "S27F19", "phi_sign": "PHI_SYMBOL2",
        "partial_sum": "L48F19", "fitted_y": "S27F19",
        "measurement": "D18F14", "residual": "D18F14",
    },
    "vector_axpy": {
        "p": "S27F19", "scaled_p": "S27F19", "x": "S27F19",
        "sum": "S27F19", "result": "S27F19",
    },
    "dot_norm": {"a": "S27F19", "b": "S27F19", "partial_sum": "A62F38"},
    "phi_support_forward": {
        "support_coefficient": "S27F19", "phi_sign": "PHI_SYMBOL2",
        "partial_sum": "L48F19",
        "lane_partial": "L48F19", "measurement_projection": "S27F19",
    },
    "phi_support_transpose": {
        "t": "S27F19", "phi_sign": "PHI_SYMBOL2",
        "partial_sum": "L48F19",
        "lane_partial": "L48F19", "normal_operator_result": "S27F19",
    },
    "topk_stream": {
        "score": "S27F19", "absolute_score": "S27F19",
        "candidate": "TOPK_RECORD37", "best_set": "TOPK_STATE",
        "global_topk": "TOPK_STATE",
    },
    "support_union": {
        "existing_index": "INDEX10", "candidate_index": "INDEX10",
        "is_new": "PREDICATE1", "work_list": "SUPPORT_LIST",
        "complete_work_support": "SUPPORT_LIST",
    },
    "restricted_refinement": {
        "d": "S27F19", "delta": "A62F38", "alpha": "S27F19",
        "r": "S27F19", "g": "S27F19", "gamma": "A62F38",
        "beta": "S27F19", "p": "S27F19", "x": "S27F19",
        "normal_residual": "A62F38",
    },
}


KERNEL_BINDINGS = {
    "correlation": {
        "loads": {"load_r": "residual_current"},
        "stores": {}, "phi": "phi_dense", "loop_limit": "SIGNAL_LENGTH",
    },
    "residual_update": {
        "loads": {"load_x": "solver_x", "load_y": "measurement_y"},
        "stores": {"store_r": "residual_current"},
        "phi": "phi_support_forward", "loop_limit": "MEASUREMENT_COUNT",
    },
    "phi_support_forward": {
        "loads": {"load_p": "solver_p"}, "stores": {"store_t": "solver_d"},
        "phi": "phi_support_forward", "loop_limit": "RUN_PARAMETER_0",
    },
    "phi_support_transpose": {
        "loads": {"load_t": "solver_d"}, "stores": {"store_q": "solver_g"},
        "phi": "phi_support_transpose", "loop_limit": "MEASUREMENT_COUNT",
    },
}


MEMORY_OBJECTS = (
    # IDs follow docs/v3/10: 0..15 measurement, 16..31 solver, 40..47 Phi.
    (0, "measurement_y", 128, "D18F14", True, False, False),
    (1, "residual_current", 128, "D18F14", True, True, True),
    (2, "residual_proposed", 128, "D18F14", True, True, True),
    (16, "solver_d", 128, "S27F19", True, True, False),
    (17, "solver_x", 96, "S27F19", True, True, True),
    (18, "solver_g", 96, "S27F19", True, True, False),
    (19, "solver_p", 96, "S27F19", True, True, False),
    (20, "solver_r", 128, "S27F19", True, True, False),
    (21, "iht_x_dense", 1024, "S27F19", True, True, True),
    (22, "iht_gradient_dense", 1024, "S27F19", True, True, False),
    (23, "iht_tentative_dense", 1024, "S27F19", True, True, False),
)


def _enum(enum_type: type, name: str) -> int:
    return int(enum_type[name])


def typed_ssa(ddg: graphs.ArrayRoutineDDG) -> dict[str, Any]:
    if ddg.name not in EDGE_TYPES:
        raise ValueError(f"{ddg.name}: missing edge type table")
    type_table = EDGE_TYPES[ddg.name]
    actual = {edge.value for edge in ddg.dependencies}
    if actual != set(type_table):
        raise ValueError(
            f"{ddg.name}: edge type coverage mismatch "
            f"missing={sorted(actual - set(type_table))} "
            f"stale={sorted(set(type_table) - actual)}")
    values: dict[tuple[str, str], dict[str, Any]] = {}
    operation_inputs = {operation.name: [] for operation in ddg.operations}
    operation_outputs = {operation.name: [] for operation in ddg.operations}
    for edge in ddg.dependencies:
        value_type = VALUE_TYPES[type_table[edge.value]]
        if value_type.fraction > value_type.width:
            raise ValueError(f"{ddg.name}.{edge.value}: invalid fixed-point type")
        key = (edge.source, edge.value)
        value_id = f"{ddg.name}.{edge.source}.{edge.value}"
        if key not in values:
            values[key] = {
                "id": value_id,
                "base_name": edge.value,
                "producer": edge.source,
                "type": asdict(value_type),
                "consumers": [],
                "loop_carried": False,
            }
            operation_outputs[edge.source].append(value_id)
        values[key]["consumers"].append({
            "operation": edge.target,
            "iteration_distance": edge.iteration_distance,
            "transport": edge.route,
        })
        values[key]["loop_carried"] |= edge.iteration_distance > 0
        operation_inputs[edge.target].append(value_id)
    return {
        "schema": "cscgra-v3-typed-ssa-v1",
        "routine": ddg.name,
        "operations": [
            {
                "name": operation.name,
                "operation": operation.operation,
                "inputs": operation_inputs[operation.name],
                "outputs": operation_outputs[operation.name],
            }
            for operation in ddg.operations
        ],
        "values": sorted(values.values(), key=lambda item: item["id"]),
    }


def allocate_local_rf(ddg: graphs.ArrayRoutineDDG, mapping: dict[str, Any],
                      ssa: dict[str, Any]) -> dict[str, Any]:
    placements = mapping["placements"]
    typed = {value["id"]: value for value in ssa["values"]}
    intervals = []
    for edge in ddg.dependencies:
        if edge.route != "same_tile_bundle":
            continue
        value_id = f"{ddg.name}.{edge.source}.{edge.value}"
        value = typed[value_id]
        if value["type"]["width"] > 27 or value["type"]["aggregate"]:
            raise ValueError(f"{value_id}: local RF accepts only scalar values up to 27 bits")
        definition = placements[edge.source]["schedule_time"] + placements[edge.source]["latency"]
        last_use = placements[edge.target]["schedule_time"] + edge.iteration_distance * mapping["candidate_ii"]
        if last_use < definition:
            raise ValueError(f"{value_id}: use precedes definition")
        rotations = max(1, ceil((last_use - definition + 1) / mapping["candidate_ii"]))
        intervals.append({
            "value": value_id, "producer": edge.source, "consumer": edge.target,
            "definition_time": definition, "last_use_time": last_use,
            "rotation_count": rotations,
        })
    active: list[dict[str, Any]] = []
    peak = 0
    for interval in sorted(intervals, key=lambda item: (item["definition_time"], item["value"])):
        active = [item for item in active
                  if item["last_use_time"] >= interval["definition_time"]]
        occupied = {address for item in active for address in item["register_addresses"]}
        free = [address for address in range(8) if address not in occupied]
        if len(free) < interval["rotation_count"]:
            raise ValueError(f"{ddg.name}: local RF pressure exceeds 8x27")
        interval["register_addresses"] = free[:interval["rotation_count"]]
        active.append(interval)
        peak = max(peak, len(occupied) + interval["rotation_count"])
    return {
        "schema": "cscgra-v3-local-rf-allocation-v1",
        "routine": ddg.name,
        "physical_rf": "one 8x27 RF in each PE; addresses mirrored across paired tiles",
        "allocations": intervals,
        "peak_registers": peak,
    }


def allocate_memory(configuration: dict[str, Any]) -> dict[str, Any]:
    bank_count = configuration["memory"]["vector_bank_count"]
    bank_depth = configuration["memory"]["vector_bank_depth"]
    base = 0
    objects = []
    configurations = []
    for config_id, name, count, type_name, readable, writable, atomic in MEMORY_OBJECTS:
        if type_name == "D18F14":
            per_word, element_format, packing = 4, isa.ElementFormat.DATA18, isa.PackingMode.FOUR
        else:
            per_word, element_format, packing = 2, isa.ElementFormat.SOLVER27, isa.PackingMode.TWO
        words_per_bank = ceil(count / (bank_count * per_word))
        if base + words_per_bank > bank_depth:
            raise ValueError(f"{name}: vector scratchpad capacity exceeded")
        memory = isa.MemoryConfiguration(
            base_word_address=base, element_count=count, element_stride_words=1,
            bank_base=0, bank_count_log2=3, bank_mode=isa.BankMode.CYCLIC,
            element_format=element_format, packing_mode=packing,
            read_enable=int(readable), write_enable=int(writable),
            atomic_commit=int(atomic), memory_space=isa.MemorySpace.VECTOR_SCRATCHPAD,
        )
        word = isa.pack_memory_configuration(memory)
        assert isa.unpack_memory_configuration(word) == memory
        objects.append({
            "name": name, "configuration_id": config_id, "value_type": type_name,
            "element_count": count, "base_word_address_per_bank": base,
            "words_per_bank": words_per_bank, "bank_mask": "0xff",
        })
        configurations.append({"id": config_id, "name": name, "word": word})
        base += words_per_bank

    object_by_name = {item["name"]: item for item in objects}
    for config_id, alias_name, source_name, address_phase in (
            (24, "solver_d_even_stripes", "solver_d", 0),
            (25, "solver_d_odd_stripes", "solver_d", 1),
            (26, "solver_r_even_stripes", "solver_r", 0),
            (27, "solver_r_odd_stripes", "solver_r", 1)):
        source = object_by_name[source_name]
        memory = isa.MemoryConfiguration(
            base_word_address=(source["base_word_address_per_bank"] +
                               address_phase),
            element_count=source["element_count"], element_stride_words=2,
            bank_base=0, bank_count_log2=3, bank_mode=isa.BankMode.CYCLIC,
            element_format=isa.ElementFormat.SOLVER27,
            packing_mode=isa.PackingMode.TWO,
            read_enable=1, write_enable=0, atomic_commit=0,
            memory_space=isa.MemorySpace.VECTOR_SCRATCHPAD,
        )
        word = isa.pack_memory_configuration(memory)
        assert isa.unpack_memory_configuration(word) == memory
        configurations.append({"id": config_id, "name": alias_name,
                               "word": word, "alias_of": source_name})

    phi_specs = (
        (40, "phi_dense", isa.BankMode.LINEAR, 1024,
         isa.ElementFormat.RAW32, isa.PackingMode.ONE),
        (41, "phi_support_forward", isa.BankMode.SUPPORT_ROW_MAJOR, 96,
         isa.ElementFormat.INDEX10, isa.PackingMode.SEVEN),
        (42, "phi_support_transpose", isa.BankMode.CLUSTER_LOCAL, 96,
         isa.ElementFormat.INDEX10, isa.PackingMode.SEVEN),
        (43, "phi_support_refill", isa.BankMode.CYCLIC, 96,
         isa.ElementFormat.INDEX10, isa.PackingMode.SEVEN),
        (44, "phi_dense_no_capture", isa.BankMode.LINEAR, 1024,
         isa.ElementFormat.RAW32, isa.PackingMode.ONE),
    )
    for config_id, name, mode, count, element_format, packing in phi_specs:
        memory = isa.MemoryConfiguration(
            base_word_address=0, element_count=count, element_stride_words=1,
            bank_base=0, bank_count_log2=1, bank_mode=mode,
            element_format=element_format, packing_mode=packing,
            read_enable=1, write_enable=0, atomic_commit=0,
            memory_space=isa.MemorySpace.PHI_COORDINATE_STREAM,
        )
        word = isa.pack_memory_configuration(memory)
        assert isa.unpack_memory_configuration(word) == memory
        configurations.append({"id": config_id, "name": name, "word": word})

    return {
        "schema": "cscgra-v3-memory-bank-allocation-v1",
        "bank_count": bank_count,
        "bank_depth_words": bank_depth,
        "allocated_words_per_bank": base,
        "objects": objects,
        "configurations": configurations,
        "forbidden_objects": ["proxy[N]", "rhs_cache[N]"],
    }


def _configuration_ids(memory: dict[str, Any]) -> dict[str, int]:
    return {item["name"]: item["id"] for item in memory["configurations"]}


def _rf_by_operation(rf: dict[str, Any]) -> tuple[dict[str, int], dict[str, int]]:
    writes: dict[str, int] = {}
    reads: dict[str, int] = {}
    for item in rf["allocations"]:
        writes[item["producer"]] = item["register_addresses"][0]
        reads[item["consumer"]] = item["register_addresses"][0]
    return writes, reads


def _tile_context(operation: str, rf_write: int | None, rf_read: int | None) -> isa.TileContext:
    kwargs: dict[str, int] = {"operation": _enum(isa.TileOperation, operation)}
    if operation in {"PHI_SIGN_SCALE", "PHI_ACCUMULATE",
                     "PHI_DATA_ACCUMULATE"}:
        kwargs.update(source_a=isa.OperandSource.EXTERNAL,
                      source_b=isa.OperandSource.ZERO)
    elif operation == "SATURATING_ADD":
        kwargs.update(source_a=isa.OperandSource.LOCAL_RF,
                      source_b=isa.OperandSource.ACCUMULATOR)
    elif operation == "SUB":
        kwargs.update(source_a=isa.OperandSource.EXTERNAL,
                      source_b=isa.OperandSource.EXTERNAL)
    if rf_read is not None:
        kwargs["rf_read_a"] = rf_read
    if rf_write is not None:
        kwargs.update(rf_write_address=rf_write, rf_write_enable=1)
    return isa.TileContext(**kwargs)


def _resource_context(kernel: str, operation: str, store_id: int | None) -> isa.ResourceContext:
    count = {
        "correlation": isa.ResourceCountSource.SIGNAL_LENGTH,
        "residual_update": isa.ResourceCountSource.MEASUREMENT_COUNT,
        "phi_support_forward": isa.ResourceCountSource.ACTIVE_WORK_COUNT,
        "phi_support_transpose": isa.ResourceCountSource.MEASUREMENT_COUNT,
    }[kernel]
    if operation == "REDUCE_SUM":
        output = {
            "correlation": isa.ResourceOutput.SCALAR_0,
            "residual_update": isa.ResourceOutput.PE_SCALAR_BROADCAST,
            "phi_support_forward": isa.ResourceOutput.MEMORY_STREAM,
            "phi_support_transpose": isa.ResourceOutput.MEMORY_STREAM,
        }[kernel]
        return isa.ResourceContext(
            operation=isa.ResourceOperation.REDUCE_SUM,
            input_select=isa.ResourceInput.CLUSTER_REDUCTION,
            output_select=output, configuration_id=store_id or 0,
            count_select=count, lane_mask=0xf, accumulate=1,
            commit_after=int(store_id is not None), wait_for_ready=1,
        )
    if operation == "TOPK_PUSH":
        return isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_PUSH,
            input_select=isa.ResourceInput.GLOBAL_REDUCTION,
            output_select=isa.ResourceOutput.TOPK_STATE,
            count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
            lane_mask=0xf, wait_for_ready=1, event_id=1,
        )
    raise ValueError(f"{kernel}: unsupported emitted resource operation {operation}")


def _loop_limit(kernel: str) -> int:
    return _enum(isa.LoopLimitSource, KERNEL_BINDINGS[kernel]["loop_limit"])


def _encode_kernel_contexts(kernel: str, entry_pc: int,
                            contexts: list[tuple[str, list[isa.TileContext],
                                                 isa.ArrayControlContext,
                                                 isa.StreamContext,
                                                 isa.ResourceContext,
                                                 list[str]]]) -> list[dict[str, Any]]:
    encoded = []
    for offset, (region, tiles, control, stream, resource, semantic_ops) in enumerate(contexts):
        isa.validate_context_bundle(control, stream, resource)
        tile_words = [isa.pack_tile(item) for item in tiles]
        control_word = isa.pack_array_control(control)
        stream_word = isa.pack_stream(stream)
        resource_word = isa.pack_resource(resource)
        if [isa.unpack_tile(word) for word in tile_words] != tiles:
            raise ValueError(f"{kernel}: tile context round-trip failed")
        if isa.unpack_array_control(control_word) != control:
            raise ValueError(f"{kernel}: control context round-trip failed")
        if isa.unpack_stream(stream_word) != stream:
            raise ValueError(f"{kernel}: stream context round-trip failed")
        if isa.unpack_resource(resource_word) != resource:
            raise ValueError(f"{kernel}: resource context round-trip failed")
        encoded.append({
            "pc": entry_pc + offset, "region": region,
            "semantic_operations": semantic_ops, "tile_words": tile_words,
            "array_control_word": control_word, "stream_word": stream_word,
            "resource_word": resource_word,
        })
    return encoded


def restricted_refinement_resource_segments(
) -> list[tuple[str, list[tuple[str, isa.ResourceContext]]]]:
    def pair(stage: str, operation: isa.ResourceOperation,
             input_select: isa.ResourceInput,
             output_select: isa.ResourceOutput,
             count_select: isa.ResourceCountSource,
             configuration_id: int = 0,
             clear_before: int = 0,
             accumulate: int = 0,
             commit_after: int = 0,
             event_id: int = 0) -> list[tuple[str, isa.ResourceContext]]:
        return [
            (f"{stage}_issue", isa.ResourceContext(
                operation=operation, input_select=input_select,
                output_select=output_select, configuration_id=configuration_id,
                count_select=count_select, lane_mask=0xf,
                clear_before=clear_before, accumulate=accumulate,
                commit_after=commit_after, wait_for_ready=1, event_id=event_id)),
            (f"{stage}_wait", isa.ResourceContext(
                operation=operation,
                output_select=(isa.ResourceOutput.EVENT
                               if operation == isa.ResourceOperation.REFINEMENT_CHECK
                               else isa.ResourceOutput.DISCARD),
                wait_for_result=1, event_id=event_id)),
        ]

    return [
        ("restricted_refinement_initialize", []),
        ("restricted_refinement_pre_transpose", [
            *pair("alpha", isa.ResourceOperation.SCALAR_DIVIDE,
                  isa.ResourceInput.SCALAR_0,
                  isa.ResourceOutput.SCALAR_1,
                  isa.ResourceCountSource.ACTIVE_WORK_COUNT),
            *pair("update_x", isa.ResourceOperation.SHARED_VECTOR_AXPY,
                  isa.ResourceInput.SCALAR_1,
                  isa.ResourceOutput.MEMORY_STREAM,
                  isa.ResourceCountSource.ACTIVE_WORK_COUNT),
            *pair("update_r", isa.ResourceOperation.SHARED_VECTOR_AXPY,
                  isa.ResourceInput.SCALAR_1,
                  isa.ResourceOutput.MEMORY_STREAM,
                  isa.ResourceCountSource.MEASUREMENT_COUNT,
                  configuration_id=1),
        ]),
        ("restricted_refinement_certificate", [
            *pair("post_d18_check", isa.ResourceOperation.REFINEMENT_CHECK,
                  isa.ResourceInput.SCALAR_0,
                  isa.ResourceOutput.EVENT,
                  isa.ResourceCountSource.ACTIVE_SUPPORT_COUNT,
                  event_id=1),
        ]),
        ("restricted_refinement_continuation", [
            *pair("beta", isa.ResourceOperation.SCALAR_DIVIDE,
                  isa.ResourceInput.SCALAR_1,
                  isa.ResourceOutput.SCALAR_0,
                  isa.ResourceCountSource.ACTIVE_WORK_COUNT),
            *pair("update_p", isa.ResourceOperation.SHARED_VECTOR_AXPY,
                  isa.ResourceInput.SCALAR_0,
                  isa.ResourceOutput.MEMORY_STREAM,
                  isa.ResourceCountSource.ACTIVE_WORK_COUNT),
        ]),
        ("restricted_refinement_restart_residual", []),
        ("restricted_refinement_restart_direction", []),
    ]

def _emit_omp_support_append(entry_pc: int) -> dict[str, Any]:
    blank_tiles = [isa.TileContext()] * 16
    contexts = [
        ("append_issue", blank_tiles,
         isa.ArrayControlContext(cluster_enable_mask=0b11),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_APPEND,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=0, wait_for_ready=1, event_id=3),
         ["append_top_candidate"]),
        ("append_wait", blank_tiles,
         isa.ArrayControlContext(cluster_enable_mask=0b11),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_APPEND,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=3), []),
        ("commit_issue", blank_tiles,
         isa.ArrayControlContext(cluster_enable_mask=0b11),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=4), ["commit_support"]),
        ("commit_wait", blank_tiles,
         isa.ArrayControlContext(cluster_enable_mask=0b11),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=4), []),
        ("epilogue", blank_tiles,
         isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=0b11, routine_done=1,
             safe_abort_point=1, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext(), ["complete"]),
    ]
    encoded = _encode_kernel_contexts(
        "omp_support_append_commit", entry_pc, contexts)
    return {
        "kernel": "omp_support_append_commit",
        "entry_pc": entry_pc,
        "context_count": len(encoded),
        "body_ii": 1,
        "contexts": encoded,
        "operator_contract": {
            "candidate_slot": 0,
            "selection_source": "correlation_topk_epoch",
            "support_update": "append_then_commit",
            "algorithm_decode_in_hardware": False,
        },
    }


def _emit_iht_dense_correlation(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    accumulate = [_tile_context("PHI_ACCUMULATE", None, None)] * 16
    clear = [isa.TileContext(operation=isa.TileOperation.ACCUMULATOR_CLEAR)] * 16
    config_ids = _configuration_ids(memory)
    middle_setup_pc = entry_pc + 5
    drain_pc = entry_pc + 9
    reduction_issue = isa.ResourceContext(
        operation=isa.ResourceOperation.REDUCE_SUM,
        input_select=isa.ResourceInput.CLUSTER_REDUCTION,
        output_select=isa.ResourceOutput.MEMORY_STREAM,
        configuration_id=config_ids["iht_gradient_dense"], lane_mask=15,
        clear_before=1, accumulate=1, commit_after=1, wait_for_ready=1)
    reduction_wait = isa.ResourceContext(
        operation=isa.ResourceOperation.REDUCE_SUM,
        output_select=isa.ResourceOutput.MEMORY_STREAM,
        wait_for_result=1)
    column_setup = isa.ResourceContext(
        configuration_id=1, stream_boundary=isa.StreamBoundary.FIRST)
    body_stream = isa.StreamContext(
        vector_read_a_enable=1,
        vector_configuration_a=config_ids["residual_current"],
        external_a_select=isa.ExternalStreamSource.VECTOR_A,
        phi_command=isa.PhiStreamCommand.CONSUME,
        advance_vector_streams=1, stall_on_input=1)
    write_stream = isa.StreamContext(
        vector_write_enable=1,
        vector_configuration_write=config_ids["iht_gradient_dense"],
        advance_vector_streams=1, stall_on_output=1)
    contexts = [
        ("prologue", blank, isa.ArrayControlContext(
            loop_counter_select=1, loop_counter_reset=1, cluster_enable_mask=3),
        isa.StreamContext(phi_command=isa.PhiStreamCommand.START,
            phi_configuration_id=config_ids["phi_dense_no_capture"],
            stall_on_input=1),
         isa.ResourceContext(), ["start"]),
        ("column_setup", clear, isa.ArrayControlContext(
            loop_counter_select=0, loop_counter_reset=1, cluster_enable_mask=3),
         isa.StreamContext(), column_setup, ["column_setup"]),
        ("row_block_body", accumulate, isa.ArrayControlContext(
            next_pc=entry_pc + 2, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
            loop_counter_select=0, loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_0,
            cluster_enable_mask=3), body_stream, isa.ResourceContext(),
         ["correlate"]),
        ("prime_reduction_issue", blank, isa.ArrayControlContext(
            next_pc=middle_setup_pc, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
            loop_counter_select=1, loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH,
            cluster_enable_mask=3), isa.StreamContext(), reduction_issue,
         ["reduce"]),
        ("single_column_drain_jump", blank, isa.ArrayControlContext(
            next_pc=drain_pc, next_pc_mode=isa.NextPcMode.JUMP,
            cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(), []),
        ("middle_column_setup", clear, isa.ArrayControlContext(
            loop_counter_select=0, loop_counter_reset=1, cluster_enable_mask=3),
         isa.StreamContext(), column_setup, ["column_setup"]),
        ("middle_row_block_body", accumulate, isa.ArrayControlContext(
            next_pc=entry_pc + 6, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
            loop_counter_select=0, loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_0,
            cluster_enable_mask=3), body_stream, isa.ResourceContext(),
         ["correlate"]),
        ("middle_reduction_issue", blank, isa.ArrayControlContext(
            cluster_enable_mask=3), isa.StreamContext(), reduction_issue,
         ["reduce"]),
        ("middle_wait_writeback", blank, isa.ArrayControlContext(
            next_pc=middle_setup_pc, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
            loop_counter_select=1, loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH,
            cluster_enable_mask=3), write_stream, reduction_wait,
         ["normalize", "store_gradient"]),
        ("drain_wait_writeback", blank, isa.ArrayControlContext(
            cluster_enable_mask=3), write_stream, reduction_wait,
         ["normalize", "store_gradient"]),
        ("normalizer_drain_pack", blank, isa.ArrayControlContext(
            cluster_enable_mask=3), write_stream, isa.ResourceContext(),
         ["store_gradient"]),
        ("normalizer_drain_final", blank, isa.ArrayControlContext(
            cluster_enable_mask=3), write_stream, isa.ResourceContext(),
         ["normalize", "store_gradient"]),
        ("epilogue", blank, isa.ArrayControlContext(
            next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE, cluster_enable_mask=3,
            routine_done=1, safe_abort_point=1, guaranteed_commit=1),
         isa.StreamContext(phi_command=isa.PhiStreamCommand.STOP),
         isa.ResourceContext(), ["complete"]),
    ]
    encoded = _encode_kernel_contexts("iht_dense_correlation", entry_pc, contexts)
    return {"kernel": "iht_dense_correlation", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 1,
        "loop_axis": "signal_column", "completion_predicate_select": 2,
        "operator_contract": {"candidate_output": "iht_gradient_dense",
            "column_pipeline": "prime_middle_double_drain",
            "hardware_execution_ready": True, "execution_blockers": []},
        "contexts": encoded}


def _emit_iht_vector_axpy(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    ids = _configuration_ids(memory)
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
            loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=7,
            stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1, vector_read_b_enable=1,
            vector_configuration_a=ids["iht_x_dense"],
            vector_configuration_b=ids["iht_gradient_dense"],
            advance_vector_streams=1, stall_on_input=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_AXPY,
            input_select=isa.ResourceInput.SCALAR_0,
            output_select=isa.ResourceOutput.MEMORY_STREAM,
            count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
            lane_mask=15, wait_for_ready=1), ["vector_axpy"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
            next_pc_mode=isa.NextPcMode.COUNTED_LOOP, loop_counter_select=0,
            loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH_STRIPES_16,
            cluster_enable_mask=3), isa.StreamContext(vector_write_enable=1,
            vector_configuration_write=ids["iht_tentative_dense"],
            advance_vector_streams=1, stall_on_output=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_AXPY,
            wait_for_result=1), ["store_tentative"]),
        ("epilogue", blank, isa.ArrayControlContext(
            next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE, cluster_enable_mask=3,
            routine_done=1, safe_abort_point=1, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext(), ["complete"]),
    ]
    encoded = _encode_kernel_contexts("vector_axpy", entry_pc, contexts)
    return {"kernel": "vector_axpy", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 2,
        "loop_axis": "signal_stripe_16", "completion_predicate_select": 2,
        "operator_contract": {"step_size_source": "scalar_0",
            "hardware_execution_ready": True, "execution_blockers": []},
        "contexts": encoded}


def _emit_iht_support_replace(entry_pc: int, memory: dict[str, Any],
                              kernel_name: str = "iht_support_replace",
                              defer_activation: bool = False) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    refill_id = _configuration_ids(memory)["phi_support_refill"]
    support_configuration_id = int(defer_activation) | 2
    contexts = [
        ("clear_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_CLEAR,
             configuration_id=support_configuration_id,
             wait_for_ready=1, event_id=1), ["clear_proposal"]),
        ("clear_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_CLEAR,
             wait_for_result=1, event_id=1), ["clear_wait"]),
        ("replace_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             input_select=isa.ResourceInput.MEMORY_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=support_configuration_id,
             wait_for_ready=1, event_id=2), ["replace_support"]),
        ("replace_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=2), ["replace_wait"]),
        ("refill_prepare_issue", blank,
         isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_COMMIT,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=support_configuration_id,
             wait_for_ready=1, event_id=3), ["prepare_refill"]),
        ("refill_prepare_wait", blank,
         isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=3), ["prepare_wait"]),
        ("refill_start", blank,
         isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(phi_command=isa.PhiStreamCommand.START,
             phi_configuration_id=refill_id, stall_on_input=1),
         isa.ResourceContext(), ["start_refill"]),
        ("finalize_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=support_configuration_id,
             wait_for_ready=1, event_id=4), ["finalize"]),
        ("finalize_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=4), ["finalize_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1),
         isa.StreamContext(phi_command=isa.PhiStreamCommand.STOP),
         isa.ResourceContext(),
          ["complete"]),
    ]
    encoded = _encode_kernel_contexts(kernel_name, entry_pc, contexts)
    return {"kernel": kernel_name, "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "operator_contract": {
            "support_update": "clear_union_prepare_refill_finalize",
            "coefficient_source": "topk_candidate_value",
            "phi_refill_source": "proposal_support_stream",
            "activation": "deferred" if defer_activation else "immediate",
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}


def _emit_iht_dense_rebuild(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    ids = _configuration_ids(memory)
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
             loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=5,
             stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
             vector_configuration_a=ids["iht_tentative_dense"],
             advance_vector_streams=1, stall_on_input=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=2,
             count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
             wait_for_ready=1), ["masked_copy"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
             next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
             loop_counter_select=0, loop_counter_increment=1,
             loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH_STRIPES_16,
             cluster_enable_mask=3),
         isa.StreamContext(vector_write_enable=1,
             vector_configuration_write=ids["iht_x_dense"],
             advance_vector_streams=1, stall_on_output=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=2,
             wait_for_result=1), ["store_pruned_dense"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("iht_dense_rebuild", entry_pc, contexts)
    return {"kernel": "iht_dense_rebuild", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 2,
        "operator_contract": {"mask_source": "active_support_bitmap",
            "nonselected_value": 0, "hardware_algorithm_decode": False},
        "contexts": encoded}


def _emit_iht_support_pack(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    ids = _configuration_ids(memory)
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
             loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=5,
             stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
             vector_configuration_a=ids["iht_x_dense"],
             advance_vector_streams=1, stall_on_input=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=1,
             count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
             wait_for_ready=1), ["pack_support_coefficients"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
             next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
             loop_counter_select=0, loop_counter_increment=1,
             loop_limit_select=isa.LoopLimitSource.ACTIVE_WORK_STRIPES_16,
             cluster_enable_mask=3),
         isa.StreamContext(vector_write_enable=1,
             vector_configuration_write=ids["solver_x"],
             advance_vector_streams=1, stall_on_output=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=1, wait_for_result=1), ["store_solver_x"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("iht_support_pack", entry_pc, contexts)
    return {"kernel": "iht_support_pack", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 2,
        "operator_contract": {"coefficient_source": "active_support_slots",
            "destination": "solver_x", "hardware_algorithm_decode": False},
        "contexts": encoded}

def _emit_htp_support_coefficient_scatter(
        entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    solver_x = _configuration_ids(memory)["solver_x"]
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
             loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=1,
             stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
             vector_configuration_a=solver_x, advance_vector_streams=1,
             stall_on_input=1), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_SCATTER,
             input_select=isa.ResourceInput.MEMORY_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
             wait_for_ready=1, event_id=1),
         ["scatter_refined_coefficient"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
             next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
             loop_counter_select=0, loop_counter_increment=1,
             loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_1,
             cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_SCATTER,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=1), ["scatter_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts(
        "htp_support_coefficient_scatter", entry_pc, contexts)
    return {"kernel": "htp_support_coefficient_scatter",
        "entry_pc": entry_pc, "context_count": len(encoded), "body_ii": 2,
        "operator_contract": {
            "source": "solver_x",
            "destination": "active_support_coefficients",
            "slot_order": "stream_element_index",
            "element_count_source": "run_parameter_1",
            "opens_support_proposal": False,
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}

def _emit_htp_dense_scatter(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    ids = _configuration_ids(memory)
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
             loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=5,
             stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
             vector_configuration_a=ids["iht_x_dense"],
             advance_vector_streams=1, stall_on_input=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=2,
             count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
             wait_for_ready=1), ["scatter_support_dense"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
             next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
             loop_counter_select=0, loop_counter_increment=1,
             loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH_STRIPES_16,
             cluster_enable_mask=3),
         isa.StreamContext(vector_write_enable=1,
             vector_configuration_write=ids["iht_x_dense"],
             advance_vector_streams=1, stall_on_output=1),
         isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=2, wait_for_result=1), ["store_refined_dense"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("htp_dense_scatter", entry_pc, contexts)
    return {"kernel": "htp_dense_scatter", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 2,
        "operator_contract": {
            "index_source": "active_support_indices",
            "coefficient_source": "active_support_coefficients",
            "destination": "iht_x_dense",
            "nonselected_value": 0,
            "configuration_id": 2,
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}


def _emit_vector_topk(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    source = _configuration_ids(memory)["iht_tentative_dense"]
    contexts = [
        ("push_issue", blank, isa.ArrayControlContext(next_pc=entry_pc,
            next_pc_mode=isa.NextPcMode.COUNTED_LOOP, loop_counter_select=0,
            loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH,
            cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
            vector_configuration_a=source, advance_vector_streams=1,
            stall_on_input=1), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_PUSH,
            input_select=isa.ResourceInput.MEMORY_STREAM,
            output_select=isa.ResourceOutput.TOPK_STATE,
            count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
            wait_for_ready=1, event_id=9), ["topk_stream"]),
        ("push_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_PUSH,
            output_select=isa.ResourceOutput.TOPK_STATE,
            wait_for_result=1, event_id=9), ["topk_wait"]),
        ("commit_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_COMMIT,
            output_select=isa.ResourceOutput.TOPK_STATE,
            wait_for_ready=1, event_id=2), ["commit"]),
        ("commit_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_COMMIT,
            output_select=isa.ResourceOutput.TOPK_STATE,
            wait_for_result=1, event_id=2), ["commit_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
            next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE, cluster_enable_mask=3,
            routine_done=1, safe_abort_point=1, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext(), ["complete"]),
    ]
    encoded = _encode_kernel_contexts("topk_stream", entry_pc, contexts)
    return {"kernel": "topk_stream", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "loop_axis": "signal_element", "completion_predicate_select": 2,
        "operator_contract": {"candidate_source": "memory_stream",
            "support_exclusion": False, "retained_count": "selection_k",
            "hardware_execution_ready": True, "execution_blockers": []},
        "contexts": encoded}


def _emit_cosamp_union_3k(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    contexts = [
        ("union_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             input_select=isa.ResourceInput.GLOBAL_REDUCTION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=1), ["union_active_k_candidate_2k"]),
        ("union_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=1), ["union_wait"]),
        ("commit_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=2), ["commit_work_support"]),
        ("commit_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=2), ["commit_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("cosamp_union_3k", entry_pc, contexts)
    return {"kernel": "cosamp_union_3k", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "operator_contract": {
            "candidate_source": "correlation_top2k_epoch",
            "support_update": "active_union_candidates_then_commit",
            "maximum_work_support": "three_times_sparsity",
            "next_run_parameter_1": "resident_work_count",
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}


def _emit_cosamp_coefficient_topk(
        entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    source = _configuration_ids(memory)["solver_x"]
    contexts = [
        ("push_issue", blank, isa.ArrayControlContext(next_pc=entry_pc,
            next_pc_mode=isa.NextPcMode.COUNTED_LOOP, loop_counter_select=0,
            loop_counter_increment=1,
            loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_1,
            cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
            vector_configuration_a=source, advance_vector_streams=1,
            stall_on_input=1), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_PUSH,
            input_select=isa.ResourceInput.MEMORY_STREAM,
            output_select=isa.ResourceOutput.TOPK_STATE,
            configuration_id=1,
            count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
            wait_for_ready=1, event_id=9), ["coefficient_topk"]),
        ("push_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_PUSH,
            output_select=isa.ResourceOutput.TOPK_STATE,
            wait_for_result=1, event_id=9), ["coefficient_topk_wait"]),
        ("commit_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_COMMIT,
            output_select=isa.ResourceOutput.TOPK_STATE,
            wait_for_ready=1, event_id=2), ["commit"]),
        ("commit_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_COMMIT,
            output_select=isa.ResourceOutput.TOPK_STATE,
            wait_for_result=1, event_id=2), ["commit_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
            next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE, cluster_enable_mask=3,
            routine_done=1, safe_abort_point=1, guaranteed_commit=1),
         isa.StreamContext(), isa.ResourceContext(), ["complete"]),
    ]
    encoded = _encode_kernel_contexts(
        "cosamp_coefficient_topk", entry_pc, contexts)
    return {"kernel": "cosamp_coefficient_topk", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "loop_axis": "active_work_slot",
        "operator_contract": {
            "candidate_source": "solver_x",
            "candidate_index": "active_support_atom_at_stream_slot",
            "retained_count": "selection_k",
            "configuration_controlled_slot_remap": True,
            "loop_count_source": "resident_work_count_via_run_parameter_1",
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}


def _emit_cosamp_prune_support(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    segment = _emit_iht_support_replace(entry_pc, memory)
    segment["kernel"] = "cosamp_prune_support"
    segment["operator_contract"] = {
        "support_update": "clear_union_selected_coefficients_refill_finalize",
        "coefficient_source": "coefficient_topk_candidate_value",
        "atom_source": "coefficient_topk_slot_remap",
        "phi_refill_source": "proposal_support_stream",
        "hardware_algorithm_decode": False,
    }
    for context in segment["contexts"]:
        context["kernel"] = "cosamp_prune_support"
    return segment

def _emit_sp_union_2k(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    contexts = [
        ("union_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             input_select=isa.ResourceInput.GLOBAL_REDUCTION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=1), ["union_active_k_candidate_k"]),
        ("union_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=1), ["union_wait"]),
        ("prepare_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=1, wait_for_ready=1, event_id=2),
         ["prepare_proposal_view"]),
        ("prepare_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=1, wait_for_result=1, event_id=2),
         ["prepare_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("sp_union_2k", entry_pc, contexts)
    return {"kernel": "sp_union_2k", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "operator_contract": {
            "candidate_source": "correlation_topk_epoch",
            "support_update": "active_union_candidates_prepare_without_swap",
            "maximum_work_support": "two_times_sparsity",
            "proposal_view_persists": True,
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}

def _emit_sp_prune_support(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    segment = _emit_iht_support_replace(
        entry_pc, memory, "sp_prune_support", defer_activation=True)
    segment["operator_contract"].update({
        "support_update": "replace_proposal_k_refill_without_swap",
        "coefficient_source": "coefficient_topk_candidate_value",
        "atom_source": "coefficient_topk_slot_remap",
        "proposal_view_persists": True,
    })
    return segment

def _emit_sp_proposal_coefficient_scatter(
        entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    solver_x = _configuration_ids(memory)["solver_x"]
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
             loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=1,
             stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(vector_read_a_enable=1,
             vector_configuration_a=solver_x, advance_vector_streams=1,
             stall_on_input=1), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_SCATTER,
             input_select=isa.ResourceInput.MEMORY_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=1,
             count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
             wait_for_ready=1, event_id=1),
         ["scatter_proposal_coefficient"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
             next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
             loop_counter_select=0, loop_counter_increment=1,
             loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_1,
             cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_SCATTER,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=1, wait_for_result=1, event_id=1),
         ["scatter_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts(
        "sp_proposal_coefficient_scatter", entry_pc, contexts)
    return {"kernel": "sp_proposal_coefficient_scatter",
        "entry_pc": entry_pc, "context_count": len(encoded), "body_ii": 2,
        "operator_contract": {
            "source": "solver_x",
            "destination": "proposal_support_coefficients",
            "element_count_source": "run_parameter_1",
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}

def _emit_sp_support_resolution(entry_pc: int, operation: isa.ResourceOperation,
                                kernel_name: str) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    contexts = [
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(operation=operation,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=1), [kernel_name]),
        ("wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(operation=operation,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=1), [f"{kernel_name}_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts(kernel_name, entry_pc, contexts)
    return {"kernel": kernel_name, "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "operator_contract": {
            "support_resolution": operation.name.lower(),
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}

def _emit_sp_accept(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    del memory
    return _emit_sp_support_resolution(
        entry_pc, isa.ResourceOperation.SUPPORT_COMMIT, "sp_accept")

def _emit_sp_rollback(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    del memory
    return _emit_sp_support_resolution(
        entry_pc, isa.ResourceOperation.SUPPORT_ROLLBACK, "sp_rollback")

def _emit_gp_top1_stream(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    emitted = _emit_vector_topk(entry_pc, memory)
    ids = _configuration_ids(memory)
    for context in emitted["contexts"]:
        stream = isa.unpack_stream(context["stream_word"])
        if stream.vector_read_a_enable:
            stream = isa.StreamContext(**{
                **asdict(stream),
                "vector_configuration_a": ids["iht_gradient_dense"],
            })
            context["stream_word"] = isa.pack_stream(stream)
        resource = isa.unpack_resource(context["resource_word"])
        if (resource.operation == isa.ResourceOperation.TOPK_PUSH and
                resource.wait_for_ready):
            resource = isa.ResourceContext(**{
                **asdict(resource), "configuration_id": 2})
            context["resource_word"] = isa.pack_resource(resource)
    emitted["kernel"] = "gp_top1_stream"
    emitted["operator_contract"] = {
        **emitted["operator_contract"],
        "candidate_source": "iht_gradient_dense",
        "support_exclusion": False,
        "active_support_gradient_capture": True,
        "configuration_id": 2,
        "hardware_algorithm_decode": False,
    }
    return emitted

def _emit_gomp_top2_stream(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    emitted = _emit_gp_top1_stream(entry_pc, memory)
    for context in emitted["contexts"]:
        resource = isa.unpack_resource(context["resource_word"])
        if (resource.operation == isa.ResourceOperation.TOPK_PUSH and
                resource.wait_for_ready):
            resource = isa.ResourceContext(**{
                **asdict(resource),
                "input_select": isa.ResourceInput.MEMORY_STREAM,
                "configuration_id": 0x20 | 2})
            context["resource_word"] = isa.pack_resource(resource)
    emitted["kernel"] = "gomp_top2_stream"
    emitted["operator_contract"] = {
        **emitted["operator_contract"],
        "retained_count": 2,
        "selection_count_source": "resource_configuration_literal",
        "support_exclusion": True,
        "active_support_gradient_capture": True,
        "configuration_id": 0x20 | 2,
    }
    return emitted

def _emit_gomp_support_union(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    refill_id = _configuration_ids(memory)["phi_support_refill"]
    contexts = [
        ("union_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             input_select=isa.ResourceInput.GLOBAL_REDUCTION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=1), ["union_active_support_top2"]),
        ("union_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_UNION,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=1), ["union_wait"]),
        ("refill_prepare_issue", blank,
         isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_COMMIT,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=2), ["prepare_refill"]),
        ("refill_prepare_wait", blank,
         isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=2), ["prepare_wait"]),
        ("refill_start", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(phi_command=isa.PhiStreamCommand.START,
             phi_configuration_id=refill_id, stall_on_input=1),
         isa.ResourceContext(), ["start_refill"]),
        ("finalize_issue", blank,
         isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=3), ["finalize"]),
        ("finalize_wait", blank,
         isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=3), ["finalize_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1),
         isa.StreamContext(phi_command=isa.PhiStreamCommand.STOP),
         isa.ResourceContext(), ["complete"]),
    ]
    encoded = _encode_kernel_contexts("gomp_support_union", entry_pc, contexts)
    return {"kernel": "gomp_support_union", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None, "contexts": encoded,
        "operator_contract": {
        "candidate_source": "gomp_top2_epoch",
        "support_update": "active_union_prepare_refill_finalize",
        "maximum_work_support": "active_support_plus_two",
        "phi_cache_source": "proposal_support_refill",
        "hardware_algorithm_decode": False,
    }}

def _emit_gp_support_policy(entry_pc: int, memory: dict[str, Any],
                            refill_entry_pc: int) -> dict[str, Any]:
    del memory
    blank = [isa.TileContext()] * 16
    contexts = [
        ("append_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_APPEND,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             configuration_id=0, wait_for_ready=1, event_id=1),
         ["append_or_reselect_zero_x"]),
        ("append_wait", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_APPEND,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=1), ["append_wait"]),
        ("commit_issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_ready=1, event_id=2), ["commit_support"]),
        ("commit_wait", blank, isa.ArrayControlContext(
             next_pc=refill_entry_pc, next_pc_mode=isa.NextPcMode.JUMP,
             cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SUPPORT_COMMIT,
             output_select=isa.ResourceOutput.SUPPORT_STREAM,
             wait_for_result=1, event_id=2), ["commit_wait"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("gp_support_policy", entry_pc, contexts)
    return {"kernel": "gp_support_policy", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": None,
        "operator_contract": {
            "reselection": "preserve_count_and_existing_x",
            "new_atom_x": 0,
            "new_atom_gradient_sideband": True,
            "hardware_algorithm_decode": False,
        }, "contexts": encoded}

def _emit_gp_direction_pack(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank = [isa.TileContext()] * 16
    solver_p = _configuration_ids(memory)["solver_p"]
    contexts = [
        ("restart", blank, isa.ArrayControlContext(loop_counter_select=0,
             loop_counter_reset=1, cluster_enable_mask=3), isa.StreamContext(),
         isa.ResourceContext(configuration_id=5,
             stream_boundary=isa.StreamBoundary.FIRST), ["restart"]),
        ("issue", blank, isa.ArrayControlContext(cluster_enable_mask=3),
         isa.StreamContext(), isa.ResourceContext(
             operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=3,
             count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
             wait_for_ready=1), ["pack_active_gradients"]),
        ("wait", blank, isa.ArrayControlContext(next_pc=entry_pc + 1,
             next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
             loop_counter_select=0, loop_counter_increment=1,
             loop_limit_select=isa.LoopLimitSource.ACTIVE_WORK_STRIPES_16,
             cluster_enable_mask=3), isa.StreamContext(vector_write_enable=1,
             vector_configuration_write=solver_p, advance_vector_streams=1,
             stall_on_output=1), isa.ResourceContext(
             operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
             input_select=isa.ResourceInput.SUPPORT_STREAM,
             output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=3, wait_for_result=1), ["store_direction"]),
        ("epilogue", blank, isa.ArrayControlContext(
             next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
             cluster_enable_mask=3, routine_done=1, safe_abort_point=1,
             guaranteed_commit=1), isa.StreamContext(), isa.ResourceContext(),
         ["complete"]),
    ]
    encoded = _encode_kernel_contexts("gp_direction_pack", entry_pc, contexts)
    return {"kernel": "gp_direction_pack", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 2,
        "operator_contract": {"source": "captured_active_gradients",
            "destination": "solver_p", "hardware_algorithm_decode": False},
        "contexts": encoded}

def _emit_mp_direction_pack(entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    emitted = _emit_gp_direction_pack(entry_pc, memory)
    for context in emitted["contexts"]:
        resource = isa.unpack_resource(context["resource_word"])
        if resource.operation == isa.ResourceOperation.SHARED_VECTOR_COPY:
            resource = isa.ResourceContext(**{
                **asdict(resource), "configuration_id": 4})
            context["resource_word"] = isa.pack_resource(resource)
    emitted["kernel"] = "mp_direction_pack"
    emitted["operator_contract"] = {
        **emitted["operator_contract"],
        "source": "selected_active_gradient",
        "selection": "top1_atom_one_hot_over_active_support",
    }
    return emitted


def _emit_htp_fresh_refinement_marker(
        entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    del memory
    blank_tiles = [isa.TileContext()] * 16
    contexts = [(
        "mark_fresh_refinement",
        blank_tiles,
        isa.ArrayControlContext(
            cluster_enable_mask=0b11,
            routine_done=1,
            safe_abort_point=1),
        isa.StreamContext(),
        isa.ResourceContext(
            configuration_id=6,
            stream_boundary=isa.StreamBoundary.FIRST),
        ["fresh_zero_estimate_measurement_residual"],
    )]
    encoded = _encode_kernel_contexts(
        "htp_fresh_refinement_marker", entry_pc, contexts)
    return {
        "kernel": "htp_fresh_refinement_marker",
        "entry_pc": entry_pc,
        "context_count": len(encoded),
        "body_ii": None,
        "loop_axis": None,
        "operator_contract": {
            "next_refinement_initial_estimate": "zero",
            "next_refinement_initial_residual": "measurement_y",
            "hardware_algorithm_decode": False,
        },
        "contexts": encoded,
    }


def _emit_restricted_refinement_segment(
        name: str, entry_pc: int, memory: dict[str, Any]) -> dict[str, Any]:
    blank_tiles = [isa.TileContext()] * 16
    config_ids = _configuration_ids(memory)
    contexts: list[tuple[str, list[isa.TileContext], isa.ArrayControlContext,
                         isa.StreamContext, isa.ResourceContext, list[str]]] = []

    def add(region: str, control: isa.ArrayControlContext,
            stream: isa.StreamContext, resource: isa.ResourceContext,
            semantic: str) -> None:
        contexts.append((region, blank_tiles, control, stream, resource, [semantic]))

    def restart(stage: str, mask: int, counter: int) -> None:
        add(f"{stage}_restart", isa.ArrayControlContext(
                loop_counter_select=counter, loop_counter_reset=1,
                cluster_enable_mask=0b11), isa.StreamContext(),
            isa.ResourceContext(configuration_id=mask,
                stream_boundary=isa.StreamBoundary.FIRST,
                wait_for_ready=1), stage)

    def norm(stage: str, configuration_id: int, output: isa.ResourceOutput,
             count: isa.ResourceCountSource, limit: isa.LoopLimitSource,
             counter: int) -> None:
        base_pc = entry_pc + len(contexts)
        next_pc = base_pc + 6
        issue_stream = isa.StreamContext(
            vector_read_a_enable=1,
            vector_configuration_a=configuration_id,
            advance_vector_streams=1, stall_on_input=1)
        restart(stage, 1, counter)
        add(f"{stage}_first_issue", isa.ArrayControlContext(
                cluster_enable_mask=0b11), issue_stream,
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=output, count_select=count, lane_mask=0xf,
                clear_before=1, accumulate=1, commit_after=1,
                wait_for_ready=1), stage)
        add(f"{stage}_first_wait", isa.ArrayControlContext(
                next_pc=base_pc + 4, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=limit, cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                wait_for_result=1), stage)
        add(f"{stage}_single_done", isa.ArrayControlContext(
                next_pc=next_pc, next_pc_mode=isa.NextPcMode.JUMP,
                cluster_enable_mask=0b11, guaranteed_commit=1),
            isa.StreamContext(), isa.ResourceContext(), stage)
        add(f"{stage}_continue_issue", isa.ArrayControlContext(
                cluster_enable_mask=0b11), issue_stream,
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=output, count_select=count, lane_mask=0xf,
                accumulate=1, commit_after=1, wait_for_ready=1), stage)
        add(f"{stage}_continue_wait", isa.ArrayControlContext(
                next_pc=base_pc + 4, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=limit, cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                wait_for_result=1), stage)

    def dot(stage: str, configuration_a: int, configuration_b: int,
            output: isa.ResourceOutput, count: isa.ResourceCountSource,
            limit: isa.LoopLimitSource, counter: int) -> None:
        base_pc = entry_pc + len(contexts)
        next_pc = base_pc + 6
        issue_stream = isa.StreamContext(
            vector_read_a_enable=1, vector_read_b_enable=1,
            vector_configuration_a=configuration_a,
            vector_configuration_b=configuration_b,
            advance_vector_streams=1, stall_on_input=1)
        restart(stage, 3, counter)
        add(f"{stage}_first_issue", isa.ArrayControlContext(
                cluster_enable_mask=0b11), issue_stream,
            isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_DOT,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=output, count_select=count, lane_mask=0xf,
                clear_before=1, accumulate=1, commit_after=1,
                wait_for_ready=1), stage)
        add(f"{stage}_first_wait", isa.ArrayControlContext(
                next_pc=base_pc + 4, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=limit, cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_DOT,
                wait_for_result=1), stage)
        add(f"{stage}_single_done", isa.ArrayControlContext(
                next_pc=next_pc, next_pc_mode=isa.NextPcMode.JUMP,
                cluster_enable_mask=0b11, guaranteed_commit=1),
            isa.StreamContext(), isa.ResourceContext(), stage)
        add(f"{stage}_continue_issue", isa.ArrayControlContext(
                cluster_enable_mask=0b11), issue_stream,
            isa.ResourceContext(operation=isa.ResourceOperation.SHARED_VECTOR_DOT,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=output, count_select=count, lane_mask=0xf,
                accumulate=1, commit_after=1, wait_for_ready=1), stage)
        add(f"{stage}_continue_wait", isa.ArrayControlContext(
                next_pc=base_pc + 4, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=limit, cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_DOT,
                wait_for_result=1), stage)

    def scalar(stage: str, input_select: isa.ResourceInput,
               output_select: isa.ResourceOutput) -> None:
        add(f"{stage}_issue", isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SCALAR_DIVIDE,
                input_select=input_select, output_select=output_select,
                count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
                lane_mask=0xf, wait_for_ready=1), stage)
        add(f"{stage}_wait", isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SCALAR_DIVIDE,
                wait_for_result=1), stage)

    def pack_support_values(stage: str, config_w: int,
                            rebuild_configuration: int,
                            counter: int) -> None:
        base_pc = entry_pc + len(contexts)
        restart(stage, 5, counter)
        add(f"{stage}_issue", isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                input_select=isa.ResourceInput.SUPPORT_STREAM,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
                configuration_id=rebuild_configuration,
                count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
                wait_for_ready=1), stage)
        add(f"{stage}_wait", isa.ArrayControlContext(
                next_pc=base_pc + 1, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.ACTIVE_WORK_STRIPES_16,
                cluster_enable_mask=0b11),
            isa.StreamContext(vector_write_enable=1,
                vector_configuration_write=config_w,
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                input_select=isa.ResourceInput.SUPPORT_STREAM,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
             configuration_id=rebuild_configuration,
             wait_for_result=1), stage)

    def copy_vector(stage: str, config_a: int, config_w: int,
                    count: isa.ResourceCountSource,
                    limit: isa.LoopLimitSource, counter: int) -> None:
        base_pc = entry_pc + len(contexts)
        restart(stage, 5, counter)
        add(f"{stage}_issue", isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(vector_read_a_enable=1,
                vector_configuration_a=config_a,
                advance_vector_streams=1, stall_on_input=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
                count_select=count, lane_mask=0xf, wait_for_ready=1), stage)
        add(f"{stage}_wait", isa.ArrayControlContext(
                next_pc=base_pc + 1, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=limit, cluster_enable_mask=0b11),
            isa.StreamContext(vector_write_enable=1,
                vector_configuration_write=config_w,
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                wait_for_result=1), stage)

    def axpy(stage: str, config_a: int, config_b: int, config_w: int,
             scalar_select: isa.ResourceInput, subtract: bool,
             count: isa.ResourceCountSource, limit: isa.LoopLimitSource,
             counter: int) -> None:
        base_pc = entry_pc + len(contexts)
        restart(stage, 7, counter)
        add(f"{stage}_issue", isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(
                vector_read_a_enable=1, vector_read_b_enable=1,
                vector_configuration_a=config_a,
                vector_configuration_b=config_b,
                advance_vector_streams=1, stall_on_input=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_AXPY,
                input_select=scalar_select,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
                configuration_id=int(subtract), count_select=count,
                lane_mask=0xf, wait_for_ready=1), stage)
        add(f"{stage}_wait", isa.ArrayControlContext(
                next_pc=base_pc + 1, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=counter, loop_counter_increment=1,
                loop_limit_select=limit, cluster_enable_mask=0b11),
            isa.StreamContext(vector_write_enable=1,
                vector_configuration_write=config_w,
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_AXPY,
                wait_for_result=1), stage)

    measurement_limit = isa.LoopLimitSource.MEASUREMENT_STRIPES_16
    work_limit = isa.LoopLimitSource.ACTIVE_WORK_STRIPES_16
    if name == "restricted_refinement_initialize":
        copy_vector("initial_residual", config_ids["residual_current"],
                    config_ids["solver_r"],
                    isa.ResourceCountSource.MEASUREMENT_COUNT,
                    measurement_limit, 0)
        pack_support_values("initial_estimate", config_ids["solver_x"], 1, 0)
        pack_support_values("initial_direction", config_ids["solver_p"], 3, 0)
        norm("gamma_reference", config_ids["solver_p"],
             isa.ResourceOutput.SCALAR_0,
             isa.ResourceCountSource.ACTIVE_WORK_COUNT, work_limit, 0)
    elif name == "restricted_refinement_pre_transpose":
        scalar("alpha", isa.ResourceInput.SCALAR_0,
               isa.ResourceOutput.SCALAR_1)
        axpy("update_x", config_ids["solver_x"], config_ids["solver_p"],
             config_ids["solver_x"], isa.ResourceInput.SCALAR_1, False,
             isa.ResourceCountSource.ACTIVE_WORK_COUNT, work_limit, 1)
        axpy("update_r", config_ids["solver_r"], config_ids["solver_d"],
             config_ids["solver_r"], isa.ResourceInput.SCALAR_1, True,
             isa.ResourceCountSource.MEASUREMENT_COUNT, measurement_limit, 2)
    elif name == "restricted_refinement_certificate":
        add("post_d18_check_issue",
            isa.ArrayControlContext(
                next_pc=entry_pc + 1,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH,
                cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.REFINEMENT_CHECK,
                input_select=isa.ResourceInput.SCALAR_0,
                output_select=isa.ResourceOutput.EVENT,
                count_select=isa.ResourceCountSource.ACTIVE_SUPPORT_COUNT,
                lane_mask=0xf, wait_for_ready=1, event_id=1),
            "post_d18_check")
        add("post_d18_check_wait",
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.REFINEMENT_CHECK,
                output_select=isa.ResourceOutput.EVENT,
                wait_for_result=1, event_id=1), "post_d18_check")
    elif name == "restricted_refinement_continuation":
        scalar("beta", isa.ResourceInput.SCALAR_1,
               isa.ResourceOutput.SCALAR_0)
        axpy("update_p", config_ids["solver_g"], config_ids["solver_p"],
             config_ids["solver_p"], isa.ResourceInput.SCALAR_0, False,
             isa.ResourceCountSource.ACTIVE_WORK_COUNT, work_limit, 0)
    elif name == "restricted_refinement_restart_residual":
        add("residual_copy_issue",
            isa.ArrayControlContext(loop_counter_select=0,
                cluster_enable_mask=0b11),
            isa.StreamContext(vector_read_a_enable=1,
                vector_configuration_a=config_ids["residual_current"],
                advance_vector_streams=1, stall_on_input=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
                count_select=isa.ResourceCountSource.MEASUREMENT_COUNT,
                lane_mask=0xf, wait_for_ready=1), "restart_residual")
        add("residual_copy_wait", isa.ArrayControlContext(
                next_pc=entry_pc, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=0, loop_counter_increment=1,
                loop_limit_select=measurement_limit,
                cluster_enable_mask=0b11),
            isa.StreamContext(vector_write_enable=1,
                vector_configuration_write=config_ids["solver_r"],
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                wait_for_result=1), "restart_residual")
    elif name == "restricted_refinement_restart_direction":
        add("direction_copy_issue",
            isa.ArrayControlContext(loop_counter_select=0,
                cluster_enable_mask=0b11),
            isa.StreamContext(vector_read_a_enable=1,
                vector_configuration_a=config_ids["solver_g"],
                advance_vector_streams=1, stall_on_input=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
                count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
                lane_mask=0xf, wait_for_ready=1), "restart_direction")
        add("direction_copy_wait", isa.ArrayControlContext(
                next_pc=entry_pc, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=0, loop_counter_increment=1,
                loop_limit_select=work_limit, cluster_enable_mask=0b11),
            isa.StreamContext(vector_write_enable=1,
                vector_configuration_write=config_ids["solver_p"],
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_COPY,
                wait_for_result=1), "restart_direction")
        gamma_base = entry_pc + len(contexts)
        gamma_done = gamma_base + 5
        gamma_stream = isa.StreamContext(vector_read_a_enable=1,
            vector_configuration_a=config_ids["solver_g"],
            advance_vector_streams=1, stall_on_input=1)
        add("gamma_restart_first_issue", isa.ArrayControlContext(
                loop_counter_select=1, loop_counter_reset=1,
                cluster_enable_mask=0b11), gamma_stream,
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=isa.ResourceOutput.SCALAR_0,
                count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
                lane_mask=0xf, clear_before=1, accumulate=1,
                commit_after=1, wait_for_ready=1), "gamma_restart")
        add("gamma_restart_first_wait", isa.ArrayControlContext(
                next_pc=gamma_base + 3,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=work_limit, cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                wait_for_result=1), "gamma_restart")
        add("gamma_restart_single_done", isa.ArrayControlContext(
                next_pc=gamma_done, next_pc_mode=isa.NextPcMode.JUMP,
                cluster_enable_mask=0b11, guaranteed_commit=1),
            isa.StreamContext(), isa.ResourceContext(), "gamma_restart")
        add("gamma_restart_continue_issue", isa.ArrayControlContext(
                cluster_enable_mask=0b11), gamma_stream,
            isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=isa.ResourceOutput.SCALAR_0,
                count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
                lane_mask=0xf, accumulate=1, commit_after=1,
                wait_for_ready=1), "gamma_restart")
        add("gamma_restart_continue_wait", isa.ArrayControlContext(
                next_pc=gamma_base + 3,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=work_limit, cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                wait_for_result=1), "gamma_restart")
    elif name == "gp_line_search":
        norm("numerator", config_ids["solver_p"],
             isa.ResourceOutput.SCALAR_0,
             isa.ResourceCountSource.ACTIVE_WORK_COUNT, work_limit, 0)
        norm("denominator", config_ids["solver_d"],
             isa.ResourceOutput.SCALAR_1,
             isa.ResourceCountSource.MEASUREMENT_COUNT, measurement_limit, 1)
        scalar("alpha", isa.ResourceInput.SCALAR_0,
               isa.ResourceOutput.SCALAR_0)
    elif name == "gp_update":
        axpy("update_x", config_ids["solver_x"], config_ids["solver_p"],
             config_ids["solver_x"], isa.ResourceInput.SCALAR_0, False,
             isa.ResourceCountSource.ACTIVE_WORK_COUNT, work_limit, 0)
    elif name == "residual_measure":
        norm("residual_norm", config_ids["residual_current"],
             isa.ResourceOutput.SCALAR_1,
             isa.ResourceCountSource.MEASUREMENT_COUNT, measurement_limit, 0)
        add("termination_check_issue",
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.REFINEMENT_CHECK,
                input_select=isa.ResourceInput.SCALAR_1,
                output_select=isa.ResourceOutput.EVENT,
                configuration_id=32,
                count_select=isa.ResourceCountSource.MEASUREMENT_COUNT,
                lane_mask=0xf, wait_for_ready=1, event_id=2),
            "termination_check")
        add("termination_check_wait",
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.REFINEMENT_CHECK,
                output_select=isa.ResourceOutput.EVENT,
                configuration_id=32, wait_for_result=1, event_id=2),
            "termination_check")
    else:
        raise ValueError(f"unknown restricted refinement segment {name}")

    add("epilogue", isa.ArrayControlContext(
            next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
            cluster_enable_mask=0b11, routine_done=1,
            safe_abort_point=1, guaranteed_commit=1),
        isa.StreamContext(), isa.ResourceContext(), "complete")
    encoded = _encode_kernel_contexts(name, entry_pc, contexts)
    return {
        "kernel": name,
        "entry_pc": entry_pc,
        "context_count": len(encoded),
        "body_ii": None,
        "loop_axis": "refinement_iteration",
        "completion_predicate_select": 2,
        "operator_contract": {
            "execution_model": "phase_launched_resource_segment",
            "solver_pc": False,
            "active_work_count_source": "run_parameter_1",
            "hardware_execution_ready": True,
            "execution_blockers": [],
        },
        "contexts": encoded,
    }


def _emit_restricted_refinement_transpose(
        ddg: graphs.ArrayRoutineDDG, mapping: dict[str, Any],
        memory: dict[str, Any], entry_pc: int) -> dict[str, Any]:
    emitted = _emit_nested_operator_contexts(
        "phi_support_transpose", ddg, mapping, memory, entry_pc)
    config_ids = _configuration_ids(memory)
    for context in emitted["contexts"]:
        stream = isa.unpack_stream(context["stream_word"])
        if (stream.vector_read_a_enable and
                stream.vector_configuration_a ==
                config_ids["solver_d_even_stripes"]):
            stream = isa.StreamContext(**{
                **asdict(stream),
                "vector_configuration_a":
                    config_ids["solver_r_even_stripes"],
                "vector_configuration_b":
                    config_ids["solver_r_odd_stripes"],
            })
            context["stream_word"] = isa.pack_stream(stream)
    emitted["kernel"] = "restricted_refinement_transpose"
    emitted["operator_contract"] = {
        **emitted["operator_contract"],
        "input_object": "solver_r",
        "output_object": "solver_g",
        "hardware_execution_ready": True,
        "execution_blockers": [],
    }
    return emitted


def _emit_correlation_contexts(ddg: graphs.ArrayRoutineDDG,
                               mapping: dict[str, Any], memory: dict[str, Any],
                               entry_pc: int) -> dict[str, Any]:
    config_ids = _configuration_ids(memory)
    blank_tiles = [isa.TileContext()] * 16
    accumulate_tiles = [_tile_context("PHI_ACCUMULATE", None, None)] * 16
    clear_tiles = [isa.TileContext(operation=isa.TileOperation.ACCUMULATOR_CLEAR)] * 16
    middle_setup_pc = entry_pc + 5
    drain_pc = entry_pc + 10
    column_setup = isa.ResourceContext(
        operation=isa.ResourceOperation.NOP,
        configuration_id=0b001,
        stream_boundary=isa.StreamBoundary.FIRST)
    body_stream = isa.StreamContext(
        vector_read_a_enable=1,
        vector_configuration_a=config_ids["residual_current"],
        external_a_select=isa.ExternalStreamSource.VECTOR_A,
        phi_command=isa.PhiStreamCommand.CONSUME,
        advance_vector_streams=1, stall_on_input=1)
    reduction_issue = isa.ResourceContext(
        operation=isa.ResourceOperation.REDUCE_SUM,
        input_select=isa.ResourceInput.CLUSTER_REDUCTION,
        output_select=isa.ResourceOutput.TOPK_STATE,
        count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
        lane_mask=0xf, clear_before=1, accumulate=1,
        commit_after=1, wait_for_ready=1)
    topk_push_issue = isa.ResourceContext(
        operation=isa.ResourceOperation.TOPK_PUSH,
        input_select=isa.ResourceInput.GLOBAL_REDUCTION,
        output_select=isa.ResourceOutput.TOPK_STATE,
        count_select=isa.ResourceCountSource.SIGNAL_LENGTH,
        configuration_id=0b000010,
        wait_for_ready=1, event_id=9)
    topk_push_wait = isa.ResourceContext(
        operation=isa.ResourceOperation.TOPK_PUSH,
        output_select=isa.ResourceOutput.TOPK_STATE,
        wait_for_result=1, event_id=9)
    contexts = [
        (
            "prologue", blank_tiles,
            isa.ArrayControlContext(
                next_pc_mode=isa.NextPcMode.SEQUENTIAL,
                loop_counter_select=1, loop_counter_reset=1,
                cluster_enable_mask=0b11),
            isa.StreamContext(
                phi_command=isa.PhiStreamCommand.START,
                phi_configuration_id=config_ids["phi_dense"],
                stall_on_input=1),
            isa.ResourceContext(), [],
        ),
        (
            "column_setup", clear_tiles,
            isa.ArrayControlContext(
                next_pc_mode=isa.NextPcMode.SEQUENTIAL,
                loop_counter_select=0, loop_counter_reset=1,
                cluster_enable_mask=0b11),
            isa.StreamContext(), column_setup, [],
        ),
        (
            "row_block_body", accumulate_tiles,
            isa.ArrayControlContext(
                next_pc=entry_pc + 2,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=0, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_0,
                cluster_enable_mask=0b11),
            body_stream, isa.ResourceContext(),
            ["load_r", "phi", "phi_accumulate"],
        ),
        (
            "prime_reduction_issue", blank_tiles,
            isa.ArrayControlContext(
                next_pc=middle_setup_pc,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH,
                cluster_enable_mask=0b11),
            isa.StreamContext(), reduction_issue, ["reduce"],
        ),
        (
            "single_column_drain_jump", blank_tiles,
            isa.ArrayControlContext(
                next_pc=drain_pc, next_pc_mode=isa.NextPcMode.JUMP,
                cluster_enable_mask=0b11),
            isa.StreamContext(), isa.ResourceContext(), [],
        ),
        (
            "middle_column_setup", clear_tiles,
            isa.ArrayControlContext(
                next_pc_mode=isa.NextPcMode.SEQUENTIAL,
                loop_counter_select=0, loop_counter_reset=1,
                cluster_enable_mask=0b11),
            isa.StreamContext(), column_setup, [],
        ),
        (
            "middle_row_block_body", accumulate_tiles,
            isa.ArrayControlContext(
                next_pc=entry_pc + 6,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=0, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_0,
                cluster_enable_mask=0b11),
            body_stream, isa.ResourceContext(),
            ["load_r", "phi", "phi_accumulate"],
        ),
        (
            "middle_reduction_issue", blank_tiles,
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), reduction_issue, ["reduce"],
        ),
        (
            "middle_topk_push_issue", blank_tiles,
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), topk_push_issue, ["collect"],
        ),
        (
            "middle_topk_push_wait", blank_tiles,
            isa.ArrayControlContext(
                next_pc=middle_setup_pc,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.SIGNAL_LENGTH,
                cluster_enable_mask=0b11),
            isa.StreamContext(), topk_push_wait, [],
        ),
        (
            "drain_topk_push_issue", blank_tiles,
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), topk_push_issue, ["collect"],
        ),
        (
            "drain_topk_push_wait", blank_tiles,
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(), topk_push_wait, [],
        ),
        (
            "topk_commit_issue", blank_tiles,
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(),
            isa.ResourceContext(
                operation=isa.ResourceOperation.TOPK_COMMIT,
                output_select=isa.ResourceOutput.TOPK_STATE,
                wait_for_ready=1, event_id=2), [],
        ),
        (
            "topk_commit_wait", blank_tiles,
            isa.ArrayControlContext(cluster_enable_mask=0b11),
            isa.StreamContext(),
            isa.ResourceContext(
                operation=isa.ResourceOperation.TOPK_COMMIT,
                output_select=isa.ResourceOutput.TOPK_STATE,
                wait_for_result=1, event_id=2), [],
        ),
        (
            "epilogue", blank_tiles,
            isa.ArrayControlContext(
                next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
                cluster_enable_mask=0b11, routine_done=1,
                safe_abort_point=1, guaranteed_commit=1),
            isa.StreamContext(phi_command=isa.PhiStreamCommand.STOP),
            isa.ResourceContext(), [],
        ),
    ]
    encoded = _encode_kernel_contexts("correlation", entry_pc, contexts)
    mapped = set(mapping["placements"])
    emitted = {name for context in encoded
               for name in context["semantic_operations"]}
    if mapped != emitted:
        raise ValueError("correlation: emitted operation coverage differs from mapping")
    return {
        "kernel": "correlation", "entry_pc": entry_pc,
        "context_count": len(encoded), "body_ii": 1,
        "loop_axis": ddg.loop_axis, "completion_predicate_select": 2,
        "operator_contract": {
            "inner_loop_counter": 0, "inner_limit": "RUN_PARAMETER_0",
            "inner_limit_formula": "ceil(M/32)",
            "outer_loop_counter": 1, "outer_limit": "SIGNAL_LENGTH",
            "column_pipeline": "prime_middle_drain",
            "vector_restart_mask": 1,
            "reduction_emit": True, "normalizer_required": True,
            "candidate_index_source": "registered_phi_column",
            "reduction_response_wait": False,
            "topk_push_response_wait": True,
            "topk_commit_response_wait": True,
            "declared_fill_drain": {
                "scratchpad_read": 1, "reduction": 5,
                "phi_normalizer": 4, "topk_push": 2,
                "topk_commit": 1,
            },
        },
        "contexts": encoded,
    }


def emit_kernel_contexts(kernel: str, ddg: graphs.ArrayRoutineDDG,
                         mapping: dict[str, Any], rf: dict[str, Any],
                         memory: dict[str, Any], entry_pc: int) -> dict[str, Any]:
    if kernel == "correlation":
        return _emit_correlation_contexts(ddg, mapping, memory, entry_pc)
    if kernel in {"residual_update", "phi_support_forward",
                  "phi_support_transpose"}:
        return _emit_nested_operator_contexts(
            kernel, ddg, mapping, memory, entry_pc)
    binding = KERNEL_BINDINGS[kernel]
    config_ids = _configuration_ids(memory)
    writes, reads = _rf_by_operation(rf)
    ii = mapping["candidate_ii"]
    by_slot: dict[int, list[tuple[str, dict[str, Any]]]] = {slot: [] for slot in range(ii)}
    for name, placement in mapping["placements"].items():
        by_slot[placement["modulo_slot"]].append((name, placement))

    contexts = []
    prologue_control = isa.ArrayControlContext(
        next_pc_mode=isa.NextPcMode.SEQUENTIAL, loop_counter_select=0,
        loop_counter_reset=1, cluster_enable_mask=0b11,
    )
    prologue_stream = isa.StreamContext(
        phi_command=isa.PhiStreamCommand.START,
        phi_configuration_id=config_ids[binding["phi"]], stall_on_input=1,
    )
    prologue_tiles = [isa.TileContext(operation=isa.TileOperation.ACCUMULATOR_CLEAR)] * 16
    contexts.append(("prologue", prologue_tiles, prologue_control,
                     prologue_stream, isa.ResourceContext(), []))

    body_start = entry_pc + 1
    operation_names = {operation.name: operation for operation in ddg.operations}
    for slot in range(ii):
        entries = sorted(by_slot[slot])
        tile_entries = [(name, value) for name, value in entries
                        if value["resource_class"] == "paired_context_tile"]
        resource_entries = [(name, value) for name, value in entries
                            if value.get("issue_domains") == ["resource_context"]]
        if len(tile_entries) > 1 or len(resource_entries) > 1:
            raise ValueError(f"{kernel}: context slot cannot encode mapped operations")
        tile = isa.TileContext()
        if tile_entries:
            name, placement = tile_entries[0]
            tile = _tile_context(placement["operation"], writes.get(name), reads.get(name))
        tiles = [tile] * 16

        stream_values: dict[str, int] = {}
        read_sources: dict[str, int] = {}
        store_id: int | None = None
        semantic_ops = [name for name, _ in entries]
        for name, placement in entries:
            if name in binding["loads"]:
                port = int(placement["resources"][0].rsplit("_", 1)[1])
                object_id = config_ids[binding["loads"][name]]
                if port == 0:
                    stream_values.update(vector_read_a_enable=1,
                                         vector_configuration_a=object_id)
                    read_sources[name] = isa.ExternalStreamSource.VECTOR_A
                else:
                    stream_values.update(vector_read_b_enable=1,
                                         vector_configuration_b=object_id)
                    read_sources[name] = isa.ExternalStreamSource.VECTOR_B
            if name in binding["stores"]:
                store_id = config_ids[binding["stores"][name]]
                stream_values.update(vector_write_enable=1,
                                     vector_configuration_write=store_id)
            if placement["operation"] == "PHI_SIGN_WORD":
                stream_values["phi_command"] = isa.PhiStreamCommand.CONSUME
        if tile_entries:
            tile_name = tile_entries[0][0]
            if tile_name in {"scale", "phi_accumulate"}:
                load_name = next(name for name in binding["loads"]
                                 if name in read_sources)
                stream_values["external_a_select"] = read_sources[load_name]
            elif tile_name == "subtract":
                stream_values["external_a_select"] = read_sources["load_y"]
                stream_values["external_b_select"] = isa.ExternalStreamSource.SCALAR_BROADCAST
        has_stream = any(key in stream_values for key in (
            "vector_read_a_enable", "vector_read_b_enable", "vector_write_enable"))
        if has_stream:
            stream_values["advance_vector_streams"] = 1
            stream_values["stall_on_input"] = int(
                "vector_read_a_enable" in stream_values or
                "vector_read_b_enable" in stream_values or
                stream_values.get("phi_command") == isa.PhiStreamCommand.CONSUME)
            stream_values["stall_on_output"] = int("vector_write_enable" in stream_values)
        stream = isa.StreamContext(**stream_values)

        resource = isa.ResourceContext()
        if resource_entries:
            resource_store_id = store_id
            if (resource_entries[0][1]["operation"] == "REDUCE_SUM" and
                    kernel in {"phi_support_forward", "phi_support_transpose"}):
                resource_store_id = config_ids[next(iter(binding["stores"].values()))]
            resource = _resource_context(
                kernel, resource_entries[0][1]["operation"], resource_store_id)
        last = slot == ii - 1
        control = isa.ArrayControlContext(
            next_pc=body_start if last else 0,
            next_pc_mode=(isa.NextPcMode.COUNTED_LOOP if last
                          else isa.NextPcMode.SEQUENTIAL),
            loop_counter_select=0, loop_counter_increment=int(last),
            loop_limit_select=_loop_limit(kernel), cluster_enable_mask=0b11,
        )
        contexts.append(("body", tiles, control, stream, resource, semantic_ops))

    drain_pc = entry_pc + len(contexts)
    contexts.append((
        "drain_wait", [isa.TileContext()] * 16,
        isa.ArrayControlContext(
            next_pc=drain_pc + 1, next_pc_mode=isa.NextPcMode.WAIT_EVENT,
            predicate_select=2, cluster_enable_mask=0b11),
        isa.StreamContext(), isa.ResourceContext(), []))
    contexts.append((
        "epilogue", [isa.TileContext()] * 16,
        isa.ArrayControlContext(
            next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE,
            cluster_enable_mask=0b11, routine_done=1, safe_abort_point=1,
            guaranteed_commit=1),
        isa.StreamContext(phi_command=isa.PhiStreamCommand.STOP),
        isa.ResourceContext(), []))

    encoded = []
    for offset, (region, tiles, control, stream, resource, semantic_ops) in enumerate(contexts):
        isa.validate_context_bundle(control, stream, resource)
        tile_words = [isa.pack_tile(item) for item in tiles]
        control_word = isa.pack_array_control(control)
        stream_word = isa.pack_stream(stream)
        resource_word = isa.pack_resource(resource)
        if [isa.unpack_tile(word) for word in tile_words] != tiles:
            raise ValueError(f"{kernel}: tile context round-trip failed")
        if isa.unpack_array_control(control_word) != control:
            raise ValueError(f"{kernel}: control context round-trip failed")
        if isa.unpack_stream(stream_word) != stream:
            raise ValueError(f"{kernel}: stream context round-trip failed")
        if isa.unpack_resource(resource_word) != resource:
            raise ValueError(f"{kernel}: resource context round-trip failed")
        encoded.append({
            "pc": entry_pc + offset, "region": region,
            "semantic_operations": semantic_ops, "tile_words": tile_words,
            "array_control_word": control_word, "stream_word": stream_word,
            "resource_word": resource_word,
        })
    mapped = set(mapping["placements"])
    emitted = {name for context in encoded for name in context["semantic_operations"]}
    if mapped != emitted:
        raise ValueError(f"{kernel}: emitted operation coverage differs from mapping")
    return {
        "kernel": kernel, "entry_pc": entry_pc, "context_count": len(encoded),
        "body_ii": ii, "loop_axis": ddg.loop_axis,
        "completion_predicate_select": 2,
        "contexts": encoded,
    }


def _emit_nested_operator_contexts(kernel: str, ddg: graphs.ArrayRoutineDDG,
        mapping: dict[str, Any], memory: dict[str, Any], entry_pc: int) -> dict[str, Any]:
    config_ids = _configuration_ids(memory)
    binding = KERNEL_BINDINGS[kernel]
    blank = [isa.TileContext()] * 16
    clear = [isa.TileContext(operation=isa.TileOperation.ACCUMULATOR_CLEAR)] * 16
    accumulate_operation = ("PHI_DATA_ACCUMULATE"
                            if kernel == "residual_update"
                            else "PHI_ACCUMULATE")
    accumulate = [_tile_context(accumulate_operation, None, None)] * 16
    contexts = [("prologue", blank, isa.ArrayControlContext(
        loop_counter_select=1, loop_counter_reset=1, cluster_enable_mask=3),
        isa.StreamContext(phi_command=isa.PhiStreamCommand.START,
            phi_configuration_id=config_ids[binding["phi"]], stall_on_input=1),
        isa.ResourceContext(), [])]
    setup_pc = entry_pc + 1
    setup_name = "support_setup" if kernel == "phi_support_transpose" else "row_block_setup"
    contexts.append((setup_name, clear, isa.ArrayControlContext(
        loop_counter_select=0, loop_counter_reset=1, cluster_enable_mask=3),
        isa.StreamContext(), isa.ResourceContext(operation=isa.ResourceOperation.NOP,
            configuration_id=(3 if kernel == "phi_support_transpose" else 1),
            stream_boundary=isa.StreamBoundary.FIRST), []))
    if kernel == "phi_support_transpose":
        load_name, load_object, inner_limit, body_name = (
            "load_t", "solver_d_even_stripes",
            isa.LoopLimitSource.RUN_PARAMETER_0, "row_block_body")
    else:
        load_name = "load_x" if kernel == "residual_update" else "load_p"
        load_object = "solver_x" if kernel == "residual_update" else "solver_p"
        inner_limit, body_name = isa.LoopLimitSource.RUN_PARAMETER_1, "support_body"
    contexts.append((body_name, accumulate, isa.ArrayControlContext(
        next_pc=entry_pc + 2, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
        loop_counter_select=0, loop_counter_increment=1,
        loop_limit_select=inner_limit, cluster_enable_mask=3),
        isa.StreamContext(vector_read_a_enable=1,
            vector_configuration_a=config_ids[load_object],
            vector_read_b_enable=int(kernel == "phi_support_transpose"),
            vector_configuration_b=(
                config_ids["solver_d_odd_stripes"]
                if kernel == "phi_support_transpose" else 0),
            external_a_select=(isa.ExternalStreamSource.VECTOR_A
                if kernel == "phi_support_transpose"
                else isa.ExternalStreamSource.SCALAR_BROADCAST),
            phi_command=isa.PhiStreamCommand.CONSUME,
            advance_vector_streams=1, stall_on_input=1),
        isa.ResourceContext(), [load_name, "phi", "phi_accumulate"]))
    store_name = {"residual_update":"store_r", "phi_support_forward":"store_t",
                  "phi_support_transpose":"store_q"}[kernel]
    store_id = config_ids[binding["stores"][store_name]]
    if kernel == "phi_support_transpose":
        reduction_issue = isa.ResourceContext(
            operation=isa.ResourceOperation.REDUCE_SUM,
            input_select=isa.ResourceInput.CLUSTER_REDUCTION,
            output_select=isa.ResourceOutput.MEMORY_STREAM,
            configuration_id=store_id, lane_mask=15, clear_before=1,
            accumulate=1, commit_after=1, wait_for_ready=1)
        reduction_wait = isa.ResourceContext(
            operation=isa.ResourceOperation.REDUCE_SUM,
            output_select=isa.ResourceOutput.MEMORY_STREAM,
            wait_for_result=1)
        contexts.append(("prime_reduction_issue", blank,
            isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
            reduction_issue, ["reduce"]))
        middle_setup_pc = entry_pc + 6
        drain_pc = entry_pc + 10
        contexts.append(("prime_reduction_wait", blank,
            isa.ArrayControlContext(
                next_pc=middle_setup_pc,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_1,
                cluster_enable_mask=3),
            isa.StreamContext(), reduction_wait, []))
        contexts.append(("single_item_drain_jump", blank,
            isa.ArrayControlContext(
                next_pc=drain_pc, next_pc_mode=isa.NextPcMode.JUMP,
                cluster_enable_mask=3),
            isa.StreamContext(), isa.ResourceContext(), []))
        contexts.append(("middle_support_setup", clear,
            isa.ArrayControlContext(
                loop_counter_select=0, loop_counter_reset=1,
                cluster_enable_mask=3),
            isa.StreamContext(), isa.ResourceContext(
                operation=isa.ResourceOperation.NOP,
                configuration_id=3,
                stream_boundary=isa.StreamBoundary.FIRST), []))
        contexts.append(("middle_row_block_body", accumulate,
            isa.ArrayControlContext(
                next_pc=entry_pc + 7,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=0, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_0,
                cluster_enable_mask=3),
            isa.StreamContext(
                vector_read_a_enable=1,
                vector_configuration_a=config_ids[load_object],
                vector_read_b_enable=1,
                vector_configuration_b=config_ids["solver_d_odd_stripes"],
                external_a_select=isa.ExternalStreamSource.VECTOR_A,
                phi_command=isa.PhiStreamCommand.CONSUME,
                advance_vector_streams=1, stall_on_input=1),
            isa.ResourceContext(), [load_name, "phi", "phi_accumulate"]))
        contexts.append(("middle_reduction_issue", blank,
            isa.ArrayControlContext(cluster_enable_mask=3), isa.StreamContext(),
            reduction_issue, ["reduce"]))
        contexts.append(("middle_reduction_wait_writeback", blank,
            isa.ArrayControlContext(
                next_pc=middle_setup_pc,
                next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
                loop_counter_select=1, loop_counter_increment=1,
                loop_limit_select=isa.LoopLimitSource.RUN_PARAMETER_1,
                cluster_enable_mask=3),
            isa.StreamContext(
                vector_write_enable=1,
                vector_configuration_write=store_id,
                advance_vector_streams=1, stall_on_output=1),
            reduction_wait, [store_name]))
    elif kernel == "phi_support_forward":
        contexts.append(("accumulator_read",
            [_tile_context("PHI_ACCUMULATOR_CAPTURE", None, None)] * 16,
            isa.ArrayControlContext(cluster_enable_mask=3),
            isa.StreamContext(), isa.ResourceContext(), ["read_accumulator"]))
    if kernel == "residual_update":
        contexts.append(("subtract", [isa.TileContext(
                operation=isa.TileOperation.PHI_RESIDUAL_CAPTURE,
                source_a=isa.OperandSource.EXTERNAL,
                source_b=isa.OperandSource.ACCUMULATOR)] * 16,
            isa.ArrayControlContext(cluster_enable_mask=3),
            isa.StreamContext(vector_read_b_enable=1,
                vector_configuration_b=config_ids["measurement_y"],
                external_a_select=isa.ExternalStreamSource.VECTOR_B,
                advance_vector_streams=1, stall_on_input=1),
            isa.ResourceContext(), ["load_y", "subtract"]))
    outer_limit = (isa.LoopLimitSource.RUN_PARAMETER_1 if kernel == "phi_support_transpose"
                   else isa.LoopLimitSource.RUN_PARAMETER_0)
    if kernel == "phi_support_forward":
        contexts.append(("writeback_low", blank,
            isa.ArrayControlContext(cluster_enable_mask=3),
            isa.StreamContext(vector_write_enable=1,
                vector_configuration_write=store_id,
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(), []))
    if kernel == "phi_support_transpose":
        contexts.append(("drain_writeback", blank,
            isa.ArrayControlContext(cluster_enable_mask=3),
            isa.StreamContext(
                vector_write_enable=1,
                vector_configuration_write=store_id,
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(), [store_name]))
    else:
        contexts.append(("writeback", blank, isa.ArrayControlContext(
            next_pc=setup_pc, next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
            loop_counter_select=1, loop_counter_increment=1,
            loop_limit_select=outer_limit, cluster_enable_mask=3),
            isa.StreamContext(vector_write_enable=1, vector_configuration_write=store_id,
                advance_vector_streams=1, stall_on_output=1),
            isa.ResourceContext(), [store_name]))
    contexts.append(("epilogue", blank, isa.ArrayControlContext(
        next_pc_mode=isa.NextPcMode.RETURN_TO_PHASE, cluster_enable_mask=3,
        routine_done=1, safe_abort_point=1, guaranteed_commit=1),
        isa.StreamContext(phi_command=isa.PhiStreamCommand.STOP),
        isa.ResourceContext(), []))
    encoded = _encode_kernel_contexts(kernel, entry_pc, contexts)
    emitted = {name for context in encoded for name in context["semantic_operations"]}
    if set(mapping["placements"]) != emitted:
        raise ValueError(f"{kernel}: emitted operation coverage differs from mapping")
    return {"kernel": kernel, "entry_pc": entry_pc, "context_count": len(encoded),
        "body_ii": 1, "loop_axis": ddg.loop_axis, "completion_predicate_select": 2,
        "operator_contract": {"inner_loop_counter": 0,
            "inner_limit": isa.LoopLimitSource(inner_limit).name,
            "outer_loop_counter": 1, "outer_limit": isa.LoopLimitSource(outer_limit).name,
            "vector_restart_mask": 3 if kernel == "phi_support_transpose" else 1,
            "reduction_emit": kernel == "phi_support_transpose",
            "reduction_response_wait": kernel == "phi_support_transpose",
            "writeback_after_response": True,
            "transpose_pipeline_shape": (
                "prime_middle_drain" if kernel == "phi_support_transpose" else None),
            "outer_increment_at_writeback": kernel != "phi_support_transpose",
            "phi_stop_epilogue": True,
            "schedule_shape_valid": True, "hardware_execution_ready": True,
            "execution_blockers": []},
        "contexts": encoded}


def _validate_bank_ports(kernel: dict[str, Any]) -> None:
    for context in kernel["contexts"]:
        stream = isa.unpack_stream(context["stream_word"])
        accesses = int(stream.vector_read_a_enable) + int(stream.vector_read_b_enable)
        accesses += int(stream.vector_write_enable)
        if accesses > 2:
            raise ValueError(
                f"{kernel['kernel']} PC {context['pc']}: more than two accesses per bank")


def _plane_images(ranges: list[dict[str, Any]]) -> dict[str, list[int]]:
    contexts = [context for item in ranges for context in item["contexts"]]
    planes = {f"array_plane_{plane}": [] for plane in range(10)}
    for context in contexts:
        tiles = context["tile_words"]
        for plane in range(8):
            planes[f"array_plane_{plane}"].append(
                tiles[2 * plane] | (tiles[2 * plane + 1] << 36))
        planes["array_plane_8"].append(
            context["array_control_word"] | (context["stream_word"] << 36))
        planes["array_plane_9"].append(context["resource_word"])
    return planes


def validate_compiled(compiled: dict[str, Any],
                      configuration: dict[str, Any] | None = None) -> None:
    configuration = configuration or architecture.load()
    if compiled["architecture_hash"] != architecture.configuration_hash(configuration):
        raise ValueError("scheduled context library has a stale architecture hash")
    if compiled["context_revision"] != isa.CONTEXT_FORMAT_REVISION:
        raise ValueError("scheduled context library has a stale context revision")
    blocked = compiled.get("blocked_kernels", [])
    for item in blocked:
        for operation in item["operations"]:
            if architecture.resource_operation_is_schedulable(configuration, operation):
                raise ValueError(f"{item['kernel']}: stale blocked operation {operation}")
    memory = compiled["memory_allocation"]
    ranges = sorted((item["base_word_address_per_bank"],
                     item["base_word_address_per_bank"] + item["words_per_bank"],
                     item["name"]) for item in memory["objects"])
    for left, right in zip(ranges, ranges[1:]):
        if left[1] > right[0]:
            raise ValueError(f"scratchpad allocation overlap: {left[2]} and {right[2]}")
    if ranges and ranges[-1][1] > configuration["memory"]["vector_bank_depth"]:
        raise ValueError("scratchpad allocation exceeds physical bank depth")
    object_names = {item["name"] for item in memory["objects"]}
    if object_names & {"proxy", "rhs_cache", "dense_x"}:
        raise ValueError("forbidden dense matrix-free object was allocated")
    next_pc = 0
    context_ranges = compiled["kernels"] + compiled.get("resident_segments", [])
    for kernel in context_ranges:
        if kernel["entry_pc"] != next_pc:
            raise ValueError("kernel context ranges are not contiguous")
        if kernel["context_count"] != len(kernel["contexts"]):
            raise ValueError(f"{kernel['kernel']}: context count mismatch")
        _validate_bank_ports(kernel)
        for context in kernel["contexts"]:
            tiles = [isa.unpack_tile(word) for word in context["tile_words"]]
            control = isa.unpack_array_control(context["array_control_word"])
            stream = isa.unpack_stream(context["stream_word"])
            resource = isa.unpack_resource(context["resource_word"])
            operation_name = isa.ResourceOperation(resource.operation).name
            if not architecture.resource_operation_is_schedulable(
                    configuration, operation_name):
                raise ValueError(
                    f"{kernel['kernel']}: unavailable resource operation "
                    f"{operation_name} cannot be emitted")
            if len(tiles) != 16:
                raise ValueError(f"{kernel['kernel']}: context has wrong tile count")
            _validate_production_tile_capabilities(
                kernel["kernel"], context["pc"], tiles)
            isa.validate_context_bundle(control, stream, resource)
        next_pc += kernel["context_count"]
    if next_pc != compiled["array_context_count"]:
        raise ValueError("array context total differs from kernel ranges")
    if next_pc > configuration["context_storage"]["context_depth"]:
        raise ValueError("scheduled contexts exceed context image depth")


def payload() -> dict[str, Any]:
    configuration = architecture.load()
    _, ddgs = graphs.validate_all()
    mappings = mmg.payload()
    memory = allocate_memory(configuration)
    typed = {name: typed_ssa(ddg) for name, ddg in ddgs.items()}
    kernels = []
    blocked_kernels = []
    rf_allocations = {}
    next_pc = 0
    for name in mmg.MODULO_KERNELS:
        mapping = mappings["kernels"][name]["mapping"]
        rf = allocate_local_rf(ddgs[name], mapping, typed[name])
        rf_allocations[name] = rf
        blocked_operations = sorted({
            operation.operation for operation in ddgs[name].operations
            if operation.operation in isa.ResourceOperation.__members__ and
            not architecture.resource_operation_is_schedulable(
                configuration, operation.operation)
        })
        if blocked_operations:
            blocked_kernels.append({
                "kernel": name, "operations": blocked_operations,
                "reason": "resource capability is not implemented",
            })
            continue
        kernel = emit_kernel_contexts(name, ddgs[name], mapping, rf, memory, next_pc)
        _validate_bank_ports(kernel)
        kernels.append(kernel)
        next_pc += kernel["context_count"]
    resident_segments = []
    refinement_transpose = _emit_restricted_refinement_transpose(
        ddgs["phi_support_transpose"],
        mappings["kernels"]["phi_support_transpose"]["mapping"],
        memory, next_pc)
    resident_segments.append(refinement_transpose)
    next_pc += refinement_transpose["context_count"]
    for name, _ in restricted_refinement_resource_segments():
        segment = _emit_restricted_refinement_segment(name, next_pc, memory)
        resident_segments.append(segment)
        next_pc += segment["context_count"]
    omp_support_append = _emit_omp_support_append(next_pc)
    resident_segments.append(omp_support_append)
    next_pc += omp_support_append["context_count"]
    for emitter in (_emit_iht_dense_correlation, _emit_iht_vector_axpy,
                    _emit_vector_topk, _emit_iht_support_replace,
                    _emit_iht_dense_rebuild, _emit_iht_support_pack,
                    _emit_htp_support_coefficient_scatter,
                    _emit_htp_dense_scatter, _emit_cosamp_union_3k,
                    _emit_cosamp_coefficient_topk,
                    _emit_cosamp_prune_support, _emit_sp_union_2k,
                    _emit_sp_prune_support,
                    _emit_sp_proposal_coefficient_scatter,
                    _emit_sp_accept, _emit_sp_rollback,
                    _emit_gp_top1_stream):
        segment = emitter(next_pc, memory)
        resident_segments.append(segment)
        next_pc += segment["context_count"]
    for name in ("gp_line_search", "gp_update"):
        segment = _emit_restricted_refinement_segment(name, next_pc, memory)
        resident_segments.append(segment)
        next_pc += segment["context_count"]
    gomp_top2 = _emit_gomp_top2_stream(next_pc, memory)
    resident_segments.append(gomp_top2)
    next_pc += gomp_top2["context_count"]
    gomp_support_union = _emit_gomp_support_union(next_pc, memory)
    resident_segments.append(gomp_support_union)
    next_pc += gomp_support_union["context_count"]
    gp_support_policy = _emit_gp_support_policy(
        next_pc, memory, gomp_support_union["entry_pc"] + 4)
    resident_segments.append(gp_support_policy)
    next_pc += gp_support_policy["context_count"]
    for emitter in (_emit_gp_direction_pack, _emit_mp_direction_pack):
        segment = emitter(next_pc, memory)
        resident_segments.append(segment)
        next_pc += segment["context_count"]
    residual_measure = _emit_restricted_refinement_segment(
        "residual_measure", next_pc, memory)
    resident_segments.append(residual_measure)
    next_pc += residual_measure["context_count"]
    htp_fresh_refinement_marker = _emit_htp_fresh_refinement_marker(
        next_pc, memory)
    resident_segments.append(htp_fresh_refinement_marker)
    next_pc += htp_fresh_refinement_marker["context_count"]
    if next_pc > configuration["context_storage"]["context_depth"]:
        raise ValueError("emitted kernel library exceeds context RAM depth")
    segment_lookup = {item["kernel"]: item for item in resident_segments}
    result = {
        "schema": "cscgra-v3-scheduled-context-library-v2",
        "architecture_hash": architecture.configuration_hash(configuration),
        "context_revision": isa.CONTEXT_FORMAT_REVISION,
        "status": "correlation and nested matrix schedules executable through the M8 operator harness",
        "typed_ssa": typed,
        "local_rf_allocations": rf_allocations,
        "memory_allocation": memory,
        "kernels": kernels,
        "resident_segments": resident_segments,
        "hierarchical_routines": [{
            "routine": "restricted_refinement_iteration",
            "execution_model": "phase_orchestrated_segments",
            "solver_pc": False,
            "scalar_state_lifetime": "refinement_transaction",
            "initialization": {"kind": "resident_segment",
                "target": "restricted_refinement_initialize"},
            "launch_order": [
                {"kind": "array_operator", "target": "phi_support_forward"},
                {"kind": "resident_segment",
                 "target": "restricted_refinement_pre_transpose"},
                {"kind": "resident_segment",
                 "target": "restricted_refinement_transpose"},
                {"kind": "resident_segment",
                 "target": "restricted_refinement_certificate"},
                {"kind": "conditional_resident_segment",
                 "target": "restricted_refinement_continuation",
                 "condition": "certificate_continue"},
            ],
            "segments": [{
                "name": "restricted_refinement_transpose",
                "entry_pc": segment_lookup["restricted_refinement_transpose"]["entry_pc"],
                "context_count": segment_lookup["restricted_refinement_transpose"]["context_count"],
            }, *[{
                "name": name,
                "entry_pc": segment_lookup[name]["entry_pc"],
                "context_count": segment_lookup[name]["context_count"],
            } for name, _ in restricted_refinement_resource_segments()]],
            "hardware_execution_ready": True,
            "execution_blockers": [],
        }],
        "blocked_kernels": blocked_kernels,
        "array_context_count": next_pc,
        "plane_images": _plane_images(kernels + resident_segments),
    }
    validate_compiled(result, configuration)
    return result


def mem_files(compiled: dict[str, Any]) -> dict[str, str]:
    result = {}
    for name, words in compiled["plane_images"].items():
        width = 72 if name != "array_plane_9" else 36
        digits = width // 4
        result[f"{name}.mem"] = "".join(f"{word:0{digits}x}\n" for word in words)
    memory_words = {item["id"]: item["word"]
                    for item in compiled["memory_allocation"]["configurations"]}
    result["memory_configurations.mem"] = "".join(
        f"{memory_words.get(address, 0):016x}\n" for address in range(64))
    return result
