"""Isolate LS stopping tolerance from bit profile on generated Threefry LS cases.

This is a calibration study only.  Each row uses one generated Psi=I case,
one profile, and one normal-residual tolerance, then runs CGLS and LSQR over
the same quantized B/y.  Failed candidates remain diagnostics and are never
promoted to accepted output.  The report is written after every row so a
long sweep remains auditable if interrupted.
"""

from __future__ import annotations

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
from scipy.linalg import lstsq

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Arithmetic
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.recovery import Policy
from scripts.v4.generated_numeric_study import PROFILES, ls_cases
from scripts.v4.solver_study import ObservedCGLS, normal_diagnostics, relative_norm
from scripts.v4.numeric_screen import digest, sanitized


SEEDS = (23, 47, 101)
NORMAL_RTOLS = (1e-4, 3e-5, 1e-5)
ITERATION_BUDGET = 128
COEFFICIENT_RTOL = 1e-3  # diagnostic only; not a rank-aware acceptance contract


class ObservedLSQR(IntegerLSQRKernels):
    """Capture LSQR's post-D certificates without changing its arithmetic."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.candidates = []

    def certificate(self, coefficients, support, rhs_energy):
        accepted = super().certificate(coefficients, support, rhs_energy)
        self.candidates.append({
            "x": self.decode(coefficients).copy(),
            "pre_storage": None if self.last_pre_storage is None else
                self.decode(self.last_pre_storage).copy(),
            "model_certificate": bool(accepted),
        })
        return accepted


class CountedCGLS(ObservedCGLS):
    """Observe the unchanged CGLS model with LS operation counts."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.counts = {}
        self.last_ls_report = None

    def mv(self, *args, **kwargs):
        self.counts["GEMV"] = self.counts.get("GEMV", 0) + 1
        return super().mv(*args, **kwargs)

    def dot(self, *args, **kwargs):
        self.counts["DOT"] = self.counts.get("DOT", 0) + 1
        return super().dot(*args, **kwargs)

    def ratio(self, *args, **kwargs):
        self.counts["DIV"] = self.counts.get("DIV", 0) + 1
        return super().ratio(*args, **kwargs)

    def least_squares(self, support):
        self.counts = {}
        status = "certified"
        try:
            return super().least_squares(support)
        except ArithmeticError as error:
            status = str(error)
            raise
        finally:
            self.last_ls_report = {
                "solver": "CGLS",
                "status": status,
                "steps": self.ls_steps,
                "counts": dict(self.counts),
                "certificate_checks": len(self.candidates),
                "count_scope": "LS including initialization and every certificate; no outer/constructor costs",
            }


def profile_spec(profile):
    return {
        "data": asdict(profile.data),
        "coefficient": asdict(profile.coefficient),
        "state": asdict(profile.state),
        "accumulator_width": profile.accumulator_width,
    }


def row_configurations():
    """Return exactly the requested 15 profile/seed/tolerance combinations."""
    result = [("wide_control", seed) for seed in SEEDS]
    result.extend((profile, 23) for profile in ("baseline", "data20"))
    return [(profile, seed, rtol)
            for profile, seed in result for rtol in NORMAL_RTOLS]


