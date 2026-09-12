"""Standalone one-copy, 32-bank GEMV research prototype.

The candidate stores an ``M x N`` integer matrix once.  A coefficient at
``(row, column)`` is placed in

``bank = (row + column) % 32`` and
``address = row * ceil(N / 32) + floor(column / 32)``.

This file models packing, bank requests, and exact integer replay.  It does
not model RTL, pipeline registers, routing timing, DMA, or implementation
quality.  In particular, every cycle and resource number in the report is an
analytic/reference quantity, not a hardware proof.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
from operator import index
from pathlib import Path
from typing import Any, Sequence

BANK_COUNT = 32
COEFFICIENT_BITS = 18
NO_RTL_NO_PIPELINE_PROOF = "NO_RTL_NO_PIPELINE_PROOF"


def _integer(value: Any, name: str, *, minimum: int = 0) -> int:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be an integer, not bool")
    try:
        result = index(value)
    except TypeError as exc:
        raise ValueError(f"{name} must be an integer") from exc
    if result < minimum:
        raise ValueError(f"{name} must be >= {minimum}")
    return result


def _ceil_div(numerator: int, denominator: int) -> int:
    return (numerator + denominator - 1) // denominator


def _checked_values(values: Sequence[int], name: str) -> list[int]:
    try:
        length = len(values)
    except TypeError as exc:
        raise ValueError(f"{name} must be a sequence of integers") from exc
    result: list[int] = []
    for position in range(length):
        value = values[position]
        if isinstance(value, bool):
            raise ValueError(f"{name}[{position}] must be an integer, not bool")
        try:
            result.append(index(value))
        except TypeError as exc:
            raise ValueError(f"{name}[{position}] must be an integer") from exc
    return result


def _validate_matrix(matrix: Sequence[Sequence[int]], rows: int, columns: int) -> list[list[int]]:
    try:
        if len(matrix) != rows:
            raise ValueError("matrix row count differs from layout")
    except TypeError as exc:
        raise ValueError("matrix must be a rectangular sequence") from exc
    checked: list[list[int]] = []
    for row_number, row in enumerate(matrix):
        try:
            if len(row) != columns:
                raise ValueError("matrix shape differs from layout")
        except TypeError as exc:
            raise ValueError("matrix must be a rectangular sequence") from exc
        checked.append(_checked_values(row, f"matrix[{row_number}]") )
    return checked


@dataclass(frozen=True)
class SingleMatrixLayout:
    """The one-copy physical layout for an original ``M x N`` matrix."""

    matrix_rows: int
    matrix_columns: int
    bank_count: int = BANK_COUNT

    def __post_init__(self) -> None:
        _integer(self.matrix_rows, "matrix_rows", minimum=1)
        _integer(self.matrix_columns, "matrix_columns", minimum=1)
        if _integer(self.bank_count, "bank_count", minimum=1) != BANK_COUNT:
            raise ValueError("this prototype has exactly 32 physical banks")

    @property
    def rows(self) -> int:
        return self.matrix_rows

    @property
    def columns(self) -> int:
        return self.matrix_columns

    @property
    def padded_columns(self) -> int:
        return _ceil_div(self.matrix_columns, BANK_COUNT) * BANK_COUNT

    @property
    def column_words(self) -> int:
        return self.padded_columns // BANK_COUNT

    @property
    def bank_depth(self) -> int:
        return self.matrix_rows * self.column_words

    @property
    def payload_words(self) -> int:
        return self.matrix_rows * self.matrix_columns

    @property
    def padded_words(self) -> int:
        return self.bank_count * self.bank_depth

    @property
    def copy_count(self) -> int:
        return 1

    def physical_bank(self, row: int, column: int) -> int:
        row = _integer(row, "row", minimum=0)
        column = _integer(column, "column", minimum=0)
        if row >= self.matrix_rows or column >= self.padded_columns:
            raise ValueError("physical coordinate outside padded matrix")
        return (row + column) % BANK_COUNT

    def physical_address(self, row: int, column: int) -> int:
        row = _integer(row, "row", minimum=0)
        column = _integer(column, "column", minimum=0)
        if row >= self.matrix_rows or column >= self.padded_columns:
            raise ValueError("physical coordinate outside padded matrix")
        return row * self.column_words + column // BANK_COUNT

    def physical_coordinate(self, bank: int, address: int) -> tuple[int, int]:
        """Invert every physical slot, including padded zero columns."""
        bank = _integer(bank, "bank", minimum=0)
        address = _integer(address, "address", minimum=0)
        if bank >= BANK_COUNT or address >= self.bank_depth:
            raise ValueError("physical bank/address outside layout")
        row, word = divmod(address, self.column_words)
        column = word * BANK_COUNT + ((bank - row) % BANK_COUNT)
        return row, column

    # Short aliases make the mapping easy to use from small experiments.
    bank = physical_bank
    address = physical_address
    inverse = physical_coordinate

    def logical_coordinate(self, output: int, reduction: int, *, transpose: bool = False) -> tuple[int, int]:
        output = _integer(output, "output", minimum=0)
        reduction = _integer(reduction, "reduction", minimum=0)
        if transpose:
            if output >= self.matrix_columns or reduction >= self.matrix_rows:
                raise ValueError("logical coordinate outside transposed matrix")
            return reduction, output
        if output >= self.matrix_rows or reduction >= self.matrix_columns:
            raise ValueError("logical coordinate outside matrix")
        return output, reduction

    def logical_address(self, output: int, reduction: int, *, transpose: bool = False) -> tuple[int, int]:
        row, column = self.logical_coordinate(output, reduction, transpose=transpose)
        return self.physical_bank(row, column), self.physical_address(row, column)

    def pack(self, matrix: Sequence[Sequence[int]]) -> tuple[tuple[int, ...], ...]:
        """Pack exact integer coefficients; padded columns are physical zero tails."""
        checked = _validate_matrix(matrix, self.matrix_rows, self.matrix_columns)
        banks = [[0 for _ in range(self.bank_depth)] for _ in range(BANK_COUNT)]
        for row in range(self.matrix_rows):
            for column, value in enumerate(checked[row]):
                bank = self.physical_bank(row, column)
                address = self.physical_address(row, column)
                banks[bank][address] = value
        return tuple(tuple(bank) for bank in banks)

    def unpack(self, banks: Sequence[Sequence[int]]) -> tuple[tuple[int, ...], ...]:
        if len(banks) != BANK_COUNT or any(len(bank) != self.bank_depth for bank in banks):
            raise ValueError("bank image shape differs from layout")
        # Validate every physical word, including padded tails. This keeps a
        # packed image an exact representation of the raw matrix.
        checked_banks: list[list[int]] = []
        for bank_number, bank in enumerate(banks):
            checked_bank: list[int] = []
            for address, value in enumerate(bank):
                if isinstance(value, bool):
                    raise ValueError("bank image values must be integers, not bool")
                try:
                    checked_value = index(value)
                except TypeError as exc:
                    raise ValueError("bank image values must be integers") from exc
                _, column = self.physical_coordinate(bank_number, address)
                if column >= self.matrix_columns and checked_value != 0:
                    raise ValueError("padded bank tail must be zero")
                checked_bank.append(checked_value)
            checked_banks.append(checked_bank)
        result: list[list[int]] = []
        for row in range(self.matrix_rows):
            values: list[int] = []
            for column in range(self.matrix_columns):
                values.append(checked_banks[self.physical_bank(row, column)]
                              [self.physical_address(row, column)])
            result.append(values)
        return tuple(tuple(row) for row in result)

    def verify_inverse_bijection(self) -> bool:
        slots = [self.physical_coordinate(bank, address)
                 for bank in range(BANK_COUNT) for address in range(self.bank_depth)]
        expected = [(row, column) for row in range(self.matrix_rows)
                    for column in range(self.padded_columns)]
        return len(set(slots)) == len(slots) and set(slots) == set(expected)


@dataclass(frozen=True)
class ReadSlot:
    output_index: int
    reduction_index: int
    lane: int
    u: int
    bank: int
    address: int
    active: bool


@dataclass(frozen=True)
class PayloadIssue:
    index: int
    output_tile: int
    reduction_tile: int
    u: int
    reads: tuple[ReadSlot, ...]

    @property
    def active_reads(self) -> tuple[ReadSlot, ...]:
        return tuple(read for read in self.reads if read.active)

    @property
    def active_read_count(self) -> int:
        return sum(read.active for read in self.reads)

    @property
    def tail_mask(self) -> tuple[bool, ...]:
        return tuple(read.active for read in self.reads)


@dataclass(frozen=True)
class SingleMatrixSchedule:
    layout: SingleMatrixLayout
    transpose: bool
    reduction_lanes: int
    accumulator_bits: int = 64

    def __post_init__(self) -> None:
        if not isinstance(self.transpose, bool):
            raise ValueError("transpose must be bool")
        lanes = _integer(self.reduction_lanes, "reduction_lanes", minimum=1)
        if lanes not in (1, 4):
            raise ValueError("only R=1 and R=4 are defined")
        _integer(self.accumulator_bits, "accumulator_bits", minimum=1)

    @property
    def output_count(self) -> int:
        return self.layout.matrix_columns if self.transpose else self.layout.matrix_rows

    @property
    def reduction_count(self) -> int:
        return self.layout.matrix_rows if self.transpose else self.layout.matrix_columns

    @property
    def output_tiles(self) -> int:
        return _ceil_div(self.output_count, 32 if self.reduction_lanes == 1 else 8)

    @property
    def reduction_tiles(self) -> int:
        return _ceil_div(self.reduction_count, 32 if self.reduction_lanes == 4 else 1)

    def _safe_address(self, output: int, reduction: int) -> tuple[int, int]:
        # Masked tail slots still carry a concrete physical address so every
        # recorded request can be audited without optional/None addresses.
        safe_output = min(max(output, 0), self.output_count - 1)
        safe_reduction = min(max(reduction, 0), self.reduction_count - 1)
        return self.layout.logical_address(safe_output, safe_reduction, transpose=self.transpose)

    def requests(self) -> tuple[PayloadIssue, ...]:
        issues: list[PayloadIssue] = []
        if self.reduction_lanes == 1:
            for output_tile, output_base in enumerate(range(0, self.output_count, 32)):
                for reduction in range(self.reduction_count):
                    reads = []
                    for offset in range(32):
                        output = output_base + offset
                        active = output < self.output_count
                        bank, address = (self.layout.logical_address(output, reduction, transpose=self.transpose)
                                         if active else self._safe_address(output, reduction))
                        reads.append(ReadSlot(output, reduction, 0, 0, bank, address, active))
                    issues.append(PayloadIssue(len(issues), output_tile, reduction, 0, tuple(reads)))
            return tuple(issues)

        for output_tile, output_base in enumerate(range(0, self.output_count, 8)):
            for reduction_tile, reduction_base in enumerate(range(0, self.reduction_count, 32)):
                # u is the eighth-of-a-block issue index.  Every issue has
                # 8 outputs x 4 lanes and therefore at most 32 reads.
                for u in range(8):
                    reads = []
                    for output_offset in range(8):
                        output = output_base + output_offset
                        for lane in range(4):
                            reduction = reduction_base + 8 * lane + u
                            active = output < self.output_count and reduction < self.reduction_count
                            bank, address = (self.layout.logical_address(output, reduction, transpose=self.transpose)
                                             if active else self._safe_address(output, reduction))
                            reads.append(ReadSlot(output, reduction, lane, u, bank, address, active))
                    issues.append(PayloadIssue(len(issues), output_tile, reduction_tile, u, tuple(reads)))
        return tuple(issues)

    generate_requests = requests

    def metrics(self) -> dict[str, Any]:
        issues = self.requests()
        conflict_count = 0
        max_reads = 0
        max_vector_words = 0
        for issue in issues:
            active = issue.active_reads
            banks = [read.bank for read in active]
            if len(banks) != len(set(banks)):
                conflict_count += 1
            max_reads = max(max_reads, len(active))
            max_vector_words = max(max_vector_words, len({read.reduction_index for read in active}))
        nominal = (self.output_tiles * self.reduction_tiles *
                   (1 if self.reduction_lanes == 1 else 8))
        return {
            "orientation": "transpose" if self.transpose else "forward",
            "O": self.output_count,
            "K": self.reduction_count,
            "reduction_lanes": self.reduction_lanes,
            "useful_macs": self.output_count * self.reduction_count,
            "payload_issues": len(issues),
            "nominal_payload_issues": nominal,
            "active_payload_issues": sum(issue.active_read_count > 0 for issue in issues),
            "max32_reads": max_reads <= 32,
            "max_active_reads_per_issue": max_reads,
            "max32_reads_per_issue": max_reads,
            "vector_unique_words_per_issue_max": max_vector_words,
            "vector_unique_words_per_mac_cycle_max": max_vector_words,
            "bank_read_conflict_count": conflict_count,
            "bank_read_conflict_assertions_passed": conflict_count == 0,
            "tail_mask_explicit": True,
            "all_recorded_bank_addresses_concrete": all(
                isinstance(read.bank, int) and isinstance(read.address, int)
                for issue in issues for read in issue.reads),
            "matrix_bank_count": BANK_COUNT,
            "matrix_bank_depth": self.layout.bank_depth,
            "matrix_storage_words_payload": self.layout.payload_words,
            "matrix_storage_words_padded": self.layout.padded_words,
            "matrix_storage_bits_padded_at_C18": self.layout.padded_words * COEFFICIENT_BITS,
            "single_matrix_copy": True,
            "accumulator_bits": self.accumulator_bits,
            "proof_status": NO_RTL_NO_PIPELINE_PROOF,
            "overhead_status": "unknown_or_reference_only",
            "costs_excluded": ["RTL/pipeline/register timing", "DMA/refill", "router implementation",
                               "support gather/execution", "RII or free-RII claims"],
        }

    def to_dict(self) -> dict[str, Any]:
        return {"schema": "cscgra-v4-single-matrix-gemv-prototype-v1",
                "layout": asdict(self.layout), "transpose": self.transpose,
                "reduction_lanes": self.reduction_lanes,
                "accumulator_bits": self.accumulator_bits, "metrics": self.metrics()}


def compile_single_matrix(matrix_rows: int, matrix_columns: int, *, transpose: bool = False,
                          reduction_lanes: int = 1, accumulator_bits: int = 64) -> SingleMatrixSchedule:
    rows = _integer(matrix_rows, "matrix_rows", minimum=1)
    columns = _integer(matrix_columns, "matrix_columns", minimum=1)
    return SingleMatrixSchedule(SingleMatrixLayout(rows, columns), transpose,
                                _integer(reduction_lanes, "reduction_lanes", minimum=1),
                                _integer(accumulator_bits, "accumulator_bits", minimum=1))


def direct_gemv(matrix: Sequence[Sequence[int]], vector: Sequence[int], *, transpose: bool = False) -> list[int]:
    rows = len(matrix)
    if rows < 1:
        raise ValueError("matrix must have at least one row")
    columns = len(matrix[0])
    if columns < 1:
        raise ValueError("matrix must have at least one column")
    checked = _validate_matrix(matrix, rows, columns)
    values = _checked_values(vector, "vector")
    if len(values) != (rows if transpose else columns):
        raise ValueError("vector length differs from matrix orientation")
    if transpose:
        return [sum(checked[row][output] * values[row] for row in range(rows))
                for output in range(columns)]
    return [sum(checked[row][column] * values[column] for column in range(columns))
            for row in range(rows)]


def replay_gemv(schedule: SingleMatrixSchedule, matrix: Sequence[Sequence[int]], vector: Sequence[int], *,
                check_accumulator_range: bool = True,
                packed_banks: Sequence[Sequence[int]] | None = None) -> list[int]:
    """Replay bank requests and exact integer reductions.

    R4 checks each lane prefix as requests arrive, then checks both pair sums
    and the final sum in the specified ``(0+1)+(2+3)`` order.  These checks
    intentionally reject a narrow lane overflow even if the final total fits.
    """
    checked_matrix = _validate_matrix(matrix, schedule.layout.matrix_rows, schedule.layout.matrix_columns)
    values = _checked_values(vector, "vector")
    if len(values) != schedule.reduction_count:
        raise ValueError("vector length differs from schedule orientation")
    banks = schedule.layout.pack(checked_matrix) if packed_banks is None else packed_banks
    if packed_banks is not None:
        # Keep the mathematical replay auditable: an externally supplied image
        # must be exactly the one-copy packing of the stated raw matrix.
        if schedule.layout.unpack(banks) != tuple(tuple(row) for row in checked_matrix):
            raise ValueError("packed bank image differs from raw matrix")
    issues = schedule.requests()
    width = schedule.accumulator_bits

    def bounded(value: int, where: str) -> int:
        if check_accumulator_range and not -(1 << (width - 1)) <= value < (1 << (width - 1)):
            raise ValueError(f"{where} overflow at {width} bits")
        return value

    if schedule.reduction_lanes == 1:
        accumulators = [0] * schedule.output_count
        for issue in issues:
            used_banks: set[int] = set()
            for read in issue.active_reads:
                if read.bank in used_banks:
                    raise ValueError(f"matrix bank read conflict in issue {issue.index}")
                used_banks.add(read.bank)
                expected = schedule.layout.logical_address(read.output_index, read.reduction_index,
                                                            transpose=schedule.transpose)
                if (read.bank, read.address) != expected:
                    raise ValueError("request steering differs from physical layout")
                row, column = schedule.layout.physical_coordinate(read.bank, read.address)
                coefficient = banks[read.bank][read.address]
                if (row, column) != schedule.layout.logical_coordinate(read.output_index, read.reduction_index,
                                                                        transpose=schedule.transpose):
                    raise ValueError("request inverse differs from logical coordinate")
                accumulators[read.output_index] = bounded(
                    accumulators[read.output_index] + coefficient * values[read.reduction_index],
                    f"R1 output {read.output_index} prefix")
        return accumulators

    # Each output has four independent exact integer lane partials.
    partials = [[0, 0, 0, 0] for _ in range(schedule.output_count)]
    for issue in issues:
        used_banks: set[int] = set()
        for read in issue.active_reads:
            if read.bank in used_banks:
                raise ValueError(f"matrix bank read conflict in issue {issue.index}")
            used_banks.add(read.bank)
            expected = schedule.layout.logical_address(read.output_index, read.reduction_index,
                                                       transpose=schedule.transpose)
            if (read.bank, read.address) != expected:
                raise ValueError("request steering differs from physical layout")
            row, column = schedule.layout.physical_coordinate(read.bank, read.address)
            if (row, column) != schedule.layout.logical_coordinate(read.output_index, read.reduction_index,
                                                                    transpose=schedule.transpose):
                raise ValueError("request inverse differs from logical coordinate")
            partials[read.output_index][read.lane] = bounded(
                partials[read.output_index][read.lane] + banks[read.bank][read.address] * values[read.reduction_index],
                f"R4 output {read.output_index} lane {read.lane} prefix")
    result: list[int] = []
    for output, lane in enumerate(partials):
        pair01 = bounded(lane[0] + lane[1], f"R4 output {output} pair01")
        pair23 = bounded(lane[2] + lane[3], f"R4 output {output} pair23")
        result.append(bounded(pair01 + pair23, f"R4 output {output} final"))
    return result


# Conventional names for small scripts using the prototype.
compile_gemv = compile_single_matrix
replay = replay_gemv


def generate_requests(schedule: SingleMatrixSchedule, matrix: Sequence[Sequence[int]] | None = None,
                      vector: Sequence[int] | None = None) -> tuple[PayloadIssue, ...]:
    """Return concrete bank requests; optional operands are accepted for CLI ergonomics.

    Request generation depends only on shape/orientation.  When operands are
    supplied, validate them here so a request dump cannot silently use a
    malformed integer matrix or vector.
    """
    if matrix is not None:
        _validate_matrix(matrix, schedule.layout.matrix_rows, schedule.layout.matrix_columns)
    if vector is not None:
        values = _checked_values(vector, "vector")
        if len(values) != schedule.reduction_count:
            raise ValueError("vector length differs from schedule orientation")
    return schedule.requests()


def _reference_two_orientation(rows: int, columns: int, reduction_lanes: int) -> dict[str, Any]:
    forward_words = 32 * _ceil_div(rows, 32) * columns
    transpose_words = 32 * _ceil_div(columns, 32) * rows
    if reduction_lanes == 1:
        forward_issues = _ceil_div(rows, 32) * columns
        transpose_issues = _ceil_div(columns, 32) * rows
    else:
        # Existing twoorientationMatrixLayout R4 has four reduction lanes;
        # count its MAC payload phases separately from this candidate's eight
        # u issues per 32-word block.
        forward_issues = _ceil_div(rows, 8) * _ceil_div(columns, 4)
        transpose_issues = _ceil_div(columns, 8) * _ceil_div(rows, 4)
    dual_words = forward_words + transpose_words
    forward_depth = _ceil_div(rows, 32) * columns
    transpose_depth = _ceil_div(columns, 32) * rows
    return {"status": "reference_formula_only", "reference": "existing twoorientation MatrixLayout formulas",
            "copies": 2,
            "forward_padded_words": forward_words, "transpose_padded_words": transpose_words,
            "dual_padded_words": dual_words,
            "dual_storage_bits_at_C18": dual_words * COEFFICIENT_BITS,
            "dual_storage_KiB_at_C18": dual_words * COEFFICIENT_BITS / 8 / 1024,
            "forward_bram36_at_C18": BANK_COUNT * _ceil_div(forward_depth, 2048),
            "transpose_bram36_at_C18": BANK_COUNT * _ceil_div(transpose_depth, 2048),
            "dual_bram36_at_C18": BANK_COUNT * (_ceil_div(forward_depth, 2048) + _ceil_div(transpose_depth, 2048)),
            "forward_payload_issues": forward_issues, "transpose_payload_issues": transpose_issues}


def build_study_report(rows: int = 128, columns: int = 1024) -> dict[str, Any]:
    rows = _integer(rows, "rows", minimum=1)
    columns = _integer(columns, "columns", minimum=1)
    layout = SingleMatrixLayout(rows, columns)
    orientations: dict[str, Any] = {}
    for transpose in (False, True):
        key = "transpose" if transpose else "forward"
        orientations[key] = {f"R{lanes}": compile_single_matrix(
            rows, columns, transpose=transpose, reduction_lanes=lanes).metrics()
            for lanes in (1, 4)}
    restricted: dict[str, Any] = {}
    if rows == 128:
        for support in (8, 32, 96):
            restricted[f"M{rows}S{support}"] = {
                "forward_R1": compile_single_matrix(rows, support, reduction_lanes=1).metrics(),
                "forward_R4": compile_single_matrix(rows, support, reduction_lanes=4).metrics(),
                "transpose_R1": compile_single_matrix(rows, support, transpose=True, reduction_lanes=1).metrics(),
                "transpose_R4": compile_single_matrix(rows, support, transpose=True, reduction_lanes=4).metrics(),
                "two_orientation_reference": _reference_two_orientation(rows, support, 4),
            }
    source_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    return {
        "schema": "cscgra-v4-single-matrix-study-v1",
        "claim_status": NO_RTL_NO_PIPELINE_PROOF,
        "source_hash_sha256": source_hash,
        "candidate": {
            "mapping": "bank=(row+column)%32; address=row*ceil(N/32)+floor(column/32)",
            "address_behavior": "row-dependent per-bank addresses",
            "arbitrary_32word_barrel_rotation": "required_but_not_implemented; existing reference only covers multiples of eight",
            "padcolumns": 32,
            "physical_banks": BANK_COUNT,
            "copies": 1,
            "coefficient_bits": COEFFICIENT_BITS,
            "matrix_rows_M": rows, "matrix_columns_N": columns,
            "bank_depth": layout.bank_depth,
            "padded_words": layout.padded_words,
            "payload_words": layout.payload_words,
            "padded_storage_bits": layout.padded_words * COEFFICIENT_BITS,
            "padded_storage_KiB_at_C18": layout.padded_words * COEFFICIENT_BITS / 8 / 1024,
            # Conservative whole-BRAM36-per-bank estimate for an 18-bit
            # logical word (2048 x 18 per BRAM36), with no half packing.
            "bram36_at_C18": BANK_COUNT * _ceil_div(layout.bank_depth, 2048),
            "bram36_allocation": "whole BRAM36 per bank; ceil(bank_depth/2048), no half packing",
        },
        "orientations": orientations,
        "restricted_M128_supports": restricted,
        "two_orientation_reference": _reference_two_orientation(rows, columns, 4),
        "reduction_order": "R4 order changed: lane partials then pairadd((lane0+lane1)+(lane2+lane3)); no cross-cluster links",
        "tails": {"mask_explicit": True, "R4_emits_8_u_issues_per_ceilK32_block": True,
                  "allmasked_tail_issues_allowed": True},
        "limitations": [
            "NO_RTL_NO_PIPELINE_PROOF",
            "Cycle, registered-router, BRAM inference, timing, DMA, and refill overhead are unknown or reference-only.",
            "The R4 reduction order is specified and can reject a lane-prefix overflow even when the final sum fits.",
            "No claim is made that arbitrary bank permutation routing is free or that numerical order is bit-exact to the existing baseline.",
            "Support-cache reuse/gather execution is unmodeled; no support-gather execution result is claimed.",
            "No RII or free-RII claim is made.",
        ],
    }


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=128)
    parser.add_argument("--columns", type=int, default=1024)
    parser.add_argument("--output", type=Path, default=Path("reports/v4/single_matrix_study.json"))
    args = parser.parse_args(argv)
    report = build_study_report(args.rows, args.columns)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "source_hash_sha256": report["source_hash_sha256"],
                      "claim_status": report["claim_status"]}, indent=2))


if __name__ == "__main__":
    main()
