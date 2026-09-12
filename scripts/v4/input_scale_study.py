"""Measure a power-of-two input block scale on the low-amplitude LS case.

This is a calibration proposal.  It does not select an RTL normalization
policy: the output block exponent is metadata that the current RTL does not
carry, so ADC bits lost before normalization cannot be recovered here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4 import recovery
from models.v4.fixed import Arithmetic
from models.v4.quality import compare
from scripts.v4.generated_numeric_study import (
    NORMAL_RTOL,
    ObservedLSQR,
    PROFILES,
    QUALITY,
    ls_cases,
)
from scripts.v4.solver_study import normal_diagnostics, relative_norm


PROFILE_NAME = "baseline"
MAX_STEPS = 128
SEEDS = (23, 47, 101)
CASE_FRAGMENT = "m128_s8_noise30_amp0.001"


def digest(values) -> str:
    array = np.asarray(values, dtype="<f8")
    return hashlib.sha256(array.tobytes(order="C")).hexdigest()


def source_hashes() -> dict[str, str]:
    paths = [
        Path(__file__),
        ROOT / "scripts/v4/generated_numeric_study.py",
        ROOT / "scripts/v4/solver_study.py",
        ROOT / "models/v4/fixed.py",
        ROOT / "models/v4/recovery.py",
        ROOT / "models/v4/lsqr.py",
        ROOT / "models/v4/quality.py",
        ROOT / "models/v4/generated_operator.py",
    ]
    return {
        path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in paths
        if path.exists()
    }


def power_of_two_metadata(measurement: np.ndarray) -> dict:
    max_abs = float(np.max(np.abs(measurement)))
    if not math.isfinite(max_abs) or max_abs <= 0.0:
        raise ValueError("measurement must have a finite non-zero maximum")
    exponent = math.floor(math.log2(1.0 / max_abs))
    gain = math.ldexp(1.0, exponent)
    scaled_max = max_abs * gain
    return {
        "mode": "power_of_two_output_block",
        "e": int(exponent),
        "gain": float(gain),
        "max_abs_y": max_abs,
        "scaled_max_abs_y": float(scaled_max),
        "target_range": "max_abs(gain*y) in [0.5,1]",
        "metadata_required_by_current_rtl": True,
        "metadata_present_in_current_rtl": False,
        "adc_bits_lost_before_normalization_recoverable": False,
    }


def _one_case(case: dict, mode: str, profile) -> dict:
    original_a = np.asarray(case["a"], dtype=float)
    original_y = np.asarray(case["y"], dtype=float)
    truth = np.asarray(case["truth"], dtype=float)
    support = list(case["support"])
    if mode == "raw":
        exponent, gain = 0, 1.0
        scale_meta = {
            "mode": "raw",
            "e": exponent,
            "gain": gain,
            "max_abs_y": float(np.max(np.abs(original_y))),
            "scaled_max_abs_y": float(np.max(np.abs(original_y))),
            "metadata_required_by_current_rtl": False,
            "metadata_present_in_current_rtl": False,
            "adc_bits_lost_before_normalization_recoverable": False,
        }
    elif mode == "power_of_two":
        scale_meta = power_of_two_metadata(original_y)
        exponent, gain = scale_meta["e"], scale_meta["gain"]
    else:
        raise ValueError(f"unknown mode {mode}")

    work_y = original_y * gain
    policy = recovery.Policy(
        sparsity=len(support),
        ls_normal_rtol=NORMAL_RTOL,
        ls_max_iterations=MAX_STEPS,
    )
    started = time.perf_counter()
    accepted = None
    status = "not_started"
    candidates = []
    constructor_events = None
    solver_report = None
    k = None
    try:
        k = ObservedLSQR(original_a, work_y, policy, profile)
        constructor_events = dict(k.events)
        if any(k.events.values()):
            raise ArithmeticError("numeric_fault")
        accepted_raw = k.least_squares(support)
        accepted = k.decode(accepted_raw)
        candidates = [np.asarray(candidate, dtype=float) for candidate in k.observed_candidates] \
            if hasattr(k, "observed_candidates") else []
        status = "accepted"
    except ArithmeticError as exc:
        status = str(exc)
        if k is not None and hasattr(k, "observed_candidates"):
            candidates = [np.asarray(candidate, dtype=float) for candidate in k.observed_candidates]
    except Exception as exc:  # retain an exceptional row for the incremental study
        status = f"exception:{type(exc).__name__}"
    elapsed = time.perf_counter() - started
    if k is not None:
        solver_report = getattr(k, "last_ls_report", None)
        constructor_events = dict(k.events)

    last = accepted if accepted is not None else (candidates[-1] if candidates else None)
    if accepted is not None:
        recovered_original = accepted / gain
    elif last is not None:
        recovered_original = last / gain
    else:
        recovered_original = None

    # SVD on the original problem is the unscaled reference.  The quantized
    # SVD is formed from exactly the B and y representation supplied to LSQR.
    original_svd = np.linalg.lstsq(original_a[:, support], original_y, rcond=None)[0]
    quantized_svd = None
    quantized_svd_report = None
    if k is not None:
        b = k.arithmetic.decode(k.a[:, support], profile.coefficient)
        yq = k.decode(k.y)
        quantized_svd, _, rank, singular = np.linalg.lstsq(b, yq, rcond=None)
        quantized_svd_report = {
            "method": "numpy.linalg.lstsq rcond=None SVD on quantized B and scaled y",
            "rank": int(rank),
            "condition": float(singular[0] / singular[-1]) if singular[-1] else math.inf,
            "matrix_digest": digest(b),
            "measurement_digest": digest(yq),
            "measurement_range": {
                "min": float(np.min(yq)),
                "max": float(np.max(yq)),
                "max_abs": float(np.max(np.abs(yq))),
            },
        }

    row = {
        "case": case["name"],
        "seed": int(case["seed"]),
        "mode": mode,
        "profile_id": profile.name,
        "support": support,
        "support_order_digest": hashlib.sha256(json.dumps(support).encode()).hexdigest(),
        "operator_digest": digest(original_a),
        "measurement_digest": digest(original_y),
        "truth_digest": digest(truth),
        "scale": scale_meta,
        "solver": "LSQR",
        "max_steps": MAX_STEPS,
        "status": status,
        "accepted": accepted is not None,
        "failed_all": accepted is None and last is None,
        "no_accept_last": accepted is None and last is not None,
        "iterations": int(k.ls_steps) if k is not None else 0,
        "elapsed_seconds": float(elapsed),
        "constructor_events": constructor_events,
        "solver_report": solver_report,
        "original_svd": {
            "method": "numpy.linalg.lstsq rcond=None SVD on unscaled A/y",
            "normal": normal_diagnostics(original_a[:, support], original_y, original_svd),
        },
        "quantized_svd": quantized_svd_report,
        "original_quality": None,
        "coefficient_agreement": None,
        "range_overflow": {
            "float_y_min": float(np.min(original_y)),
            "float_y_max": float(np.max(original_y)),
            "float_scaled_y_min": float(np.min(work_y)),
            "float_scaled_y_max": float(np.max(work_y)),
            "accumulator_limit": [
                -(1 << (profile.accumulator_width - 1)),
                (1 << (profile.accumulator_width - 1)) - 1,
            ],
            "events": constructor_events,
            "solver_energy_prefix_max_abs": (
                None if not solver_report else solver_report.get("energy_prefix_max_abs")
            ),
        },
    }
    if recovered_original is not None:
        row["original_quality"] = compare(
            truth, original_svd, recovered_original, **QUALITY
        )
        row["last_candidate_original_normal"] = normal_diagnostics(
            original_a[:, support], original_y, recovered_original
        )
        if quantized_svd is not None:
            candidate_scaled = accepted if accepted is not None else last
            row["coefficient_agreement"] = {
                "scaled_solver_vs_quantized_svd_relative": relative_norm(
                    candidate_scaled - quantized_svd, quantized_svd
                ),
                "original_solver_vs_unscaled_svd_relative": relative_norm(
                    recovered_original - original_svd, original_svd
                ),
                "scaled_truth_digest": digest(truth * gain),
            }
    return row


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path,
        default=ROOT / "reports/v4/input_scale_study.json",
    )
    args = parser.parse_args()
    selected = [
        case for case in ls_cases(SEEDS, "threefry") if CASE_FRAGMENT in case["name"]
    ]
    if len(selected) != len(SEEDS):
        raise ValueError(f"expected one selected case per seed, got {len(selected)}")
    profile = PROFILES[PROFILE_NAME]
    report = {
        "schema": "v4-input-scale-study-v1",
        "complete": False,
        "scope": "calibration_proposal_only",
        "configuration": {
            "generator": "threefry",
            "seeds": list(SEEDS),
            "case_fragment": CASE_FRAGMENT,
            "profile": PROFILE_NAME,
            "solver": "LSQR",
            "max_steps": MAX_STEPS,
            "normal_rtol": NORMAL_RTOL,
            "quality_thresholds": QUALITY,
            "normalization": "e=floor(log2(1/max(abs(y)))); gain=2^e before D quantization",
            "same_operator_and_ordered_support": True,
        },
        "output_block_exponent": {
            "required_for_normalized_output": True,
            "present_in_current_rtl": False,
            "adc_bits_lost_before_normalization_recoverable": False,
        },
        "python": platform.python_version(),
        "numpy": np.__version__,
        "source_sha256": source_hashes(),
        "rows": [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save() -> None:
        args.output.write_text(
            json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8"
        )

    save()
    for case in selected:
        for mode in ("raw", "power_of_two"):
            try:
                row = _one_case(case, mode, profile)
            except Exception as exc:
                row = {
                    "case": case["name"],
                    "seed": int(case["seed"]),
                    "mode": mode,
                    "status": f"study_exception:{type(exc).__name__}",
                    "error": str(exc),
                    "failed_all": True,
                    "no_accept_last": False,
                }
            report["rows"].append(row)
            save()
    report["complete"] = len(report["rows"]) == 6
    save()


if __name__ == "__main__":
    main()
