"""Optional study-only acceleration for the v4 integer arithmetic model.

The context manager in this module temporarily patches only arithmetic
primitives.  It never changes recovery or LSQR algorithms.  Each accelerated
path first proves that all raw integer products and absolute prefix sums fit
signed int64; otherwise it delegates to the original arbitrary-precision
implementation.  Clipping, rounding, and event accounting remain in the
existing Arithmetic methods.
"""

from __future__ import annotations

from contextlib import contextmanager
from numbers import Integral
from typing import Any, Iterator

import numpy as np

from models.v4.fixed import Arithmetic, Format, _integer


INT64_MAX = (1 << 63) - 1
INT64_MIN = -(1 << 63)


def _raw_int64(values: Any) -> tuple[np.ndarray, int] | None:
    """Return int64 values and maximum magnitude, or None when unsafe."""
    array = np.asarray(values, dtype=object)
    raw: list[int] = []
    maximum = 0
    for value in array.flat:
        if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
            return None
        integer = int(value)
        if integer < INT64_MIN or integer > INT64_MAX:
            return None
        raw.append(integer)
        maximum = max(maximum, abs(integer))
    return np.asarray(raw, dtype=np.int64).reshape(array.shape), maximum


def _fast_round_shift(original, raw: Any, shift: Any):
    """Exact int64 fast path for Arithmetic.round_shift."""
    try:
        shift = _integer(shift, "shift")
    except (TypeError, ValueError):
        return original(raw, shift)
    # Let the patched scalar classmethod handle Python/NumPy Integral values
    # directly; constructing a temporary NumPy array would erase the gain.
    if isinstance(raw, Integral):
        return original(raw, shift)
    checked = _raw_int64(raw)
    if checked is None:
        return original(raw, shift)
    values, maximum = checked
    magnitude_shift = -shift if shift <= 0 else 0
    # Keep every vector operation inside signed int64.  Larger shifts are
    # uncommon and safely handled by the reference arbitrary-precision path.
    if magnitude_shift > 62 or (magnitude_shift and maximum > (INT64_MAX >> magnitude_shift)):
        return original(raw, shift)
    if shift > 62 or (shift > 0 and np.any(values == INT64_MIN)):
        return original(raw, shift)
    if shift <= 0:
        result = values << magnitude_shift
    else:
        divisor = 1 << shift
        quotient = np.abs(values) // divisor
        remainder = np.abs(values) % divisor
        quotient += (remainder * 2 >= divisor).astype(np.int64)
        result = np.where(values < 0, -quotient, quotient)
    if np.any(result < INT64_MIN) or np.any(result > INT64_MAX):
        return original(raw, shift)
    result = np.asarray(result, dtype=object)
    return int(result.item()) if result.ndim == 0 else result


def _safe_dot_bound(left_max: int, right_max: int, length: int) -> bool:
    return left_max == 0 or right_max == 0 or left_max * right_max * length <= INT64_MAX


def _fast_dot_raw(original, arithmetic: Arithmetic, left: Any, right: Any) -> int:
    """Exact int64 dot path; final accumulator clipping stays unchanged."""
    left_array = np.asarray(left, dtype=object)
    right_array = np.asarray(right, dtype=object)
    if left_array.ndim != 1 or right_array.ndim != 1 or left_array.shape != right_array.shape:
        return original(arithmetic, left, right)
    left_checked = _raw_int64(left_array)
    right_checked = _raw_int64(right_array)
    if left_checked is None or right_checked is None:
        return original(arithmetic, left, right)
    left64, left_max = left_checked
    right64, right_max = right_checked
    if not _safe_dot_bound(left_max, right_max, left64.size):
        return original(arithmetic, left, right)
    total = int(np.dot(left64, right64))
    return int(arithmetic._accumulator_clip(total))


