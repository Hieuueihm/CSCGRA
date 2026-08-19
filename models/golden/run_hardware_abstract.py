"""Generate/check the hardware-aware CoSaMP RTL trace manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import asdict
from pathlib import Path
from typing import Any

try:
    from . import canonical_fixed as fixed
    from . import hardware_abstract as abstract
    from .generate_canonical_k_sweep import CASES, IMMUTABLE, parse_hex_func, parse_int_func
except ImportError:  # direct ``python models/golden/*.py`` execution
    import canonical_fixed as fixed
    import hardware_abstract as abstract
    from generate_canonical_k_sweep import CASES, IMMUTABLE, parse_hex_func, parse_int_func


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "models" / "golden" / "abstract_rtl_hardware_trace_manifest.json"


def _digest(values: Any) -> str:
    payload = json.dumps(values, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _case_inputs() -> list[tuple[int, int, int, list[list[int]], list[int]]]:
    frozen = IMMUTABLE.read_text(errors="ignore")
    y_func = parse_hex_func(frozen, "gold_y")
    seed = parse_int_func(frozen, "gold_case_seed").get(0, 17)
    scale_q = parse_hex_func(frozen, "gold_case_scale").get(0, 0x4000)
    return [
        (case_idx, m_size, n_size,
         fixed.make_phi(m_size, n_size, seed, scale_q),
         [fixed.s24(y_func.get(idx, 0)) for idx in range(m_size)])
        for case_idx, (m_size, n_size, _k_size) in enumerate(CASES)
    ]


def build_manifest(include_values: bool = False) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    for case_idx, m_size, n_size, phi, y in _case_inputs():
        k_size = CASES[case_idx][2]
        trace = abstract.run("CoSaMP", phi, y, k_size)
        phase_records = [
            {
                "iteration": phase.iteration,
                "phase": phase.phase,
                "support_digest": _digest(phase.support),
                "values_digest": _digest(phase.values),
                "digest": phase.digest(),
            }
            for phase in trace.phases
        ]
        entry: dict[str, Any] = {
            "case": case_idx,
            "shape": {"M": m_size, "N": n_size, "K": k_size},
            "algorithm": "CoSaMP",
            "contract": trace.contract,
            "rtl_capacity_supported": k_size <= 8,
            "phase_count": len(trace.phases),
            "phase_records": phase_records,
            "trace_digest": trace.digest(),
            "final_x_digest": _digest(trace.x),
            "final_residual_digest": _digest(trace.residual),
            "final_support_digest": _digest(trace.support),
        }
        if include_values:
            entry["final_x"] = trace.x
            entry["final_residual"] = trace.residual
            entry["final_support"] = trace.support
            entry["phases"] = [asdict(phase) for phase in trace.phases]
        entries.append(entry)
    return {
        "schema": "abstract-rtl-hardware-phase-trace-v1",
        "source": "models/golden/hardware_fixed.py",
        "model": "models/golden/hardware_abstract.py",
        "contract": {
            "data_width": 24,
            "fractional_bits": 16,
            "saturation": "signed-24",
            "solver": "LDLT",
            "diagonal_regularization": 1,
            "inverse_d_fractional_bits": 32,
            "ingress": "PE0-to-PE1-to-PE2-to-PE3",
            "active_ls_requests": 1,
        },
        "canonical_golden_unchanged": True,
        "entries": entries,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dump-values", action="store_true")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    generated = json.dumps(build_manifest(args.dump_values), indent=2, sort_keys=True) + "\n"
    if args.check:
        existing = output.read_text() if output.exists() else None
        if existing != generated:
            raise SystemExit(f"hardware trace manifest mismatch: {output}")
        print(f"hardware trace check PASS: {output}")
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generated, newline="\n")
    print(output)


if __name__ == "__main__":
    main()
