"""Independent fixed-point canonical references.

This module is the numerical contract between the canonical algorithm and the
RTL.  It intentionally does not import RTL-compatible golden generators or
inspect RTL state.  The GP implementation follows the canonical equation from
the algorithms in ``canonical_algorithms.py`` while making the
Q16/signed-24-bit arithmetic explicit.
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
    history: list[tuple[list[int], list[int], list[int]]]


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


def _residual(phi: list[list[int]], y: Sequence[int], x: Sequence[int]) -> list[int]:
    fitted = _matvec(phi, x)
    return [sat_s24(s24(y[row]) - fitted[row]) for row in range(len(phi))]


def _argmax_abs(values: Sequence[int], excluded: set[int]) -> int:
    candidates = [idx for idx in range(len(values)) if idx not in excluded]
    return min(candidates, key=lambda idx: (-abs(s24(values[idx])), idx))


def _div_trunc(num: int, den: int) -> int:
    """Signed integer division truncated toward zero, matching RTL divider."""

    if den == 0:
        return 0
    quotient = abs(num) // abs(den)
    return -quotient if (num < 0) ^ (den < 0) else quotient


def _least_squares(phi: list[list[int]], y: Sequence[int], support: Sequence[int]) -> tuple[list[int], list[int]]:
    """Fixed-point normal-equation solve, independent of the RTL LS service.

    Matrix entries and the returned vector are Q16 signed-24-bit values.  The
    Gram/RHS accumulators and elimination workspace are deliberately wider so
    this reference defines arithmetic precision rather than inheriting a
    particular BRAM/DSP implementation.
    """

    support = list(dict.fromkeys(support))
    n_size = len(phi[0])
    if not support:
        return [0] * n_size, [s24(value) for value in y]
    gram = []
    rhs = []
    for i in support:
        rhs.append(sum(phi[row][i] * s24(y[row]) for row in range(len(phi))) >> Q)
        gram.append([
            sum(phi[row][i] * phi[row][j] for row in range(len(phi))) >> Q
            for j in support
        ])

    # Gauss-Jordan with deterministic largest-magnitude pivoting.  Each
    # quotient is returned to Q16 before the next elimination operation.
    order = len(support)
    for col in range(order):
        pivot = max(range(col, order), key=lambda row: abs(gram[row][col]))
        if gram[pivot][col] == 0:
            continue
        if pivot != col:
            gram[col], gram[pivot] = gram[pivot], gram[col]
            rhs[col], rhs[pivot] = rhs[pivot], rhs[col]
        pivot_value = gram[col][col]
        for row in range(order):
            if row == col:
                continue
            factor = _div_trunc(gram[row][col] << Q, pivot_value)
            if factor == 0:
                continue
            for k in range(col, order):
                gram[row][k] -= (factor * gram[col][k]) >> Q
            rhs[row] -= (factor * rhs[col]) >> Q
    coeff = [sat_s24(_div_trunc(rhs[idx] << Q, gram[idx][idx])) if gram[idx][idx] else 0 for idx in range(order)]
    x = [0] * n_size
    for idx, value in zip(support, coeff):
        x[idx] = value
    return x, _residual(phi, y, x)


def _top(values: Sequence[int], count: int, excluded: set[int] | None = None) -> list[int]:
    excluded = excluded or set()
    ranked = [idx for idx in range(len(values)) if idx not in excluded]
    ranked.sort(key=lambda idx: (-abs(s24(values[idx])), idx))
    return ranked[:max(0, count)]


def _threshold(values: Sequence[int], count: int) -> list[int]:
    return sorted(_top(values, count))


def _trace(history: list[tuple[list[int], list[int], list[int]]], support: Sequence[int], x: Sequence[int], residual: Sequence[int]) -> None:
    history.append((list(support), list(x), list(residual)))


def gradient_pursuit(phi: list[list[int]], y: Sequence[int], k: int) -> FixedTrace:
    """Canonical GP with explicit Q16 arithmetic and RTL-independent state."""

    n_size = len(phi[0])
    x = [0] * n_size
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        gradient = _corr(phi, residual)
        support.append(_argmax_abs(gradient, set(support)))
        direction = [gradient[idx] if idx in support else 0 for idx in range(n_size)]
        projected = _matvec(phi, direction)
        numerator = sum(s24(residual[row]) * s24(projected[row]) for row in range(len(phi)))
        denominator = sum(s24(projected[row]) * s24(projected[row]) for row in range(len(phi)))
        alpha_q = _div_trunc(numerator << Q, denominator)
        x = [sat_s24(x[idx] + ((direction[idx] * alpha_q) >> Q)) for idx in range(n_size)]
        residual = _residual(phi, y, x)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def omp(phi: list[list[int]], y: Sequence[int], k: int) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        support.append(_argmax_abs(_corr(phi, residual), set(support)))
        x, residual = _least_squares(phi, y, support)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def cosamp(phi: list[list[int]], y: Sequence[int], k: int) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        candidates = _top(_corr(phi, residual), 2 * k)
        merged = sorted(set(support).union(candidates))
        temp_x, _ = _least_squares(phi, y, merged)
        support = _threshold(temp_x, k)
        x, residual = _least_squares(phi, y, support)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def iht(phi: list[list[int]], y: Sequence[int], k: int, step_shift: int = 3) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        gradient = _corr(phi, residual)
        z = [sat_s24(x[idx] + (gradient[idx] >> step_shift)) for idx in range(len(x))]
        support = _threshold(z, k)
        keep = set(support)
        x = [z[idx] if idx in keep else 0 for idx in range(len(z))]
        residual = _residual(phi, y, x)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def htp(phi: list[list[int]], y: Sequence[int], k: int, step_shift: int = 3) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        gradient = _corr(phi, residual)
        z = [sat_s24(x[idx] + (gradient[idx] >> step_shift)) for idx in range(len(x))]
        support = _threshold(z, k)
        x, residual = _least_squares(phi, y, support)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def subspace_pursuit(phi: list[list[int]], y: Sequence[int], k: int) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        candidates = _top(_corr(phi, residual), k)
        merged = sorted(set(support).union(candidates))
        temp_x, _ = _least_squares(phi, y, merged)
        support = _threshold(temp_x, k)
        x, residual = _least_squares(phi, y, support)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def gomp(phi: list[list[int]], y: Sequence[int], k: int, atoms_per_iteration: int = 2) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    while len(support) < k:
        count = min(atoms_per_iteration, k - len(support))
        support.extend(_top(_corr(phi, residual), count, set(support)))
        x, residual = _least_squares(phi, y, support)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def mp(phi: list[list[int]], y: Sequence[int], k: int) -> FixedTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    denominator = sum(phi[row][0] * phi[row][0] for row in range(len(phi))) >> Q
    for _ in range(k):
        scores = _corr(phi, residual)
        idx = _argmax_abs(scores, set())
        norm = sum(phi[row][idx] * phi[row][idx] for row in range(len(phi))) >> Q
        alpha_q = _div_trunc(scores[idx] << Q, norm or denominator or 1)
        x[idx] = sat_s24(x[idx] + alpha_q)
        if idx not in support:
            support.append(idx)
        residual = _residual(phi, y, x)
        _trace(history, support, x, residual)
    return FixedTrace(x, residual, support, history)


def run_all(phi: list[list[int]], y: Sequence[int], k: int, step_shift: int = 3) -> dict[str, FixedTrace]:
    """Run the full fixed-point canonical suite without RTL capacity limits."""

    return {
        "OMP": omp(phi, y, k),
        "CoSaMP": cosamp(phi, y, k),
        "IHT": iht(phi, y, k, step_shift),
        "HTP": htp(phi, y, k, step_shift),
        "SP": subspace_pursuit(phi, y, k),
        "GP": gradient_pursuit(phi, y, k),
        "GOMP": gomp(phi, y, k),
        "MP": mp(phi, y, k),
    }
