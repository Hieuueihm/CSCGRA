"""Small, explicit fixed-point arithmetic primitives.

Raw fixed-point values are signed integers.  The arithmetic kernels below use
Python integers so intermediate calculations cannot wrap silently.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from numbers import Integral, Real
from typing import Callable

import numpy as np


def _integer(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise TypeError(f"{label} must be an integer")
    return int(value)


@dataclass(frozen=True)
class Format:
    """Signed two's-complement storage format."""

    width: int
    frac: int

    def __post_init__(self) -> None:
        width = _integer(self.width, "width")
        frac = _integer(self.frac, "frac")
        if width < 1:
            raise ValueError("width must be at least one")
        if frac < 0:
            raise ValueError("frac must be non-negative")
        object.__setattr__(self, "width", width)
        object.__setattr__(self, "frac", frac)

    @property
    def scale(self) -> int:
        return 1 << self.frac

    @property
    def minimum(self) -> int:
        return -(1 << (self.width - 1))

    @property
    def maximum(self) -> int:
        return (1 << (self.width - 1)) - 1


@dataclass(frozen=True)
class Profile:
    data: Format
    coefficient: Format
    state: Format
    accumulator_width: int

    def __post_init__(self) -> None:
        if not isinstance(self.data, Format):
            raise TypeError("data must be a Format")
        if not isinstance(self.coefficient, Format):
            raise TypeError("coefficient must be a Format")
        if not isinstance(self.state, Format):
            raise TypeError("state must be a Format")
        accumulator_width = _integer(self.accumulator_width, "accumulator_width")
        if accumulator_width < 1:
            raise ValueError("accumulator_width must be at least one")
        object.__setattr__(self, "accumulator_width", accumulator_width)

    @property
    def name(self) -> str:
        return (
            f"D{self.data.width}F{self.data.frac}_"
            f"C{self.coefficient.width}F{self.coefficient.frac}_"
            f"S{self.state.width}F{self.state.frac}_"
            f"A{self.accumulator_width}"
        )


