"""Deterministic LFSR32 comparison operator for generated sign matrices.

The stream definition follows the v2 RTL Galois right-shift generator: the
current least-significant bit is emitted first, then the state is advanced.
This module is a numerical reference model only.  It does not assert a
maximum period, compressed-sensing quality, or implementation throughput.
"""

from __future__ import annotations

import numbers
from typing import Any

import numpy as np


LFSR32_TAPS = 0x80200003
LFSR32_DEFAULT_SEED = 0xDEADBEEF
LFSR32_MASK = 0xFFFFFFFF
# The indexed API uses a finite unsigned 64-bit stream counter.  Rejecting
# larger indices makes accidental counter wrap explicit and reproducible.
LFSR32_MAX_STREAM_INDEX = (1 << 64) - 1
LFSR32_OPERATOR_ID = "lfsr32-galois-rightshift-v2-columnmajor-rademacher"

# Convenient aliases for callers comparing this model with the v2 source.
TAPS = LFSR32_TAPS
DEFAULT_SEED = LFSR32_DEFAULT_SEED


def _as_int(value: Any, name: str) -> int:
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, numbers.Integral):
        raise TypeError(f"{name} must be an integer")
    return int(value)


def _validate_seed(seed: Any) -> int:
    seed_i = _as_int(seed, "seed")
    if not 0 <= seed_i <= LFSR32_MASK:
        raise ValueError("seed must be a 32-bit unsigned integer")
    return LFSR32_DEFAULT_SEED if seed_i == 0 else seed_i


def _validate_dimensions(rows: Any, columns: Any) -> tuple[int, int]:
    rows_i = _as_int(rows, "rows")
    columns_i = _as_int(columns, "columns")
    if rows_i <= 0 or columns_i <= 0:
        raise ValueError("rows and columns must be positive")
    count = rows_i * columns_i
    if count - 1 > LFSR32_MAX_STREAM_INDEX:
        raise ValueError("matrix stream index would exceed the 64-bit counter limit")
    return rows_i, columns_i


def _validate_scale(scale: Any) -> float:
    if isinstance(scale, (bool, np.bool_)) or not isinstance(scale, numbers.Real):
        raise TypeError("scale must be a real number")
    scale_f = float(scale)
    if not np.isfinite(scale_f) or scale_f <= 0.0:
        raise ValueError("scale must be finite and strictly positive")
    return scale_f


def galois_step(state: Any) -> int:
    """Advance one state using the v2 Galois right-shift recurrence."""

    state_i = _as_int(state, "state")
    if not 0 <= state_i <= LFSR32_MASK:
        raise ValueError("state must be a 32-bit unsigned integer")
    shifted = state_i >> 1
    if state_i & 1:
        shifted ^= LFSR32_TAPS
    return shifted & LFSR32_MASK


def _apply_transform(transform: tuple[int, ...], state: int) -> int:
    result = 0
    remaining = state & LFSR32_MASK
    while remaining:
        bit = remaining & -remaining
        result ^= transform[bit.bit_length() - 1]
        remaining ^= bit
    return result & LFSR32_MASK


def _compose(first: tuple[int, ...], second: tuple[int, ...]) -> tuple[int, ...]:
    """Return the GF(2) transform ``first(second(state))``."""

    return tuple(_apply_transform(first, vector) for vector in second)


def _build_jump_powers() -> tuple[tuple[int, ...], ...]:
    basis = tuple(galois_step(1 << bit) for bit in range(32))
    powers = [basis]
    # 64 powers cover every permitted stream index without integer wrap.
    for _ in range(1, 64):
        powers.append(_compose(powers[-1], powers[-1]))
    return tuple(powers)


_JUMP_POWERS = _build_jump_powers()


def lfsr32_advance(seed: Any, steps: Any) -> int:
    """Return the state after ``steps`` advances using GF(2) jump-ahead."""

    state = _validate_seed(seed)
    steps_i = _as_int(steps, "steps")
    if not 0 <= steps_i <= LFSR32_MAX_STREAM_INDEX:
        raise ValueError("steps must fit the 64-bit stream counter")
    power = 0
    while steps_i:
        if steps_i & 1:
            state = _apply_transform(_JUMP_POWERS[power], state)
        steps_i >>= 1
        power += 1
    return state


