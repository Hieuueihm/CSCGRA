"""Bounded float grid with one calibration-selected wavelet per domain.

ECG uses db4 and camera uses Haar, selected from the preserved basis feasibility
calibration. Existing signals, block shapes, LFSR seeds and paired noise seeds
are unchanged. All full coefficients are sensed in a coefficient-domain encoder;
this is not a raw-signal Phi*Psi hardware experiment or a held-out study.
"""
from __future__ import annotations

import os
for _variable in ("OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "OMP_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[_variable] = "1"

import argparse
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.v4 import lfsr_application_tuning as common
from scripts.v4.lfsr_basis_feasibility import build_case
from scripts.v4.numeric_screen import digest, sanitized

PRESELECTED_BASES = {"ecg": "db4", "camera": "haar"}
SOURCE_CASES = ("ecg_window_3600", "ecg_window_7200", "camera_patch_192_240", "camera_patch_64_64")


def source_hashes():
    hashes = common.source_hashes()
    for path in (Path(__file__), ROOT / "scripts/v4/lfsr_basis_feasibility.py"):
        hashes[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def build_cases():
    cases = []
    for name in SOURCE_CASES:
        basis = PRESELECTED_BASES["ecg" if name.startswith("ecg") else "camera"]
        case = build_case(name, basis)
        # Same shared float/fixed-safe spectral policy as the original grid.
        original = float(np.linalg.norm(case["a"], 2) ** 2)
        magnitude = float(abs(case["a"][0, 0]))
        q = math.floor(magnitude * (1 << 16) + .5) / (1 << 16)
        case["spectral_sq_original"] = original
        case["spectral_sq"] = max(original, original * (q / magnitude) ** 2)
        cases.append(case)
    return cases


def case_record(case):
    return {"name": case["name"], "source_case": case["source_case"],
            "basis_name": case["basis_name"], "domain": common.domain(case),
            "track": case["track"], "seed": case["seed"],
            "M": case["a"].shape[0], "N": case["a"].shape[1],
            "operator_sha256": digest(case["a"]), "measurement_sha256": digest(case["y"]),
            "truth_sha256": digest(case["truth"]), "original_sha256": digest(case["original"]),
            "original": case["original"].tolist(), "truth": case["truth"].tolist(),
            "measurement": case["y"].tolist(), "source": case["source"],
            "mean": case["mean"], "scale": case["scale"],
            "spectral_sq_original": case["spectral_sq_original"], "spectral_sq": case["spectral_sq"],
            "measurement_snr_db": 30, "paired_noise": case["paired_noise"],
            "transform": case["transform"],
            "original_reconstruction_max_abs_error": case["original_reconstruction_max_abs_error"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/v4/lfsr_wavelet_float_tuning.json")
    parser.add_argument("--algorithms", nargs="+", choices=common.ALGORITHMS, default=list(common.ALGORITHMS))
    args = parser.parse_args()
    hashes = source_hashes()
    cases = build_cases()
    feasibility = ROOT / "reports/v4/lfsr_basis_feasibility.json"
    report = {"schema": "v4-lfsr-application-float-tuning-v1", "complete": False,
        "scope": "calibration_only_existing_4_windows_with_preselected_domain_wavelets",
        "fixed_point_run": False, "configuration": {**vars(args), "output": args.output.as_posix()},
        "source_sha256": hashes, "python": platform.python_version(),
        "packages": {n: importlib.metadata.version(n) for n in ("numpy", "scipy", "scikit-image", "PyWavelets")},
        "limits": {"M": 128, "N": 1024, "configured_K": 32,
                   "indexed_active_list_capacity": 96, "LS_support_capacity": 96},
        "actual_shape": {"M": 128, "N": 256},
        "thresholds": {"full_original_snr_min_db": 20, "preferred_margin_db": 20.5},
        "basis_selection": {"preselected_per_domain": PRESELECTED_BASES,
                            "evidence": feasibility.relative_to(ROOT).as_posix(),
                            "evidence_sha256": hashlib.sha256(feasibility.read_bytes()).hexdigest(),
                            "calibration_selected_not_independent_validation": True,
                            "source_windows_and_paired_noise_unchanged": True,
                            "basis_change_explicitly_changes_coefficient_domain_encoder": True},
        "selection_is_shared_per_domain_algorithm": True, "held_out_validation": False,
        "original_signals_sparsified": False, "raw_signal_PhiPsi_hardware_claim": False,
        "fixed_budget_completion_is_not_convergence": True, "hardware_performance_claim": False,
        "MP_GP_K_not_enforced_by_existing_semantics": True,
        "proximal_dense_nonzero_set_is_not_an_indexed_active_list": True,
        "blas_threads": 1, "cases": [case_record(case) for case in cases],
        "rows": [], "selected_policies": []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.output.write_text(json.dumps(sanitized(report), indent=2, allow_nan=False) + "\n", encoding="utf-8")
    save()
    finished = []
    for family in ("ecg", "camera"):
        for algorithm in args.algorithms:
            for index, recipe in enumerate(common.recipes(algorithm, family)):
                recipe_id = f"{family}_{algorithm}_{index:02d}"
                for case in (case for case in cases if common.domain(case) == family):
                    row = common.run_one(case, algorithm, recipe, recipe_id)
                    row["source_case"] = case["source_case"]
                    row["basis_name"] = case["basis_name"]
                    report["rows"].append(row)
                if index % 3 == 0:
                    save()
            finished.append((family, algorithm))
            report["selected_policies"] = common.selections(report, finished)
            save()
            selection = report["selected_policies"][-1]
            print(f"{family} {algorithm}: minSNR={selection['winner']['minimum_full_snr_db']:.3f} "
                  f"eligible20={selection['selected_for_fixed_check']} recipe={selection['winner']['recipe']}", flush=True)
    report["source_unchanged_during_run"] = source_hashes() == hashes
    report["complete"] = report["source_unchanged_during_run"]
    report["summary"] = {"rows": len(report["rows"]), "domain_algorithm_pairs": len(finished),
        "shared_policies_snr20_pass": sum(s["selected_for_fixed_check"] for s in report["selected_policies"]),
        "shared_policies_margin20_5_pass": sum(s["winner"]["all_margin20_5"] for s in report["selected_policies"]),
        "exception_rows": sum(r["exception"] is not None for r in report["rows"]),
        "capacity_ineligible_rows": sum(not r["capacity_eligible"] for r in report["rows"])}
    save()
    print(json.dumps(report["summary"]), flush=True)
    if not report["source_unchanged_during_run"]:
        raise RuntimeError("executed source changed during study")


if __name__ == "__main__":
    main()