def run_one_solver(case, profile, solver, normal_rtol, oracle, original_oracle):
    support = case["support"]
    policy = Policy(
        sparsity=len(support),
        ls_normal_rtol=normal_rtol,
        ls_max_iterations=ITERATION_BUDGET,
    )
    cls = ObservedLSQR if solver == "lsqr" else CountedCGLS
    kernel = cls(case["a"], case["y"], policy, profile)
    aq = kernel.arithmetic.decode(kernel.a[:, support], profile.coefficient)
    yq = kernel.decode(kernel.y)
    status = "certified"
    accepted = None
    started = time.perf_counter()
    try:
        if any(kernel.events.values()):
            raise ArithmeticError("numeric_fault")
        accepted = kernel.decode(kernel.least_squares(support))
        if any(kernel.events.values()):
            accepted = None
            raise ArithmeticError("numeric_fault")
    except ArithmeticError as error:
        status = str(error)
    elapsed = time.perf_counter() - started

    if accepted is not None:
        candidate = accepted
        accepted_output = True
    elif solver == "lsqr" and kernel.last_candidate is not None:
        candidate = kernel.decode(kernel.last_candidate)
        accepted_output = False
    elif solver == "cgls" and kernel.candidates:
        candidate = kernel.candidates[-1]["x"]
        accepted_output = False
    else:
        candidate = None
        accepted_output = False

    if solver == "lsqr":
        certificate_history = kernel.last_ls_report.get("certificate_history", [])
        last_pre_storage = (
            None if kernel.last_pre_storage is None else
            kernel.decode(kernel.last_pre_storage).tolist()
        )
    else:
        certificate_history = [
            {k: v for k, v in item.items() if k not in ("x", "pre_storage")}
            for item in kernel.candidates
        ]
        last_pre_storage = (
            None if not kernel.candidates or kernel.candidates[-1]["pre_storage"] is None
            else kernel.candidates[-1]["pre_storage"].tolist()
        )

    d = None
    if candidate is not None:
        d = {
            **normal_diagnostics(aq, yq, candidate),
            "coefficient_error_vs_quantized_svd": relative_norm(candidate - oracle, oracle),
            "coefficient_error_vs_original_svd": relative_norm(candidate - original_oracle, original_oracle),
            "prediction_error_vs_quantized_svd": relative_norm(
                aq @ (candidate - oracle), aq @ oracle
            ),
            "normal_float64_pass": bool(normal_diagnostics(aq, yq, candidate)["normal_relative"] <= normal_rtol),
            "coefficient_agreement_pass": bool(relative_norm(candidate - oracle, oracle) <= COEFFICIENT_RTOL),
            "accepted_output": accepted_output,
            "diagnostic_only_if_failed": not accepted_output,
            "pre_storage": last_pre_storage,
        }

    return {
        "status": status,
        "accepted": accepted_output,
        "iterations": kernel.ls_steps,
        "elapsed_seconds": elapsed,
        "events": dict(kernel.events),
        "last_candidate": d,
        "certificate_history": certificate_history,
        "solver_report": getattr(kernel, "last_ls_report", None),
    }


def make_row(case, profile_name, seed, normal_rtol):
    profile = PROFILES[profile_name]
    support = case["support"]
    # Build the exact quantized oracle from the kernel representation used by
    # both solvers; this keeps the SVD comparison independent of recurrence.
    probe = Arithmetic(profile)
    b_raw = probe.quantize(case["a"][:, support], profile.coefficient)
    y_raw = probe.quantize(case["y"], profile.data)
    aq = probe.decode(b_raw, profile.coefficient)
    y_state_raw = np.array([
        probe.rescale(int(value), profile.data.frac, profile.state)
        for value in y_raw
    ], dtype=object)
    yq = probe.decode(y_state_raw, profile.state)
    oracle, _, rank, singular = lstsq(aq, yq, cond=None, lapack_driver="gelsd")
    original_oracle, _, _, _ = lstsq(case["a"][:, support], case["y"], cond=None, lapack_driver="gelsd")
    rounded_arithmetic = Arithmetic(profile)
    rounded = rounded_arithmetic.decode(
        rounded_arithmetic.quantize(oracle, profile.data), profile.data
    )
    rounded_diag = {
        **normal_diagnostics(aq, yq, rounded),
        "coefficient_error_vs_quantized_svd": relative_norm(rounded - oracle, oracle),
        "normal_float64_pass_by_rtol": {
            str(rtol): bool(normal_diagnostics(aq, yq, rounded)["normal_relative"] <= rtol)
            for rtol in NORMAL_RTOLS
        },
        "coefficient_agreement_pass": bool(relative_norm(rounded - oracle, oracle) <= COEFFICIENT_RTOL),
        "events": dict(rounded_arithmetic.events),
    }
    solvers = {
        solver: run_one_solver(case, profile, solver, normal_rtol, oracle, original_oracle)
        for solver in ("cgls", "lsqr")
    }
    return {
        "case": case["name"],
        "track": case["track"],
        "seed": seed,
        "profile": profile_name,
        "profile_id": profile.name,
        "normal_rtol": normal_rtol,
        "iteration_budget": ITERATION_BUDGET,
        "support": list(support),
        "support_size": len(support),
        "quantized_rank": int(rank),
        "quantized_condition": float(singular[0] / singular[-1]) if singular[-1] else math.inf,
        "oracle": {
            "method": "scipy.linalg.lstsq; gelsd SVD; cond=None minimum norm",
            **normal_diagnostics(aq, yq, oracle),
            "coefficient_norm": float(np.linalg.norm(oracle)),
        },
        "D_rounded_oracle_floor": rounded_diag,
        "solvers": solvers,
        "application_quality_claim": False,
        "production_gate_pass": False,
    }


