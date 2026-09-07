#!/usr/bin/env python3
"""Bit-exact context/VLIW codec for the paired-cluster v3 CGRA.

The codec is the software authority for context images. RTL constants will be
generated from this contract only after opcode/mapping review.
"""

from __future__ import annotations

from dataclasses import dataclass, fields
from enum import IntEnum


CONTEXT_FORMAT_REVISION = 9
TILE_CONTEXT_WIDTH = 36
ARRAY_CONTROL_CONTEXT_WIDTH = 36
STREAM_CONTEXT_WIDTH = 36
RESOURCE_CONTEXT_WIDTH = 36
PHASE_INSTRUCTION_WIDTH = 36
MEMORY_CONFIGURATION_WIDTH = 64


class TileOperation(IntEnum):
    NOP = 0
    PASS = 1
    ADD = 2
    SUB = 3
    ABS = 4
    MIN = 5
    MAX = 6
    COMPARE_EQ = 7
    COMPARE_LT = 8
    COMPARE_LE = 9
    SELECT = 10
    SHIFT = 11
    BIT_AND = 12
    BIT_OR = 13
    BIT_XOR = 14
    # Code 15 is a homogeneous sign/zero MAC introduced in revision 7. It uses
    # the local L48 accumulator and never infers a general multiplier. Code 16
    # remains unavailable; S27xS27 multiply is a scheduled shared resource.
    PHI_ACCUMULATE = 15
    ACCUMULATOR_READ = 17
    SATURATING_ADD = 18
    SATURATING_SUB = 19
    PHI_SIGN_SCALE = 20
    ACCUMULATOR_CLEAR = 21
    PHI_ACCUMULATOR_CAPTURE = 22
    PHI_RESIDUAL_CAPTURE = 23
    PHI_DATA_ACCUMULATE = 24


class OperandSource(IntEnum):
    ZERO = 0
    LOCAL_RF = 1
    NORTH = 2
    EAST = 3
    SOUTH = 4
    WEST = 5
    ACCUMULATOR = 6
    EXTERNAL = 7


class RouteSource(IntEnum):
    HOLD = 0
    PE_RESULT = 1
    NORTH = 2
    EAST = 3
    SOUTH = 4
    WEST = 5
    ROW_OR_COLUMN_EXPRESS = 6
    EXTERNAL = 7


class NextPcMode(IntEnum):
    SEQUENTIAL = 0
    JUMP = 1
    COUNTED_LOOP = 2
    PREDICATE_SELECT = 3
    WAIT_EVENT = 4
    RETURN_TO_PHASE = 5


class LoopLimitSource(IntEnum):
    IMMEDIATE = 0
    MEASUREMENT_COUNT = 1
    SIGNAL_LENGTH = 2
    SPARSITY_LEVEL = 3
    TWICE_SPARSITY = 4
    THREE_TIMES_SPARSITY = 5
    OUTER_ITERATION_LIMIT = 6
    REFINEMENT_ITERATION_LIMIT = 7
    RUN_PARAMETER_0 = 8
    RUN_PARAMETER_1 = 9
    MEASUREMENT_STRIPES_16 = 10
    ACTIVE_WORK_STRIPES_16 = 11
    SIGNAL_LENGTH_STRIPES_16 = 12
    SIGNAL_LENGTH_MINUS_IMMEDIATE = 13


class PhaseOperation(IntEnum):
    NOP = 0
    LAUNCH_ARRAY = 1
    WAIT_CONDITION = 2
    BRANCH = 3
    COMPLETE = 4
    RAISE_ERROR = 5


class PhaseCondition(IntEnum):
    ALWAYS = 0
    ARRAY_ROUTINE_DONE = 1
    RESOURCE_EVENT = 2
    DMA_DONE = 3
    RESIDUAL_LIMIT = 4
    ITERATION_LIMIT = 5
    SUPPORT_STABLE = 6
    RESIDUAL_DECREASED = 7
    SOLVER_CONVERGED = 8
    SOLVER_FAULT = 9
    ABORT_PENDING = 10
    ERROR_PENDING = 11
    SOLVER_RECOMPUTE_REQUIRED = 12
    SOLVER_REPLACEMENT_REQUIRED = 13


class ExternalStreamSource(IntEnum):
    ZERO = 0
    VECTOR_A = 1
    VECTOR_B = 2
    SCALAR_BROADCAST = 3


