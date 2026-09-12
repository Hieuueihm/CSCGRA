"""Generated Phi and compact sign-cache reference model for v4.

This module is deliberately a software contract.  It describes coordinates,
packing and integer replay; it does not model a clocked generator or claim an
RTL throughput.  ``Phi`` is generated with the v3 Random123 mapping:
``counter=(column, row_block >> 1)``, ``key=(seed_lo, seed_hi)`` and the
selected output word is ``row_block & 1``.

The first v4 profile is ``A = Phi`` (Psi is the identity).  A transform is
therefore never silently applied by this model.  Callers that need a
non-identity Psi must construct and qualify a separate staged operator.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from numbers import Integral, Real
from typing import Any, Iterable, Iterator, Mapping, Sequence

import numpy as np

from .fixed import Format, Profile


MASK32 = (1 << 32) - 1
THREEFRY_PARITY32 = 0x1BD11BDA
THREEFRY_ROUNDS = 20
THREEFRY_ROTATIONS_2X32 = (13, 15, 26, 6, 17, 29, 16, 24)
ROWS_PER_WORD = 32
BANK_COUNT = 8
GENERATOR_REVISION = 1


def _as_int(value: object, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError(f"{name} must be an integer")
    return int(value)


def _check_nonnegative(value: object, name: str) -> int:
    result = _as_int(value, name)
    if result < 0:
        raise ValueError(f"{name} must be non-negative")
    return result


def _u32(value: int) -> int:
    return int(value) & MASK32


def _rotl32(value: int, amount: int) -> int:
    value = _u32(value)
    return _u32((value << amount) | (value >> (32 - amount)))


def threefry2x32_20(
    counter: tuple[int, int], key: tuple[int, int]
) -> tuple[int, int]:
    """Return the canonical Random123 Threefry2x32-20 output."""

    if len(counter) != 2 or len(key) != 2:
        raise ValueError("counter and key must contain two words")
    key0 = _as_int(key[0], "key_word_0")
    key1 = _as_int(key[1], "key_word_1")
    counter0 = _as_int(counter[0], "counter_word_0")
    counter1 = _as_int(counter[1], "counter_word_1")
    key_words = (
        _u32(key0),
        _u32(key1),
        _u32(THREEFRY_PARITY32 ^ key0 ^ key1),
    )
    x0 = _u32(counter0 + key_words[0])
    x1 = _u32(counter1 + key_words[1])
    for round_index in range(THREEFRY_ROUNDS):
        x0 = _u32(x0 + x1)
        x1 = _rotl32(x1, THREEFRY_ROTATIONS_2X32[round_index & 7]) ^ x0
        if (round_index + 1) % 4 == 0:
            injection = (round_index + 1) // 4
            x0 = _u32(x0 + key_words[injection % 3])
            x1 = _u32(x1 + key_words[(injection + 1) % 3] + injection)
    return x0, x1


def _validate_seed(seed: object) -> int:
    seed = _as_int(seed, "seed")
    if not 0 <= seed < (1 << 64):
        raise ValueError("seed must fit 64 bits")
    return seed


def phi_sign_word(seed: int, column: int, row_block: int) -> int:
    """Return the 32-bit sign word for one column and row block."""

    seed = _validate_seed(seed)
    column = _as_int(column, "column")
    row_block = _as_int(row_block, "row_block")
    if not 0 <= column < (1 << 32):
        raise ValueError("column must fit 32 bits")
    if not 0 <= row_block < (1 << 33):
        raise ValueError("row_block is out of range")
    words = threefry2x32_20(
        (_u32(column), _u32(row_block >> 1)),
        (_u32(seed), _u32(seed >> 32)),
    )
    return words[row_block & 1]


def phi_sign(seed: int, row: int, column: int) -> int:
    """Return the Rademacher sign (+1 or -1) at ``Phi[row, column]``."""

    row = _check_nonnegative(row, "row")
    column = _as_int(column, "column")
    word = phi_sign_word(seed, column, row // ROWS_PER_WORD)
    return 1 if (word >> (row % ROWS_PER_WORD)) & 1 else -1


def _default_scale(rows: int) -> float:
    return 1.0 / math.sqrt(rows)


def _validate_scale(scale: object, rows: int | None = None) -> float:
    if scale is None:
        if rows is None:
            raise ValueError("rows is required when scale is omitted")
        return _default_scale(rows)
    if isinstance(scale, bool) or not isinstance(scale, Real):
        raise TypeError("scale must be a real number")
    scale = float(scale)
    if not math.isfinite(scale) or scale <= 0.0:
        raise ValueError("scale must be finite and positive")
    return scale


def generated_matrix(
    seed: int,
    rows: int,
    columns: int,
    scale: float | None = None,
) -> np.ndarray:
    """Materialize the generated ``rows x columns`` Phi as float64.

    When omitted, ``scale`` is the study convention ``1/sqrt(rows)``.  No
    column normalization is performed and no transform is inferred.
    """

    operator = GeneratedOperator(seed, rows, columns, scale=scale)
    return operator.matrix()


def _format_from(value: Format | Profile) -> Format:
    if isinstance(value, Profile):
        return value.coefficient
    if isinstance(value, Format):
        return value
    raise TypeError("expected a coefficient Format or Profile")


def quantized_scale(scale: float, fmt_or_profile: Format | Profile) -> int:
    """Quantize the common positive magnitude once, with ties away from zero."""

    fmt = _format_from(fmt_or_profile)
    scale = _validate_scale(scale)
    raw = math.floor(scale * fmt.scale + 0.5)
    if raw <= 0:
        raise ValueError("scale rounds to zero in coefficient format")
    if raw > fmt.maximum:
        raise ValueError("common quantized scale does not fit coefficient format")
    return int(raw)


@dataclass(frozen=True)
class GeneratedOperator:
    """Descriptor and reference implementation for ``A = Phi * I``."""

    seed: int
    rows: int
    columns: int
    scale: float | None = None
    generator_revision: int = GENERATOR_REVISION

    def __post_init__(self) -> None:
        object.__setattr__(self, "seed", _validate_seed(self.seed))
        rows = _as_int(self.rows, "rows")
        columns = _as_int(self.columns, "columns")
        if rows <= 0 or columns <= 0:
            raise ValueError("rows and columns must be positive")
        object.__setattr__(self, "rows", rows)
        object.__setattr__(self, "columns", columns)
        revision = _as_int(self.generator_revision, "generator_revision")
        if revision != GENERATOR_REVISION:
            raise ValueError(
                f"unsupported generator_revision {revision}; "
                f"only revision {GENERATOR_REVISION} is implemented"
            )
        object.__setattr__(self, "generator_revision", revision)
        object.__setattr__(self, "scale", _validate_scale(self.scale, rows))

    @classmethod
    def construct(
        cls,
        seed: int,
        rows: int | None = None,
        columns: int | None = None,
        scale: float | None = None,
        generator_revision: int = GENERATOR_REVISION,
        **aliases: Any,
    ) -> "GeneratedOperator":
        """Named constructor accepting v3-style dimension aliases."""

        if rows is None:
            rows = aliases.pop("measurement_count", None)
        if columns is None:
            columns = aliases.pop("signal_length", None)
        if aliases:
            raise TypeError(f"unexpected descriptor fields: {', '.join(aliases)}")
        if rows is None or columns is None:
            raise TypeError("rows and columns are required")
        return cls(seed, rows, columns, scale, generator_revision)

    @property
    def key(self) -> tuple[Any, ...]:
        """Stable cache key, including revision and the scale contract."""

        return (
            "threefry2x32-20",
            int(self.generator_revision),
            int(self.seed),
            int(self.rows),
            int(self.columns),
            float(self.scale),
            "identity",
        )

    @property
    def descriptor(self) -> Mapping[str, Any]:
        return {
            "family": "threefry2x32-20-rademacher",
            "generator_revision": self.generator_revision,
            "seed": self.seed,
            "rows": self.rows,
            "columns": self.columns,
            "scale": self.scale,
            "psi": "I",
        }

    @property
    def row_blocks(self) -> int:
        return (self.rows + ROWS_PER_WORD - 1) // ROWS_PER_WORD

    def sign_word(self, column: int, row_block: int) -> int:
        column = _as_int(column, "column")
        row_block = _as_int(row_block, "row_block")
        if not 0 <= column < self.columns:
            raise IndexError("column is outside operator")
        if not 0 <= row_block < self.row_blocks:
            raise IndexError("row_block is outside operator")
        return phi_sign_word(self.seed, column, row_block)

    def sign(self, row: int, column: int) -> int:
        row = _as_int(row, "row")
        column = _as_int(column, "column")
        if not 0 <= row < self.rows or not 0 <= column < self.columns:
            raise IndexError("coordinate is outside operator")
        word = self.sign_word(column, row // ROWS_PER_WORD)
        return 1 if (word >> (row % ROWS_PER_WORD)) & 1 else -1

    def matrix(self) -> np.ndarray:
        result = np.empty((self.rows, self.columns), dtype=np.float64)
        for column in range(self.columns):
            for row_block in range(self.row_blocks):
                word = self.sign_word(column, row_block)
                start = row_block * ROWS_PER_WORD
                for lane in range(min(ROWS_PER_WORD, self.rows - start)):
                    result[start + lane, column] = (
                        self.scale if (word >> lane) & 1 else -self.scale
                    )
        return result

    def sign_matrix(self) -> np.ndarray:
        return np.where(self.matrix() > 0.0, 1, -1).astype(np.int8)

    def raw_scale(self, fmt_or_profile: Format | Profile) -> int:
        return quantized_scale(self.scale, fmt_or_profile)

    def raw_coefficient(
        self, row: int, column: int, fmt_or_profile: Format | Profile
    ) -> int:
        return self.sign(row, column) * self.raw_scale(fmt_or_profile)

    coefficient_raw = raw_coefficient

    def raw_matrix(self, fmt_or_profile: Format | Profile) -> np.ndarray:
        magnitude = self.raw_scale(fmt_or_profile)
        return self.sign_matrix().astype(object) * magnitude

    matrix_raw = raw_matrix

    def matvec(self, vector: object) -> np.ndarray:
        values = np.asarray(vector, dtype=float)
        if values.ndim != 1 or values.shape[0] != self.columns:
            raise ValueError("vector must have one entry per operator column")
        return self.matrix() @ values

    def transpose_matvec(self, vector: object) -> np.ndarray:
        values = np.asarray(vector, dtype=float)
        if values.ndim != 1 or values.shape[0] != self.rows:
            raise ValueError("vector must have one entry per operator row")
        return self.matrix().T @ values

    def raw_matvec(
        self,
        vector_raw: Sequence[int],
        fmt_or_profile: Format | Profile,
        *,
        transpose: bool = False,
        accumulator_width: int | None = None,
        check_prefix: bool = True,
    ) -> np.ndarray:
        return self.cache().raw_gemv(
            vector_raw,
            fmt_or_profile,
            transpose=transpose,
            accumulator_width=accumulator_width,
            check_prefix=check_prefix,
        )

    def cache(self) -> "SignCache8Banks":
        return SignCache8Banks.build(self)

    # A useful spelling for callers treating the descriptor as a factory.
    build_cache = cache


@dataclass(frozen=True)
class Schedule:
    """Explicit request records and a conflict summary for one feeder mode."""

    mode: str
    requests: tuple[Mapping[str, Any], ...]
    conflict_report: Mapping[str, Any]

    def __iter__(self) -> Iterator[Mapping[str, Any]]:
        return iter(self.requests)

    def __len__(self) -> int:
        return len(self.requests)

    def __getitem__(self, item: int) -> Mapping[str, Any]:
        return self.requests[item]

    def as_dict(self) -> dict[str, Any]:
        return {
            "mode": self.mode,
            "requests": [dict(request) for request in self.requests],
            "bank_conflicts": dict(self.conflict_report),
        }


def _row_mask(rows: int, row_block: int) -> int:
    valid = min(ROWS_PER_WORD, rows - row_block * ROWS_PER_WORD)
    return 0 if valid <= 0 else (1 << valid) - 1


def bank_conflict_report(requests: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Report same-cycle duplicate-bank accesses in a request stream."""

    by_cycle: dict[Any, list[Mapping[str, Any]]] = {}
    for request in requests:
        cycle = request.get("cycle", 0)
        if "accesses" in request:
            for access in request["accesses"]:
                by_cycle.setdefault(cycle, []).append(
                    {"cycle": cycle, "bank": access["bank"]}
                )
        elif "banks" in request:
            for bank in request["banks"]:
                by_cycle.setdefault(cycle, []).append(
                    {"cycle": cycle, "bank": bank}
                )
        else:
            by_cycle.setdefault(cycle, []).append(request)
    conflicts = []
    for cycle, cycle_requests in by_cycle.items():
        by_bank: dict[int, list[Mapping[str, Any]]] = {}
        for request in cycle_requests:
            bank = int(request["bank"])
            by_bank.setdefault(bank, []).append(request)
        for bank, matches in by_bank.items():
            if len(matches) > 1:
                conflicts.append(
                    {"cycle": cycle, "bank": bank, "count": len(matches)}
                )
    return {
        "cycle_count": len(by_cycle),
        "conflict_count": len(conflicts),
        "conflicts": conflicts,
        "conflict_free": not conflicts,
    }