def indexed_sign(seed: Any, rows: Any, row: Any, column: Any) -> int:
    """Return the ±1 sign at ``(row, column)`` in column-major stream order.

    The stream index is exactly ``column * rows + row``.  The current state is
    sampled before stepping, matching the v2 RTL output timing.
    """

    rows_i = _as_int(rows, "rows")
    row_i = _as_int(row, "row")
    column_i = _as_int(column, "column")
    if rows_i <= 0:
        raise ValueError("rows must be positive")
    if row_i < 0 or row_i >= rows_i:
        raise ValueError("row must satisfy 0 <= row < rows")
    if column_i < 0:
        raise ValueError("column must be non-negative")
    index = column_i * rows_i + row_i
    if index > LFSR32_MAX_STREAM_INDEX:
        raise ValueError("matrix stream index would exceed the 64-bit counter limit")
    return 1 if (lfsr32_advance(seed, index) & 1) else -1


def lfsr32_matrix(seed: Any, rows: Any, columns: Any, scale: Any = 1.0) -> np.ndarray:
    """Materialize a float sign matrix with v2-compatible stream ordering."""

    rows_i, columns_i = _validate_dimensions(rows, columns)
    scale_f = _validate_scale(scale)
    state = _validate_seed(seed)
    matrix = np.empty((rows_i, columns_i), dtype=np.float64)
    for column in range(columns_i):
        for row in range(rows_i):
            matrix[row, column] = scale_f if state & 1 else -scale_f
            state = galois_step(state)
    return matrix


def operator_identity(seed: Any, rows: Any, columns: Any, scale: Any = 1.0) -> dict[str, Any]:
    """Describe the complete matrix identity, including its shape and scale."""

    rows_i, columns_i = _validate_dimensions(rows, columns)
    scale_f = _validate_scale(scale)
    seed_input = _as_int(seed, "seed")
    normalized_seed = _validate_seed(seed_input)
    return {
        "operator_id": LFSR32_OPERATOR_ID,
        "family": "LFSR32 Galois right-shift",
        "taps": f"0x{LFSR32_TAPS:08X}",
        "seed_input": seed_input,
        "seed": normalized_seed,
        "zero_seed_substitution": f"0x{LFSR32_DEFAULT_SEED:08X}",
        "rows": rows_i,
        "columns": columns_i,
        "shape": [rows_i, columns_i],
        "scale": scale_f,
        "stream_index": "column * rows + row",
        "output": "current_state_lsb_then_galois_step",
    }


def generator_quality(matrix: Any) -> dict[str, Any]:
    """Compute lightweight descriptive diagnostics for a materialized matrix."""

    values = np.asarray(matrix, dtype=np.float64)
    if values.ndim != 2 or values.shape[0] == 0 or values.shape[1] == 0:
        raise ValueError("matrix must be a non-empty two-dimensional array")
    if not np.all(np.isfinite(values)):
        raise ValueError("matrix must contain only finite values")

    rows, columns = values.shape
    signs = np.where(values >= 0.0, 1, -1).astype(np.int8)
    positive = int(np.count_nonzero(values > 0.0))
    negative = int(np.count_nonzero(values < 0.0))
    zero = int(values.size - positive - negative)

    duplicate_count = 0
    negated_count = 0
    for left in range(columns):
        for right in range(left + 1, columns):
            if np.array_equal(signs[:, left], signs[:, right]):
                duplicate_count += 1
            elif np.array_equal(signs[:, left], -signs[:, right]):
                negated_count += 1

    norms = np.linalg.norm(values, axis=0)
    coherence = 0.0
    if columns > 1 and np.all(norms > 0.0):
        normalized = values / norms
        gram = np.abs(normalized.T @ normalized)
        np.fill_diagonal(gram, 0.0)
        coherence = float(np.max(gram))

    total = int(values.size)
    return {
        "shape": [int(rows), int(columns)],
        "sign_balance": {
            "positive": positive,
            "negative": negative,
            "zero": zero,
            "positive_fraction": positive / total,
            "negative_fraction": negative / total,
            "mean_sign": float(np.mean(signs)),
        },
        "duplicate_column_count": duplicate_count,
        "negated_column_count": negated_count,
        "mutual_coherence": coherence,
    }


__all__ = [
    "DEFAULT_SEED",
    "LFSR32_DEFAULT_SEED",
    "LFSR32_MASK",
    "LFSR32_MAX_STREAM_INDEX",
    "LFSR32_OPERATOR_ID",
    "LFSR32_TAPS",
    "TAPS",
    "galois_step",
    "generator_quality",
    "indexed_sign",
    "lfsr32_advance",
    "lfsr32_matrix",
    "operator_identity",
]
