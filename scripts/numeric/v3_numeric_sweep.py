#!/usr/bin/env python3
"""Deterministic fixed-point width sweep for the v3 CGRA numeric contract.

This is an architecture study, not the golden algorithm model.  It exercises
the matrix-free ordinary/regularized PCG solve used by OMP/HTP/GOMP (d=32),
SP (d=64) and CoSaMP (d=96), records fixed-point saturation/overflow, and
checks the analytic accumulator envelope used by the certified production
profile.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class Profile:
    name: str
    data_w: int
    data_f: int
    solver_w: int
    solver_f: int
    acc_w: int


@dataclass
class Events:
    data_saturation: int = 0
    solver_saturation: int = 0
    acc_overflow: int = 0
    max_abs_data_raw: int = 0
    max_abs_solver_raw: int = 0
    max_abs_acc_raw: int = 0


PROFILES = (
    # Range-preserving precision ladder: DATA remains Q3.*, SOLVER Q7.*.
    Profile("D16F12_S24F16_A56", 16, 12, 24, 16, 56),
    Profile("D16F12_S26F18_A60", 16, 12, 26, 18, 60),
    Profile("D16F12_S28F20_A64", 16, 12, 28, 20, 64),
    Profile("D17F13_S24F16_A56", 17, 13, 24, 16, 56),
    Profile("D17F13_S26F18_A60", 17, 13, 26, 18, 60),
    Profile("D17F13_S28F20_A64", 17, 13, 28, 20, 64),
    Profile("D18F14_S24F16_A56", 18, 14, 24, 16, 56),
    Profile("D18F14_S26F18_A60", 18, 14, 26, 18, 60),
    Profile("D18F14_S27F19_A62", 18, 14, 27, 19, 62),
    Profile("D18F14_S28F20_A48", 18, 14, 28, 20, 48),
    Profile("D18F14_S28F20_A56", 18, 14, 28, 20, 56),
    Profile("D18F14_S28F20_A64", 18, 14, 28, 20, 64),
    Profile("D18F14_S32F24_A56", 18, 14, 32, 24, 56),
    Profile("D18F14_S32F24_A64", 18, 14, 32, 24, 64),
    Profile("D18F14_S32F24_A70", 18, 14, 32, 24, 70),
    Profile("D18F14_S32F24_A72", 18, 14, 32, 24, 72),
    Profile("D20F16_S32F24_A64", 20, 16, 32, 24, 64),
    Profile("D20F16_S32F24_A72", 20, 16, 32, 24, 72),
    Profile("D24F16_S40F28_A64", 24, 16, 40, 28, 64),
)

M = 128
N = 1024
K = 32
PHI_SCALE = 1.0 / 8.0
X_LIMIT = 0.75
LAMBDA = 1.0 / 1024.0
MAX_ITER = 128
REL_RESIDUAL_LIMIT = 2.0**-14
# Individual coefficients are not a stable acceptance metric for deliberately
# near-correlated columns.  Gate coefficient error on random cases, and gate
# correlated cases by normal residual plus Top-K agreement.
RANDOM_REL_ERROR_LIMIT = 2.0**-8
MIN_ACC_HEADROOM_BITS = 2.0


def round_div_away(num: int, den: int) -> int:
    if den == 0:
        raise ZeroDivisionError("fixed-point denominator is zero")
    neg = (num < 0) ^ (den < 0)
    a, b = abs(num), abs(den)
    q = (a + b // 2) // b
    return -q if neg else q


def round_shift_away(values: np.ndarray, shift: int) -> np.ndarray:
    if shift == 0:
        return values.astype(np.int64, copy=False)
    half = 1 << (shift - 1)
    values = values.astype(np.int64, copy=False)
    return np.where(values >= 0, (values + half) >> shift,
                    -(((-values) + half) >> shift)).astype(np.int64)


def quantize(values: np.ndarray, width: int, frac: int, kind: str,
             events: Events) -> np.ndarray:
    scaled = np.sign(values) * np.floor(np.abs(values) * (1 << frac) + 0.5)
    return saturate(scaled.astype(np.int64), width, kind, events)


def saturate(values: np.ndarray, width: int, kind: str,
             events: Events) -> np.ndarray:
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    values = values.astype(np.int64, copy=False)
    count = int(np.count_nonzero((values < lo) | (values > hi)))
    max_abs = int(np.max(np.abs(values))) if values.size else 0
    if kind == "data":
        events.data_saturation += count
        events.max_abs_data_raw = max(events.max_abs_data_raw, max_abs)
    else:
        events.solver_saturation += count
        events.max_abs_solver_raw = max(events.max_abs_solver_raw, max_abs)
    return np.clip(values, lo, hi).astype(np.int64)


def check_acc(values: np.ndarray | list[int] | int, width: int,
              events: Events) -> None:
    if isinstance(values, np.ndarray):
        vals = [int(v) for v in values.ravel()]
    elif isinstance(values, list):
        vals = values
    else:
        vals = [int(values)]
    if not vals:
        return
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    events.acc_overflow += sum(v < lo or v > hi for v in vals)
    events.max_abs_acc_raw = max(events.max_abs_acc_raw,
                                 max(abs(v) for v in vals))


def qmul(a: np.ndarray, b: np.ndarray | int, profile: Profile,
         events: Events) -> np.ndarray:
    raw = a.astype(np.int64) * np.asarray(b, dtype=np.int64)
    check_acc(raw, profile.acc_w, events)
    shifted = round_shift_away(raw, profile.solver_f)
    return saturate(shifted, profile.solver_w, "solver", events)


def qdiv_same(num: int, den: int, profile: Profile, events: Events) -> int:
    value = round_div_away(num << profile.solver_f, den)
    return int(saturate(np.asarray([value]), profile.solver_w,
                        "solver", events)[0])


def solver_div(a: np.ndarray, den: int, profile: Profile,
               events: Events) -> np.ndarray:
    values = np.asarray(
        [round_div_away(int(v) << profile.solver_f, den) for v in a],
        dtype=np.int64,
    )
    return saturate(values, profile.solver_w, "solver", events)


def dot(a: np.ndarray, b: np.ndarray, profile: Profile,
        events: Events) -> int:
    value = sum(int(x) * int(y) for x, y in zip(a, b))
    check_acc(value, profile.acc_w, events)
    return value


def apply_a(phi_q: np.ndarray, p: np.ndarray, lambda_q: int,
            profile: Profile, events: Events) -> np.ndarray:
    # DATA(Fd) x SOLVER(Fs), accumulated raw at Fd+Fs, returned at Fs.
    t_raw = phi_q.astype(np.int64) @ p.astype(np.int64)
    check_acc(t_raw, profile.acc_w, events)
    t = saturate(round_shift_away(t_raw, profile.data_f),
                 profile.solver_w, "solver", events)
    q_raw = phi_q.astype(np.int64).T @ t
    check_acc(q_raw, profile.acc_w, events)
    q = saturate(round_shift_away(q_raw, profile.data_f),
                 profile.solver_w, "solver", events)
    regularization = qmul(p, lambda_q, profile, events)
    return saturate(q + regularization, profile.solver_w, "solver", events)


def phi_transpose_y(phi_q: np.ndarray, y_q: np.ndarray, profile: Profile,
                    events: Events) -> np.ndarray:
    # Convert DATA y to SOLVER before the matrix-free Phi^T pass.
    shift = profile.solver_f - profile.data_f
    y_s = saturate(y_q.astype(np.int64) << shift, profile.solver_w,
                   "solver", events)
    raw = phi_q.astype(np.int64).T @ y_s
    check_acc(raw, profile.acc_w, events)
    return saturate(round_shift_away(raw, profile.data_f),
                    profile.solver_w, "solver", events)


def pcg(phi_q: np.ndarray, y_q: np.ndarray, profile: Profile,
        events: Events) -> tuple[np.ndarray, int, float, str, float]:
    scale_d = float(1 << profile.data_f)
    scale_s = float(1 << profile.solver_f)
    lambda_q = int(round(LAMBDA * scale_s))
    b = phi_transpose_y(phi_q, y_q, profile, events)
    x = np.zeros(phi_q.shape[1], dtype=np.int64)
    r = b.copy()
    # Jacobi preconditioner; Bernoulli columns have a constant exact norm.
    diag = phi_q[:, 0].astype(np.int64)
    diag_raw = sum(int(v) * int(v) for v in diag)
    diag_q = round_div_away(diag_raw << profile.solver_f,
                            1 << (2 * profile.data_f)) + lambda_q
    z = solver_div(r, diag_q, profile, events)
    p = z.copy()
    rz = dot(r, z, profile, events)
    b_norm = max(np.linalg.norm(b.astype(np.float64) / scale_s), 1e-30)
    reason = "max_iter"
    iterations = 0
    for iterations in range(1, MAX_ITER + 1):
        q = apply_a(phi_q, p, lambda_q, profile, events)
        pq = dot(p, q, profile, events)
        if pq <= 0 or rz <= 0:
            reason = "breakdown"
            break
        alpha = qdiv_same(rz, pq, profile, events)
        x = saturate(x + qmul(p, alpha, profile, events),
                     profile.solver_w, "solver", events)
        r = saturate(r - qmul(q, alpha, profile, events),
                     profile.solver_w, "solver", events)
        rel_residual = float(np.linalg.norm(r.astype(np.float64) / scale_s) /
                             b_norm)
        if rel_residual <= REL_RESIDUAL_LIMIT:
            reason = "converged"
            break
        z = solver_div(r, diag_q, profile, events)
        rz_new = dot(r, z, profile, events)
        if rz_new <= 0:
            reason = "breakdown"
            break
        beta = qdiv_same(rz_new, rz, profile, events)
        p = saturate(z + qmul(p, beta, profile, events),
                     profile.solver_w, "solver", events)
        rz = rz_new

    phi_f = phi_q.astype(np.float64) / scale_d
    y_f = y_q.astype(np.float64) / scale_d
    ref = np.linalg.solve(phi_f.T @ phi_f + LAMBDA * np.eye(phi_q.shape[1]),
                          phi_f.T @ y_f)
    got = x.astype(np.float64) / scale_s
    rel_error = float(np.linalg.norm(got - ref) /
                      max(np.linalg.norm(ref), 1e-30))
    normal_resid = float(np.linalg.norm(
        (phi_f.T @ phi_f + LAMBDA * np.eye(phi_q.shape[1])) @ got -
        phi_f.T @ y_f) / max(np.linalg.norm(phi_f.T @ y_f), 1e-30))
    return got, iterations, rel_error, reason, normal_resid


def make_case(seed: int, d: int, correlated: bool) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed + d * 1009 + (100_000 if correlated else 0))
    phi = rng.choice(np.asarray([-PHI_SCALE, PHI_SCALE]), size=(M, d))
    if correlated and d >= 64:
        # Stress low-margin solve and prune decisions without making A singular.
        pairs = min(8, d - K)
        for j in range(pairs):
            phi[:, K + j] = phi[:, j]
            flips = rng.choice(M, size=2, replace=False)
            phi[flips, K + j] *= -1.0
    x_true = np.zeros(d)
    magnitudes = rng.uniform(0.25, X_LIMIT, size=K)
    signs = rng.choice(np.asarray([-1.0, 1.0]), size=K)
    x_true[:K] = magnitudes * signs
    rng.shuffle(x_true)
    y = phi @ x_true
    noise_rms = np.linalg.norm(y) / math.sqrt(M) * 10.0**(-50.0 / 20.0)
    y += rng.normal(0.0, noise_rms, size=M)
    return phi, y, x_true


def top_indices(values: np.ndarray, count: int) -> list[int]:
    indices = np.arange(values.size)
    return [int(i) for i in np.lexsort((indices, -np.abs(values)))[:count]]


def run_profile(profile: Profile, seeds: int) -> dict:
    all_cases = []
    totals = Events()
    for d in (32, 64, 96):
        for correlated in (False, True):
            if correlated and d == 32:
                continue
            for seed in range(seeds):
                events = Events()
                phi, y, _ = make_case(seed, d, correlated)
                phi_q = quantize(phi, profile.data_w, profile.data_f,
                                 "data", events)
                y_q = quantize(y, profile.data_w, profile.data_f,
                               "data", events)
                got, iterations, rel_error, reason, normal_resid = pcg(
                    phi_q, y_q, profile, events)
                phi_f = phi_q.astype(np.float64) / (1 << profile.data_f)
                y_f = y_q.astype(np.float64) / (1 << profile.data_f)
                ref = np.linalg.solve(
                    phi_f.T @ phi_f + LAMBDA * np.eye(d), phi_f.T @ y_f)
                overlap = len(set(top_indices(got, min(K, d))) &
                              set(top_indices(ref, min(K, d))))
                all_cases.append({
                    "d": d,
                    "kind": "correlated" if correlated else "random",
                    "seed": seed,
                    "iterations": iterations,
                    "reason": reason,
                    "relative_solution_error": rel_error,
                    "normal_residual": normal_resid,
                    "top32_overlap": overlap,
                    "events": asdict(events),
                })
                for field in ("data_saturation", "solver_saturation", "acc_overflow"):
                    setattr(totals, field, getattr(totals, field) + getattr(events, field))
                for field in ("max_abs_data_raw", "max_abs_solver_raw", "max_abs_acc_raw"):
                    setattr(totals, field, max(getattr(totals, field), getattr(events, field)))

    errors = [c["relative_solution_error"] for c in all_cases]
    random_errors = [c["relative_solution_error"] for c in all_cases
                     if c["kind"] == "random"]
    residuals = [c["normal_residual"] for c in all_cases]
    iterations = [c["iterations"] for c in all_cases]
    overlaps = [c["top32_overlap"] for c in all_cases if c["d"] > K]
    converged = sum(c["reason"] == "converged" for c in all_cases)
    numerical_pass = (
        converged == len(all_cases)
        and max(random_errors) <= RANDOM_REL_ERROR_LIMIT
        and max(residuals) <= REL_RESIDUAL_LIMIT * 2
        and (min(overlaps) if overlaps else K) >= K - 1
        and totals.data_saturation == 0
        and totals.solver_saturation == 0
        and totals.acc_overflow == 0
    )
    return {
        "profile": asdict(profile),
        "summary": {
            "cases": len(all_cases),
            "converged": converged,
            "max_iterations": max(iterations),
            "median_iterations": float(np.median(iterations)),
            "max_relative_solution_error": max(errors),
            "max_random_relative_solution_error": max(random_errors),
            "max_normal_residual": max(residuals),
            "min_top32_overlap": min(overlaps) if overlaps else K,
            "events": asdict(totals),
            "numerical_pass": numerical_pass,
        },
        "cases": all_cases,
    }


def analytic_bounds(profile: Profile) -> dict:
    data_limit_raw = int(round(X_LIMIT * (1 << profile.data_f)))
    phi_raw = int(round(PHI_SCALE * (1 << profile.data_f)))
    y_abs = K * PHI_SCALE * X_LIMIT
    residual_abs = 2.0 * y_abs
    corr_abs = M * PHI_SCALE * residual_abs
    solver_raw_max = (1 << (profile.solver_w - 1)) - 1
    solver_abs_max = solver_raw_max / float(1 << profile.solver_f)
    solver_dot_raw = 96 * solver_raw_max * solver_raw_max
    acc_max = (1 << (profile.acc_w - 1)) - 1
    headroom_bits = math.log2(acc_max / solver_dot_raw)
    return {
        "production_input": {
            "phi_abs": PHI_SCALE,
            "x_abs_max": X_LIMIT,
            "y_abs_bound": y_abs,
            "residual_abs_bound": residual_abs,
            "correlation_abs_bound": corr_abs,
            "data_limit_raw": data_limit_raw,
            "phi_raw": phi_raw,
        },
        "solver_dot_d96": {
            "operand_abs_max": solver_abs_max,
            "required_raw_abs": solver_dot_raw,
            "acc_positive_max": acc_max,
            "headroom_bits": headroom_bits,
            "minimum_headroom_bits": MIN_ACC_HEADROOM_BITS,
            "fits": solver_dot_raw <= acc_max,
            "pass": headroom_bits >= MIN_ACC_HEADROOM_BITS,
        },
    }


def markdown(result: dict) -> str:
    lines = [
        "# v3 numerical width sweep",
        "",
        "Generated by `scripts/numeric/v3_numeric_sweep.py`.",
        "",
        "## Locked production contract",
        "",
        "- `DATA_W=18`, `DATA_F=14` (signed Q3.14, range -8 to 7.99994).",
        "- `SOLVER_W=28`, `SOLVER_F=20` (signed Q7.20, range -128 to 127.999999).",
        "- `ACC_W=64`; accumulator binary point is opcode/context dependent.",
        "- Round to nearest, ties away from zero; signed saturation on narrowing.",
        "- Certified normalization: `|Phi|=1/8`, `|x_i|<=0.75`, `K<=32`,",
        "  hence `|y|<=3`, conservative `|residual|<=6`, and `|Phi^T r|<=96`.",
        "- ACC64 covers a d=96 dot product over the complete non-saturated",
        "  Q7.20 solver range with at least two bits of positive headroom.",
        "",
        "## Sweep matrix",
        "",
        f"- N={N}, M={M}, K={K}; matrix-free "
        f'{"ordinary" if LAMBDA == 0 else "regularized"} PCG at d=32/64/96.',
        f"- Lambda={LAMBDA:g}; random and near-correlated support matrices; 50 dB noise.",
        f"- Acceptance: all cases converge; random-case relative error <= {RANDOM_REL_ERROR_LIMIT:g};",
        f"  all-case normal residual <= {REL_RESIDUAL_LIMIT * 2:g}; Top-32 overlap >=31/32;",
        "  and zero data/solver/accumulator overflow.",
        "",
        "## Results",
        "",
        "| Profile | Numeric | Bound | Eligible | Cases | Conv. | Max iter | Max random error | Max all error | Max normal residual | Min Top32 | Data sat | Solver sat | ACC ovf |",
        "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for entry in result["profiles"]:
        p = entry["profile"]
        s = entry["summary"]
        e = s["events"]
        label = f'D{p["data_w"]}F{p["data_f"]}/S{p["solver_w"]}F{p["solver_f"]}/A{p["acc_w"]}'
        bound_pass = entry["analytic_bounds"]["solver_dot_d96"]["pass"]
        lines.append(
            f'| {label} | {"PASS" if s["numerical_pass"] else "FAIL"} | '
            f'{"PASS" if bound_pass else "FAIL"} | '
            f'{"YES" if entry["production_eligible"] else "NO"} | '
            f'{s["cases"]} | {s["converged"]} | {s["max_iterations"]} | '
            f'{s["max_random_relative_solution_error"]:.3e} | '
            f'{s["max_relative_solution_error"]:.3e} | {s["max_normal_residual"]:.3e} | '
            f'{s["min_top32_overlap"]} | {e["data_saturation"]} | '
            f'{e["solver_saturation"]} | {e["acc_overflow"]} |'
        )
    locked = next((p for p in result["profiles"]
                   if p["profile"]["name"] == "D18F14_S28F20_A64"), None)
    if locked is not None:
        bound = locked["analytic_bounds"]["solver_dot_d96"]
        lines += [
            "",
            "## Current baseline context",
            "",
            "The current baseline profile uses the 18-bit PE data path that preserves a",
            "single DSP48E2-friendly operand width. S28 crosses the DSP48E2 27-bit",
            "operand boundary and therefore requires explicit decomposition; exact",
            "cycle/DSP cost must be measured in OOC synthesis. S28 still reduces solver",
            "state by 12.5% versus S32 and permits ACC64 instead of ACC72. At d=96 over the complete",
            f'Q7.20 range, the raw Q40 dot-product bound is `{bound["required_raw_abs"]}`;',
            f' ACC64 provides `{bound["headroom_bits"]:.2f}` bits of signed-positive headroom.',
            "A56 fails this certified bound even if a finite random sample happens not",
            "to overflow. S32F24/A72 remains the optional high-precision debug profile.",
        ]
    lines += [
        "",
        "This sweep validates the LS/PCG numeric kernel used at work dimensions",
        "32, 64 and 96. It does not replace the later bit-exact end-to-end golden",
        "regression for all eight algorithms or FPGA synthesis/timing sign-off.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    global LAMBDA
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=6)
    parser.add_argument("--lambda-value", type=float, default=LAMBDA,
                        help="LS regularization; use 0 for paper-equivalent ordinary LS")
    parser.add_argument("--out-dir", type=Path,
                        default=Path("reports/v3/numeric_width_sweep"))
    parser.add_argument(
        "--profiles", nargs="*", metavar="NAME",
        help="optional profile-name subset; defaults to the complete sweep",
    )
    args = parser.parse_args()
    LAMBDA = args.lambda_value
    by_name = {profile.name: profile for profile in PROFILES}
    unknown = sorted(set(args.profiles or ()) - set(by_name))
    if unknown:
        parser.error("unknown profile(s): " + ", ".join(unknown))
    selected_profiles = ([by_name[name] for name in args.profiles]
                         if args.profiles else list(PROFILES))
    result = {
        "schema": 1,
        "constants": {
            "N": N, "M": M, "K": K, "dimensions": [32, 64, 96],
            "phi_scale": PHI_SCALE, "x_limit": X_LIMIT,
            "minimum_acc_headroom_bits": MIN_ACC_HEADROOM_BITS, "lambda": LAMBDA,
            "max_iter": MAX_ITER, "seeds": args.seeds,
            "rounding": "round-to-nearest-ties-away-from-zero",
            "narrowing": "signed-saturating",
        },
        "profiles": [],
    }
    for profile in selected_profiles:
        entry = run_profile(profile, args.seeds)
        entry["analytic_bounds"] = analytic_bounds(profile)
        entry["production_eligible"] = bool(
            entry["summary"]["numerical_pass"]
            and entry["analytic_bounds"]["solver_dot_d96"]["pass"]
        )
        result["profiles"].append(entry)
        s = entry["summary"]
        print(profile.name, "PASS" if s["numerical_pass"] else "FAIL",
              f'{s["converged"]}/{s["cases"]}',
              f'err={s["max_relative_solution_error"]:.3e}',
              f'acc_ovf={s["events"]["acc_overflow"]}')
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "results.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (args.out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")


if __name__ == "__main__":
    main()
