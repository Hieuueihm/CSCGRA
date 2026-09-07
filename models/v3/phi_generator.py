"""Bit-exact generated sensing-matrix contract for architecture v3.

Phi is never materialized in RTL memory.  A coordinate-addressable
Threefry2x32-20 function maps ``(seed, column, row_block)`` to 32 Bernoulli
signs.  The mapping follows the Random123 Threefry2x32-20 definition so the
host, golden model, FPGA and future ASIC can share known-answer vectors.

Bit value 1 maps to +1/8 and bit value 0 maps to -1/8.  The two 32-bit output
words of one Threefry invocation cover 64 consecutive rows of one column.
"""

from __future__ import annotations

from typing import Iterable

import numpy as np


MASK32 = (1 << 32) - 1
THREEFRY_PARITY32 = 0x1BD11BDA
THREEFRY_ROUNDS = 20
THREEFRY_ROTATIONS_2X32 = (13, 15, 26, 6, 17, 29, 16, 24)
PHI_ROWS_PER_WORD = 32
PHI_WORDS_PER_COUNTER = 2
PHI_SCALE = 1.0 / 8.0
PHI_Q3_14_MAGNITUDE = 1 << 11
SOLVER_WIDTH = 27


def _u32(value: int) -> int:
    return int(value) & MASK32


def _rotl32(value: int, amount: int) -> int:
    value = _u32(value)
    return _u32((value << amount) | (value >> (32 - amount)))


def threefry2x32_20(
    counter: tuple[int, int], key: tuple[int, int]
) -> tuple[int, int]:
    """Return the canonical Random123 Threefry2x32 result after 20 rounds."""

    key_words = (
        _u32(key[0]),
        _u32(key[1]),
        _u32(THREEFRY_PARITY32 ^ key[0] ^ key[1]),
    )
    x0 = _u32(counter[0] + key_words[0])
    x1 = _u32(counter[1] + key_words[1])

    for round_index in range(THREEFRY_ROUNDS):
        x0 = _u32(x0 + x1)
        x1 = _rotl32(x1, THREEFRY_ROTATIONS_2X32[round_index & 7]) ^ x0
        if (round_index + 1) % 4 == 0:
            injection = (round_index + 1) // 4
            x0 = _u32(x0 + key_words[injection % 3])
            x1 = _u32(x1 + key_words[(injection + 1) % 3] + injection)

    return x0, x1


def phi_sign_word(seed: int, column: int, row_block: int) -> int:
    """Generate signs for rows ``32*row_block .. 32*row_block+31``.

    ``seed`` is a 64-bit key, ``column`` is counter word 0 and each pair of
    row blocks shares counter word 1.  The mapping is random-access: requests
    may be issued in any order without changing any result.
    """

    if not 0 <= seed < (1 << 64):
        raise ValueError("seed must fit 64 bits")
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
    """Return +1 or -1 for one generated Phi coordinate."""

    if row < 0:
        raise ValueError("row must be non-negative")
    word = phi_sign_word(seed, column, row // PHI_ROWS_PER_WORD)
    return 1 if ((word >> (row % PHI_ROWS_PER_WORD)) & 1) else -1


def phi_q3_14(seed: int, row: int, column: int) -> int:
    """Return one generated Phi entry as signed D18F14 raw integer."""

    return phi_sign(seed, row, column) * PHI_Q3_14_MAGNITUDE


def matrix(seed: int, measurement_count: int, signal_length: int) -> np.ndarray:
    """Materialize float Phi for software/golden use only, never for RTL."""

    if measurement_count <= 0 or signal_length <= 0:
        raise ValueError("matrix dimensions must be positive")
    result = np.empty((measurement_count, signal_length), dtype=np.float64)
    for column in range(signal_length):
        for row in range(measurement_count):
            result[row, column] = phi_sign(seed, row, column) * PHI_SCALE
    return result


def words_for_column(
    seed: int, column: int, measurement_count: int
) -> Iterable[tuple[int, int]]:
    """Yield ``(lane_mask, sign_word)`` in the RTL column-major order."""

    if measurement_count <= 0:
        raise ValueError("measurement_count must be positive")
    for row_block in range((measurement_count + 31) // 32):
        valid_rows = min(32, measurement_count - 32 * row_block)
        lane_mask = MASK32 if valid_rows == 32 else (1 << valid_rows) - 1
        yield lane_mask, phi_sign_word(seed, column, row_block)

def runtime_scale_s27(
    value_raw_f19: int, mantissa_uq17: int, exponent: int
) -> tuple[int, bool]:
    """Scale one signed F19 value and saturate to the S27 contract.

    The result is ``value * mantissa * 2**exponent / 2**17`` rounded to
    nearest with ties away from zero.  ``mantissa_uq17`` is unsigned Q1.17.
    """

    if not 1 <= mantissa_uq17 < (1 << 18):
        raise ValueError("mantissa_uq17 must be nonzero UQ1.17")
    if not -(1 << 4) <= exponent < (1 << 4):
        raise ValueError("exponent must fit signed five bits")
    product = int(value_raw_f19) * int(mantissa_uq17)
    shift = 17 - exponent
    magnitude = abs(product)
    if shift > 0:
        magnitude = (magnitude + (1 << (shift - 1))) >> shift
    else:
        magnitude <<= -shift
    scaled = -magnitude if product < 0 else magnitude
    minimum = -(1 << (SOLVER_WIDTH - 1))
    maximum = (1 << (SOLVER_WIDTH - 1)) - 1
    saturated = scaled < minimum or scaled > maximum
    return max(minimum, min(maximum, scaled)), saturated