class PhiStreamCommand(IntEnum):
    IDLE = 0
    START = 1
    CONSUME = 2
    STOP = 3


class ResourceOperation(IntEnum):
    NOP = 0
    REDUCE_SUM = 1
    REDUCE_NORM_SQ = 2
    REDUCE_MAX_ABS = 3
    ARGMAX = 4
    TOPK_PUSH = 5
    TOPK_COMMIT = 6
    SUPPORT_CLEAR = 7
    SUPPORT_APPEND = 8
    SUPPORT_UNION = 9
    SUPPORT_MEMBERSHIP = 10
    SUPPORT_GATHER = 11
    SUPPORT_SCATTER = 12
    SUPPORT_COMMIT = 13
    SUPPORT_ROLLBACK = 14
    SCALAR_RECIPROCAL = 15
    SCALAR_DIVIDE = 16
    SCALAR_SQRT = 17
    DMA_PREFETCH = 18
    DMA_DRAIN = 19
    SHARED_VECTOR_DOT = 20
    SHARED_VECTOR_NORM_SQ = 21
    SHARED_VECTOR_SCALE = 22
    SHARED_VECTOR_AXPY = 23
    SHARED_VECTOR_COPY = 24
    REFINEMENT_CHECK = 25


class ResourceInput(IntEnum):
    NONE = 0
    EAST_EDGE = 1
    CLUSTER_REDUCTION = 2
    MEMORY_STREAM = 3
    SUPPORT_STREAM = 4
    SCALAR_0 = 5
    SCALAR_1 = 6
    GLOBAL_REDUCTION = 7


class ResourceOutput(IntEnum):
    DISCARD = 0
    SCALAR_0 = 1
    SCALAR_1 = 2
    MEMORY_STREAM = 3
    SUPPORT_STREAM = 4
    TOPK_STATE = 5
    PE_SCALAR_BROADCAST = 6
    EVENT = 7


class ResourceCountSource(IntEnum):
    IMMEDIATE = 0
    MEASUREMENT_COUNT = 1
    SIGNAL_LENGTH = 2
    SPARSITY_LEVEL = 3
    TWICE_SPARSITY = 4
    THREE_TIMES_SPARSITY = 5
    ACTIVE_SUPPORT_COUNT = 6
    ACTIVE_WORK_COUNT = 7
    CONFIGURATION_LENGTH = 8
    REFINEMENT_ITERATION_LIMIT = 9


class StreamBoundary(IntEnum):
    BODY = 0
    FIRST = 1
    LAST = 2
    SINGLE = 3


class MemorySpace(IntEnum):
    VECTOR_SCRATCHPAD = 0
    SUPPORT_WORKSPACE = 1
    EXTERNAL_DMA_WINDOW = 2
    PHI_COORDINATE_STREAM = 3


class ElementFormat(IntEnum):
    DATA18 = 0
    SOLVER27 = 1
    ACC62 = 2
    INDEX10 = 3
    BITMAP1 = 4
    RAW32 = 5
    RAW64 = 6


class BankMode(IntEnum):
    LINEAR = 0
    CYCLIC = 1
    BROADCAST = 2
    CLUSTER_LOCAL = 3
    PING_PONG = 4
    SUPPORT_ROW_MAJOR = 5


class PackingMode(IntEnum):
    ONE = 0
    TWO = 1
    FOUR = 2
    SIX = 3
    SEVEN = 4
    RAW72 = 5


@dataclass(frozen=True)
class Field:
    lsb: int
    width: int

    @property
    def mask(self) -> int:
        return ((1 << self.width) - 1) << self.lsb


TILE_FIELDS = {
    "operation": Field(0, 5),
    "source_a": Field(5, 3),
    "source_b": Field(8, 3),
    "rf_read_a": Field(11, 3),
    "rf_read_b": Field(14, 3),
    "rf_write_address": Field(17, 3),
    "rf_write_enable": Field(20, 1),
    "predicate_select": Field(21, 2),
    "predicate_invert": Field(23, 1),
    "route_north_select": Field(24, 3),
    "route_east_select": Field(27, 3),
    "route_south_select": Field(30, 3),
    "route_west_select": Field(33, 3),
}