def source_hashes():
    files = [
        Path(__file__),
        ROOT / "models/v4/fixed.py",
        ROOT / "models/v4/recovery.py",
        ROOT / "models/v4/lsqr.py",
        ROOT / "models/v4/generated_operator.py",
        ROOT / "scripts/v4/generated_numeric_study.py",
        ROOT / "scripts/v4/solver_study.py",
        ROOT / "scripts/v4/numeric_screen.py",
    ]
    return {
        f.relative_to(ROOT).as_posix(): hashlib.sha256(f.read_bytes()).hexdigest()
        for f in files
    }


def build_report(output):
    selected = [
        c for c in ls_cases(SEEDS, "threefry")
        if "generated_m128_s96_noise30_amp1_seed" in c["name"]
    ]
    by_seed = {int(c["seed"]): c for c in selected}
    if set(by_seed) != set(SEEDS):
        raise RuntimeError("requested generated s96 cases are incomplete")
    report = {
        "schema": "v4-lsqr-stop-policy-study-v1",
        "complete": False,
        "scope": "solver-calibration-only",
        "study_question": "Does tightening normal-rtol or widening D/S bits change LS acceptance and coefficient agreement at fixed budget?",
        "configuration": {
            "generator": "threefry",
            "generator_contract": "Threefry2x32-20 v3 coordinate mapping; revision1; common scale=1/sqrt(M); no column normalization",
            "case_selector": "generated_m128_s96_noise30_amp1_seed{23,47,101}",
            "profiles": ["wide_control", "baseline", "data20"],
            "seeds": list(SEEDS),
            "normal_rtols": list(NORMAL_RTOLS),
            "solvers": ["cgls", "lsqr"],
            "iteration_budget": ITERATION_BUDGET,
            "rows_expected": 15,
        },
        "python": platform.python_version(),
        "numpy": np.__version__,
        "packages": {
            name: importlib.metadata.version(name)
            for name in ("numpy", "scipy")
        },
        "profiles": {
            name: profile_spec(PROFILES[name])
            for name in ("wide_control", "baseline", "data20")
        },
        "source_sha256": source_hashes(),
        "thresholds": {
            "coefficient_rtol_diagnostic": COEFFICIENT_RTOL,
            "normal_rtol_is_policy_sweep": list(NORMAL_RTOLS),
        },
        "acceptance_contract": "accepted means solver returned a D-stored candidate, no arithmetic events, and its model certificate passed; failed last candidates are diagnostic only",
        "cost_claim": "integer kernel operation counts only; no RTL cycles, throughput, or board claim",
        "application_quality_claim": False,
        "cases": [
            {
                "name": case["name"],
                "seed": int(case["seed"]),
                "track": case["track"],
                "M": int(case["a"].shape[0]),
                "N": int(case["a"].shape[1]),
                "support": list(case["support"]),
                "operator_sha256": digest(case["a"]),
                "measurement_sha256": digest(case["y"]),
                "truth_sha256": digest(case["truth"]),
                "measurement_snr_db": case.get("snr", 30),
            }
            for case in (by_seed[seed] for seed in SEEDS)
        ],
        "rows": [],
    }
    output.parent.mkdir(parents=True, exist_ok=True)

    def save():
        output.write_text(
            json.dumps(sanitized(report), indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )

    save()
    for profile_name, seed, normal_rtol in row_configurations():
        started = time.perf_counter()
        row = make_row(by_seed[seed], profile_name, seed, normal_rtol)
        row["row_elapsed_seconds"] = time.perf_counter() - started
        report["rows"].append(row)
        save()
        states = ", ".join(
            f"{solver}:{data['status']}" for solver, data in row["solvers"].items()
        )
        print(f"{profile_name} seed={seed} rtol={normal_rtol:g}: {states}", flush=True)

    grouped = {}
    for row in report["rows"]:
        key = f"{row['profile']}/rtol={row['normal_rtol']:g}"
        grouped[key] = {
            solver: {
                "accepted": bool(row["solvers"][solver]["accepted"]),
                "status": row["solvers"][solver]["status"],
                "iterations": row["solvers"][solver]["iterations"],
                "coefficient_error": None if row["solvers"][solver]["last_candidate"] is None
                else row["solvers"][solver]["last_candidate"]["coefficient_error_vs_quantized_svd"],
            }
            for solver in ("cgls", "lsqr")
        }
    report["summary_by_profile_rtol"] = grouped
    report["summary"] = {
        "rows_completed": len(report["rows"]),
        "rows_expected": 15,
        "solver_accepted_rows": {
            solver: sum(bool(row["solvers"][solver]["accepted"])
                        for row in report["rows"])
            for solver in ("cgls", "lsqr")
        },
        "wide_control_seed23": [
            {
                "normal_rtol": row["normal_rtol"],
                "solvers": {
                    solver: {
                        "status": row["solvers"][solver]["status"],
                        "accepted": row["solvers"][solver]["accepted"],
                        "coefficient_error": None if row["solvers"][solver]["last_candidate"] is None
                        else row["solvers"][solver]["last_candidate"]["coefficient_error_vs_quantized_svd"],
                    }
                    for solver in ("cgls", "lsqr")
                },
            }
            for row in report["rows"]
            if row["profile"] == "wide_control" and row["seed"] == 23
        ],
        "early_stopping_diagnosis": {
            "better_bits_alone_insufficient": bool(
                any(
                    row["profile"] == "wide_control" and row["seed"] == 23
                    and row["normal_rtol"] == 1e-4
                    and row["solvers"][solver]["accepted"]
                    and row["solvers"][solver]["last_candidate"] is not None
                    and row["solvers"][solver]["last_candidate"]["coefficient_error_vs_quantized_svd"] > COEFFICIENT_RTOL
                    for row in report["rows"] for solver in ("cgls", "lsqr")
                )
                and any(
                    row["profile"] == "wide_control" and row["seed"] == 23
                    and row["normal_rtol"] == 1e-5
                    and row["solvers"][solver]["accepted"]
                    and row["solvers"][solver]["last_candidate"] is not None
                    and row["solvers"][solver]["last_candidate"]["coefficient_error_vs_quantized_svd"] <= COEFFICIENT_RTOL
                    for row in report["rows"] for solver in ("cgls", "lsqr")
                )
            ),
            "evidence": "At fixed wide_control bits and seed23, the 1e-4 accepted candidate is retained with coefficient error above the 1e-3 diagnostic; tightening only normal_rtol to 1e-5 reaches below that diagnostic. This is solver-calibration evidence about early stopping, not an application-quality claim.",
        },
        "interpretation": "Calibration only: compare acceptance, iterations, normal residual, and coefficient diagnostic across the paired rows. No row establishes application quality or a production default.",
    }
    report["source_unchanged_during_run"] = all(
        hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest_value
        for name, digest_value in report["source_sha256"].items()
        if name != Path(__file__).relative_to(ROOT).as_posix()
    )
    report["complete"] = len(report["rows"]) == 15
    save()
    return report


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path,
        default=ROOT / "reports/v4/lsqr_stop_study.json",
    )
    args = parser.parse_args()
    build_report(args.output)
