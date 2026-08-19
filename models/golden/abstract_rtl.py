"""Phase-level abstract RTL model for the fixed canonical algorithms.

The model is intentionally independent from RTL source files.  It exposes the
same phase boundaries that a hardware controller must implement and asserts
that its final state is byte-for-byte equal to ``canonical_fixed.run_all``.
It is therefore the intermediate executable specification between the frozen
fixed golden and the real RTL.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
from typing import Any, Sequence

try:
    from . import canonical_fixed as fixed
except ImportError:  # direct ``python models/golden/*.py`` execution
    import canonical_fixed as fixed


@dataclass
class PhaseRecord:
    iteration: int
    phase: str
    support: list[int]
    values: dict[str, Any]

    def digest(self) -> str:
        payload = json.dumps(asdict(self), sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass
class AbstractTrace:
    algorithm: str
    x: list[int]
    residual: list[int]
    support: list[int]
    phases: list[PhaseRecord]

    def phase_counts(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for phase in self.phases:
            counts[phase.phase] = counts.get(phase.phase, 0) + 1
        return counts

    def digest(self) -> str:
        payload = json.dumps(
            [asdict(phase) for phase in self.phases],
            sort_keys=True,
            separators=(",", ":"),
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _phase(phases: list[PhaseRecord], iteration: int, name: str, support: Sequence[int], **values: Any) -> None:
    phases.append(PhaseRecord(iteration, name, list(support), values))


def _residual(phi: list[list[int]], y: Sequence[int], x: Sequence[int]) -> list[int]:
    fitted = fixed._matvec(phi, x)
    return [fixed.sat_s24(fixed.s24(y[row]) - fitted[row]) for row in range(len(phi))]


def _finish(name: str, phi: list[list[int]], y: Sequence[int], k: int, x: list[int], residual: list[int], support: list[int], phases: list[PhaseRecord]) -> AbstractTrace:
    expected = fixed.run_all(phi, y, k)[name]
    if x != expected.x or residual != expected.residual or support != expected.support:
        raise AssertionError(f"abstract {name} diverged from canonical_fixed")
    return AbstractTrace(name, x, residual, support, phases)


def _run_omp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        idx = fixed._argmax_abs(corr, set(support)); support.append(idx); _phase(phases, iteration, "SUPPORT_SELECT", support, selected=idx)
        x, residual = fixed._least_squares(phi, y, support); _phase(phases, iteration, "LS_SOLVE", support, x=x)
        _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("OMP", phi, y, k, x, residual, support, phases)


def _run_cosamp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        candidates = fixed._top(corr, 2 * k); merged = sorted(set(support).union(candidates)); _phase(phases, iteration, "SUPPORT_MERGE", merged, candidates=candidates)
        temp_x, _ = fixed._least_squares(phi, y, merged); support = fixed._threshold(temp_x, k); _phase(phases, iteration, "SUPPORT_PRUNE", support, x=temp_x)
        x, residual = fixed._least_squares(phi, y, support); _phase(phases, iteration, "LS_SOLVE", support, x=x)
        _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("CoSaMP", phi, y, k, x, residual, support, phases)


def _run_iht(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        z = [fixed.sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]; support = fixed._threshold(z, k); _phase(phases, iteration, "SUPPORT_PRUNE", support, candidate_x=z)
        keep = set(support); x = [z[i] if i in keep else 0 for i in range(len(z))]; _phase(phases, iteration, "UPDATE_X", support, x=x)
        residual = _residual(phi, y, x); _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("IHT", phi, y, k, x, residual, support, phases)


def _run_htp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        z = [fixed.sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]; support = fixed._threshold(z, k); _phase(phases, iteration, "SUPPORT_PRUNE", support, candidate_x=z)
        x, residual = fixed._least_squares(phi, y, support); _phase(phases, iteration, "LS_SOLVE", support, x=x)
        _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("HTP", phi, y, k, x, residual, support, phases)


def _run_sp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        candidates = fixed._top(corr, k); merged = sorted(set(support).union(candidates)); _phase(phases, iteration, "SUPPORT_MERGE", merged, candidates=candidates)
        temp_x, _ = fixed._least_squares(phi, y, merged); support = fixed._threshold(temp_x, k); _phase(phases, iteration, "SUPPORT_PRUNE", support, x=temp_x)
        x, residual = fixed._least_squares(phi, y, support); _phase(phases, iteration, "LS_SOLVE", support, x=x)
        _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("SP", phi, y, k, x, residual, support, phases)


def _run_gp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        idx = fixed._argmax_abs(corr, set(support)); support.append(idx); _phase(phases, iteration, "SUPPORT_SELECT", support, selected=idx)
        direction = [corr[i] if i in support else 0 for i in range(len(x))]; projected = fixed._matvec(phi, direction); _phase(phases, iteration, "PROJECT", support, direction=direction, projected=projected)
        numerator = sum(fixed.s24(residual[row]) * fixed.s24(projected[row]) for row in range(len(phi)))
        denominator = sum(fixed.s24(projected[row]) * fixed.s24(projected[row]) for row in range(len(phi)))
        alpha = fixed._div_trunc(numerator << fixed.Q, denominator); _phase(phases, iteration, "LINE_SEARCH", support, numerator=numerator, denominator=denominator, alpha=alpha)
        x = [fixed.sat_s24(x[i] + ((direction[i] * alpha) >> fixed.Q)) for i in range(len(x))]; _phase(phases, iteration, "UPDATE_X", support, x=x)
        residual = _residual(phi, y, x); _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("GP", phi, y, k, x, residual, support, phases)


def _run_gomp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []; iteration = 0
    while len(support) < k:
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        count = min(2, k - len(support)); selected = fixed._top(corr, count, set(support)); support.extend(selected); _phase(phases, iteration, "SUPPORT_SELECT", support, selected=selected)
        x, residual = fixed._least_squares(phi, y, support); _phase(phases, iteration, "LS_SOLVE", support, x=x); _phase(phases, iteration, "RESIDUAL", support, residual=residual); iteration += 1
    return _finish("GOMP", phi, y, k, x, residual, support, phases)


def _run_mp(phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    x = [0] * len(phi[0]); residual = [fixed.s24(v) for v in y]; support: list[int] = []; phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual); _phase(phases, iteration, "CORRELATION", support, correlation=corr)
        idx = fixed._argmax_abs(corr, set()); norm = sum(phi[row][idx] * phi[row][idx] for row in range(len(phi))) >> fixed.Q; alpha = fixed._div_trunc(corr[idx] << fixed.Q, norm or 1); support = support if idx in support else support + [idx]; _phase(phases, iteration, "UPDATE_X", support, selected=idx, alpha=alpha)
        x[idx] = fixed.sat_s24(x[idx] + alpha); residual = _residual(phi, y, x); _phase(phases, iteration, "RESIDUAL", support, residual=residual)
    return _finish("MP", phi, y, k, x, residual, support, phases)


RUNNERS = {"OMP": _run_omp, "CoSaMP": _run_cosamp, "IHT": _run_iht, "HTP": _run_htp, "SP": _run_sp, "GP": _run_gp, "GOMP": _run_gomp, "MP": _run_mp}


def run(algorithm: str, phi: list[list[int]], y: Sequence[int], k: int) -> AbstractTrace:
    return RUNNERS[algorithm](phi, y, k)