ARRAY_CONTROL_FIELDS = {
    "next_pc": Field(0, 8),
    "next_pc_mode": Field(8, 3),
    "loop_counter_select": Field(11, 2),
    "loop_counter_reset": Field(13, 1),
    "loop_counter_increment": Field(14, 1),
    "loop_limit_select": Field(15, 4),
    "loop_limit_immediate": Field(19, 8),
    "predicate_select": Field(27, 3),
    "predicate_invert": Field(30, 1),
    "cluster_enable_mask": Field(31, 2),
    "routine_done": Field(33, 1),
    "safe_abort_point": Field(34, 1),
    # Revision 6 reuses the redundant revision-5 stall_on_resource bit.
    # Resource waits are already explicit in RESOURCE_FIELDS. Keeping the word
    # at 36 bits avoids another context RAM plane.
    "guaranteed_commit": Field(35, 1),
}


STREAM_FIELDS = {
    "vector_read_a_enable": Field(0, 1),
    "vector_read_b_enable": Field(1, 1),
    "vector_write_enable": Field(2, 1),
    "vector_configuration_a": Field(3, 6),
    "vector_configuration_b": Field(9, 6),
    "vector_configuration_write": Field(15, 6),
    "external_a_select": Field(21, 2),
    "external_b_select": Field(23, 2),
    "phi_command": Field(25, 2),
    "phi_configuration_id": Field(27, 6),
    "advance_vector_streams": Field(33, 1),
    "stall_on_input": Field(34, 1),
    "stall_on_output": Field(35, 1),
}


PHASE_FIELDS = {
    "operation": Field(0, 3),
    "array_entry_pc": Field(3, 8),
    "condition_select": Field(11, 4),
    "condition_invert": Field(15, 1),
    "target_pc": Field(16, 8),
    "event_id": Field(24, 4),
    "terminal_code": Field(28, 4),
    "safe_abort_point": Field(32, 1),
    "trace_emit": Field(33, 1),
    "reserved": Field(34, 2),
}


RESOURCE_FIELDS = {
    "operation": Field(0, 5),
    "input_select": Field(5, 3),
    "output_select": Field(8, 3),
    "configuration_id": Field(11, 6),
    "count_select": Field(17, 4),
    "lane_mask": Field(21, 4),
    "stream_boundary": Field(25, 2),
    "clear_before": Field(27, 1),
    "accumulate": Field(28, 1),
    "commit_after": Field(29, 1),
    "wait_for_ready": Field(30, 1),
    "wait_for_result": Field(31, 1),
    "event_id": Field(32, 4),
}


MEMORY_CONFIGURATION_FIELDS = {
    "base_word_address": Field(0, 16),
    "element_count": Field(16, 16),
    "element_stride_words": Field(32, 12),
    "bank_base": Field(44, 3),
    "bank_count_log2": Field(47, 2),
    "bank_mode": Field(49, 3),
    "element_format": Field(52, 3),
    "packing_mode": Field(55, 3),
    "read_enable": Field(58, 1),
    "write_enable": Field(59, 1),
    "atomic_commit": Field(60, 1),
    "memory_space": Field(61, 2),
    "reserved": Field(63, 1),
}


TILE_ENUM_FIELDS = {
    "operation": TileOperation,
    "source_a": OperandSource,
    "source_b": OperandSource,
    "route_north_select": RouteSource,
    "route_east_select": RouteSource,
    "route_south_select": RouteSource,
    "route_west_select": RouteSource,
}

ARRAY_CONTROL_ENUM_FIELDS = {
    "next_pc_mode": NextPcMode,
    "loop_limit_select": LoopLimitSource,
}

PHASE_ENUM_FIELDS = {
    "operation": PhaseOperation,
    "condition_select": PhaseCondition,
}

STREAM_ENUM_FIELDS = {
    "external_a_select": ExternalStreamSource,
    "external_b_select": ExternalStreamSource,
    "phi_command": PhiStreamCommand,
}

RESOURCE_ENUM_FIELDS = {
    "operation": ResourceOperation,
    "input_select": ResourceInput,
    "output_select": ResourceOutput,
    "count_select": ResourceCountSource,
    "stream_boundary": StreamBoundary,
}

MEMORY_CONFIGURATION_ENUM_FIELDS = {
    "bank_mode": BankMode,
    "element_format": ElementFormat,
    "packing_mode": PackingMode,
    "memory_space": MemorySpace,
}