class Arithmetic:
    """Saturating fixed-point arithmetic with observable exceptional events."""

    def __init__(self, profile: Profile):
        if not isinstance(profile, Profile):
            raise TypeError("profile must be a Profile")
        self.profile = profile
        self.events = {
            "saturation": 0,
            "accumulator_overflow": 0,
            "divide_by_zero": 0,
        }

    @staticmethod
    def _as_object_array(values: object) -> np.ndarray:
        return np.asarray(values, dtype=object)

    @staticmethod
    def _restore_scalar(result: np.ndarray) -> int | np.ndarray:
        if result.ndim == 0:
            return int(result.item())
        return result

    @classmethod
    def _unary_int_map(
        cls, values: object, operation: Callable[[int], int]
    ) -> int | np.ndarray:
        source = cls._as_object_array(values)
        result = np.empty(source.shape, dtype=object)
        for index in np.ndindex(source.shape):
            result[index] = operation(_integer(source[index], "raw value"))
        return cls._restore_scalar(result)

    @classmethod
    def _binary_int_map(
        cls, left: object, right: object, operation: Callable[[int, int], int]
    ) -> int | np.ndarray:
        left_array, right_array = np.broadcast_arrays(
            cls._as_object_array(left), cls._as_object_array(right)
        )
        result = np.empty(left_array.shape, dtype=object)
        for index in np.ndindex(result.shape):
            result[index] = operation(
                _integer(left_array[index], "raw value"),
                _integer(right_array[index], "raw value"),
            )
        return cls._restore_scalar(result)

    def quantize(self, values: object, fmt: Format) -> np.ndarray:
        """Convert real values to raw integers, rounding halfway away from zero."""
        if not isinstance(fmt, Format):
            raise TypeError("fmt must be a Format")
        source = np.asarray(values)
        result = np.empty(source.shape, dtype=object)
        for index in np.ndindex(source.shape):
            value = source[index].item() if hasattr(source[index], "item") else source[index]
            if isinstance(value, bool) or not isinstance(value, Real):
                raise TypeError("quantize values must be real numbers")
            if not math.isfinite(value):
                raise ValueError("quantize values must be finite")
            magnitude = math.floor(abs(value) * fmt.scale + 0.5)
            raw = -magnitude if value < 0 else magnitude
            result[index] = self.clip(raw, fmt)
        return result

    @staticmethod
    def decode(values: object, fmt: Format) -> np.ndarray:
        """Convert raw integers to floating-point real values."""
        if not isinstance(fmt, Format):
            raise TypeError("fmt must be a Format")
        source = np.asarray(values, dtype=object)
        result = np.empty(source.shape, dtype=float)
        for index in np.ndindex(source.shape):
            result[index] = _integer(source[index], "raw value") / fmt.scale
        return result

    @staticmethod
    def round_shift(raw: object, shift: int) -> int | np.ndarray:
        """Shift left exactly or shift right with halfway values away from zero."""
        shift = _integer(shift, "shift")

        def operation(value: int) -> int:
            if shift <= 0:
                return value << -shift
            divisor = 1 << shift
            quotient, remainder = divmod(abs(value), divisor)
            if remainder * 2 >= divisor:
                quotient += 1
            return -quotient if value < 0 else quotient

        return Arithmetic._unary_int_map(raw, operation)

    def clip(self, raw: object, fmt: Format) -> int | np.ndarray:
        if not isinstance(fmt, Format):
            raise TypeError("fmt must be a Format")

        def operation(value: int) -> int:
            if value < fmt.minimum:
                self.events["saturation"] += 1
                return fmt.minimum
            if value > fmt.maximum:
                self.events["saturation"] += 1
                return fmt.maximum
            return value

        return self._unary_int_map(raw, operation)

    def rescale(self, raw: object, source_frac: int, target_fmt: Format) -> int | np.ndarray:
        source_frac = _integer(source_frac, "source_frac")
        if source_frac < 0:
            raise ValueError("source_frac must be non-negative")
        if not isinstance(target_fmt, Format):
            raise TypeError("target_fmt must be a Format")
        shifted = self.round_shift(raw, source_frac - target_fmt.frac)
        return self.clip(shifted, target_fmt)

    def add(self, a: object, b: object, fmt: Format) -> int | np.ndarray:
        return self.clip(self._binary_int_map(a, b, lambda x, y: x + y), fmt)

    def sub(self, a: object, b: object, fmt: Format) -> int | np.ndarray:
        return self.clip(self._binary_int_map(a, b, lambda x, y: x - y), fmt)

    def mul(
        self, a: object, b: object, fa: Format, fb: Format, out: Format
    ) -> int | np.ndarray:
        product = self._binary_int_map(a, b, lambda x, y: x * y)
        return self.rescale(product, fa.frac + fb.frac, out)

    def _accumulator_clip(self, value: int) -> int:
        minimum = -(1 << (self.profile.accumulator_width - 1))
        maximum = (1 << (self.profile.accumulator_width - 1)) - 1
        if value < minimum:
            self.events["accumulator_overflow"] += 1
            return minimum
        if value > maximum:
            self.events["accumulator_overflow"] += 1
            return maximum
        return value

    def dot_raw(self, a: object, b: object) -> int:
        """Return the exact product sum narrowed once to the accumulator width.

        This numerical contract detects overflow of the final mathematical sum.
        It does not model a cycle-by-cycle accumulator: cancelling terms can have
        out-of-range prefix sums.  Hardware accumulator sizing therefore needs a
        separate analytic bound on every prefix (or a specified summation tree).
        """
        left = self._as_object_array(a)
        right = self._as_object_array(b)
        if left.ndim != 1 or right.ndim != 1:
            raise ValueError("dot operands must be one-dimensional")
        if left.shape != right.shape:
            raise ValueError("dot operands must have the same shape")
        total = 0
        for x, y in zip(left, right):
            total += _integer(x, "raw value") * _integer(y, "raw value")
        return self._accumulator_clip(total)

    def dot(
        self, a: object, b: object, fa: Format, fb: Format, out: Format
    ) -> int:
        total = self.dot_raw(a, b)
        return int(self.rescale(total, fa.frac + fb.frac, out))

    def ratio(
        self,
        numerator: object,
        denominator: object,
        source_frac: int,
        out: Format,
    ) -> int | np.ndarray:
        """Divide raw values and round the requested fixed-point result.

        ``source_frac`` is numerator_frac minus denominator_frac.  A zero
        denominator records ``divide_by_zero`` and produces raw zero.
        """
        source_frac = _integer(source_frac, "source_frac")
        if not isinstance(out, Format):
            raise TypeError("out must be a Format")
        exponent = out.frac - source_frac

        def operation(n: int, d: int) -> int:
            if d == 0:
                self.events["divide_by_zero"] += 1
                return 0
            scaled_numerator = n << exponent if exponent >= 0 else n
            scaled_denominator = d if exponent >= 0 else d << -exponent
            sign_negative = (scaled_numerator < 0) != (scaled_denominator < 0)
            quotient, remainder = divmod(abs(scaled_numerator), abs(scaled_denominator))
            if remainder * 2 >= abs(scaled_denominator):
                quotient += 1
            raw = -quotient if sign_negative else quotient
            return int(self.clip(raw, out))

        return self._binary_int_map(numerator, denominator, operation)

    def matvec(
        self,
        matrix: object,
        vector: object,
        ma_fmt: Format,
        vec_fmt: Format,
        out: Format,
        transpose: bool = False,
    ) -> np.ndarray:
        matrix_array = self._as_object_array(matrix)
        vector_array = self._as_object_array(vector)
        if matrix_array.ndim != 2:
            raise ValueError("matrix must be two-dimensional")
        if vector_array.ndim != 1:
            raise ValueError("vector must be one-dimensional")
        if not isinstance(transpose, (bool, np.bool_)):
            raise TypeError("transpose must be boolean")
        operand = matrix_array.T if transpose else matrix_array
        if operand.shape[1] != vector_array.shape[0]:
            raise ValueError("matrix and vector dimensions do not align")
        result = np.empty(operand.shape[0], dtype=object)
        for row_index, row in enumerate(operand):
            total = self.dot_raw(row, vector_array)
            result[row_index] = self.rescale(total, ma_fmt.frac + vec_fmt.frac, out)
        return result
