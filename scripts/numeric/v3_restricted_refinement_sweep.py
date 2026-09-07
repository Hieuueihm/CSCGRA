#!/usr/bin/env python3
"""Fixed-point correctness sweep for strict/balanced/fast refinement."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, paper
from scripts.golden.generate_v3_phase_golden import (
    macro_names, suite, valid_macro_grammar,
)


NUMERIC_PROFILE = hardware.NumericProfile()
POLICIES = {
    "strict_paper": hardware.RefinementPolicy(profile="strict_paper"),
    "balanced_variant": hardware.RefinementPolicy(profile="balanced_variant"),
    "fast_variant": hardware.RefinementPolicy(profile="fast_variant"),
}
FIXED_ABSOLUTE_SNR_MIN_DB = 40.0
TRUTH_SNR_GAP_MAX_DB = 0.50
TRUTH_MSE_RATIO_MAX = 1.10


def snr_db(reference: np.ndarray, estimate: np.ndarray) -> float:
    noise = float(np.linalg.norm(reference - estimate))
    signal = float(np.linalg.norm(reference))
    return 300.0 if noise == 0.0 else float(
        20.0 * np.log10(max(signal, 1.0e-30) / noise))


def round_shift(value: int, shift: int) -> int:
    if shift == 0:
        return value
    rounded = (abs(value) + (1 << (shift - 1))) >> shift
    return -rounded if value < 0 else rounded


def saturate(value: int, width: int) -> int:
    low = -(1 << (width - 1))
    high = (1 << (width - 1)) - 1
    return max(low, min(high, int(value)))


def quantize_data(value: float) -> int:
    scaled = int(np.floor(abs(value) * (1 << NUMERIC_PROFILE.data_f) + 0.5))
    return saturate(-scaled if value < 0.0 else scaled, NUMERIC_PROFILE.data_w)


def independent_residual(case: dict, x: list[int]) -> list[int]:
    phi_q = [[quantize_data(float(value)) for value in row]
             for row in np.asarray(case["phi"])]
    y_q = [quantize_data(float(value)) for value in np.asarray(case["y"])]
    residual = []
    for row, measurement in zip(phi_q, y_q):
        raw = sum(int(coefficient) * int(value)
                  for coefficient, value in zip(row, x))
        fitted = saturate(
            round_shift(raw, NUMERIC_PROFILE.data_f),
            NUMERIC_PROFILE.data_w,
        )
        residual.append(saturate(
            int(measurement) - fitted, NUMERIC_PROFILE.data_w))
    return residual


def run_case(case: dict, selected: hardware.RefinementPolicy) -> dict:
    records = {}
    for algorithm in paper.ALGORITHMS:
        reference = paper.run(algorithm, case["phi"], case["y"], case["policy"])
        fixed = hardware.run(
            algorithm, case["phi"], case["y"], case["policy"],
            NUMERIC_PROFILE, selected)
        events = asdict(fixed.events)
        active_events = {name: count for name, count in events.items() if count}
        rollback = sum(phase.name == "REFINEMENT_ROLLBACK" for phase in fixed.phases)
        steps = sum(phase.name == "REFINEMENT_STEP" for phase in fixed.phases)
        certificates = sum(
            phase.name == "REFINEMENT_CERTIFICATE" for phase in fixed.phases)
        common = len(set(reference.support) & set(fixed.support))
        denominator = max(1, min(len(reference.support), len(fixed.support)))
        overlap = common / denominator
        paper_x = np.asarray(reference.x, dtype=np.float64)
        fixed_x = np.asarray(fixed.x, dtype=np.float64) / (
            1 << NUMERIC_PROFILE.data_f)
        coefficient_error = float(
            np.linalg.norm(fixed_x - paper_x)
            / max(float(np.linalg.norm(paper_x)), 1.0e-30))
        paper_truth_snr = snr_db(np.asarray(case["x_true"]), paper_x)
        fixed_truth_snr = snr_db(np.asarray(case["x_true"]), fixed_x)
        truth_snr_gap = paper_truth_snr - fixed_truth_snr
        paper_truth_mse = float(np.mean((np.asarray(case["x_true"]) - paper_x) ** 2))
        fixed_truth_mse = float(np.mean((np.asarray(case["x_true"]) - fixed_x) ** 2))
        truth_mse_ratio = (
            fixed_truth_mse / paper_truth_mse if paper_truth_mse > 0.0
            else (1.0 if fixed_truth_mse == 0.0 else float("inf"))
        )
        residual_exact = fixed.residual == independent_residual(case, fixed.x)
        grammar_pass = valid_macro_grammar(
            algorithm, macro_names("hardware", fixed))
        quality_pass = (
            fixed_truth_snr >= FIXED_ABSOLUTE_SNR_MIN_DB
            or (truth_snr_gap <= TRUTH_SNR_GAP_MAX_DB
                and truth_mse_ratio <= TRUTH_MSE_RATIO_MAX)
        )
        passed = (
            not active_events and rollback == 0 and grammar_pass
            and residual_exact and quality_pass
        )
        records[algorithm] = {
            "pass": passed,
            "quality_pass": quality_pass,
            "support_exact": reference.support == fixed.support,
            "support_overlap": overlap,
            "coefficient_relative_error": coefficient_error,
            "paper_truth_snr_db": paper_truth_snr,
            "fixed_truth_snr_db": fixed_truth_snr,
            "truth_snr_gap_db": truth_snr_gap,
            "paper_truth_mse": paper_truth_mse,
            "fixed_truth_mse": fixed_truth_mse,
            "truth_mse_ratio_fixed_over_paper": truth_mse_ratio,
            "residual_bit_exact": residual_exact,
            "macro_grammar_pass": grammar_pass,
            "refinement_steps": steps,
            "certificate_count": certificates,
            "rollback_count": rollback,
            "events": events,
            "paper_stop_reason": reference.stop_reason,
            "fixed_stop_reason": fixed.stop_reason,
        }
    return {
        "case": case["name"],
        "geometry": {
            "m": case["m"], "n": case["n"], "k": case["k"],
            "seed": case["seed"],
            "outer_iteration_limit": case["policy"].max_iterations,
        },
        "algorithms": records,
        "pass": all(item["pass"] for item in records.values()),
    }


def markdown(result: dict) -> str:
    lines = [
        "# V3 fixed-point correctness sweep",
        "",
        "This is the second correctness gate, after the independent floating-point",
        "oracle. It covers D18F14/S27F19/A62 with strict, balanced and fast",
        "restricted-refinement profiles. RTL and measured cycles are outside this gate.",
        "",
        f'Overall: **{"PASS" if result["pass"] else "FAIL"}**',
        "",
        "| Profile | Result | Runs | Exact support | Min overlap | Max coeff. error | Min fixed SNR | Max MSE ratio | Residual exact | Faults/rollback |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for profile in result["profiles"]:
        rows = [algorithm for case in profile["cases"]
                for algorithm in case["algorithms"].values()]
        faults = sum(
            sum(row["events"].values()) + row["rollback_count"] for row in rows)
        lines.append(
            f'| `{profile["name"]}` | {"PASS" if profile["pass"] else "FAIL"} | '
            f'{sum(row["pass"] for row in rows)}/{len(rows)} | '
            f'{sum(row["support_exact"] for row in rows)}/{len(rows)} | '
            f'{min(row["support_overlap"] for row in rows):.3f} | '
            f'{max(row["coefficient_relative_error"] for row in rows):.3e} | '
            f'{min(row["fixed_truth_snr_db"] for row in rows):.3f} dB | '
            f'{max(row["truth_mse_ratio_fixed_over_paper"] for row in rows):.3e} | '
            f'{sum(row["residual_bit_exact"] for row in rows)}/{len(rows)} | '
            f'{faults} |')
    lines += [
        "",
        f'Total: **{result["passed"]}/{result["total"]}** fixed-point cases.',
        "",
        "Pass thresholds:",
        f'- Absolute fixed-point truth SNR: `>= {FIXED_ABSOLUTE_SNR_MIN_DB:.1f} dB`; or',
        f'- Truth SNR loss: `<= {TRUTH_SNR_GAP_MAX_DB:.2f} dB` and MSE ratio: `<= {TRUTH_MSE_RATIO_MAX:.2f}`.',
        "- Final residual must match an independent D18 recomputation bit-for-bit.",
        "- Numeric fault counters and refinement rollbacks must be zero.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("reports/v3/fixed_correctness_sweep"))
    args = parser.parse_args()
    cases = suite("correctness")
    result = {
        "schema": "cscgra-v3-fixed-correctness-sweep-v2",
        "numeric_profile": asdict(NUMERIC_PROFILE),
        "thresholds": {
            "fixed_absolute_snr_min_db": FIXED_ABSOLUTE_SNR_MIN_DB,
            "truth_snr_gap_max_db": TRUTH_SNR_GAP_MAX_DB,
            "truth_mse_ratio_max": TRUTH_MSE_RATIO_MAX,
        },
        "profiles": [],
    }
    for name, selected in POLICIES.items():
        entry = {
            "name": name,
            "policy": asdict(selected),
            "cases": [run_case(case, selected) for case in cases],
        }
        entry["pass"] = all(case["pass"] for case in entry["cases"])
        result["profiles"].append(entry)
        passed = sum(
            algorithm["pass"] for case in entry["cases"]
            for algorithm in case["algorithms"].values())
        total = sum(len(case["algorithms"]) for case in entry["cases"])
        print(name, "PASS" if entry["pass"] else "FAIL", f"{passed}/{total}")
    rows = [algorithm for profile in result["profiles"]
            for case in profile["cases"]
            for algorithm in case["algorithms"].values()]
    result["passed"] = sum(row["pass"] for row in rows)
    result["total"] = len(rows)
    result["pass"] = all(profile["pass"] for profile in result["profiles"])
    out = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    report = markdown(result)
    (out / "summary.md").write_text(report, encoding="utf-8")
    print(report)
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
