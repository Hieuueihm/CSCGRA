"""Floating-point canonical sparse-recovery references.

This module intentionally contains no RTL-specific limits, Q-format shifts, or
PE scheduling. It implements the mathematical algorithmic steps for the same
matrix/vector supplied by the caller. ``canonical_fixed.py`` is the separate
fixed-point numerical contract used when those equations are moved into RTL.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Iterable, Sequence


Vector = list[float]
Matrix = list[list[float]]


@dataclass
class Trace:
    """State after each canonical iteration, plus the final state."""

    x: Vector
    residual: Vector
    support: list[int]
    history: list[tuple[list[int], Vector, Vector]]


def _dot(a: Sequence[float], b: Sequence[float]) -> float:
    return sum(x * y for x, y in zip(a, b))


def _column(a: Matrix, index: int) -> Vector:
    return [row[index] for row in a]


def _matvec(a: Matrix, x: Sequence[float]) -> Vector:
    return [_dot(row, x) for row in a]


def _corr(a: Matrix, residual: Sequence[float]) -> Vector:
    return [_dot(_column(a, j), residual) for j in range(len(a[0]))]


def _column_norm_sq(a: Matrix, index: int) -> float:
    return _dot(_column(a, index), _column(a, index))


def _ranked(values: Sequence[float], exclude: Iterable[int] = ()) -> list[int]:
    excluded = set(exclude)
    # Deterministic tie break: lower dictionary index wins.
    return sorted(
        (idx for idx in range(len(values)) if idx not in excluded),
        key=lambda idx: (-abs(values[idx]), idx),
    )


def _top(values: Sequence[float], count: int, exclude: Iterable[int] = ()) -> list[int]:
    return _ranked(values, exclude)[: max(0, count)]


def _solve_linear(a: Matrix, b: Vector) -> Vector:
    """Small dense Gauss-Jordan solve with deterministic pivoting."""

    n = len(b)
    if n == 0:
        return []
    aug = [list(a[row]) + [b[row]] for row in range(n)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(aug[row][col]))
        if abs(aug[pivot][col]) <= 1.0e-15:
            continue
        if pivot != col:
            aug[col], aug[pivot] = aug[pivot], aug[col]
        scale = aug[col][col]
        for k in range(col, n + 1):
            aug[col][k] /= scale
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col]
            if factor:
                for k in range(col, n + 1):
                    aug[row][k] -= factor * aug[col][k]
    return [aug[row][n] for row in range(n)]


def least_squares(a: Matrix, y: Sequence[float], support: Sequence[int]) -> tuple[Vector, Vector]:
    """Return the least-squares fit restricted to ``support``."""

    support = list(dict.fromkeys(support))
    n = len(a[0])
    if not support:
        return [0.0] * n, list(y)
    gram = [
        [_dot(_column(a, support[i]), _column(a, support[j])) for j in range(len(support))]
        for i in range(len(support))
    ]
    rhs = [_dot(_column(a, idx), y) for idx in support]
    coeff = _solve_linear(gram, rhs)
    x = [0.0] * n
    for idx, value in zip(support, coeff):
        x[idx] = value
    residual = [yi - ai for yi, ai in zip(y, _matvec(a, x))]
    return x, residual


def _hard_threshold(x: Sequence[float], k: int) -> list[int]:
    return sorted(_top(x, k))


def _trace_step(history: list[tuple[list[int], Vector, Vector]], support: Sequence[int], x: Vector, residual: Vector) -> None:
    history.append((list(support), list(x), list(residual)))


def omp(a: Matrix, y: Vector, k: int) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        support += _top(_corr(a, residual), 1, support)
        x, residual = least_squares(a, y, support)
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def cosamp(a: Matrix, y: Vector, k: int) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        candidates = _top(_corr(a, residual), 2 * k)
        merged = sorted(set(support).union(candidates))
        temp_x, _ = least_squares(a, y, merged)
        support = _hard_threshold(temp_x, k)
        x, residual = least_squares(a, y, support)
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def iht(a: Matrix, y: Vector, k: int, step_size: float) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        z = [xi + step_size * gi for xi, gi in zip(x, _corr(a, residual))]
        support = _hard_threshold(z, k)
        keep = set(support)
        x = [z[idx] if idx in keep else 0.0 for idx in range(len(z))]
        residual = [yi - ai for yi, ai in zip(y, _matvec(a, x))]
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def htp(a: Matrix, y: Vector, k: int, step_size: float) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        z = [xi + step_size * gi for xi, gi in zip(x, _corr(a, residual))]
        support = _hard_threshold(z, k)
        x, residual = least_squares(a, y, support)
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def subspace_pursuit(a: Matrix, y: Vector, k: int) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        candidates = _top(_corr(a, residual), k)
        merged = sorted(set(support).union(candidates))
        temp_x, _ = least_squares(a, y, merged)
        support = _hard_threshold(temp_x, k)
        x, residual = least_squares(a, y, support)
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def gomp(a: Matrix, y: Vector, k: int, atoms_per_iteration: int = 2) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    while len(support) < k:
        count = min(atoms_per_iteration, k - len(support))
        support += _top(_corr(a, residual), count, support)
        x, residual = least_squares(a, y, support)
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def mp(a: Matrix, y: Vector, k: int) -> Trace:
    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        corr = _corr(a, residual)
        idx = _top(corr, 1)[0]
        denom = _column_norm_sq(a, idx)
        alpha = corr[idx] / denom if denom else 0.0
        x[idx] += alpha
        if idx not in support:
            support.append(idx)
        residual = [yi - ai for yi, ai in zip(y, _matvec(a, x))]
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def gradient_pursuit(a: Matrix, y: Vector, k: int) -> Trace:
    """Basic Gradient Pursuit with support expansion and exact line search.

    This is deliberately distinct from IHT/HTP: the update direction is the
    restricted gradient on the active support and the step is chosen by a
    residual line search.  It follows the Gradient Pursuits family rather than
    the RTL's current full-vector ``x += (A^T r >>> mu_shift)`` shortcut.
    """

    x = [0.0] * len(a[0])
    residual = list(y)
    support: list[int] = []
    history: list[tuple[list[int], Vector, Vector]] = []
    for _ in range(k):
        support += _top(_corr(a, residual), 1, support)
        gradient = _corr(a, residual)
        direction = [gradient[idx] if idx in support else 0.0 for idx in range(len(x))]
        projected = _matvec(a, direction)
        denom = _dot(projected, projected)
        alpha = _dot(residual, projected) / denom if denom else 0.0
        x = [xi + alpha * di for xi, di in zip(x, direction)]
        residual = [yi - ai for yi, ai in zip(y, _matvec(a, x))]
        _trace_step(history, support, x, residual)
    return Trace(x, residual, support, history)


def run_all(a: Matrix, y: Vector, k: int, iht_step: float) -> dict[str, Trace]:
    """Run the canonical set using the active TB algorithm names."""

    return {
        "OMP": omp(a, y, k),
        "CoSaMP": cosamp(a, y, k),
        "IHT": iht(a, y, k, iht_step),
        "HTP": htp(a, y, k, iht_step),
        "SP": subspace_pursuit(a, y, k),
        "GP": gradient_pursuit(a, y, k),
        "GOMP": gomp(a, y, k),
        "MP": mp(a, y, k),
    }


def spectral_step_size(a: Matrix, iterations: int = 32) -> float:
    """Estimate 1/lambda_max(A^T A) for a deterministic IHT/HTP step."""

    n = len(a[0])
    v = [1.0 / math.sqrt(n)] * n
    for _ in range(iterations):
        av = _matvec(a, v)
        atav = [_dot(_column(a, j), av) for j in range(n)]
        norm = math.sqrt(_dot(atav, atav))
        if norm <= 1.0e-15:
            return 1.0
        v = [value / norm for value in atav]
    av = _matvec(a, v)
    atav = [_dot(_column(a, j), av) for j in range(n)]
    eigenvalue = _dot(v, atav)
    return 1.0 / eigenvalue if eigenvalue > 1.0e-15 else 1.0
