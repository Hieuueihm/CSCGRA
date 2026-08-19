"""Run the phase-level abstract RTL model and write a reproducible trace manifest.

The manifest is an executable-specification checkpoint, not a replacement for
the frozen Verilog golden.  Every entry is regenerated from ``canonical_fixed``
and carries digests for the final state and for every phase payload.  A future
RTL phase can be compared with these digests without changing the golden to fit
hardware behaviour.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

try:
    from . import abstract_rtl as abstract
    from . import canonical_fixed as fixed
    from .generate_canonical_k_sweep import (
        ALGORITHM_NAMES,
        CASES,
        IMMUTABLE,
        parse_hex_func,
        parse_int_func,
    )
except ImportError:  # direct ``python models/golden/*.py`` execution
    import abstract_rtl as abstract
    import canonical_fixed as fixed
    from generate_canonical_k_sweep import (
        ALGORITHM_NAMES,
        CASES,
        IMMUTABLE,
        parse_hex_func,
        parse_int_func,
    )


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "models" / "golden" / "abstract_rtl_trace_manifest.json"


def _digest(values: Any) -> str:
    payload = json.dumps(values, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _case_inputs() -> list[tuple[int, int, int, list[list[int]], list[int]]]:
    frozen = IMMUTABLE.read_text(errors="ignore")
    y_func = parse_hex_func(frozen, "gold_y")
    seed = parse_int_func(frozen, "gold_case_seed").get(0, 17)
    scale_q = parse_hex_func(frozen, "gold_case_scale").get(0, 0x4000)
    cases = []
    for case_idx, (m_size, n_size, k_size) in enumerate(CASES):
        # The immutable dataset defines one deterministic y vector.  The
        # canonical sweep uses its first M entries for each configured case.
        phi = fixed.make_phi(m_size, n_size, seed, scale_q)
        y = [fixed.s24(y_func.get(idx, 0)) for idx in range(m_size)]
        cases.append((case_idx, m_size, n_size, phi, y))
    return cases


def build_manifest(include_values: bool = False) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    for case_idx, m_size, n_size, phi, y in _case_inputs():
        k_size = CASES[case_idx][2]
        for algorithm in ALGORITHM_NAMES:
            trace = abstract.run(algorithm, phi, y, k_size)
            expected = fixed.run_all(phi, y, k_size)[algorithm]
            exact_match = (
                trace.x == expected.x
                and trace.residual == expected.residual
                and trace.support == expected.support
            )
            if not exact_match:
                raise AssertionError(f"abstract trace mismatch: case={case_idx} alg={algorithm}")
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
                "algorithm": algorithm,
                "exact_match": True,
                "phase_count": len(trace.phases),
                "phase_counts": trace.phase_counts(),
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
                entry["phases"] = [
                    {
                        "iteration": phase.iteration,
                        "phase": phase.phase,
                        "support": phase.support,
                        "values": phase.values,
                    }
                    for phase in trace.phases
                ]
            entries.append(entry)
    return {
        "schema": "abstract-rtl-phase-trace-v1",
        "source": "models/golden/canonical_fixed.py",
        "model": "models/golden/abstract_rtl.py",
        "contract": {"data_width": 24, "fractional_bits": 16, "saturation": "signed-24"},
        "canonical_golden_unchanged": True,
        "all_final_states_exact_match": all(item["exact_match"] for item in entries),
        "cases": len(CASES),
        "algorithms": ALGORITHM_NAMES,
        "entries": entries,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="regenerate in memory and compare existing manifest")
    parser.add_argument("--dump-values", action="store_true", help="include complete phase payloads (large JSON)")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    generated = json.dumps(build_manifest(args.dump_values), indent=2, sort_keys=True) + "\n"
    if args.check:
        existing = output.read_text() if output.exists() else None
        if existing != generated:
            raise SystemExit(f"abstract RTL trace manifest mismatch: {output}")
        print(f"abstract RTL trace check PASS: {output}")
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generated, newline="\n")
    print(output)


if __name__ == "__main__":
    main()