@dataclass(frozen=True)
class TileContext:
    operation: int = TileOperation.NOP
    source_a: int = OperandSource.ZERO
    source_b: int = OperandSource.ZERO
    rf_read_a: int = 0
    rf_read_b: int = 0
    rf_write_address: int = 0
    rf_write_enable: int = 0
    predicate_select: int = 0
    predicate_invert: int = 0
    route_north_select: int = RouteSource.HOLD
    route_east_select: int = RouteSource.HOLD
    route_south_select: int = RouteSource.HOLD
    route_west_select: int = RouteSource.HOLD


@dataclass(frozen=True)
class ArrayControlContext:
    next_pc: int = 0
    next_pc_mode: int = NextPcMode.SEQUENTIAL
    loop_counter_select: int = 0
    loop_counter_reset: int = 0
    loop_counter_increment: int = 0
    loop_limit_select: int = LoopLimitSource.IMMEDIATE
    loop_limit_immediate: int = 0
    predicate_select: int = 0
    predicate_invert: int = 0
    cluster_enable_mask: int = 0b11
    routine_done: int = 0
    safe_abort_point: int = 0
    guaranteed_commit: int = 0


@dataclass(frozen=True)
class PhaseInstruction:
    operation: int = PhaseOperation.NOP
    array_entry_pc: int = 0
    condition_select: int = PhaseCondition.ALWAYS
    condition_invert: int = 0
    target_pc: int = 0
    event_id: int = 0
    terminal_code: int = 0
    safe_abort_point: int = 0
    trace_emit: int = 0
    reserved: int = 0


@dataclass(frozen=True)
class StreamContext:
    vector_read_a_enable: int = 0
    vector_read_b_enable: int = 0
    vector_write_enable: int = 0
    vector_configuration_a: int = 0
    vector_configuration_b: int = 0
    vector_configuration_write: int = 0
    external_a_select: int = ExternalStreamSource.ZERO
    external_b_select: int = ExternalStreamSource.ZERO
    phi_command: int = PhiStreamCommand.IDLE
    phi_configuration_id: int = 0
    advance_vector_streams: int = 0
    stall_on_input: int = 0
    stall_on_output: int = 0


@dataclass(frozen=True)
class ResourceContext:
    operation: int = ResourceOperation.NOP
    input_select: int = ResourceInput.NONE
    output_select: int = ResourceOutput.DISCARD
    configuration_id: int = 0
    count_select: int = ResourceCountSource.IMMEDIATE
    lane_mask: int = 0
    stream_boundary: int = StreamBoundary.BODY
    clear_before: int = 0
    accumulate: int = 0
    commit_after: int = 0
    wait_for_ready: int = 0
    wait_for_result: int = 0
    event_id: int = 0


@dataclass(frozen=True)
class MemoryConfiguration:
    base_word_address: int = 0
    element_count: int = 0
    element_stride_words: int = 0
    bank_base: int = 0
    bank_count_log2: int = 0
    bank_mode: int = BankMode.LINEAR
    element_format: int = ElementFormat.DATA18
    packing_mode: int = PackingMode.FOUR
    read_enable: int = 0
    write_enable: int = 0
    atomic_commit: int = 0
    memory_space: int = MemorySpace.VECTOR_SCRATCHPAD
    reserved: int = 0


def _pack(instance: object, layout: dict[str, Field]) -> int:
    value = 0
    for item in fields(instance):
        field = layout[item.name]
        raw = int(getattr(instance, item.name))
        if raw < 0 or raw >= (1 << field.width):
            raise ValueError(f"{item.name}={raw} does not fit {field.width} bits")
        value |= raw << field.lsb
    return value


def _validate_enums(instance: object, enum_fields: dict[str, type[IntEnum]]) -> None:
    for name, enum_type in enum_fields.items():
        raw = int(getattr(instance, name))
        try:
            enum_type(raw)
        except ValueError as exc:
            raise ValueError(
                f"{name}={raw} is not defined by context format revision "
                f"{CONTEXT_FORMAT_REVISION}"
            ) from exc


