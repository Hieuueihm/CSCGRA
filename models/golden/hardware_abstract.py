"""Phase trace for the hardware-aware fixed-point RTL contract.

This module is intentionally separate from :mod:`abstract_rtl`.  The latter
freezes algorithmic canonical semantics; this trace freezes implementation
semantics that are valid architectural choices in the RTL: PE0 ingress,
four-row streaming, Q16 quantisation and the shared LDLT LS service.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
from typing import Any, Sequence

try:
    from . import canonical_fixed as fixed
    from . import hardware_fixed as hw
except ImportError:  # direct ``python models/golden/*.py`` execution
    import canonical_fixed as fixed
    import hardware_fixed as hw


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
class HardwareTrace:
    algorithm: str
    contract: str
    x: list[int]
    residual: list[int]
    support: list[int]
    phases: list[PhaseRecord]

    def digest(self) -> str:
        payload = json.dumps([asdict(phase) for phase in self.phases], sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _phase(phases: list[PhaseRecord], iteration: int, name: str, support: Sequence[int], **values: Any) -> None:
    phases.append(PhaseRecord(iteration, name, list(support), values))


def run_cosamp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    """Trace the current CoSaMP hardware schedule with an independent LDLT model."""

    x = [0] * len(phi[0])
    residual = [fixed.s24(value) for value in y]
    support: list[int] = []
    phases: list[PhaseRecord] = []
    for iteration in range(k):
        corr = fixed._corr(phi, residual)
        _phase(phases, iteration, "CORRELATION", support, correlation=corr,
               ingress="PE0", rows=4)
        candidates = fixed._top(corr, 2 * k)
        merged = sorted(set(support).union(candidates))[:hw.MAX_SUPPORT]
        _phase(phases, iteration, "SUPPORT_MERGE", merged,
               candidates=candidates, capacity=hw.MAX_SUPPORT)
        temp_x, _ = hw._ldlt_solve(phi, y, merged)
        _phase(phases, iteration, "LS_SOLVE_TEMP", merged, x=temp_x,
               solver="LDLT", diagonal_regularization=1,
               inv_d_fractional_bits=32)
        support = fixed._threshold(temp_x, k)
        _phase(phases, iteration, "SUPPORT_PRUNE", support, x=temp_x)
        x, residual = hw._ldlt_solve(phi, y, support)
        _phase(phases, iteration, "LS_SOLVE_FINAL", support, x=x,
               solver="LDLT", diagonal_regularization=1,
               inv_d_fractional_bits=32)
        _phase(phases, iteration, "RESIDUAL", support, residual=residual,
               ingress="PE0", rows=4)
    expected = hw.run("CoSaMP", phi, y, k)
    if x != expected.x or residual != expected.residual or support != expected.support:
        raise AssertionError("hardware abstract CoSaMP diverged from hardware_fixed")
    return HardwareTrace("CoSaMP", "hardware-ldlt-q16-s24", x, residual, support, phases)


def run(algorithm: str, phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    if algorithm != "CoSaMP":
        raise ValueError("hardware abstract trace currently covers CoSaMP LS migration")
    return run_cosamp(phi, y, k)
