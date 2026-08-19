"""Blackbox bridge from the canonical Python model to the hardware model.

The bridge deliberately returns both results.  A consumer can feed one fixed
input to the canonical algorithm and to the hardware-aware implementation,
then compare the final state or inspect the hardware phase trace without
opening RTL internals.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Sequence

try:
    from . import canonical_fixed as canonical
    from . import hardware_abstract
    from . import hardware_fixed as hardware
except ImportError:  # direct ``python models/golden/*.py`` execution
    import canonical_fixed as canonical
    import hardware_abstract
    import hardware_fixed as hardware


@dataclass
class BlackboxResult:
    algorithm: str
    canonical: canonical.FixedTrace
    hardware: hardware.HardwareTrace
    hardware_phases: list[Any]

    @property
    def support_equal(self) -> bool:
        return self.canonical.support == self.hardware.support

    @property
    def x_equal(self) -> bool:
        return self.canonical.x == self.hardware.x

    @property
    def residual_equal(self) -> bool:
        return self.canonical.residual == self.hardware.residual

    def summary(self) -> dict[str, Any]:
        return {
            "algorithm": self.algorithm,
            "canonical_support": self.canonical.support,
            "hardware_support": self.hardware.support,
            "support_equal": self.support_equal,
            "x_equal": self.x_equal,
            "residual_equal": self.residual_equal,
            "hardware_phase_count": len(self.hardware_phases),
            "hardware_contract": {
                "solver": "LDLT",
                "fractional_bits": 16,
                "inverse_d_fractional_bits": 32,
                "data_width": 24,
                "ingress": "PE0-to-PE1-to-PE2-to-PE3",
            },
        }


def _quantize_inputs(phi: Sequence[Sequence[int]], y: Sequence[int]) -> tuple[list[list[int]], list[int]]:
    """Apply the same signed-24 boundary before either model sees the input."""

    return (
        [[canonical.s24(value) for value in row] for row in phi],
        [canonical.s24(value) for value in y],
    )


def run(algorithm: str, phi: Sequence[Sequence[int]], y: Sequence[int], k: int) -> BlackboxResult:
    """Run canonical and hardware models from the same fixed-point input.

    CoSaMP currently has a detailed controller phase trace.  Other algorithms
    still return their hardware fixed result and iteration history; detailed
    phase migration can be added without changing this bridge's contract.
    """

    phi_q, y_q = _quantize_inputs(phi, y)
    canonical_trace = canonical.run_all(phi_q, y_q, k)[algorithm]
    hardware_trace = hardware.run(algorithm, phi_q, y_q, k)
    if algorithm == "CoSaMP":
        phases = hardware_abstract.run(algorithm, phi_q, y_q, k).phases
    else:
        phases = [
            {
                "iteration": iteration,
                "phase": "ITERATION_RESULT",
                "support": support,
                "x": x,
                "residual": residual,
            }
            for iteration, (support, x, residual) in enumerate(hardware_trace.history)
        ]
    return BlackboxResult(algorithm, canonical_trace, hardware_trace, phases)
