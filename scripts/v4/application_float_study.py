"""Bounded float-only application policy study for the v4 calibration screen.

The study reuses the four application windows and generated Threefry
measurements from generated_numeric_study.outer_cases. It runs no fixed point
profiles: the purpose is to compare iteration, sparsity, regularization and
budget policies before any numeric-width decision. Results are calibration
candidates only; no held-out quality claim is emitted.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4 import proximal, recovery
from models.v4.quality import metrics
from scripts.v4.generated_numeric_study import outer_cases
from scripts.v4.numeric_screen import digest


SEEDS = (23, 47, 101)
GENERATOR = "threefry"
RECOVERY_ALGORITHMS = recovery.ALGORITHMS
PROXIMAL_ALGORITHMS = proximal.ALGORITHMS
RECOVERY_POLICIES = {
    # (sparsity K, iteration budget, report label)
    "OMP": ((16, 16, "K16"), (32, 32, "K32")),
    "GOMP": ((16, 16, "K16"), (32, 32, "K32")),
    "MP": ((16, 24, "budget24"), (16, 64, "budget64")),
    "GP": ((16, 24, "budget24"), (16, 64, "budget64")),
    "CoSaMP": (
        (16, 24, "K16_budget24"), (16, 64, "K16_budget64"),
        (32, 24, "K32_budget24"), (32, 64, "K32_budget64"),
    ),
    "SP": (
        (16, 24, "K16_budget24"), (16, 64, "K16_budget64"),
        (32, 24, "K32_budget24"), (32, 64, "K32_budget64"),
    ),
    "IHT": (
        (16, 24, "K16_budget24"), (16, 64, "K16_budget64"),
        (32, 24, "K32_budget24"), (32, 64, "K32_budget64"),
    ),
    "HTP": (
        (16, 24, "K16_budget24"), (16, 64, "K16_budget64"),
        (32, 24, "K32_budget24"), (32, 64, "K32_budget64"),
    ),
}
PROXIMAL_BUDGETS = (96, 192)
REGULARIZATIONS = (0.001, 0.01)


def _source_hashes() -> dict[str, str]:
    files = [Path(__file__), ROOT / "scripts/v4/generated_numeric_study.py",
             ROOT / "scripts/v4/numeric_screen.py"]
    files.extend(sorted((ROOT / "models/v4").glob("*.py")))
    return {
        path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in files
    }


def _dataset_kind(case: dict) -> str:
    if case["name"].startswith("ecg_"):
        return "ecg"
    if case["name"].startswith("camera_"):
        return "camera"
    return str(case.get("source", {}).get("kind", "unknown"))


def _spectral_sq(case: dict) -> float:
    if "_spectral_sq" not in case:
        case["_spectral_sq"] = float(
            np.linalg.norm(np.asarray(case["a"], dtype=float), 2) ** 2
        )
    return float(case["_spectral_sq"])


def _quality_row(case: dict, result, algorithm: str, policy: dict, budget_label: str,
                 *, regularization: float | None = None) -> dict:
    restored = np.asarray(case["restore"](result.x), dtype=float).reshape(-1)
    original = np.asarray(case["original"], dtype=float).reshape(-1)
    mean = float(case.get("mean", 0.0))
    full = metrics(original, restored)
    centered = metrics(original - mean, restored - mean)
    camera_psnr = None
    if _dataset_kind(case) == "camera":
        camera_psnr = math.inf if full["mse"] == 0.0 else -10.0 * math.log10(full["mse"])
    row = {
        "case": case["name"],
        "dataset_kind": _dataset_kind(case),
        "track": case["track"],
        "algorithm": algorithm,
        "budget_label": budget_label,
        "policy": policy,
        "status": result.status,
        "events": dict(result.events),
        "support_size": len(result.support),
        "support": [int(index) for index in result.support],
        "trace_length": len(result.trace),
        "truth_sha256": digest(case["truth"]),
        "operator_sha256": digest(case["a"]),
        "measurement_sha256": digest(case["y"]),
        "full": full,
        "centered": centered,
        "full_snr_db": full["snr_db"],
        "full_nmse": full["nmse"],
        "centered_snr_db": centered["snr_db"],
        "centered_nmse": centered["nmse"],
        "regularization": regularization,
        "camera_psnr_db": camera_psnr,
        "calibration_candidate_only": True,
        "heldout_quality_claim": False,
    }
    return row


def _run_recovery(case: dict, algorithm: str, sparsity: int, budget: int,
                  budget_label: str) -> dict:
    spectral = _spectral_sq(case)
    policy = recovery.Policy(
        sparsity=int(sparsity),
        max_iterations=int(budget),
        step_size=0.9 / spectral,
        residual_atol=1e-6,
    )
    started = time.perf_counter()
    result = recovery.run(algorithm, case["a"], case["y"], policy, profile=None)
    row = _quality_row(
        case, result, algorithm, asdict(policy),
        budget_label,
    )
    row["elapsed_seconds"] = time.perf_counter() - started
    row["solver"] = "float"
    return row


def _run_proximal(case: dict, algorithm: str, regularization: float, budget: int) -> dict:
    spectral = _spectral_sq(case)
    policy = proximal.Policy(
        regularization=float(regularization),
        max_iterations=int(budget),
        step_size=0.9 / spectral,
        pd_sigma=0.9,
        admm_rho=1.0,
    )
    started = time.perf_counter()
    result = proximal.run(algorithm, case["a"], case["y"], policy, profile=None)
    row = _quality_row(
        case, result, algorithm, asdict(policy), f"lambda{regularization:g}_budget{budget}",
        regularization=regularization,
    )
    row["elapsed_seconds"] = time.perf_counter() - started
    row["solver"] = "float"
    return row


def _policy_summary(rows: list[dict]) -> list[dict]:
    groups: dict[tuple[str, str], list[dict]] = {}
    for row in rows:
        groups.setdefault((row["dataset_kind"], row["algorithm"]), []).append(row)
    summary = []
    for (kind, algorithm), group in sorted(groups.items()):
        policies: dict[str, list[dict]] = {}
        for row in group:
            policies.setdefault(row["budget_label"], []).append(row)
        candidates = []
        for label, policy_rows in sorted(policies.items()):
            snr_values = [float(item["full"]["snr_db"]) for item in policy_rows]
            nmse_values = [float(item["full"]["nmse"]) for item in policy_rows]
            centered_snr_values = [float(item["centered"]["snr_db"]) for item in policy_rows]
            candidates.append({
                "policy_label": label,
                "window_count": len(policy_rows),
                "best_window_snr_db": max(snr_values),
                "worst_window_snr_db": min(snr_values),
                "mean_snr_db": float(np.mean(snr_values)),
                "worst_window_nmse": max(nmse_values),
                "mean_nmse": float(np.mean(nmse_values)),
                "worst_window_centered_snr_db": min(centered_snr_values),
            })
        best = sorted(
            candidates,
            key=lambda item: (
                -item["worst_window_snr_db"],
                item["worst_window_nmse"],
                item["policy_label"],
            ),
        )[0]
        summary.append({
            "dataset_kind": kind,
            "algorithm": algorithm,
            "best_calibration_candidate": best,
            "policies": candidates,
            "selection_rule": "maximize worst-window full-signal SNR, then minimize worst-window NMSE",
            "calibration_candidate_only": True,
            "heldout_quality_claim": False,
        })
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path,
        default=ROOT / "reports/v4/application_float_study.json",
    )
    args = parser.parse_args()
    cases = outer_cases(SEEDS, True, GENERATOR)
    if len(cases) != 4:
        raise RuntimeError(f"expected four application windows, got {len(cases)}")
    source_hashes = _source_hashes()
    report = {
        "schema": "v4-application-float-study-v1",
        "complete": False,
        "scope": "float_only_calibration_candidate",
        "python": platform.python_version(),
        "numpy": np.__version__,
        "packages": {
            name: importlib.metadata.version(name)
            for name in ("numpy", "scipy", "scikit-image")
        },
        "configuration": {
            "seeds": list(SEEDS),
            "generator": GENERATOR,
            "case_count": len(cases),
            "recovery_algorithms": list(RECOVERY_ALGORITHMS),
            "recovery_policy_grid": {
                name: [
                    {"sparsity": k, "budget": budget, "label": label}
                    for k, budget, label in values
                ]
                for name, values in RECOVERY_POLICIES.items()
            },
            "recovery_k16_k32": True,
            "proximal_algorithms": list(PROXIMAL_ALGORITHMS),
            "proximal_regularizations": list(REGULARIZATIONS),
            "proximal_budgets": list(PROXIMAL_BUDGETS),
            "step_size_rule": "0.9 / ||A||_2^2, recomputed per unchanged case",
            "admm_rho": 1.0,
            "pd_sigma": 0.9,
            "output_metrics": ["full_snr_db", "full_nmse", "centered_snr_db", "centered_nmse"],
            "camera_data_range": 1.0,
            "fixed_point_runs": 0,
        },
        "source_sha256_at_start": source_hashes,
        "source_sha256_last": source_hashes,
        "source_unchanged_during_run": None,
        "cases": [
            {
                "name": case["name"],
                "dataset_kind": _dataset_kind(case),
                "track": case["track"],
                "seed": case["seed"],
                "M": int(case["a"].shape[0]),
                "N": int(case["a"].shape[1]),
                "truth_sha256": digest(case["truth"]),
                "operator_sha256": digest(case["a"]),
                "measurement_sha256": digest(case["y"]),
                "measurement_snr_db": case.get("snr", 30),
                "normalization_mean": case.get("mean", 0.0),
                "normalization_scale": case.get("scale", 1.0),
                "source": case.get("source", {}),
            }
            for case in cases
        ],
        "rows": [],
        "policy_summary": [],
        "quality_gate": {
            "status": "not_applicable",
            "note": "Float application policy calibration only; no held-out quality claim and no profile freeze.",
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save() -> None:
        report["source_sha256_last"] = _source_hashes()
        args.output.write_text(
            json.dumps(report, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )

    save()
    for case in cases:
        # Each unchanged A gets one spectral norm evaluation shared by all
        # policy rows in this case.
        _spectral_sq(case)
        for algorithm in RECOVERY_ALGORITHMS:
            for sparsity, budget, label in RECOVERY_POLICIES[algorithm]:
                row = _run_recovery(case, algorithm, sparsity, budget, label)
                report["rows"].append(row)
                report["policy_summary"] = _policy_summary(report["rows"])
                save()
                print(
                    f'{case["name"]} {algorithm} {row["budget_label"]}: {row["status"]}',
                    flush=True,
                )
        for algorithm in PROXIMAL_ALGORITHMS:
            for regularization in REGULARIZATIONS:
                for budget in PROXIMAL_BUDGETS:
                    row = _run_proximal(case, algorithm, regularization, budget)
                    report["rows"].append(row)
                    report["policy_summary"] = _policy_summary(report["rows"])
                    save()
                    print(
                        f'{case["name"]} {algorithm} {row["budget_label"]}: {row["status"]}',
                        flush=True,
                    )
    report["policy_summary"] = _policy_summary(report["rows"])
    end_hashes = _source_hashes()
    report["source_sha256_end"] = end_hashes
    report["source_sha256_last"] = end_hashes
    report["source_unchanged_during_run"] = end_hashes == source_hashes
    report["complete"] = True
    report["summary"] = {
        "row_count": len(report["rows"]),
        "case_count": len(cases),
        "algorithms": len(RECOVERY_ALGORITHMS) + len(PROXIMAL_ALGORITHMS),
        "float_only": True,
        "fixed_runs": 0,
        "all_statuses": sorted({row["status"] for row in report["rows"]}),
    }
    save()
    if not report["source_unchanged_during_run"]:
        raise RuntimeError("source changed during study; rerun required")
    print(json.dumps(report["summary"]), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
