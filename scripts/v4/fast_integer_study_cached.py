"""Optional bounded conversion cache layered on the v4 study accelerator.

This module leaves the original accelerator and all models untouched.  It
temporarily replaces only its private raw-array converter while the existing
accelerated_arithmetic context is active.  Cache entries are limited to 2-D
object arrays containing native Python integers or NumPy integer scalars.
Each entry retains a strong object-array snapshot, so a caller's old object
cannot be collected and its pointer reused for a different value while the
key remains resident.  Unsupported, mutable, floating-point, boolean, or
out-of-range values use the original conversion and arbitrary-precision
fallback paths.
"""

from __future__ import annotations

from collections import OrderedDict
from contextlib import contextmanager
from numbers import Integral
from typing import Any, Iterator

import numpy as np

from models.v4.fixed import Arithmetic
from scripts.v4 import fast_integer_study as _base


_BASE_ACCELERATED_ARITHMETIC = _base.accelerated_arithmetic
_NUMPY_INTEGER_TYPES = tuple({
    np.dtype(name).type
    for name in (
        "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64",
        "longlong", "ulonglong", "intp", "uintp",
    )
})


def _native_integer_array(array: np.ndarray) -> bool:
    for value in array.flat:
        if isinstance(value, (bool, np.bool_)):
            return False
        if type(value) is int:
            continue
        if type(value) in _NUMPY_INTEGER_TYPES:
            continue
        return False
    return True


@contextmanager
def cached_accelerated_arithmetic(cache_limit: int = 8) -> Iterator[dict[str, Any]]:
    """Install guarded acceleration with a bounded 2-D raw conversion cache."""
    if isinstance(cache_limit, bool) or not isinstance(cache_limit, Integral) or cache_limit < 1:
        raise ValueError("cache_limit must be a positive integer")
    cache_limit = int(cache_limit)
    cache: OrderedDict[tuple[tuple[int, ...], bytes], tuple[np.ndarray, np.ndarray, int]] = OrderedDict()
    stats = {"hits": 0, "misses": 0, "bypasses": 0, "evictions": 0}
    original_converter = _base._raw_int64

    def cached_converter(values: Any):
        array = np.asarray(values, dtype=object)
        if array.ndim != 2 or array.dtype != object:
            stats["bypasses"] += 1
            return original_converter(values)
        key = (array.shape, array.tobytes(order="C"))
        entry = cache.get(key)
        if entry is not None:
            stats["hits"] += 1
            cache.move_to_end(key)
            return entry[1], entry[2]
        stats["misses"] += 1
        if not _native_integer_array(array):
            stats["bypasses"] += 1
            return original_converter(values)
        converted = original_converter(array)
        if converted is None:
            return None
        converted_array, maximum = converted
        # Retain the object pointers represented by key.  This snapshot is
        # never consulted for values; it exists to prevent pointer reuse.
        snapshot = np.array(array, dtype=object, copy=True, order="C")
        cache[key] = (snapshot, converted_array.copy(), int(maximum))
        cache.move_to_end(key)
        if len(cache) > cache_limit:
            cache.popitem(last=False)
            stats["evictions"] += 1
        return cache[key][1], cache[key][2]

    _base._raw_int64 = cached_converter
    try:
        # Capture the base context at module import so callers may temporarily
        # replace _base.accelerated_arithmetic with this context without
        # recursive self-entry.
        with _BASE_ACCELERATED_ARITHMETIC() as metadata:
            metadata = dict(metadata)
            metadata["cache"] = {
                "key": "(shape, object-array.tobytes(order='C'))",
                "limit": cache_limit,
                "native_integer_2d_only": True,
                "strong_snapshot": True,
                "stats": stats,
            }
            yield metadata
    finally:
        _base._raw_int64 = original_converter


cached_fast_arithmetic = cached_accelerated_arithmetic


__all__ = ["cached_accelerated_arithmetic", "cached_fast_arithmetic"]