def request_schedule(
    rows: int,
    columns: int,
    mode: str,
    *,
    bank_count: int = BANK_COUNT,
) -> Schedule:
    """Build a coordinate-labelled R1/R4 sign-cache access schedule.

    R1 emits one 32-bit word (32 output rows) per request.  R4 groups eight
    columns in banks and emits the four reduction-lane row positions
    ``k=32*t+8*lane+u``; ``u`` runs from 0 through 7.  Invalid rows and padded
    columns are represented by masks and never become data requests.
    """

    rows = _as_int(rows, "rows")
    columns = _as_int(columns, "columns")
    bank_count = _as_int(bank_count, "bank_count")
    if rows <= 0 or columns <= 0:
        raise ValueError("rows and columns must be positive")
    if bank_count != BANK_COUNT:
        raise ValueError("the v4 compact cache has exactly eight banks")
    row_blocks = (rows + ROWS_PER_WORD - 1) // ROWS_PER_WORD
    requests: list[Mapping[str, Any]] = []
    if mode == "R1forward32outputs":
        cycle = 0
        for column in range(columns):
            bank = column % bank_count
            column_group = column // bank_count
            for row_block in range(row_blocks):
                requests.append({
                    "mode": mode,
                    "cycle": cycle,
                    "column": column,
                    "row_block": row_block,
                    "bank": bank,
                    "address": column_group * row_blocks + row_block,
                    "row_mask": _row_mask(rows, row_block),
                    "output_count": _row_mask(rows, row_block).bit_count(),
                })
                cycle += 1
    elif mode == "R4transpose8outputs4reductionlanes":
        cycle = 0
        for column_group_start in range(0, columns, bank_count):
            valid_columns = tuple(
                column for column in range(column_group_start, min(columns, column_group_start + bank_count))
            )
            for row_block in range(row_blocks):
                for lane in range(4):
                    for u in range(8):
                        row = row_block * 32 + 8 * lane + u
                        row_valid = row < rows
                        accesses = tuple({
                            "column": column,
                            "bank": column % bank_count,
                            "address": (column // bank_count) * row_blocks + row_block,
                            "row": row,
                            "valid": row_valid,
                        } for column in valid_columns)
                        requests.append({
                            "mode": mode,
                            "cycle": cycle,
                            "column_group": column_group_start // bank_count,
                            "row_block": row_block,
                            "lane": lane,
                            "u": u,
                            "k": row,
                            "row": row,
                            "row_valid": row_valid,
                            "column_mask": sum(1 << (column - column_group_start) for column in valid_columns),
                            "accesses": accesses,
                            "banks": tuple(access["bank"] for access in accesses),
                        })
                        cycle += 1
    else:
        raise ValueError(
            "mode must be R1forward32outputs or R4transpose8outputs4reductionlanes"
        )
    flat = []
    for request in requests:
        if "accesses" in request:
            flat.extend(
                {"cycle": request["cycle"], "bank": access["bank"]}
                for access in request["accesses"]
            )
        else:
            flat.append(request)
    return Schedule(mode, tuple(requests), bank_conflict_report(flat))


class SignCache8Banks:
    """Full Phi sign payload with the v4 bank/address geometry."""

    def __init__(
        self,
        operator: GeneratedOperator,
        banks: Sequence[Sequence[int]],
    ) -> None:
        if not isinstance(operator, GeneratedOperator):
            raise TypeError("operator must be a GeneratedOperator")
        self.operator = operator
        self.banks = [list(map(int, bank)) for bank in banks]

    @classmethod
    def build(cls, operator: GeneratedOperator) -> "SignCache8Banks":
        if not isinstance(operator, GeneratedOperator):
            raise TypeError("operator must be a GeneratedOperator")
        depth = ((operator.columns + BANK_COUNT - 1) // BANK_COUNT) * operator.row_blocks
        banks = [[0] * depth for _ in range(BANK_COUNT)]
        for column in range(operator.columns):
            for row_block in range(operator.row_blocks):
                bank, address = cls.address_for(operator, column, row_block)
                word = operator.sign_word(column, row_block)
                mask = _row_mask(operator.rows, row_block)
                banks[bank][address] = word & mask
        result = cls(operator, banks)
        result.validate()
        return result

    @classmethod
    def from_packed(
        cls,
        operator: GeneratedOperator,
        banks: Sequence[Sequence[int]],
        *,
        validate: bool = True,
    ) -> "SignCache8Banks":
        result = cls(operator, banks)
        if validate:
            result.validate()
        return result

    # Familiar alternate spelling for serializer code.
    unpack = from_packed

    @property
    def rows(self) -> int:
        return self.operator.rows

    @property
    def columns(self) -> int:
        return self.operator.columns

    @property
    def row_blocks(self) -> int:
        return self.operator.row_blocks

    @property
    def padded_columns(self) -> int:
        return ((self.columns + 7) // 8) * 8

    @property
    def words_per_bank(self) -> int:
        return (self.padded_columns // 8) * self.row_blocks

    @property
    def payload_bits(self) -> int:
        return self.padded_columns * self.row_blocks * 32

    @property
    def key(self) -> tuple[Any, ...]:
        return self.operator.key + ("sign-cache-8bank",)

    @staticmethod
    def address_for(operator: GeneratedOperator, column: int, row_block: int) -> tuple[int, int]:
        column = _as_int(column, "column")
        row_block = _as_int(row_block, "row_block")
        if not 0 <= column < operator.columns:
            raise IndexError("column is outside operator")
        if not 0 <= row_block < operator.row_blocks:
            raise IndexError("row_block is outside operator")
        return column % BANK_COUNT, (column // BANK_COUNT) * operator.row_blocks + row_block

    def address(self, column: int, row_block: int) -> tuple[int, int]:
        return self.address_for(self.operator, column, row_block)

    def pack(self) -> tuple[tuple[int, ...], ...]:
        return tuple(tuple(bank) for bank in self.banks)

    def validate(self, expected: GeneratedOperator | None = None) -> None:
        expected = self.operator if expected is None else expected
        if not isinstance(expected, GeneratedOperator):
            raise TypeError("expected must be a GeneratedOperator")
        if expected.key != self.operator.key:
            raise ValueError("sign cache operator key does not match expected descriptor")
        if len(self.banks) != BANK_COUNT:
            raise ValueError("sign cache must contain eight banks")
        if any(len(bank) != self.words_per_bank for bank in self.banks):
            raise ValueError("sign cache bank depth does not match geometry")
        for bank_index, bank in enumerate(self.banks):
            for address, value in enumerate(bank):
                if not 0 <= value <= MASK32:
                    raise ValueError("sign cache word is not an unsigned 32-bit value")
                group, row_block = divmod(address, self.row_blocks)
                column = group * BANK_COUNT + bank_index
                mask = _row_mask(self.rows, row_block)
                if value & ~mask:
                    raise ValueError("sign cache padding bits must be zero")
                if column >= self.columns:
                    if value:
                        raise ValueError("sign cache padded column is nonzero")
                elif value != (phi_sign_word(expected.seed, column, row_block) & mask):
                    raise ValueError("sign cache word does not match operator key")

    def word(self, column: int, row_block: int) -> int:
        bank, address = self.address(column, row_block)
        return self.banks[bank][address] & _row_mask(self.rows, row_block)

    sign_word = word

    def sign(self, row: int, column: int) -> int:
        row = _as_int(row, "row")
        column = _as_int(column, "column")
        if not 0 <= row < self.rows or not 0 <= column < self.columns:
            raise IndexError("coordinate is outside operator")
        return 1 if (self.word(column, row // ROWS_PER_WORD) >> (row % ROWS_PER_WORD)) & 1 else -1

    def lookup(
        self,
        row: int,
        column: int,
        *,
        orientation: str = "A",
        fmt_or_profile: Format | Profile | None = None,
    ) -> float | int:
        """Look up one coefficient in A or transpose(A), preserving coordinates."""

        if orientation in {"A", "forward"}:
            sign = self.sign(row, column)
        elif orientation in {"AT", "transpose_A", "transpose", "adjoint"}:
            sign = self.sign(column, row)
        else:
            raise ValueError("orientation must be A or transpose_A")
        if fmt_or_profile is None:
            return sign * self.operator.scale
        return sign * quantized_scale(self.operator.scale, fmt_or_profile)

    coefficient = lookup

    def unpack_matrix(
        self,
        orientation: str = "A",
        fmt_or_profile: Format | Profile | None = None,
    ) -> np.ndarray:
        if orientation in {"A", "forward"}:
            shape = (self.rows, self.columns)
            source_coordinates = ((row, column) for row in range(self.rows) for column in range(self.columns))
        elif orientation in {"AT", "transpose_A", "transpose", "adjoint"}:
            shape = (self.columns, self.rows)
            source_coordinates = ((row, column) for column in range(self.columns) for row in range(self.rows))
        else:
            raise ValueError("orientation must be A or transpose_A")
        dtype = object if fmt_or_profile is not None else float
        result = np.empty(shape, dtype=dtype)
        for index, (source_row, source_column) in enumerate(source_coordinates):
            target = np.unravel_index(index, shape)
            result[target] = self.lookup(
                source_row, source_column, orientation="A",
                fmt_or_profile=fmt_or_profile,
            )
        return result

    matrix = unpack_matrix

    def support_matrix(
        self,
        support: Sequence[int],
        fmt_or_profile: Format | Profile | None = None,
    ) -> np.ndarray:
        ordered = tuple(_as_int(column, "support column") for column in support)
        if any(not 0 <= column < self.columns for column in ordered):
            raise IndexError("support column is outside operator")
        dtype = object if fmt_or_profile is not None else float
        result = np.empty((self.rows, len(ordered)), dtype=dtype)
        for slot, column in enumerate(ordered):
            for row in range(self.rows):
                result[row, slot] = self.lookup(row, column, fmt_or_profile=fmt_or_profile)
        return result

    dense_support = support_matrix
    support = support_matrix

    def coefficient_raw(
        self, row: int, column: int, fmt_or_profile: Format | Profile
    ) -> int:
        return int(self.lookup(row, column, fmt_or_profile=fmt_or_profile))

    def raw_gemv(
        self,
        vector_raw: Sequence[int],
        fmt_or_profile: Format | Profile,
        *,
        transpose: bool = False,
        accumulator_width: int | None = None,
        check_prefix: bool = True,
    ) -> np.ndarray:
        """Exact sign GEMV with one final narrowing and optional prefix checking.

        All products are accumulated in Python integers.  If an accumulator
        width is supplied, every prefix is checked before the final result is
        narrowed; this catches a cancellation case that a final-sum-only check
        would miss.  The returned values are raw accumulator integers.
        """

        values = list(vector_raw)
        expected_length = self.rows if transpose else self.columns
        if len(values) != expected_length:
            raise ValueError("vector length does not match operator orientation")
        if any(isinstance(value, bool) or not isinstance(value, Integral) for value in values):
            raise TypeError("raw GEMV vector values must be integers")
        if accumulator_width is None and isinstance(fmt_or_profile, Profile):
            accumulator_width = fmt_or_profile.accumulator_width
        if accumulator_width is not None:
            accumulator_width = _as_int(accumulator_width, "accumulator_width")
            if accumulator_width < 1:
                raise ValueError("accumulator_width must be positive")
            minimum = -(1 << (accumulator_width - 1))
            maximum = (1 << (accumulator_width - 1)) - 1
        magnitude = quantized_scale(self.operator.scale, fmt_or_profile)
        output_count = self.columns if transpose else self.rows
        result = np.empty(output_count, dtype=object)
        for output in range(output_count):
            total = 0
            length = self.rows if transpose else self.columns
            for index in range(length):
                sign = self.sign(index, output) if transpose else self.sign(output, index)
                total += sign * magnitude * int(values[index])
                if accumulator_width is not None and check_prefix and not minimum <= total <= maximum:
                    raise OverflowError("wide sign GEMV prefix exceeds accumulator width")
            if accumulator_width is not None:
                total = max(minimum, min(maximum, total))
            result[output] = total
        return result

    integer_gemv = raw_gemv
    raw_matvec = raw_gemv
    sign_gemv = raw_gemv

    def request_schedule(self, mode: str) -> Schedule:
        return request_schedule(self.rows, self.columns, mode)

    schedule = request_schedule


CompactSignCache = SignCache8Banks
PhiSignCache = SignCache8Banks


def build_sign_cache(operator: GeneratedOperator) -> SignCache8Banks:
    return SignCache8Banks.build(operator)


def pack_sign_cache(cache: SignCache8Banks) -> tuple[tuple[int, ...], ...]:
    if not isinstance(cache, SignCache8Banks):
        raise TypeError("cache must be a SignCache8Banks")
    return cache.pack()


def unpack_sign_cache(
    operator: GeneratedOperator,
    banks: Sequence[Sequence[int]],
    *,
    validate: bool = True,
) -> SignCache8Banks:
    return SignCache8Banks.from_packed(operator, banks, validate=validate)


def raw_sign_gemv(
    operator_or_cache: GeneratedOperator | SignCache8Banks,
    vector_raw: Sequence[int],
    fmt_or_profile: Format | Profile,
    *,
    transpose: bool = False,
    accumulator_width: int | None = None,
    check_prefix: bool = True,
) -> np.ndarray:
    cache = (
        operator_or_cache
        if isinstance(operator_or_cache, SignCache8Banks)
        else SignCache8Banks.build(operator_or_cache)
    )
    return cache.raw_gemv(
        vector_raw,
        fmt_or_profile,
        transpose=transpose,
        accumulator_width=accumulator_width,
        check_prefix=check_prefix,
    )


sign_gemv = raw_sign_gemv
schedule_requests = request_schedule


__all__ = [
    "BANK_COUNT",
    "CompactSignCache",
    "GENERATOR_REVISION",
    "GeneratedOperator",
    "PhiSignCache",
    "ROWS_PER_WORD",
    "Schedule",
    "SignCache8Banks",
    "bank_conflict_report",
    "build_sign_cache",
    "generated_matrix",
    "phi_sign",
    "phi_sign_word",
    "pack_sign_cache",
    "quantized_scale",
    "raw_sign_gemv",
    "schedule_requests",
    "sign_gemv",
    "threefry2x32_20",
    "unpack_sign_cache",
]
