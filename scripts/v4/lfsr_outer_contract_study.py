"""Bounded outer-contract study for the selected LFSR32 operator.

This calibration keeps a power-of-two input normalization descriptor with each
job, stores LS coefficients in an explicit X format, and decodes the result
back to original units before quality comparison.  It does not select a
production profile or claim held-out quality. Future runs apply the user's
application SNR floor from config; earlier reports retain their archived policy.
"""

from __future__ import annotations

import argparse
from collections import Counter
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
from models.v4.fixed import Format
from models.v4.lfsr_operator import operator_identity
from models.v4.normalization import Normalization
from models.v4.quality import compare
from scripts.v4.generated_numeric_study import PROFILES, outer_cases
from scripts.v4.numeric_screen import digest
from scripts.v4.solver_study import relative_norm


SEEDS = (23, 47, 101)
PROFILE_NAME = "baseline"
DEFAULT_SOLUTION_FORMAT = Format(22, 18)
DEFAULT_STATE_FORMAT = (27, 19)
DEFAULT_DATA_FORMAT = (18, 14)
DEFAULT_COEFFICIENT_FORMAT = (18, 16)
DEFAULT_NORMAL_RTOL = 1e-5
DEFAULT_LS_BUDGET = 128
NORMALIZATION_TARGET_PEAK = 0.5
RECOVERY_ALGORITHMS = tuple(recovery.ALGORITHMS)
PROXIMAL_ALGORITHMS = tuple(proximal.ALGORITHMS)
ALL_ALGORITHMS = RECOVERY_ALGORITHMS + PROXIMAL_ALGORITHMS
N1024_LS_ALGORITHMS = ("OMP", "GOMP", "CoSaMP", "SP", "HTP")


