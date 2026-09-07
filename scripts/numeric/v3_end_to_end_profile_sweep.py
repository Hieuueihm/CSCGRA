#!/usr/bin/env python3
"""Compare candidate fixed-point profiles across all v3 algorithms/cases."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import json
import math
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, paper
from scripts.golden.generate_v3_phase_golden import (
    macro_names, make_case, suite, valid_macro_grammar,
)


PROFILES = {
    "D16F12_S26F18_A60": hardware.NumericProfile(16, 12, 26, 18, 60),
    "D17F13_S26F18_A60": hardware.NumericProfile(17, 13, 26, 18, 60),
    "D18F14_S26F18_A60": hardware.NumericProfile(18, 14, 26, 18, 60),
    "D18F14_S27F19_A62": hardware.NumericProfile(18, 14, 27, 19, 62),
    "D16F12_S28F20_A64": hardware.NumericProfile(16, 12, 28, 20, 64),
    "D17F13_S28F20_A64": hardware.NumericProfile(17, 13, 28, 20, 64),
    "D18F14_S28F20_A64": hardware.NumericProfile(18, 14, 28, 20, 64),
}


def norm(values: list[int] | list[float], scale: float = 1.0) -> float:
    return float(np.linalg.norm(np.asarray(values, dtype=np.float64) / scale))


def reconstruction_metrics(reference: np.ndarray, estimate: np.ndarray) -> tuple[float, float]:
    error = np.asarray(reference, dtype=np.float64) - np.asarray(
        estimate, dtype=np.float64)
    error_energy = float(np.sum(error * error))
    mse = float(np.mean(error * error))
    if error_energy == 0.0:
        return mse, math.inf
    signal_energy = float(np.sum(np.asarray(reference, dtype=np.float64) ** 2))
    return mse, 10.0 * math.log10(signal_energy / error_energy)


def run_case(case: dict, name: str, profile: hardware.NumericProfile) -> dict:
    algorithms = {}
    all_pass = True
    for algorithm in paper.ALGORITHMS:
        reference = paper.run(algorithm, case["phi"], case["y"], case["policy"])
        fixed = hardware.run(algorithm, case["phi"], case["y"], case["policy"], profile)
        events = asdict(fixed.events)
        active_events = {key: value for key, value in events.items() if value}
        support_match = reference.support == fixed.support
        grammar_pass = valid_macro_grammar(algorithm, macro_names("hardware", fixed))
        ls_abort = sum(phase.name == "REFINEMENT_ROLLBACK" for phase in fixed.phases)
        paper_x = np.asarray(reference.x, dtype=np.float64)
        fixed_x = np.asarray(fixed.x, dtype=np.float64) / (1 << profile.data_f)
        coefficient_error = float(
            np.linalg.norm(fixed_x - paper_x) / max(np.linalg.norm(paper_x), 1e-30)
        )
        residual_ratio = norm(fixed.residual, 1 << profile.data_f) / max(norm(case["y"]), 1e-30)
        true_x = np.asarray(case["x_true"], dtype=np.float64)
        paper_mse, paper_snr = reconstruction_metrics(true_x, paper_x)
        fixed_mse, fixed_snr = reconstruction_metrics(true_x, fixed_x)
        mse_ratio = (fixed_mse / paper_mse if paper_mse > 0.0
                     else (1.0 if fixed_mse == 0.0 else math.inf))
        snr_gap = paper_snr - fixed_snr
        quality_match = (
            support_match
            or fixed_snr >= 40.0
            or (snr_gap <= 0.5 and mse_ratio <= 1.10)
        )

        gp_descent_violations = 0
        if algorithm == "GP":
            old_norm_sq = sum(int(value) * int(value)
                              for value in hardware.quantize_inputs(
                                  case["phi"], case["y"],
                                  hardware.Arithmetic(profile, hardware.Events()))[1])
            for phase in fixed.phases:
                if phase.name != "RESIDUAL":
                    continue
                new_norm_sq = sum(int(value) * int(value)
                                  for value in phase.vectors["residual"])
                gp_descent_violations += int(new_norm_sq > old_norm_sq)
                old_norm_sq = new_norm_sq

        passed = (
            quality_match and grammar_pass and not active_events
            and ls_abort == 0 and gp_descent_violations == 0
        )
        all_pass &= passed
        algorithms[algorithm] = {
            "pass": passed,
            "support_match": support_match,
            "quality_match": quality_match,
            "paper_support_size": len(reference.support),
            "hardware_support_size": len(fixed.support),
            "coefficient_relative_error": coefficient_error,
            "residual_ratio": residual_ratio,
            "paper_truth_mse": paper_mse,
            "fixed_truth_mse": fixed_mse,
            "truth_mse_ratio_fixed_over_paper": mse_ratio,
            "paper_truth_snr_db": paper_snr,
            "fixed_truth_snr_db": fixed_snr,
            "truth_snr_gap_db": snr_gap,
            "paper_stop_reason": reference.stop_reason,
            "hardware_stop_reason": fixed.stop_reason,
            "hardware_phases": len(fixed.phases),
            "macro_grammar_pass": grammar_pass,
            "ls_abort": ls_abort,
            "gp_descent_violations": gp_descent_violations,
            "events": events,
        }
    return {"case": case["name"], "pass": all_pass, "algorithms": algorithms}


def markdown(result: dict) -> str:
    lines = [
        "# v3 end-to-end fixed-point profile sweep", "",
        "A profile passes only when all frozen cases and all eight algorithms",
        "preserve paper support or equivalent reconstruction quality, obey paper",
        "macro-phase grammar, produce no numeric fault/LS abort, and GP residual",
        "never increases after a committed update. Alternative support is accepted",
        "only with <=0.5 dB SNR loss and <=1.10x MSE, or >=40 dB absolute SNR.",
        "",
        "| Profile | Result | Passed algorithms | Max coefficient error | Max residual ratio | GP ascent |",
        "| --- | --- | ---: | ---: | ---: | ---: |",
    ]
    for entry in result["profiles"]:
        records = [algorithm for case in entry["cases"]
                   for algorithm in case["algorithms"].values()]
        lines.append(
            f'| {entry["name"]} | {"PASS" if entry["pass"] else "FAIL"} | '
            f'{sum(record["pass"] for record in records)}/{len(records)} | '
            f'{max(record["coefficient_relative_error"] for record in records):.3e} | '
            f'{max(record["residual_ratio"] for record in records):.3e} | '
            f'{sum(record["gp_descent_violations"] for record in records)} |'
        )
    lines += [
        "",
        f'Cases: {result["case_count"]}, including smoke/scale and optional stress seeds.',
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profiles", nargs="*", choices=tuple(PROFILES),
                        default=list(PROFILES))
    parser.add_argument("--out-dir", type=Path,
                        default=Path("reports/v3/end_to_end_profile_sweep"))
    parser.add_argument("--random-seeds", type=int, default=0,
                        help="append M=32/N=64/K=8 Bernoulli stress cases")
    args = parser.parse_args()
    cases = suite("smoke") + suite("scale")
    cases += [make_case(f"stress_m32_n64_k8_seed{1000 + seed}", 32, 64, 8,
                        1000 + seed) for seed in range(args.random_seeds)]
    result = {"schema": 1, "case_count": len(cases), "profiles": []}
    for name in args.profiles:
        entry = {
            "name": name,
            "numeric_profile": asdict(PROFILES[name]),
            "cases": [run_case(case, name, PROFILES[name]) for case in cases],
        }
        entry["pass"] = all(case["pass"] for case in entry["cases"])
        result["profiles"].append(entry)
        passed = sum(algorithm["pass"] for case in entry["cases"]
                     for algorithm in case["algorithms"].values())
        total = len(cases) * len(paper.ALGORITHMS)
        print(name, "PASS" if entry["pass"] else "FAIL", f"{passed}/{total}")
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "results.json").write_text(json.dumps(result, indent=2) + "\n",
                                           encoding="utf-8")
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    if not all(entry["pass"] for entry in result["profiles"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
