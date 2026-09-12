"""Float-only basis calibration with unchanged, full application signals.

This compares coefficient-domain encoders, not raw-signal Phi*Psi hardware.
The source windows, measurement shape, LFSR seeds and paired noise directions
are inherited from generated_numeric_study.outer_cases. No signal is made
K-sparse before sensing. Best-K reconstruction is an offline diagnostic only.
"""
from __future__ import annotations

import os
for _variable in ("OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "OMP_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[_variable] = "1"

import argparse
from contextlib import nullcontext
from dataclasses import asdict
from functools import lru_cache
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import sys
import time

import numpy as np
from scipy.fft import dctn, idctn

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4 import recovery, proximal
from models.v4.lfsr_operator import operator_identity
from models.v4.quality import metrics
from scripts.v4.generated_numeric_study import outer_cases, noisy
from scripts.v4.numeric_screen import digest

SOURCE_SEEDS = (23, 47, 101)
CASE_NAMES = ("ecg_window_3600", "ecg_window_7200", "camera_patch_192_240")
BASES = ("dct", "haar", "db4", "sym4")
POLICIES = ("OMP_K32", "SP_K32", "FISTA_lambda0.001", "FISTA_lambda0.003")


def json_ready(value):
    if isinstance(value, np.ndarray):
        return json_ready(value.tolist())
    if isinstance(value, np.generic):
        return json_ready(value.item())
    if isinstance(value, dict):
        return {str(k): json_ready(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [json_ready(v) for v in value]
    if isinstance(value, float) and not math.isfinite(value):
        return "nan" if math.isnan(value) else "inf" if value > 0 else "-inf"
    return value


@lru_cache(maxsize=None)
def source_cases():
    return tuple(outer_cases(SOURCE_SEEDS, True, "lfsr32"))


@lru_cache(maxsize=None)
def basis_transform(basis_name, shape):
    """Return orthonormal analysis/synthesis and a checked transform contract."""
    shape = tuple(shape)
    if basis_name == "dct":
        analysis = lambda value: dctn(np.asarray(value).reshape(shape), norm="ortho").reshape(-1)
        synthesis = lambda value: idctn(np.asarray(value).reshape(shape), norm="ortho").reshape(-1)
        description = {"basis": "DCT-II", "normalization": "ortho", "shape": list(shape)}
    else:
        import pywt
        if basis_name not in BASES:
            raise ValueError("unknown basis")
        wavelet = pywt.Wavelet(basis_name)
        level = min(pywt.dwt_max_level(size, wavelet.dec_len) for size in shape)
        coeffs = pywt.wavedecn(np.zeros(shape), wavelet, mode="periodization", level=level)
        coefficient_array, slices = pywt.coeffs_to_array(coeffs)
        coefficient_shape = coefficient_array.shape
        if coefficient_array.size != math.prod(shape):
            raise ValueError("wavelet must preserve coefficient dimension")
        def analysis(value):
            coeffs = pywt.wavedecn(np.asarray(value).reshape(shape), wavelet,
                                  mode="periodization", level=level)
            return pywt.coeffs_to_array(coeffs)[0].reshape(-1)
        def synthesis(value):
            coeffs = pywt.array_to_coeffs(np.asarray(value).reshape(coefficient_shape),
                                         slices, output_format="wavedecn")
            return pywt.waverecn(coeffs, wavelet, mode="periodization").reshape(-1)
        description = {"basis": basis_name, "wavelet": wavelet.name, "mode": "periodization",
                       "level": level, "shape": list(shape),
                       "coefficient_shape": list(coefficient_shape),
                       "packing": "pywt.coeffs_to_array, C order"}
    eye = np.eye(math.prod(shape))
    analysis_matrix = np.column_stack([analysis(eye[:, i]) for i in range(eye.shape[1])])
    gram_error = float(np.max(np.abs(analysis_matrix.T @ analysis_matrix - eye)))
    closure_error = float(np.max(np.abs(np.column_stack([
        synthesis(analysis_matrix[:, i]) for i in range(eye.shape[1])]) - eye)))
    if gram_error > 1e-10 or closure_error > 1e-10:
        raise ValueError("basis closure/orthogonality failed")
    description.update({"analysis_matrix_sha256": digest(analysis_matrix),
                        "orthogonality_max_abs_error": gram_error,
                        "closure_max_abs_error": closure_error})
    return analysis, synthesis, description


def build_case(case_name: str, basis_name: str) -> dict:
    """Build a paired original application case for float or later fixed checks.

    Returns the usual outer_cases keys a/y/truth/original/restore/mean/scale,
    plus transform and paired-noise provenance. The caller must use full y.
    Names and source seeds are fixed; this API does not select easier samples.
    """
    matching = [(index, case) for index, case in enumerate(source_cases())
                if case["name"] == case_name]
    if len(matching) != 1:
        raise ValueError("unknown case_name")
    index, source = matching[0]
    original = np.asarray(source["original"], dtype=float).copy()
    shape = (16, 16) if case_name.startswith("camera_") else (256,)
    analysis, synthesis, transform = basis_transform(basis_name, shape)
    mean, scale = source["mean"], source["scale"]
    centered = (original - mean) * scale
    truth = analysis(centered)
    a = source["a"].copy()
    noise_seed = int(source["seed"]) + 12345 + index
    noise_direction = np.random.default_rng(noise_seed).normal(size=a.shape[0])
    noise_direction /= np.linalg.norm(noise_direction)
    y = noisy(a @ truth, np.random.default_rng(noise_seed), 30)
    def restore(value):
        return synthesis(value) / scale + mean
    reconstruction_error = float(np.max(np.abs(restore(truth) - original)))
    if reconstruction_error > 1e-10:
        raise ValueError("original reconstruction closure failed")
    dct_match = None
    if basis_name == "dct":
        dct_match = {"truth_max_abs_difference": float(np.max(np.abs(truth - source["truth"]))),
                     "measurement_max_abs_difference": float(np.max(np.abs(y - source["y"])))}
        if max(dct_match.values()) > 1e-12:
            raise ValueError("DCT case changed from existing source")
    return {**source, "name": case_name + "__" + basis_name, "source_case": case_name,
            "basis_name": basis_name, "a": a, "y": y, "truth": truth,
            "original": original, "restore": restore, "k": 32,
            "track": "coefficient_domain_encoder_" + basis_name + "_not_raw_signal_PhiPsi",
            "source": {**source["source"], "original_sha256": digest(original)},
            "transform": transform,
            "paired_noise": {"seed": noise_seed, "direction_sha256": digest(noise_direction),
                             "measurement_snr_db": 30,
                             "amplitude": "scaled to 30 dB using this basis's clean measurement norm",
                             "same_direction_across_bases": True},
            "input_sha256": {"a": digest(a), "y": digest(y), "truth": digest(truth),
                             "original": digest(original)},
            "original_reconstruction_max_abs_error": reconstruction_error,
            "existing_dct_case_match": dct_match}


def quality(case, estimate):
    restored = case["restore"](estimate)
    return {"original": metrics(case["original"], restored),
            "centered": metrics(case["original"] - case["mean"], restored - case["mean"]),
            "coefficient": metrics(case["truth"], estimate)}


def policy_for(case, label):
    step = .9 / float(np.linalg.norm(case["a"], 2) ** 2)
    if label in ("OMP_K32", "SP_K32"):
        return recovery.Policy(sparsity=32, max_iterations=32 if label.startswith("OMP") else 256,
                               residual_atol=1e-6, step_size=step,
                               ls_max_iterations=128, ls_normal_rtol=1e-5)
    regularization = {"FISTA_lambda0.001": .001, "FISTA_lambda0.003": .003}[label]
    return proximal.Policy(regularization=regularization, max_iterations=256, step_size=step,
                           pd_sigma=.9, admm_rho=1, inner_max_iterations=128, inner_rtol=1e-4)


def run_one(case, label):
    policy = policy_for(case, label)
    algorithm = label.split("_")[0]
    started = time.perf_counter()
    row = {"case": case["source_case"], "basis": case["basis_name"],
           "algorithm": algorithm, "policy_id": label, "policy": asdict(policy)}
    try:
        result = (recovery.run(algorithm, case["a"], case["y"], policy)
                  if algorithm in recovery.ALGORITHMS
                  else proximal.run(algorithm, case["a"], case["y"], policy))
        no_fault = not any(result.events.values()) and not any(t.get("phase") == "FAULT" for t in result.trace)
        q = quality(case, result.x)
        row.update({"status": result.status, "events": result.events, "trace": result.trace,
                    "support": result.support, "x": result.x, "x_sha256": digest(result.x),
                    "quality": q, "residual_norm": float(np.linalg.norm(result.residual)),
                    "returned_without_numeric_fault": no_fault,
                    "original_snr20_pass": bool(no_fault and q["original"]["snr_db"] >= 20),
                    "centered_snr20_diagnostic_pass": bool(no_fault and q["centered"]["snr_db"] >= 20)})
    except Exception as exc:
        row.update({"exception": {"type": type(exc).__name__, "message": str(exc)},
                    "status": "exception", "returned_without_numeric_fault": False,
                    "original_snr20_pass": False, "centered_snr20_diagnostic_pass": False})
    row["elapsed_seconds"] = time.perf_counter() - started
    return row


def source_hashes():
    paths = sorted((ROOT / "models/v4").glob("*.py")) + [Path(__file__),
        ROOT / "scripts/v4/generated_numeric_study.py", ROOT / "scripts/v4/numeric_screen.py"]
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/v4/lfsr_basis_feasibility.json")
    args = parser.parse_args()
    before = source_hashes()
    report = {"complete": False, "source_sha256": before, "python": platform.python_version(),
              "packages": {name: importlib.metadata.version(name) for name in ("numpy", "scipy", "scikit-image", "PyWavelets")},
              "policy": {"purpose": "float-only calibration basis feasibility; not held-out or hardware qualification",
                         "cases_predeclared": CASE_NAMES, "bases_predeclared": BASES,
                         "policies_predeclared": POLICIES, "source_seeds": SOURCE_SEEDS,
                         "M": 128, "N": 256, "K_max": 32, "S_max": 96,
                         "measurement_domain": "full transform coefficients; basis changes sensing protocol",
                         "raw_signal_PhiPsi_hardware_executed": False,
                         "sparsify_before_measurement": False,
                         "best_k_is_offline_diagnostic_not_runtime_oracle": True,
                         "absolute_original_snr_min_db": 20, "all_failures_retained": True,
                         "bounded_iterations_not_convergence_proof": True, "blas_threads": 1},
              "cases": [], "best_k_diagnostics": [], "rows": []}
    def save():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(json_ready(report), indent=2) + "\n", encoding="utf-8")
    with nullcontext():
        for name in CASE_NAMES:
            for basis in BASES:
                try:
                    case = build_case(name, basis)
                except Exception as exc:
                    report["cases"].append({"source_case": name, "basis": basis,
                        "exception": {"type": type(exc).__name__, "message": str(exc)}})
                    save()
                    continue
                report["cases"].append({key: value for key, value in case.items()
                    if key not in ("restore", "a", "y", "truth", "original")})
                case_record = report["cases"][-1]
                case_record["operator"] = operator_identity(case["seed"], 128, 256, 1 / math.sqrt(128))
                case_record["inputs"] = {key: case[key] for key in ("y", "truth", "original")}
                for k in (16, 24, 32):
                    indices = recovery.rank(case["truth"], k)
                    estimate = np.zeros(256)
                    estimate[indices] = case["truth"][indices]
                    report["best_k_diagnostics"].append({"case": name, "basis": basis, "k": k,
                         "quality": quality(case, estimate), "support": indices,
                         "scope": "best-K original coefficients; no measurements or runtime oracle changed"})
                for label in POLICIES:
                    row = run_one(case, label)
                    report["rows"].append(row)
                    q = row.get("quality", {}).get("original", {}).get("snr_db", float("nan"))
                    print(name, basis, label, row["status"], f"SNR={q:.4f}", flush=True)
                    save()
    report["source_unchanged_during_run"] = source_hashes() == before
    report["complete"] = report["source_unchanged_during_run"] and len(report["cases"]) == len(CASE_NAMES) * len(BASES)
    report["summary"] = {"rows": len(report["rows"]),
                         "original_snr20_pass_count": sum(row["original_snr20_pass"] for row in report["rows"]),
                         "centered_snr20_diagnostic_pass_count": sum(row["centered_snr20_diagnostic_pass"] for row in report["rows"])}
    save()


if __name__ == "__main__":
    main()