def _validate_layout(cls: type, layout: dict[str, Field], width: int) -> None:
    class_fields = {item.name for item in fields(cls)}
    if class_fields != set(layout):
        raise RuntimeError(f"{cls.__name__} fields do not match bit layout")
    occupied = 0
    for name, field in layout.items():
        if field.width <= 0 or field.lsb < 0 or field.lsb + field.width > width:
            raise RuntimeError(f"{cls.__name__}.{name} lies outside {width}-bit word")
        if occupied & field.mask:
            raise RuntimeError(f"{cls.__name__}.{name} overlaps another field")
        occupied |= field.mask
    if occupied != (1 << width) - 1:
        raise RuntimeError(f"{cls.__name__} bit layout does not cover {width} bits")


def _unpack(word: int, cls: type, layout: dict[str, Field], width: int) -> object:
    if word < 0 or word >= (1 << width):
        raise ValueError(f"context word does not fit {width} bits")
    values = {name: (word & field.mask) >> field.lsb for name, field in layout.items()}
    instance = cls(**values)
    return instance


def pack_tile(context: TileContext) -> int:
    _validate_enums(context, TILE_ENUM_FIELDS)
    return _pack(context, TILE_FIELDS)


def unpack_tile(word: int) -> TileContext:
    context = _unpack(word, TileContext, TILE_FIELDS, TILE_CONTEXT_WIDTH)
    _validate_enums(context, TILE_ENUM_FIELDS)
    return context  # type: ignore[return-value]


def pack_array_control(context: ArrayControlContext) -> int:
    if context.cluster_enable_mask == 0:
        raise ValueError("array-control cluster_enable_mask must enable a cluster")
    _validate_enums(context, ARRAY_CONTROL_ENUM_FIELDS)
    return _pack(context, ARRAY_CONTROL_FIELDS)


def unpack_array_control(word: int) -> ArrayControlContext:
    context = _unpack(
        word, ArrayControlContext, ARRAY_CONTROL_FIELDS, ARRAY_CONTROL_CONTEXT_WIDTH
    )
    if context.cluster_enable_mask == 0:
        raise ValueError("array-control cluster_enable_mask must enable a cluster")
    _validate_enums(context, ARRAY_CONTROL_ENUM_FIELDS)
    return context  # type: ignore[return-value]


def pack_phase(instruction: PhaseInstruction) -> int:
    if instruction.reserved != 0:
        raise ValueError("phase instruction reserved bits must be zero")
    _validate_enums(instruction, PHASE_ENUM_FIELDS)
    return _pack(instruction, PHASE_FIELDS)


def unpack_phase(word: int) -> PhaseInstruction:
    instruction = _unpack(word, PhaseInstruction, PHASE_FIELDS, PHASE_INSTRUCTION_WIDTH)
    if instruction.reserved != 0:
        raise ValueError("phase instruction reserved bits must be zero")
    _validate_enums(instruction, PHASE_ENUM_FIELDS)
    return instruction  # type: ignore[return-value]


def _validate_stream_semantics(context: StreamContext) -> None:
    if not context.vector_read_a_enable and context.vector_configuration_a != 0:
        raise ValueError("disabled vector A read must use configuration 0")
    if not context.vector_read_b_enable and context.vector_configuration_b != 0:
        raise ValueError("disabled vector B read must use configuration 0")
    if not context.vector_write_enable and context.vector_configuration_write != 0:
        raise ValueError("disabled vector write must use configuration 0")
    if (context.external_a_select == ExternalStreamSource.VECTOR_A or
            context.external_b_select == ExternalStreamSource.VECTOR_A):
        if not context.vector_read_a_enable:
            raise ValueError("VECTOR_A external source requires vector A read")
    if (context.external_a_select == ExternalStreamSource.VECTOR_B or
            context.external_b_select == ExternalStreamSource.VECTOR_B):
        if not context.vector_read_b_enable:
            raise ValueError("VECTOR_B external source requires vector B read")
    if context.phi_command != PhiStreamCommand.START and context.phi_configuration_id != 0:
        raise ValueError("Phi configuration ID is only encoded by START")
    if context.advance_vector_streams and not (
            context.vector_read_a_enable or context.vector_read_b_enable or
            context.vector_write_enable):
        raise ValueError("vector advance requires an enabled vector stream")


def pack_stream(context: StreamContext) -> int:
    _validate_enums(context, STREAM_ENUM_FIELDS)
    _validate_stream_semantics(context)
    return _pack(context, STREAM_FIELDS)


