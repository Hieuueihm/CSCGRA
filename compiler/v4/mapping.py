"""Executable 2 x 4 x 4 GEMV schedule candidate; every cycle is predicted.

This is a compiler/model contract, not RTL or a performance measurement. Each
PE needs a pipelined MAC with initiation interval one and a local wide
accumulator. R=1 maps 32 outputs in parallel; R=4 uses four reduction lanes per
output and registered row links for summation. The matrix is resident in 32
separately readable banks. Forward and transpose
use DIFFERENT layouts: storage duplication or repacking must be charged by the
caller. Python replay uses exact integers, with optional accumulator bounds.
The two arrays have no direct inter-array mesh link in this v4 baseline.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, replace
import json
from operator import index
from pathlib import Path
from typing import Sequence


def _integer(value: int, name: str, *, minimum: int = 0) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer, not bool")
    try:
        result = index(value)
    except TypeError as exc:
        raise ValueError(f"{name} must be an integer") from exc
    if result < minimum:
        raise ValueError(f"{name} must be >= {minimum}")
    return result


@dataclass(frozen=True)
class Architecture:
    clusters: int = 2
    rows: int = 4
    columns: int = 4
    link_latency: int = 1
    accumulator_bits: int = 64
    inter_array_neighbor_links: bool = False

    def __post_init__(self) -> None:
        for name in ("clusters", "rows", "columns", "link_latency", "accumulator_bits"):
            _integer(getattr(self, name), name, minimum=1)
        if (self.clusters, self.rows, self.columns, self.link_latency) != (2, 4, 4, 1):
            raise ValueError("this candidate supports exactly two 4x4 arrays with one-cycle links")
        if self.inter_array_neighbor_links is not False:
            raise ValueError("the v4 baseline has no inter-array mesh links")

    @property
    def pe_count(self) -> int:
        return self.clusters * self.rows * self.columns

    def coordinates(self, pe: int) -> tuple[int, int]:
        pe = _integer(pe, "pe")
        if pe >= self.pe_count:
            raise ValueError("PE outside the two arrays")
        return divmod(pe, self.columns)  # Flat display coordinates, not an inter-array link.

    def adjacent(self, source: int, destination: int) -> bool:
        a, b = self.coordinates(source), self.coordinates(destination)
        return source // 16 == destination // 16 and abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1


@dataclass(frozen=True)
class MatrixLayout:
    """Swizzled layout supports R=1 and R=4 without duplicating these modes.

    bank=(output+8*reduction)%32, address=(output//32)*K+reduction.
    Full output groups are padded to 32. Only orientation, not R, changes layout.
    """
    matrix_rows: int
    matrix_columns: int
    transpose: bool = False

    def __post_init__(self) -> None:
        _integer(self.matrix_rows, "matrix_rows", minimum=1)
        _integer(self.matrix_columns, "matrix_columns", minimum=1)
        if not isinstance(self.transpose, bool):
            raise ValueError("transpose must be bool")

    @property
    def output_count(self) -> int:
        return self.matrix_columns if self.transpose else self.matrix_rows

    @property
    def reduction_count(self) -> int:
        return self.matrix_rows if self.transpose else self.matrix_columns

    @property
    def reduction_tiles(self) -> int:
        return (self.reduction_count + 3) // 4

    @property
    def bank_depth(self) -> int:
        return ((self.output_count + 31) // 32) * self.reduction_count

    def coordinates(self, output: int, reduction: int) -> tuple[int, int]:
        output = _integer(output, "output")
        reduction = _integer(reduction, "reduction")
        if output >= self.output_count or reduction >= self.reduction_count:
            raise ValueError("logical matrix coordinate outside layout")
        return (reduction, output) if self.transpose else (output, reduction)

    def address(self, output: int, reduction: int) -> tuple[int, int]:
        self.coordinates(output, reduction)
        return ((output + 8 * reduction) % 32,
                (output // 32) * self.reduction_count + reduction)

    def pack(self, matrix: Sequence[Sequence[int]]) -> tuple[tuple[int | None, ...], ...]:
        if len(matrix) != self.matrix_rows or any(len(row) != self.matrix_columns for row in matrix):
            raise ValueError("matrix shape differs from schedule")
        banks: list[list[int | None]] = [[None] * self.bank_depth for _ in range(32)]
        for output in range(self.output_count):
            for reduction in range(self.reduction_count):
                row, column = self.coordinates(output, reduction)
                value = matrix[row][column]
                if isinstance(value, bool):
                    raise ValueError("matrix values must be integers, not bool")
                try:
                    value = index(value)
                except TypeError as exc:
                    raise ValueError("matrix values must be integers") from exc
                bank, address = self.address(output, reduction)
                if banks[bank][address] is not None:
                    raise ValueError("matrix layout aliases two coefficients")
                banks[bank][address] = value
        return tuple(tuple(bank) for bank in banks)


@dataclass(frozen=True)
class PEEvent:
    pe: int
    operation: str
    output_index: int
    reads: tuple[str, ...] = ()
    writes: str | None = None
    reduction_index: int | None = None
    matrix_bank: int | None = None
    matrix_address: int | None = None


@dataclass(frozen=True)
class RouteEvent:
    source_pe: int
    destination_pe: int
    value_id: str
    delivered_id: str
    width_bits: int


@dataclass(frozen=True)
class BankRead:
    pe: int
    output_index: int
    reduction_index: int
    bank: int
    address: int


@dataclass(frozen=True)
class Cycle:
    index: int
    phase: str
    pe_events: tuple[PEEvent, ...] = ()
    routes: tuple[RouteEvent, ...] = ()
    bank_reads: tuple[BankRead, ...] = ()


@dataclass(frozen=True)
class Schedule:
    architecture: Architecture
    layout: MatrixLayout
    reduction_lanes: int
    cycles: tuple[Cycle, ...]

    @property
    def metrics(self) -> dict:
        macs = sum(e.operation == "MAC" for c in self.cycles for e in c.pe_events)
        return {
            "cycle_evidence": "analytic_schedule_not_rtl_measured",
            "reduction_lanes": self.reduction_lanes,
            "outputs_per_tile": 32 // self.reduction_lanes,
            "predicted_compute_cycles": len(self.cycles),
            "rtl_measured_cycles": None,
            "useful_mac_count": macs,
            "scheduled_reduction_adds": sum(e.operation == "ADD" for c in self.cycles for e in c.pe_events),
            "registered_link_transfers": sum(len(c.routes) for c in self.cycles),
            "mac_slot_utilization": macs / (32 * len(self.cycles)),
            "peak_macs_per_cycle": max(sum(e.operation == "MAC" for e in c.pe_events) for c in self.cycles),
            "matrix_bank_count": 32,
            "matrix_read_latency_cycles": 1,
            "matrix_storage_words_padded": 32 * self.layout.bank_depth,
            "matrix_storage_words_payload": self.layout.output_count * self.layout.reduction_count,
            "matrix_words_read": sum(len(c.bank_reads) for c in self.cycles),
            "unique_vector_words_per_mac_cycle_max": min(self.reduction_lanes, self.layout.reduction_count),
            "output_words_written": self.layout.output_count,
            "required_matrix_read_words_per_cycle_peak": max(sum(e.operation == "MAC" for e in c.pe_events) for c in self.cycles),
            "costs_excluded": ["host/DMA", "matrix refill or forward/transpose layout conversion",
                               "context loading", "backpressure", "numeric boundary normalization"],
        }

    def to_dict(self) -> dict:
        return {"schema": "cscgra-v4-gemv-schedule-candidate-v1", **asdict(self), "metrics": self.metrics}


def predicted_cycles(output_count: int, reduction_count: int, reduction_lanes: int) -> int:
    _integer(output_count, "output_count", minimum=1)
    _integer(reduction_count, "reduction_count", minimum=1)
    reduction_lanes = _integer(reduction_lanes, "reduction_lanes", minimum=1)
    if reduction_lanes not in (1, 4):
        raise ValueError("only R=1 and R=4 have defined bank routing and schedules")
    outputs_per_tile = 32 // reduction_lanes
    overhead = 2 if reduction_lanes == 1 else 7
    return ((output_count + outputs_per_tile - 1) // outputs_per_tile) * (
        (reduction_count + reduction_lanes - 1) // reduction_lanes + overhead)


def compile_gemv(matrix_rows: int, matrix_columns: int, *, transpose: bool = False,
                 architecture: Architecture | None = None,
                 reduction_lanes: int | None = None) -> Schedule:
    """Choose R=1 or R=4 by complete predicted compute cost, or force a mode.

    There is one global schedule/PC with 32 distinct slots. A reduction block
    for R=4 has CLEAR, ceil(K/4) MAC, ROUTE, ADD, ROUTE, ROUTE, ADD, STORE
    cycles. R=1 has CLEAR, K MAC, STORE cycles and no reduction transfers.
    Neighbor results are consumed only on a later cycle. Tail PEs initialize
    to zero and never read nonexistent matrix/vector words.
    """
    arch = architecture or Architecture()
    layout = MatrixLayout(matrix_rows, matrix_columns, transpose)
    if reduction_lanes is None:
        reduction_lanes = min((1, 4), key=lambda r: predicted_cycles(
            layout.output_count, layout.reduction_count, r))
    predicted_cycles(layout.output_count, layout.reduction_count, reduction_lanes)
    output_lanes = 32 // reduction_lanes
    cycles: list[Cycle] = []

    def emit(phase: str, events=(), routes=()) -> None:
        cycles.append(Cycle(len(cycles), phase, tuple(events), tuple(routes)))

    for output_base in range(0, layout.output_count, output_lanes):
        outputs = range(output_base, min(output_base + output_lanes, layout.output_count))
        tags = {(out, col): f"o{out}.c{col}.zero" for out in outputs for col in range(reduction_lanes)}
        emit("clear", [PEEvent((out % output_lanes) * reduction_lanes + col, "CLEAR", out,
                               writes=tags[out, col])
                       for out in outputs for col in range(reduction_lanes)])
        for block in range((layout.reduction_count + reduction_lanes - 1) // reduction_lanes):
            events = []
            for out in outputs:
                for col in range(reduction_lanes):
                    reduction = block * reduction_lanes + col
                    if reduction >= layout.reduction_count:
                        continue
                    bank, address = layout.address(out, reduction)
                    tag = f"o{out}.c{col}.k{reduction}"
                    events.append(PEEvent((out % output_lanes) * reduction_lanes + col, "MAC", out,
                                          (tags[out, col],), tag, reduction, bank, address))
                    tags[out, col] = tag
            emit("mac", events)
        if reduction_lanes == 1:
            emit("store", [PEEvent(out % 32, "STORE", out, (tags[out, 0],)) for out in outputs])
            continue
        emit("pair_route", routes=[RouteEvent((out % 8) * 4 + col,
             (out % 8) * 4 + col - 1, tags[out, col], f"o{out}.r{col}", arch.accumulator_bits)
             for out in outputs for col in (1, 3)])
        emit("pair_add", [PEEvent((out % 8) * 4 + col, "ADD", out,
             (tags[out, col], f"o{out}.r{col+1}"), f"o{out}.sum{col}{col+1}")
             for out in outputs for col in (0, 2)])
        emit("cross_route_1", routes=[RouteEvent((out % 8) * 4 + 2,
             (out % 8) * 4 + 1, f"o{out}.sum23", f"o{out}.cross1", arch.accumulator_bits)
             for out in outputs])
        emit("cross_route_2", routes=[RouteEvent((out % 8) * 4 + 1,
             (out % 8) * 4, f"o{out}.cross1", f"o{out}.cross2", arch.accumulator_bits)
             for out in outputs])
        emit("final_add", [PEEvent((out % 8) * 4, "ADD", out,
             (f"o{out}.sum01", f"o{out}.cross2"), f"o{out}.result") for out in outputs])
        emit("store", [PEEvent((out % 8) * 4, "STORE", out,
                               (f"o{out}.result",)) for out in outputs])
    # Synchronous matrix SRAM: issue each operand read one cycle before MAC.
    # The CLEAR cycle prefetches the first block; subsequent reads pipeline.
    for cycle in tuple(cycles):
        reads = tuple(BankRead(e.pe, e.output_index, e.reduction_index,
                               e.matrix_bank, e.matrix_address)
                      for e in cycle.pe_events if e.operation == "MAC")
        if reads:
            previous = cycles[cycle.index - 1]
            cycles[cycle.index - 1] = replace(previous, bank_reads=reads)
    return Schedule(arch, layout, reduction_lanes, tuple(cycles))


def replay(schedule: Schedule, matrix: Sequence[Sequence[int]], vector: Sequence[int], *,
           check_accumulator_range: bool = True) -> list[int]:
    """Execute recorded bank reads, ALU events and registered link transfers.

    This deliberately does NOT return a separate direct matrix multiply. An
    invalid placement, stale register, same-cycle dependency, bank collision,
    repeated store, wrong coefficient, or missing final store raises ValueError.
    No fixed-point narrowing occurs here; the numeric model owns boundaries.
    """
    arch, layout = schedule.architecture, schedule.layout
    predicted_cycles(layout.output_count, layout.reduction_count, schedule.reduction_lanes)
    output_lanes = 32 // schedule.reduction_lanes
    banks = layout.pack(matrix)
    if len(vector) != layout.reduction_count:
        raise ValueError("vector length differs from schedule")
    try:
        if any(isinstance(value, bool) for value in vector):
            raise TypeError
        values = [index(value) for value in vector]
    except TypeError as exc:
        raise ValueError("vector values must be integers") from exc
    accumulators: dict[int, tuple[str, int]] = {}
    inbox: dict[tuple[int, int], tuple[str, int]] = {}
    coefficient_registers: dict[int, tuple[int, int, int, int, int]] = {}
    result: list[int | None] = [None] * layout.output_count

    def read(pe: int, value_id: str) -> int:
        slots = ([accumulators[pe]] if pe in accumulators else [])
        slots += [value for (destination, _), value in inbox.items() if destination == pe]
        matches = [value for tag, value in slots if tag == value_id]
        if len(matches) != 1:
            raise ValueError(f"value {value_id} is not uniquely available at PE {pe}")
        return matches[0]

    def bounded(value: int, width: int) -> int:
        if check_accumulator_range and not -(1 << (width - 1)) <= value < (1 << (width - 1)):
            raise ValueError(f"accumulator or route overflow at {width} bits")
        return value

    for expected_index, cycle in enumerate(schedule.cycles):
        if cycle.index != expected_index:
            raise ValueError("schedule cycle indices must be contiguous")
        next_acc, next_links, next_coefficients = {}, {}, {}
        used_pes, used_banks, used_links, consumed_coefficients = set(), set(), set(), set()
        for event in cycle.pe_events:
            arch.coordinates(event.pe)
            if event.pe in used_pes:
                raise ValueError("two ALU events occupy one PE slot")
            used_pes.add(event.pe)
            if not 0 <= event.output_index < layout.output_count or (
                    event.pe // schedule.reduction_lanes != event.output_index % output_lanes):
                raise ValueError("output is bound to the wrong physical row")
            expected_reads = {"CLEAR": 0, "MAC": 1, "ADD": 2, "STORE": 1}
            if event.operation not in expected_reads or len(event.reads) != expected_reads[event.operation]:
                raise ValueError("invalid operation or operand count")
            operands = [read(event.pe, tag) for tag in event.reads]
            if event.operation == "CLEAR":
                value = 0
            elif event.operation == "MAC":
                reduction = _integer(event.reduction_index, "reduction_index")
                bank, address = layout.address(event.output_index, reduction)
                expected_pe = (event.output_index % output_lanes) * schedule.reduction_lanes + (
                    reduction % schedule.reduction_lanes)
                if (event.matrix_bank, event.matrix_address) != (bank, address) or event.pe != expected_pe:
                    raise ValueError("MAC coefficient is bound to the wrong bank/address/PE")
                registered = coefficient_registers.get(event.pe)
                if registered is None or registered[:4] != (event.output_index, reduction, bank, address):
                    raise ValueError("MAC coefficient was not read on an earlier cycle")
                coefficient = registered[4]
                consumed_coefficients.add(event.pe)
                value = operands[0] + coefficient * values[reduction]
            elif event.operation == "ADD":
                value = operands[0] + operands[1]
            else:
                if event.pe % schedule.reduction_lanes or result[event.output_index] is not None or event.writes is not None:
                    raise ValueError("invalid or duplicate output store")
                result[event.output_index] = operands[0]
                continue
            if not event.writes:
                raise ValueError("ALU result requires a register tag")
            next_acc[event.pe] = (event.writes, bounded(value, arch.accumulator_bits))
        for request in cycle.bank_reads:
            expected_bank, expected_address = layout.address(request.output_index, request.reduction_index)
            expected_pe = (request.output_index % output_lanes) * schedule.reduction_lanes + (
                request.reduction_index % schedule.reduction_lanes)
            if (request.bank, request.address, request.pe) != (expected_bank, expected_address, expected_pe):
                raise ValueError("matrix read steering differs from bank layout")
            if request.bank in used_banks:
                raise ValueError("matrix bank read conflict")
            if request.pe in next_coefficients:
                raise ValueError("two matrix reads target one PE input register")
            used_banks.add(request.bank)
            value = banks[request.bank][request.address]
            if value is None:
                raise ValueError("uninitialized matrix coefficient")
            next_coefficients[request.pe] = (request.output_index, request.reduction_index,
                                              request.bank, request.address, value)
        for route in cycle.routes:
            if not arch.adjacent(route.source_pe, route.destination_pe):
                raise ValueError("route is not a legal one-hop mesh edge")
            edge = (route.destination_pe, route.source_pe)
            if edge in used_links:
                raise ValueError("registered link capacity exceeded")
            used_links.add(edge)
            if route.width_bits != arch.accumulator_bits or not route.delivered_id:
                raise ValueError("route width/tag differs from architecture contract")
            value = bounded(read(route.source_pe, route.value_id), route.width_bits)
            next_links[edge] = (route.delivered_id, value)
        # All reads above see pre-edge state; a result/link appears next cycle.
        accumulators.update(next_acc)
        inbox.update(next_links)
        for pe in consumed_coefficients:
            del coefficient_registers[pe]
        coefficient_registers.update(next_coefficients)
    if any(value is None for value in result):
        raise ValueError("schedule did not store every output")
    return [int(value) for value in result]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=128)
    parser.add_argument("--columns", type=int, default=1024)
    parser.add_argument("--transpose", action="store_true")
    parser.add_argument("--reduction-lanes", type=int, choices=(1, 4), default=None)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    schedule = compile_gemv(args.rows, args.columns, transpose=args.transpose,
                            reduction_lanes=args.reduction_lanes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(schedule.to_dict(), indent=2) + "\n", encoding="utf-8")
    print(json.dumps(schedule.metrics, indent=2))


if __name__ == "__main__":
    main()
