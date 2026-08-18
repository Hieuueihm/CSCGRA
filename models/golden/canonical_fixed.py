"""Independent fixed-point canonical references.

This module is the numerical contract between the canonical algorithm and the
RTL.  It intentionally does not import RTL-compatible golden generators or
inspect RTL state.  The GP implementation follows the canonical equation from
``canonical_algorithms.gradient_pursuit`` while making the Q16/signed-24-bit
arithmetic explicit.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


Q = 16
DATA_W = 24
DATA_MASK = (1 << DATA_W) - 1
MIN_S24 = -(1 << (DATA_W - 1))
MAX_S24 = (1 << (DATA_W - 1)) - 1
TAPS = 0x80200003


@dataclass
class FixedTrace:
    x: list[int]
    residual: list[int]
    support: list[int]


def s24(value: int) -> int:
    value &= DATA_MASK
    return value - (1 << DATA_W) if value & (1 << (DATA_W - 1)) else value


def sat_s24(value: int) -> int:
    return max(MIN_S24, min(MAX_S24, int(value)))


def galois_step(state: int) -> int:
    shifted = (state >> 1) & 0x7FFFFFFF
    return (shifted ^ TAPS) & 0xFFFFFFFF if state & 1 else shifted


def lfsr_advance(state: int, steps: int) -> int:
    for _ in range(steps):
        state = galois_step(state)
    return state


def make_phi(m_size: int, n_size: int, seed: int, scale_q: int) -> list[list[int]]:
    """Build the deterministic benchmark matrix in signed Q16 integers."""

    phi: list[list[int]] = []
    for row_idx in range(m_size):
        row_state = lfsr_advance(seed, row_idx * n_size)
        row: list[int] = []
        for col_idx in range(n_size):
            state = lfsr_advance(row_state, col_idx + 1)
            row.append(scale_q if state & 1 else -scale_q)
        phi.append(row)
    return phi


def _corr(phi: list[list[int]], residual: Sequence[int]) -> list[int]:
    n_size = len(phi[0])
    return [
        sat_s24(sum(phi[row][col] * s24(residual[row]) for row in range(len(phi))) >> Q)
        for col in range(n_size)
    ]


def _matvec(phi: list[list[int]], vector: Sequence[int]) -> list[int]:
    return [
        sat_s24(sum(phi[row][col] * s24(vector[col]) for col in range(len(vector))) >> Q)
        for row in range(len(phi))
    ]


def _argmax_abs(values: Sequence[int], excluded: set[int]) -> int:
    candidates = [idx for idx in range(len(values)) if idx not in excluded]
    return min(candidates, key=lambda idx: (-abs(s24(values[idx])), idx))


def _div_trunc(num: int, den: int) -> int:
    """Signed integer division truncated toward zero, matching RTL divider."""

    if den == 0:
        return 0
    quotient = abs(num) // abs(den)
    return -quotient if (num < 0) ^ (den < 0) else quotient


def gradient_pursuit(phi: list[list[int]], y: Sequence[int], k: int) -> FixedTrace:
    """Canonical GP with explicit Q16 arithmetic and RTL-independent state."""

    n_size = len(phi[0])
    x = [0] * n_size
    residual = [s24(value) for value in y]
    support: list[int] = []
    for _ in range(k):
        gradient = _corr(phi, residual)
        support.append(_argmax_abs(gradient, set(support)))
        direction = [gradient[idx] if idx in support else 0 for idx in range(n_size)]
        projected = _matvec(phi, direction)
        numerator = sum(s24(residual[row]) * s24(projected[row]) for row in range(len(phi)))
        denominator = sum(s24(projected[row]) * s24(projected[row]) for row in range(len(phi)))
        alpha_q = _div_trunc(numerator << Q, denominator)
        x = [sat_s24(x[idx] + ((direction[idx] * alpha_q) >> Q)) for idx in range(n_size)]
        fitted = _matvec(phi, x)
        residual = [sat_s24(s24(y[row]) - fitted[row]) for row in range(len(phi))]
    return FixedTrace(x, residual, support)
