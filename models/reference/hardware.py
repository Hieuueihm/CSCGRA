"""Hardware Python reference derived from the canonical algorithms.

This is the second and only hardware reference source beside
``reference/canonical.py``. It models the implementation choices that are
part of the RTL contract (Q16 normal equations, diagonal regularisation, LDLT
factorisation, reciprocal-D scaling and signed-24-bit coefficient
quantisation). It never imports RTL or a RTL-generated golden.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

Q = 16
DATA_W = 24
DATA_MASK = (1 << DATA_W) - 1
MIN_S24 = -(1 << (DATA_W - 1))
MAX_S24 = (1 << (DATA_W - 1)) - 1
MAX_SUPPORT = 16


def s24(value: int) -> int:
    value &= DATA_MASK
    return value - (1 << DATA_W) if value & (1 << (DATA_W - 1)) else value


def sat_s24(value: int) -> int:
    return max(MIN_S24, min(MAX_S24, int(value)))


def _div_trunc(num: int, den: int) -> int:
    if den == 0:
        return 0
    quotient = abs(num) // abs(den)
    return -quotient if (num < 0) ^ (den < 0) else quotient


def _corr(phi: list[list[int]], residual: Sequence[int]) -> list[int]:
    return [
        sat_s24(sum(phi[row][col] * s24(residual[row]) for row in range(len(phi))) >> Q)
        for col in range(len(phi[0]))
    ]


def _matvec(phi: list[list[int]], vector: Sequence[int]) -> list[int]:
    return [sat_s24(sum(phi[row][col] * s24(vector[col]) for col in range(len(vector))) >> Q) for row in range(len(phi))]


def _residual(phi: list[list[int]], y: Sequence[int], x: Sequence[int]) -> list[int]:
    fitted = _matvec(phi, x)
    return [sat_s24(s24(y[row]) - fitted[row]) for row in range(len(phi))]


def _argmax_abs(values: Sequence[int], excluded: set[int]) -> int:
    return min((idx for idx in range(len(values)) if idx not in excluded), key=lambda idx: (-abs(s24(values[idx])), idx))


def _top(values: Sequence[int], count: int, excluded: set[int] | None = None) -> list[int]:
    excluded = excluded or set()
    ranked = [idx for idx in range(len(values)) if idx not in excluded]
    ranked.sort(key=lambda idx: (-abs(s24(values[idx])), idx))
    return ranked[:max(0, count)]


def _threshold(values: Sequence[int], count: int) -> list[int]:
    return sorted(_top(values, count))


@dataclass
class HardwareTrace:
    x: list[int]
    residual: list[int]
    support: list[int]
    history: list[tuple[list[int], list[int], list[int]]]


def _ldlt_solve(phi: list[list[int]], y: Sequence[int], support: Sequence[int]) -> tuple[list[int], list[int]]:
    """Solve one support set with the controller's fixed LDLT schedule.

    Matrix values are Q16.  The RTL adds one Q16 LSB to every diagonal before
    factorisation, stores L in Q16, stores reciprocal D in Q32, and truncates
    each multiply-accumulate at the corresponding fixed-point boundary.
    """

    ordered = list(dict.fromkeys(support))[:MAX_SUPPORT]
    n_size = len(phi[0])
    if not ordered:
        return [0] * n_size, [s24(value) for value in y]
    k_size = len(ordered)
    gram = [[
        sum(phi[row][ordered[i]] * phi[row][ordered[j]] for row in range(len(phi))) >> Q
        for j in range(k_size)
    ] for i in range(k_size)]
    rhs = [sum(phi[row][ordered[i]] * s24(y[row]) for row in range(len(phi))) >> Q for i in range(k_size)]
    for i in range(k_size):
        gram[i][i] += 1

    l = [[0] * k_size for _ in range(k_size)]
    inv_d = [0] * k_size  # Q32, matching ge_div_num=2**48 and >>>32 use
    d = [0] * k_size
    for i in range(k_size):
        for j in range(i):
            # The RTL wide multiplier keeps the Q32 product of L*L and then
            # multiplies by D before one registered >>>32 reduction.  Doing
            # two early Q16 truncations here changes the factor materially.
            acc = sum((l[i][p] * l[j][p] * d[p]) >> 32 for p in range(j))
            num = gram[i][j] - acc
            l[i][j] = _div_trunc(num * inv_d[j], 1 << 32)
        acc_diag = sum((l[i][p] * l[i][p] * d[p]) >> 32 for p in range(i))
        d[i] = gram[i][i] - acc_diag
        inv_d[i] = _div_trunc(1 << 48, d[i] if d[i] else 1)
        l[i][i] = 1 << Q

    # Forward solve L z = rhs, all values Q16.
    z = [0] * k_size
    for i in range(k_size):
        z[i] = rhs[i] - sum((l[i][j] * z[j]) >> Q for j in range(i))
    # z is Q16 and inv(D) is Q32; the controller's wide product is reduced
    # once at >>>32, leaving a Q16 diagonal solve result.
    w = [_div_trunc(z[i] * inv_d[i], 1 << 32) for i in range(k_size)]

    # Back solve L^T x = w, preserving controller's truncation points.
    coeff = [0] * k_size
    for i in range(k_size - 1, -1, -1):
        value = w[i] - sum((l[j][i] * coeff[j]) >> Q for j in range(i + 1, k_size))
        coeff[i] = sat_s24(value)
    x = [0] * n_size
    for idx, value in zip(ordered, coeff):
        x[idx] = value
    return x, _residual(phi, y, x)


def _omp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        support.append(_argmax_abs(_corr(phi, residual), set(support)))
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def cosamp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        candidates = _top(_corr(phi, residual), 2 * k)
        merged = sorted(set(support).union(candidates))[:MAX_SUPPORT]
        temp_x, _ = _ldlt_solve(phi, y, merged)
        support = _threshold(temp_x, k)
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _htp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        corr = _corr(phi, residual)
        z = [sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]
        support = _threshold(z, k)
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _sp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        candidates = _top(_corr(phi, residual), k)
        merged = sorted(set(support).union(candidates))[:MAX_SUPPORT]
        temp_x, _ = _ldlt_solve(phi, y, merged)
        support = _threshold(temp_x, k)
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _gomp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    iteration = 0
    while len(support) < k:
        count = min(2, k - len(support))
        support.extend(_top(_corr(phi, residual), count, set(support)))
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
        iteration += 1
    return HardwareTrace(x, residual, support, history)


def _gradient_update(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    """Hardware gradient path: Q16 correlation followed by ``>>>3`` update."""

    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        corr = _corr(phi, residual)
        x = [sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]
        support = _threshold(x, k)
        keep = set(support)
        x = [x[i] if i in keep else 0 for i in range(len(x))]
        residual = _residual(phi, y, x)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _mp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    norm = sum(phi[row][0] * phi[row][0] for row in range(len(phi))) >> Q
    for _ in range(k):
        corr = _corr(phi, residual)
        idx = _argmax_abs(corr, set())
        alpha = _div_trunc(corr[idx] << Q, norm or 1)
        x[idx] = sat_s24(x[idx] + alpha)
        if idx not in support:
            support.append(idx)
        residual = _residual(phi, y, x)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def run(algorithm: str, phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    # LS-based algorithms use the same hardware contract: Q16 normal
    # equations, +1 diagonal regularisation, LDLT, Q32 reciprocal-D and
    # signed-24 coefficient writes.  Non-LS paths retain their fixed-point
    # algorithmic update, since they do not traverse the LS service.
    runners = {
        "OMP": _omp,
        "CoSaMP": cosamp,
        "HTP": _htp,
        "SP": _sp,
        "gOMP": _gomp,
        "GOMP": _gomp,
    }
    if algorithm in runners:
        return runners[algorithm](phi, y, k)
    if algorithm in {"IHT", "GP"}:
        return _gradient_update(phi, y, k)
    if algorithm == "MP":
        return _mp(phi, y, k)
    raise ValueError(f"unsupported hardware algorithm: {algorithm}")
