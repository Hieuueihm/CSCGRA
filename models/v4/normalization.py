"""Power-of-two input normalization for v4 numerical studies.

Normalization is selected from the finite measured input y for each job.  It
does not inspect a truth signal, subtract a mean, clip samples, or claim to
recover an already quantized ADC signal.  The immutable metadata object must
travel with encoded measurements so that results can be decoded consistently.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Any, Iterable

import numpy as np


NORMALIZATION_REVISION = 1
DEFAULT_TARGET_EXPONENT = -1  # target peak 2**-1 = 0.5
DEFAULT_EXPONENT_BOUNDS = (-31, 31)
TARGET_EXPONENT_BOUNDS = (-1022, 1023)
GAIN_EXPONENT_BOUNDS = (-1074, 1023)


def _finite_array(values: Any, *, name: str = "values") -> np.ndarray:
    array = np.asarray(values, dtype=np.float64)
    if array.size == 0:
        raise ValueError(f"{name} must be non-empty")
    if not np.all(np.isfinite(array)):
        raise ValueError(f"{name} must contain only finite values")
    return array


def _bounds(bounds: Iterable[int]) -> tuple[int, int]:
    try:
        low, high = tuple(bounds)
    except (TypeError, ValueError) as exc:
        raise ValueError("exponent_bounds must contain two integers") from exc
    if isinstance(low, bool) or isinstance(high, bool):
        raise ValueError("exponent bounds must be integers")
    if int(low) != low or int(high) != high or int(low) > int(high):
        raise ValueError("exponent_bounds must be ordered integers")
    return int(low), int(high)


def _target_exponent(target_peak: float) -> int:
    if isinstance(target_peak, bool):
        raise ValueError("target_peak must be a positive power of two")
    target = float(target_peak)
    if not math.isfinite(target) or target <= 0.0:
        raise ValueError("target_peak must be a positive power of two")
    mantissa, exponent = math.frexp(target)
    if mantissa != 0.5:
        raise ValueError("target_peak must be an exact power of two")
    result = exponent - 1
    if not TARGET_EXPONENT_BOUNDS[0] <= result <= TARGET_EXPONENT_BOUNDS[1]:
        raise ValueError("target_peak exponent is outside the finite binary64 range")
    return result


def _positive_real(value: float, *, name: str, allow_zero: bool = True) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{name} must be a finite real scalar")
    result = float(value)
    if not math.isfinite(result) or (result < 0.0 if allow_zero else result <= 0.0):
        qualifier = "nonnegative" if allow_zero else "positive"
        raise ValueError(f"{name} must be a finite {qualifier} real scalar")
    return result


def _finite_scaled(array: np.ndarray, exponent: int, *, name: str) -> np.ndarray:
    with np.errstate(over="ignore", invalid="ignore"):
        result = np.ldexp(array, exponent)
    if not np.all(np.isfinite(result)):
        raise ValueError(f"{name} overflowed to a non-finite value")
    return result


def shift_raw(values: Any, exponent: int) -> np.ndarray:
    """Shift integer raw values by a power of two without saturation.

    Positive exponents are exact left shifts.  Negative exponents use
    nearest-integer rounding with ties away from zero; callers must account
    for that quantization when using the helper.  This helper is intentionally
    separate from encode, which operates in floating point before D
    quantization.
    """
    if isinstance(exponent, bool) or int(exponent) != exponent:
        raise ValueError("exponent must be an integer")
    exponent = int(exponent)
    array = np.asarray(values)
    result = np.empty(array.shape, dtype=object)
    divisor = 1 << (-exponent) if exponent < 0 else 1
    for index, value in np.ndenumerate(array):
        if isinstance(value, (bool, np.bool_)):
            raise ValueError("raw values must be integers")
        try:
            integer = int(value)
        except (TypeError, ValueError, OverflowError) as exc:
            raise ValueError("raw values must be integers") from exc
        if integer != value:
            raise ValueError("raw values must be integers")
        if exponent >= 0:
            result[index] = integer << exponent
        else:
            magnitude = abs(integer)
            rounded = (magnitude + divisor // 2) // divisor
            result[index] = rounded if integer >= 0 else -rounded
    return result


@dataclass(frozen=True, slots=True)
class Normalization:
    """Immutable per-job power-of-two normalization metadata."""

    exponent: int
    input_peak: float
    target_exponent: int = DEFAULT_TARGET_EXPONENT
    revision: int = NORMALIZATION_REVISION
    exponent_bounds: tuple[int, int] = DEFAULT_EXPONENT_BOUNDS

    def __post_init__(self) -> None:
        if isinstance(self.exponent, bool) or int(self.exponent) != self.exponent:
            raise ValueError("exponent must be an integer")
        if not GAIN_EXPONENT_BOUNDS[0] <= int(self.exponent) <= GAIN_EXPONENT_BOUNDS[1]:
            raise ValueError("exponent is outside the finite binary64 gain range")
        if isinstance(self.target_exponent, bool) or int(self.target_exponent) != self.target_exponent:
            raise ValueError("target_exponent must be an integer")
        if not TARGET_EXPONENT_BOUNDS[0] <= int(self.target_exponent) <= TARGET_EXPONENT_BOUNDS[1]:
            raise ValueError("target_exponent is outside the finite binary64 range")
        if self.revision != NORMALIZATION_REVISION:
            raise ValueError(f"unsupported normalization revision {self.revision}")
        low, high = _bounds(self.exponent_bounds)
        if not low <= int(self.exponent) <= high:
            raise ValueError("normalization exponent is outside exponent_bounds")
        peak = _positive_real(self.input_peak, name="input_peak")
        object.__setattr__(self, "exponent", int(self.exponent))
        object.__setattr__(self, "target_exponent", int(self.target_exponent))
        object.__setattr__(self, "input_peak", peak)
        object.__setattr__(self, "exponent_bounds", (low, high))
        try:
            encoded_peak = math.ldexp(peak, int(self.exponent))
        except OverflowError as exc:
            raise ValueError("metadata gain overflows input_peak") from exc
        if not math.isfinite(encoded_peak):
            raise ValueError("metadata gain produces a non-finite encoded peak")

    @classmethod
    def derive(
        cls,
        values: Any,
        *,
        target_peak: float = 0.5,
        exponent_bounds: tuple[int, int] = DEFAULT_EXPONENT_BOUNDS,
        revision: int = NORMALIZATION_REVISION,
    ) -> "Normalization":
        array = _finite_array(values, name="y")
        target_exponent = _target_exponent(target_peak)
        bounds = _bounds(exponent_bounds)
        peak = float(np.max(np.abs(array)))
        if peak == 0.0:
            exponent = 0
        else:
            mantissa, peak_exponent = math.frexp(peak)
            exponent = target_exponent - peak_exponent
            lower = math.ldexp(1.0, target_exponent - 1)
            encoded_peak = math.ldexp(mantissa, target_exponent)
            # frexp places exact binary powers at mantissa 0.5.  The desired
            # interval is open at the lower boundary, so move those cases up.
            if encoded_peak <= lower:
                exponent += 1
        if not bounds[0] <= exponent <= bounds[1]:
            raise ValueError(
                f"normalization exponent {exponent} outside bounds {bounds}; no clipping applied"
            )
        metadata = cls(
            exponent=exponent,
            input_peak=peak,
            target_exponent=target_exponent,
            revision=revision,
            exponent_bounds=bounds,
        )
        if peak != 0.0 and not lower < metadata.encoded_peak <= metadata.target_peak:
            raise RuntimeError("normalization interval construction failed")
        return metadata

    @property
    def gain(self) -> float:
        return math.ldexp(1.0, self.exponent)

    @property
    def target_peak(self) -> float:
        return math.ldexp(1.0, self.target_exponent)

    @property
    def encoded_peak(self) -> float:
        return math.ldexp(self.input_peak, self.exponent)

    @property
    def key(self) -> tuple[int, int, int, tuple[int, int]]:
        return (self.revision, self.exponent, self.target_exponent, self.exponent_bounds)

    @property
    def descriptor(self) -> dict[str, Any]:
        return {
            "family": "power_of_two_input_normalization",
            "revision": self.revision,
            "exponent": self.exponent,
            "gain": self.gain,
            "input_peak": self.input_peak,
            "encoded_peak": self.encoded_peak,
            "target_peak": self.target_peak,
            "exponent_bounds": self.exponent_bounds,
            "mean_subtraction": False,
            "adc_quantization_recovery_claim": False,
        }

    def encode(self, values: Any) -> np.ndarray:
        """Apply the exact power-of-two gain to finite floating-point values."""
        return _finite_scaled(_finite_array(values), self.exponent, name="encoded values")

    def decode(self, values: Any) -> np.ndarray:
        """Undo the per-job gain on finite floating-point values."""
        return _finite_scaled(_finite_array(values), -self.exponent, name="decoded values")

    def encode_raw(self, values: Any) -> np.ndarray:
        return shift_raw(values, self.exponent)

    def decode_raw(self, values: Any) -> np.ndarray:
        return shift_raw(values, -self.exponent)

    def scale_residual_atol(self, residual_atol: float) -> float:
        return scale_residual_atol(residual_atol, self.gain)

    def scale_lasso_lambda(self, lasso_lambda: float) -> float:
        return scale_lasso_lambda(lasso_lambda, self.gain)


NormalizationMetadata = Normalization
PowerOfTwoNormalization = Normalization


def derive_normalization(values: Any, **kwargs: Any) -> Normalization:
    return Normalization.derive(values, **kwargs)


def normalize(values: Any, **kwargs: Any) -> tuple[np.ndarray, Normalization]:
    metadata = Normalization.derive(values, **kwargs)
    return metadata.encode(values), metadata


normalize_input = normalize


def scale_residual_atol(residual_atol: float, gain: float) -> float:
    """Scale an absolute residual tolerance for y' = gain*y."""
    atol = _positive_real(residual_atol, name="residual_atol")
    factor = _positive_real(gain, name="gain", allow_zero=False)
    result = atol * factor
    if not math.isfinite(result):
        raise ValueError("scaled residual_atol is non-finite")
    return result


def scale_lasso_lambda(lasso_lambda: float, gain: float) -> float:
    """Scale lambda under the homogeneous LASSO convention.

    With y' = gain*y, x' = gain*x, and unchanged A, the objective is
    multiplied by gain squared when lambda' = gain*lambda.  This helper does
    not apply when a solver uses a differently normalized objective.
    """
    lam = _positive_real(lasso_lambda, name="lasso_lambda")
    factor = _positive_real(gain, name="gain", allow_zero=False)
    result = lam * factor
    if not math.isfinite(result):
        raise ValueError("scaled lasso_lambda is non-finite")
    return result


__all__ = [
    "NORMALIZATION_REVISION",
    "DEFAULT_TARGET_EXPONENT",
    "DEFAULT_EXPONENT_BOUNDS",
    "TARGET_EXPONENT_BOUNDS",
    "GAIN_EXPONENT_BOUNDS",
    "Normalization",
    "NormalizationMetadata",
    "PowerOfTwoNormalization",
    "derive_normalization",
    "normalize",
    "normalize_input",
    "scale_residual_atol",
    "scale_lasso_lambda",
    "shift_raw",
]
