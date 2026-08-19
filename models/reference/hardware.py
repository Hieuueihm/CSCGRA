"""Hardware Python reference derived from the canonical algorithms.

This is the second and only hardware reference source beside
``reference/canonical.py``. It models the implementation choices that are
part of the RTL contract (Q16 normal equations, diagonal regularisation, LDLT
factorisation, reciprocal-D scaling and signed-24-bit coefficient
quantisation). It never imports RTL or a RTL-generated golden.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Sequence

try:
    from models.golden import canonical_fixed as fixed
except ImportError:  # direct ``python models/reference/hardware.py`` execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "golden"))
    import canonical_fixed as fixed


Q = fixed.Q
DATA_W = fixed.DATA_W
MAX_SUPPORT = 16


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
        return [0] * n_size, [fixed.s24(value) for value in y]
    k_size = len(ordered)
    gram = [[
        sum(phi[row][ordered[i]] * phi[row][ordered[j]] for row in range(len(phi))) >> Q
        for j in range(k_size)
    ] for i in range(k_size)]
    rhs = [sum(phi[row][ordered[i]] * fixed.s24(y[row]) for row in range(len(phi))) >> Q for i in range(k_size)]
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
            l[i][j] = fixed._div_trunc(num * inv_d[j], 1 << 32)
        acc_diag = sum((l[i][p] * l[i][p] * d[p]) >> 32 for p in range(i))
        d[i] = gram[i][i] - acc_diag
        inv_d[i] = fixed._div_trunc(1 << 48, d[i] if d[i] else 1)
        l[i][i] = 1 << Q

    # Forward solve L z = rhs, all values Q16.
    z = [0] * k_size
    for i in range(k_size):
        z[i] = rhs[i] - sum((l[i][j] * z[j]) >> Q for j in range(i))
    # z is Q16 and inv(D) is Q32; the controller's wide product is reduced
    # once at >>>32, leaving a Q16 diagonal solve result.
    w = [fixed._div_trunc(z[i] * inv_d[i], 1 << 32) for i in range(k_size)]

    # Back solve L^T x = w, preserving controller's truncation points.
    coeff = [0] * k_size
    for i in range(k_size - 1, -1, -1):
        value = w[i] - sum((l[j][i] * coeff[j]) >> Q for j in range(i + 1, k_size))
        coeff[i] = fixed.sat_s24(value)
    x = [0] * n_size
    for idx, value in zip(ordered, coeff):
        x[idx] = value
    return x, fixed._residual(phi, y, x)


def _omp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        support.append(fixed._argmax_abs(fixed._corr(phi, residual), set(support)))
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def cosamp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0])
    residual = [fixed.s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        candidates = fixed._top(fixed._corr(phi, residual), 2 * k)
        merged = sorted(set(support).union(candidates))[:MAX_SUPPORT]
        temp_x, _ = _ldlt_solve(phi, y, merged)
        support = fixed._threshold(temp_x, k)
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _htp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        corr = fixed._corr(phi, residual)
        z = [fixed.sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]
        support = fixed._threshold(z, k)
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _sp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        candidates = fixed._top(fixed._corr(phi, residual), k)
        merged = sorted(set(support).union(candidates))[:MAX_SUPPORT]
        temp_x, _ = _ldlt_solve(phi, y, merged)
        support = fixed._threshold(temp_x, k)
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _gomp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    iteration = 0
    while len(support) < k:
        count = min(2, k - len(support))
        support.extend(fixed._top(fixed._corr(phi, residual), count, set(support)))
        x, residual = _ldlt_solve(phi, y, support)
        history.append((list(support), list(x), list(residual)))
        iteration += 1
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
    }
    if algorithm in runners:
        return runners[algorithm](phi, y, k)
    trace = fixed.run_all(phi, y, k)[algorithm]
    return HardwareTrace(trace.x, trace.residual, trace.support, trace.history)