def unpack_stream(word: int) -> StreamContext:
    context = _unpack(word, StreamContext, STREAM_FIELDS, STREAM_CONTEXT_WIDTH)
    _validate_enums(context, STREAM_ENUM_FIELDS)
    _validate_stream_semantics(context)
    return context  # type: ignore[return-value]


def pack_resource(context: ResourceContext) -> int:
    _validate_enums(context, RESOURCE_ENUM_FIELDS)
    return _pack(context, RESOURCE_FIELDS)


def unpack_resource(word: int) -> ResourceContext:
    context = _unpack(word, ResourceContext, RESOURCE_FIELDS, RESOURCE_CONTEXT_WIDTH)
    _validate_enums(context, RESOURCE_ENUM_FIELDS)
    return context  # type: ignore[return-value]


def validate_context_bundle(
    control: ArrayControlContext,
    stream: StreamContext,
    resource: ResourceContext,
) -> None:
    """Validate cross-word rules that cannot be checked by one codec alone.

    ``guaranteed_commit`` is a compiler certificate.  It is legal only when
    the encoded cycle has no operation whose completion can depend on a
    runtime ready/valid join.  The RTL write-time certifier implements the
    same rule from generated constants before the context enters an image.
    """
    if not control.guaranteed_commit:
        return
    if control.next_pc_mode == NextPcMode.WAIT_EVENT:
        raise ValueError("guaranteed commit cannot encode WAIT_EVENT")
    if (stream.vector_read_a_enable or stream.vector_read_b_enable or
            stream.vector_write_enable):
        raise ValueError("guaranteed commit cannot enable a vector stream")
    if stream.phi_command == PhiStreamCommand.CONSUME:
        raise ValueError("guaranteed commit cannot consume a Phi response")
    if stream.stall_on_input or stream.stall_on_output:
        raise ValueError("guaranteed commit cannot encode a stream stall")
    if resource.wait_for_ready or resource.wait_for_result:
        raise ValueError("guaranteed commit cannot wait for a shared resource")


def _validate_memory_configuration_semantics(configuration: MemoryConfiguration) -> None:
    if configuration.memory_space == MemorySpace.PHI_COORDINATE_STREAM:
        if configuration.bank_mode not in (
                BankMode.LINEAR, BankMode.CYCLIC, BankMode.BROADCAST,
                BankMode.CLUSTER_LOCAL, BankMode.SUPPORT_ROW_MAJOR):
            raise ValueError(
                "Phi coordinate mode must be sequential, support-list, repeat or cache replay")
        if configuration.read_enable != 1 or configuration.write_enable != 0:
            raise ValueError("Phi coordinate configuration must be read-only and enabled")
        if configuration.atomic_commit != 0:
            raise ValueError("Phi coordinate configuration cannot request atomic commit")


def pack_memory_configuration(configuration: MemoryConfiguration) -> int:
    if configuration.reserved != 0:
        raise ValueError("memory configuration reserved bits must be zero")
    _validate_enums(configuration, MEMORY_CONFIGURATION_ENUM_FIELDS)
    _validate_memory_configuration_semantics(configuration)
    return _pack(configuration, MEMORY_CONFIGURATION_FIELDS)


def unpack_memory_configuration(word: int) -> MemoryConfiguration:
    configuration = _unpack(
        word, MemoryConfiguration, MEMORY_CONFIGURATION_FIELDS, MEMORY_CONFIGURATION_WIDTH
    )
    if configuration.reserved != 0:
        raise ValueError("memory configuration reserved bits must be zero")
    _validate_enums(configuration, MEMORY_CONFIGURATION_ENUM_FIELDS)
    _validate_memory_configuration_semantics(configuration)
    return configuration  # type: ignore[return-value]


_validate_layout(TileContext, TILE_FIELDS, TILE_CONTEXT_WIDTH)
_validate_layout(ArrayControlContext, ARRAY_CONTROL_FIELDS, ARRAY_CONTROL_CONTEXT_WIDTH)
_validate_layout(StreamContext, STREAM_FIELDS, STREAM_CONTEXT_WIDTH)
_validate_layout(PhaseInstruction, PHASE_FIELDS, PHASE_INSTRUCTION_WIDTH)
_validate_layout(ResourceContext, RESOURCE_FIELDS, RESOURCE_CONTEXT_WIDTH)
_validate_layout(MemoryConfiguration, MEMORY_CONFIGURATION_FIELDS, MEMORY_CONFIGURATION_WIDTH)