def _fast_matvec(original, arithmetic: Arithmetic, matrix: Any, vector: Any,
                 ma_fmt: Any, vec_fmt: Any, out: Any, transpose: bool = False) -> np.ndarray:
    """Vectorized int64 GEMV with reference rescale and clipping semantics."""
    matrix_array = np.asarray(matrix, dtype=object)
    vector_array = np.asarray(vector, dtype=object)
    if matrix_array.ndim != 2 or vector_array.ndim != 1:
        return original(arithmetic, matrix, vector, ma_fmt, vec_fmt, out, transpose=transpose)
    if not all(isinstance(fmt, Format) for fmt in (ma_fmt, vec_fmt, out)):
        return original(arithmetic, matrix, vector, ma_fmt, vec_fmt, out, transpose=transpose)
    if not isinstance(transpose, (bool, np.bool_)):
        return original(arithmetic, matrix, vector, ma_fmt, vec_fmt, out, transpose=transpose)
    operand = matrix_array.T if transpose else matrix_array
    if operand.shape[1] != vector_array.shape[0]:
        return original(arithmetic, matrix, vector, ma_fmt, vec_fmt, out, transpose=transpose)
    matrix_checked = _raw_int64(operand)
    vector_checked = _raw_int64(vector_array)
    if matrix_checked is None or vector_checked is None:
        return original(arithmetic, matrix, vector, ma_fmt, vec_fmt, out, transpose=transpose)
    operand64, matrix_max = matrix_checked
    vector64, vector_max = vector_checked
    if not _safe_dot_bound(matrix_max, vector_max, operand.shape[1]):
        return original(arithmetic, matrix, vector, ma_fmt, vec_fmt, out, transpose=transpose)
    totals = operand64 @ vector64
    result = np.empty(operand.shape[0], dtype=object)
    for index, total in enumerate(totals):
        clipped = arithmetic._accumulator_clip(int(total))
        result[index] = arithmetic.rescale(
            clipped, ma_fmt.frac + vec_fmt.frac, out
        )
    return result


def _fast_unary_int_map(original_descriptor, cls, values: Any, operation):
    """Dispatch only true Integral scalars; preserve the classmethod fallback."""
    if isinstance(values, (bool, np.bool_)) or not isinstance(values, Integral):
        return original_descriptor.__get__(None, cls)(values, operation)
    integer = _integer(values, "raw value")
    return int(operation(integer))


def _fast_binary_int_map(original_descriptor, cls, left: Any, right: Any, operation):
    """Dispatch only two true Integral scalars; preserve broadcasting fallback."""
    scalar_types = (bool, np.bool_)
    if (isinstance(left, scalar_types) or isinstance(right, scalar_types)
            or not isinstance(left, Integral) or not isinstance(right, Integral)):
        return original_descriptor.__get__(None, cls)(left, right, operation)
    left_integer = _integer(left, "raw value")
    right_integer = _integer(right, "raw value")
    return int(operation(left_integer, right_integer))


@contextmanager
def accelerated_arithmetic() -> Iterator[dict[str, Any]]:
    """Temporarily install guarded Arithmetic acceleration for a study.

    The yielded metadata is informational.  The original class methods are
    restored even if the study raises.  This context manager is process-global
    and should be used by one study at a time.
    """
    original_round_shift = Arithmetic.round_shift
    original_dot_raw = Arithmetic.dot_raw
    original_matvec = Arithmetic.matvec
    original_unary_descriptor = Arithmetic.__dict__["_unary_int_map"]
    original_binary_descriptor = Arithmetic.__dict__["_binary_int_map"]

    def round_shift(raw, shift):
        return _fast_round_shift(original_round_shift, raw, shift)

    def dot_raw(self, left, right):
        return _fast_dot_raw(original_dot_raw, self, left, right)

    def matvec(self, matrix, vector, ma_fmt, vec_fmt, out, transpose=False):
        return _fast_matvec(
            original_matvec, self, matrix, vector, ma_fmt, vec_fmt, out,
            transpose=transpose,
        )

    def unary_int_map(cls, values, operation):
        return _fast_unary_int_map(original_unary_descriptor, cls, values, operation)

    def binary_int_map(cls, left, right, operation):
        return _fast_binary_int_map(original_binary_descriptor, cls, left, right, operation)

    Arithmetic.round_shift = staticmethod(round_shift)
    Arithmetic.dot_raw = dot_raw
    Arithmetic.matvec = matvec
    Arithmetic._unary_int_map = classmethod(unary_int_map)
    Arithmetic._binary_int_map = classmethod(binary_int_map)
    try:
        yield {
            "methods": ["round_shift", "dot_raw", "matvec"],
            "scalar_dispatch_methods": ["_unary_int_map", "_binary_int_map"],
            "int64_bound": INT64_MAX,
            "unsafe_fallback": "original_arbitrary_precision",
        }
    finally:
        Arithmetic.round_shift = staticmethod(original_round_shift)
        Arithmetic.dot_raw = original_dot_raw
        Arithmetic.matvec = original_matvec
        Arithmetic._unary_int_map = original_unary_descriptor
        Arithmetic._binary_int_map = original_binary_descriptor


fast_arithmetic = accelerated_arithmetic


__all__ = [
    "INT64_MAX",
    "INT64_MIN",
    "accelerated_arithmetic",
    "fast_arithmetic",
]