def json_ready(value):
    if isinstance(value, np.ndarray):
        return json_ready(value.tolist())
    if isinstance(value, np.generic):
        return json_ready(value.item())
    if isinstance(value, (Path,)):
        return str(value)
    if isinstance(value, dict):
        return {str(k): json_ready(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_ready(v) for v in value]
    if isinstance(value, float) and not math.isfinite(value):
        return "nan" if math.isnan(value) else "inf" if value > 0 else "-inf"
    return value


def source_hashes() -> dict[str, str]:
    paths = sorted((ROOT / "models/v4").glob("*.py")) + [
        Path(__file__),
        ROOT / "scripts/v4/generated_numeric_study.py",
        ROOT / "scripts/v4/solver_study.py",
        ROOT / "scripts/v4/numeric_screen.py",
        ROOT / "config/v4_design.json",
    ]
    return {
        path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in paths
        if path.exists()
    }


def profile_with_overrides(args):
    base = PROFILES[PROFILE_NAME]
    data = Format(args.data_width, args.data_frac)
    coefficient = Format(args.coefficient_width, args.coefficient_frac)
    state = Format(args.state_width, args.state_frac)
    from models.v4.fixed import Profile
    from models.v4.quality import signed_dot_width

    return Profile(data, coefficient, state, signed_dot_width(state.width, state.width, 1024))


def case_identity(case):
    scale = abs(float(case["a"][0, 0]))
    return operator_identity(case["seed"], case["a"].shape[0], case["a"].shape[1], scale)


def prepare_case(case, profile):
    """Derive normalization and one common spectral bound for a case."""

    a = np.asarray(case["a"], dtype=float)
    y = np.asarray(case["y"], dtype=float)
    normalization = Normalization.derive(y, target_peak=NORMALIZATION_TARGET_PEAK)
    encoded_y = normalization.encode(y)
    # Use one bound for float and fixed policies. Include quantized C and a
    # conservative .9 step margin; do not recompute it per algorithm.
    from models.v4.fixed import Arithmetic
    arithmetic = Arithmetic(profile)
    quantized_c = arithmetic.decode(arithmetic.quantize(a, profile.coefficient), profile.coefficient)
    original_sq = float(np.linalg.norm(a, 2) ** 2)
    quantized_sq = float(np.linalg.norm(quantized_c, 2) ** 2)
    spectral_sq = max(original_sq, quantized_sq)
    return {
        "a": a,
        "y": y,
        "encoded_y": encoded_y,
        "normalization": normalization,
        "spectral": {
            "original_sq": original_sq,
            "quantized_coefficient_sq": quantized_sq,
            "bound_sq": spectral_sq,
            "step_margin": 0.9,
            "step_size": 0.9 / spectral_sq,
            "computed_once_per_case": True,
        },
    }


def recovery_policy(case, spectral, gain, rtol):
    k = int(case["k"])
    # Existing generated_numeric_study policy: OMP/GOMP use K, others 24.
    return recovery.Policy(
        sparsity=k,
        max_iterations=24,
        residual_atol=1e-6 * gain,
        step_size=spectral["step_size"],
        group_size=2,
        ls_max_iterations=DEFAULT_LS_BUDGET,
        ls_normal_rtol=rtol,
    )


def policy_for_recovery(case, spectral, gain, rtol, algorithm):
    base = recovery_policy(case, spectral, gain, rtol)
    if algorithm in ("OMP", "GOMP"):
        return recovery.Policy(
            sparsity=base.sparsity, max_iterations=base.sparsity,
            residual_atol=base.residual_atol, step_size=base.step_size,
            group_size=base.group_size, ls_max_iterations=base.ls_max_iterations,
            ls_normal_rtol=base.ls_normal_rtol,
        )
    return base


def policy_for_proximal(spectral, gain):
    return proximal.Policy(
        regularization=0.01 * gain,
        max_iterations=24,
        step_size=spectral["step_size"],
        pd_sigma=0.9,
        admm_rho=1.0,
        inner_max_iterations=128,
        inner_rtol=1e-4,
    )


def result_record(result, *, normalized: bool, gain: float) -> dict:
    if result is None:
        return {"status": "exception", "accepted": False}
    solver_trace = getattr(result, "solver_trace", [])
    trace = getattr(result, "trace", [])
    return {
        "status": result.status,
        "support": list(result.support),
        "events": dict(result.events),
        "trace": trace,
        "solver_trace": solver_trace,
        "solver_trace_counts": [
            {
                "support": item.get("support"),
                "status": item.get("status"),
                "steps": item.get("steps"),
                "counts": item.get("counts"),
            }
            for item in solver_trace
        ],
        "raw_x": None if result.raw_x is None else list(result.raw_x),
        "raw_x_format": result.raw_x_format,
        "raw_x_units": "normalized" if normalized else "original",
        "output_scale_exponent": None if not normalized else -int(round(math.log2(gain))),
        "returned_without_numeric_fault": not any(result.events.values()) and not any(
            item.get("phase") == "FAULT" for item in trace
        ),
    }


def run_one(case, prepared, algorithm, profile, xformat, rtol, quality_thresholds):
    a, y0, y, normalization = (
        prepared["a"], prepared["y"], prepared["encoded_y"], prepared["normalization"]
    )
    gain = normalization.gain
    spectral = prepared["spectral"]
    support = list(case.get("support", []))
    is_recovery = algorithm in RECOVERY_ALGORITHMS
    original_policy = (
        policy_for_recovery(case, spectral, 1.0, rtol, algorithm)
        if is_recovery else proximal.Policy(
            regularization=0.01, max_iterations=24,
            step_size=spectral["step_size"], pd_sigma=0.9,
            admm_rho=1.0, inner_max_iterations=128, inner_rtol=1e-4,
        )
    )
    normalized_policy = (
        policy_for_recovery(case, spectral, gain, rtol, algorithm)
        if is_recovery else policy_for_proximal(spectral, gain)
    )
    started = time.perf_counter()
    float_result = None
    fixed_result = None
    float_exception = None
    fixed_exception = None
    try:
        float_result = (recovery.run(algorithm, a, y0, original_policy)
                        if is_recovery else proximal.run(algorithm, a, y0, original_policy))
    except Exception as exc:
        float_exception = {"type": type(exc).__name__, "message": str(exc)}
    try:
        fixed_result = (
            recovery.run(
                algorithm, a, y, normalized_policy, profile,
                ls_solver="lsqr", solution_format=xformat,
            ) if is_recovery else proximal.run(algorithm, a, y, normalized_policy, profile)
        )
    except Exception as exc:
        fixed_exception = {"type": type(exc).__name__, "message": str(exc)}
    elapsed = time.perf_counter() - started

    float_x = None if float_result is None else np.asarray(float_result.x, dtype=float)
    fixed_x_norm = None if fixed_result is None else np.asarray(fixed_result.x, dtype=float)
    fixed_x = None if fixed_x_norm is None else fixed_x_norm / gain
    restore = case["restore"]
    floating_signal = None if float_x is None else restore(float_x)
    fixed_signal = None if fixed_x is None else restore(fixed_x)
    quality = None
    centered_quality = None
    if floating_signal is not None and fixed_signal is not None:
        quality = compare(case["original"], floating_signal, fixed_signal, **quality_thresholds)
        quality["application_snr_eligible"] = bool(np.any(np.asarray(case["original"]) != 0))
        if not quality["application_snr_eligible"]:
            # A perfect zero signal has no meaningful signal-to-error ratio.
            quality["application_quality_pass"] = False
            quality["paper_quality_pass"] = False
        mean = float(case.get("mean", 0.0))
        centered_quality = compare(
            np.asarray(case["original"]) - mean,
            np.asarray(floating_signal) - mean,
            np.asarray(fixed_signal) - mean,
            **{k: v for k, v in quality_thresholds.items() if k != "absolute_snr_min_db"},
        )

    fixed_record = result_record(fixed_result, normalized=True, gain=gain)
    fixed_record["events"] = None if fixed_result is None else dict(fixed_result.events)
    fixed_record["trace_fault"] = None if fixed_result is None else any(
        item.get("phase") == "FAULT" for item in fixed_result.trace
    )
    return {
        "case": case["name"],
        "track": case["track"],
        "coefficient_domain_track": case["track"] == "coefficient_domain_encoder_DCT_not_raw_signal_PhiPsi",
        "raw_signal_PhiPsi_claim": False,
        "algorithm": algorithm,
        "profile_id": profile.name,
        "solution_format": asdict(xformat),
        "normalization": normalization.descriptor,
        "operator_identity": case_identity(case),
        "operator_sha256": digest(a),
        "measurement_sha256": digest(y0),
        "encoded_measurement_sha256": digest(y),
        "truth_sha256": digest(case["truth"]),
        "support": support,
        "support_order_digest": hashlib.sha256(json.dumps(support).encode()).hexdigest(),
        "spectral_policy": spectral,
        "reference_domain": "original_unscaled_A_y",
        "float_policy": asdict(original_policy),
        "fixed_policy": asdict(normalized_policy),
        "proximal_storage_contract": (
            "D18 data storage is unchanged; proximal has no solution_format override"
            if not is_recovery else None
        ),
        "proximal_lambda_contract": (
            {"lambda_original": 0.01, "lambda_normalized": 0.01 * gain,
             "step_size_unchanged": True, "rho_unchanged": True}
            if not is_recovery else None
        ),
        "float_status": None if float_result is None else float_result.status,
        "fixed_status": None if fixed_result is None else fixed_result.status,
        "float_exception": float_exception,
        "fixed_exception": fixed_exception,
        "float_result": result_record(float_result, normalized=False, gain=1.0),
        "fixed_result": fixed_record,
        "quality_full_original_units": quality,
        "quality_centered_original_units": centered_quality,
        "runtime_seconds": elapsed,
        "application_floor_established": True,
        "application_quality_thresholds": quality_thresholds,
        "heldout_evidence": False,
        "production_profile_selected": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/v4/lfsr_outer_contract.json")
    parser.add_argument("--solution-width", type=int, default=22)
    parser.add_argument("--solution-frac", type=int, default=18)
    parser.add_argument("--state-width", type=int, default=DEFAULT_STATE_FORMAT[0])
    parser.add_argument("--state-frac", type=int, default=DEFAULT_STATE_FORMAT[1])
    parser.add_argument("--data-width", type=int, default=DEFAULT_DATA_FORMAT[0])
    parser.add_argument("--data-frac", type=int, default=DEFAULT_DATA_FORMAT[1])
    parser.add_argument("--coefficient-width", type=int, default=DEFAULT_COEFFICIENT_FORMAT[0])
    parser.add_argument("--coefficient-frac", type=int, default=DEFAULT_COEFFICIENT_FORMAT[1])
    parser.add_argument("--ls-normal-rtol", type=float, default=DEFAULT_NORMAL_RTOL)
    parser.add_argument("--ls-budget", type=int, default=DEFAULT_LS_BUDGET)
    args = parser.parse_args()
    numerical = json.loads((ROOT / "config/v4_design.json").read_text(encoding="utf-8"))["numerical"]
    quality_thresholds = {
        "max_snr_loss_db": numerical["max_snr_loss_db"],
        "max_nmse_ratio": numerical["max_nmse_ratio"],
        "absolute_snr_min_db": numerical["application_quality"]["absolute_snr_min_db"],
    }
    # Validate policy before expensive solves, using the existing metric contract.
    compare([1.0], [0.9], [0.9], **quality_thresholds)
    if args.ls_budget != DEFAULT_LS_BUDGET:
        raise ValueError("this bounded contract study requires LS budget 128")
    profile = profile_with_overrides(args)
    xformat = Format(args.solution_width, args.solution_frac)
    if not (xformat.frac <= profile.state.frac):
        raise ValueError("solution fractional bits must embed in state format")

    synthetic = outer_cases(SEEDS, False, "lfsr32")
    real = outer_cases(SEEDS, True, "lfsr32")
    cases = synthetic + real
    if len(cases) != 8:
        raise ValueError(f"expected 8 cases, got {len(cases)}")
    algorithms_for_case = {
        case["name"]: (ALL_ALGORITHMS if case["a"].shape[1] != 1024 else N1024_LS_ALGORITHMS)
        for case in cases
    }
    expected_rows = 3 * 11 + 1 * 5 + 4 * 11
    report = {
        "schema": "v4-lfsr-outer-contract-v1",
        "complete": False,
        "scope": "bounded_calibration_only",
        "generator": {
            "selected": "LFSR32_Galois_rightshift_v2",
            "taps": "0x80200003",
            "seed_width_bits": 32,
            "zero_seed_substitution": "0xDEADBEEF",
            "output": "emit_current_lsb_then_step",
            "stream_index": "column*M+row",
            "tail_policy": "valid_rows_only_padding_does_not_consume_stream",
            "threefry_role": "reference_ablation_only",
        },
        "configuration": {
            "profile": profile.name,
            "data_format": asdict(profile.data),
            "coefficient_format": asdict(profile.coefficient),
            "state_format": asdict(profile.state),
            "solution_format": asdict(xformat),
            "ls_solver": "lsqr",
            "ls_normal_rtol": args.ls_normal_rtol,
            "ls_budget": args.ls_budget,
            "normalization": "Normalization.derive(y,target_peak=0.5) before D; decode x by inverse gain",
            "spectral_bound": "max(original ||A||², quantized-C ||C||²), step=.9/bound, once per case",
            "n256_algorithms": list(ALL_ALGORITHMS),
            "n1024_algorithms": list(N1024_LS_ALGORITHMS),
        },
        "rows_expected": expected_rows,
        "python": platform.python_version(),
        "packages": {name: importlib.metadata.version(name) for name in ("numpy", "scipy", "scikit-image")},
        "source_sha256": source_hashes(),
        "application_floor_established": True,
        "application_quality_policy": numerical["application_quality"],
        "application_quality_thresholds": quality_thresholds,
        "heldout_evidence": False,
        "production_profile_selected": False,
        "cases": [],
        "rows": [],
    }
    for case in cases:
        meta = {key: value for key, value in case.items() if key not in ("a", "y", "truth", "restore")}
        meta.update({
            "operator_sha256": digest(case["a"]),
            "measurement_sha256": digest(case["y"]),
            "truth_sha256": digest(case["truth"]),
            "operator_identity": case_identity(case),
            "algorithms": list(algorithms_for_case[case["name"]]),
            "heldout": False,
            "application_floor_established": True,
        })
        report["cases"].append(meta)
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        args.output.write_text(json.dumps(json_ready(report), indent=2, allow_nan=False) + "\n", encoding="utf-8")

    save()
    for case in cases:
        prepared = prepare_case(case, profile)
        for algorithm in algorithms_for_case[case["name"]]:
            row = run_one(case, prepared, algorithm, profile, xformat, args.ls_normal_rtol, quality_thresholds)
            report["rows"].append(row)
            save()
            print(case["name"], algorithm, row["fixed_status"], flush=True)
    report["source_unchanged_during_run"] = report["source_sha256"] == source_hashes()
    report["summary"] = {
        "rows_completed": len(report["rows"]),
        "rows_expected": expected_rows,
        "fixed_statuses": dict(Counter(row["fixed_status"] for row in report["rows"])),
        "float_statuses": dict(Counter(row["float_status"] for row in report["rows"])),
        "fixed_fault_rows": sum(bool(row["fixed_exception"] or row["fixed_result"].get("trace_fault")) for row in report["rows"]),
        "quality_rows": sum(row["quality_full_original_units"] is not None for row in report["rows"]),
        "application_relative_no_fault_pass_rows": sum(
            bool(row["quality_full_original_units"]
                 and row["quality_full_original_units"]["paper_quality_pass"]
                 and all(row[f"{domain}_exception"] is None
                         and row[f"{domain}_result"].get("returned_without_numeric_fault") is True
                         for domain in ("float", "fixed")))
            for row in report["rows"]
        ),
    }
    report["complete"] = len(report["rows"]) == expected_rows and report["source_unchanged_during_run"]
    save()
    if not report["complete"]:
        raise RuntimeError("study incomplete or source changed during run")


if __name__ == "__main__":
    main()
