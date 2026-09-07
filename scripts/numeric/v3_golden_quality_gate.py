#!/usr/bin/env python3
"""Validate v3 fixed-point goldens against independent numeric quality gates."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import platform
import sys

import numpy as np
import pywt
from scipy import datasets
from scipy.fft import dctn, idctn
import scipy
from skimage import data
import skimage


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, paper, phi_generator
from scripts.golden.generate_v3_phase_golden import suite


ALGORITHMS = tuple(paper.ALGORITHMS)
PROFILE = hardware.NumericProfile()
REFINEMENT = hardware.RefinementPolicy(profile="strict_paper")
N = 64
M = 32
K = 8
PHI_SEED = 37
APPLICATION_SNR_GAP_MAX_DB = 0.5
APPLICATION_MSE_RATIO_MAX = 1.10
MRI_ORACLE_SNR_MIN_DB = 20.0
MRI_ORACLE_PSNR_MIN_DB = 30.0
MRI_ORACLE_MSE_MAX = 5.0e-4
ECG_ORACLE_SNR_MIN_DB = 18.0
ECG_ORACLE_MSE_MAX = 5.0e-3
ECG_WAVELET = "db4"
ECG_WAVELET_LEVEL = 3


def sha256_array(values: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(values).tobytes()).hexdigest()


def mse(reference: np.ndarray, estimate: np.ndarray) -> float:
    error = np.asarray(reference, dtype=np.float64) - np.asarray(
        estimate, dtype=np.float64)
    return float(np.mean(error * error))


def snr_db(reference: np.ndarray, estimate: np.ndarray) -> float:
    reference = np.asarray(reference, dtype=np.float64)
    estimate = np.asarray(estimate, dtype=np.float64)
    signal_energy = float(np.sum(reference * reference))
    error_energy = float(np.sum((reference - estimate) ** 2))
    if error_energy == 0.0:
        return math.inf
    if signal_energy == 0.0:
        return -math.inf
    return 10.0 * math.log10(signal_energy / error_energy)


def finite_metric(value: float) -> float | str:
    if math.isinf(value):
        return "inf" if value > 0 else "-inf"
    return value


def psnr_db(reference: np.ndarray, estimate: np.ndarray, data_range: float) -> float:
    error = mse(reference, estimate)
    return math.inf if error == 0.0 else 10.0 * math.log10(data_range * data_range / error)


def policy_for(phi: np.ndarray) -> paper.Policy:
    spectral_sq = float(np.linalg.norm(phi, ord=2) ** 2)
    return paper.Policy(
        sparsity=K,
        max_iterations=K,
        residual_atol=2.0**-14,
        step_size=0.9 / spectral_sq,
        group_size=2,
    )


def topk_sparse(values: np.ndarray) -> np.ndarray:
    flattened = np.asarray(values, dtype=np.float64).reshape(-1)
    indices = np.arange(flattened.size)
    selected = np.lexsort((indices, -np.abs(flattened)))[:K]
    sparse = np.zeros_like(flattened)
    sparse[selected] = flattened[selected]
    return sparse


def mri_dct_forward(signal: np.ndarray) -> np.ndarray:
    return dctn(np.asarray(signal, dtype=np.float64).reshape(8, 8),
                norm="ortho").reshape(-1)


def mri_dct_inverse(coefficients: np.ndarray) -> np.ndarray:
    return idctn(np.asarray(coefficients, dtype=np.float64).reshape(8, 8),
                 norm="ortho").reshape(-1)


def ecg_wavelet_forward(signal: np.ndarray) -> np.ndarray:
    coefficients = pywt.wavedec(
        np.asarray(signal, dtype=np.float64).reshape(-1), ECG_WAVELET,
        mode="periodization", level=ECG_WAVELET_LEVEL)
    array, _ = pywt.coeffs_to_array(coefficients)
    if array.size != N:
        raise ValueError(f"unexpected ECG wavelet coefficient count {array.size}")
    return array


def ecg_wavelet_inverse(coefficients: np.ndarray) -> np.ndarray:
    template = pywt.wavedec(
        np.zeros(N, dtype=np.float64), ECG_WAVELET,
        mode="periodization", level=ECG_WAVELET_LEVEL)
    _, coefficient_slices = pywt.coeffs_to_array(template)
    structured = pywt.array_to_coeffs(
        np.asarray(coefficients, dtype=np.float64), coefficient_slices,
        output_format="wavedec")
    return pywt.waverec(
        structured, ECG_WAVELET, mode="periodization")[:N]


def run_reconstruction(
    phi: np.ndarray,
    sparse_target: np.ndarray,
    original_signal: np.ndarray,
    inverse_transform,
) -> dict[str, dict]:
    measurement = phi @ sparse_target
    policy = policy_for(phi)
    records = {}
    for algorithm in ALGORITHMS:
        floating = paper.run(algorithm, phi, measurement, policy)
        fixed = hardware.run(
            algorithm, phi, measurement, policy, PROFILE, REFINEMENT)
        floating_x = np.asarray(floating.x, dtype=np.float64)
        fixed_x = np.asarray(fixed.x, dtype=np.float64) / (1 << PROFILE.data_f)
        floating_signal = inverse_transform(floating_x)
        fixed_signal = inverse_transform(fixed_x)
        floating_mse = mse(original_signal, floating_signal)
        fixed_mse = mse(original_signal, fixed_signal)
        fixed_float_snr = snr_db(floating_x, fixed_x)
        floating_application_snr = snr_db(original_signal, floating_signal)
        fixed_application_snr = snr_db(original_signal, fixed_signal)
        application_snr_gap = floating_application_snr - fixed_application_snr
        if floating_mse == 0.0:
            application_mse_ratio = 1.0 if fixed_mse == 0.0 else math.inf
        else:
            application_mse_ratio = fixed_mse / floating_mse
        events = asdict(fixed.events)
        passed = (
            not any(events.values())
            and application_snr_gap <= APPLICATION_SNR_GAP_MAX_DB
            and application_mse_ratio <= APPLICATION_MSE_RATIO_MAX
        )
        records[algorithm] = {
            "pass": passed,
            "support_match": fixed.support == floating.support,
            "floating_support": list(floating.support),
            "fixed_support": list(fixed.support),
            "fixed_vs_float_mse": mse(floating_x, fixed_x),
            "fixed_vs_float_snr_db": finite_metric(fixed_float_snr),
            "target_snr_float_db": finite_metric(snr_db(sparse_target, floating_x)),
            "target_snr_fixed_db": finite_metric(snr_db(sparse_target, fixed_x)),
            "application_mse_float": floating_mse,
            "application_mse_fixed": fixed_mse,
            "application_mse_ratio_fixed_over_float": finite_metric(
                application_mse_ratio),
            "application_snr_float_db": finite_metric(floating_application_snr),
            "application_snr_fixed_db": finite_metric(fixed_application_snr),
            "application_snr_gap_db": finite_metric(application_snr_gap),
            "events": events,
        }
    return records


def high_variance_blocks(
    image_stack: np.ndarray, count: int
) -> list[tuple[str, np.ndarray]]:
    candidates = []
    for slice_index, image in enumerate(image_stack):
        normalized = image.astype(np.float64)
        maximum = float(np.max(normalized))
        if maximum > 0.0:
            normalized /= maximum
        normalized -= 0.5
        for row in range(0, normalized.shape[0] - 7, 8):
            for column in range(0, normalized.shape[1] - 7, 8):
                block = normalized[row:row + 8, column:column + 8]
                candidates.append((float(np.var(block)), slice_index, row,
                                   column, block.copy()))
    candidates.sort(key=lambda item: (-item[0], item[1], item[2], item[3]))
    return [
        (f"slice{slice_index}_r{row}_c{column}", block)
        for _, slice_index, row, column, block in candidates[:count]
    ]


def high_variance_segments(
    signal: np.ndarray, count: int
) -> list[tuple[str, np.ndarray]]:
    candidates = []
    for start in range(0, len(signal) - N + 1, N):
        segment = np.asarray(signal[start:start + N], dtype=np.float64)
        centered = segment - float(np.mean(segment))
        scale = float(np.max(np.abs(centered)))
        if scale == 0.0:
            continue
        normalized = centered * (0.75 / scale)
        candidates.append((float(np.var(normalized)), start, normalized))
    candidates.sort(key=lambda item: (-item[0], item[1]))
    return [
        (f"sample{start}", segment.copy())
        for _, start, segment in candidates[:count]
    ]


def oracle_application_quality(
    image_stack: np.ndarray, ecg: np.ndarray
) -> dict:
    brain = image_stack[5].astype(np.float64)
    brain /= max(float(np.max(brain)), 1.0)
    brain_reconstructed = np.zeros_like(brain)
    for row in range(0, brain.shape[0], 8):
        for column in range(0, brain.shape[1], 8):
            block = brain[row:row + 8, column:column + 8]
            sparse = topk_sparse(mri_dct_forward(block))
            brain_reconstructed[row:row + 8, column:column + 8] = (
                mri_dct_inverse(sparse).reshape(8, 8))
    brain_mse = mse(brain, brain_reconstructed)
    brain_snr = snr_db(brain, brain_reconstructed)
    brain_psnr = psnr_db(brain, brain_reconstructed, 1.0)

    usable = (len(ecg) // N) * N
    ecg_reference = np.asarray(ecg[:usable], dtype=np.float64)
    ecg_reconstructed = np.zeros_like(ecg_reference)
    for start in range(0, usable, N):
        segment = ecg_reference[start:start + N]
        mean = float(np.mean(segment))
        centered = segment - mean
        peak = float(np.max(np.abs(centered)))
        scale = 0.75 / peak if peak > 0.0 else 1.0
        sparse = topk_sparse(ecg_wavelet_forward(centered * scale))
        ecg_reconstructed[start:start + N] = (
            ecg_wavelet_inverse(sparse) / scale + mean)
    ecg_mse = mse(ecg_reference, ecg_reconstructed)
    ecg_snr = snr_db(ecg_reference, ecg_reconstructed)
    return {
        "pass": (
            brain_snr >= MRI_ORACLE_SNR_MIN_DB
            and brain_psnr >= MRI_ORACLE_PSNR_MIN_DB
            and brain_mse <= MRI_ORACLE_MSE_MAX
            and ecg_snr >= ECG_ORACLE_SNR_MIN_DB
            and ecg_mse <= ECG_ORACLE_MSE_MAX
        ),
        "mri": {
            "slice": 5,
            "block_geometry": "8x8",
            "mse": brain_mse,
            "snr_db": brain_snr,
            "psnr_db": brain_psnr,
        },
        "ecg": {
            "segment_length": N,
            "segment_count": usable // N,
            "mse": ecg_mse,
            "snr_db": ecg_snr,
        },
    }


def benchmark_domain(
    samples: list[tuple[str, np.ndarray]], phi: np.ndarray,
    forward_transform, inverse_transform,
) -> dict:
    sample_records = []
    for name, signal in samples:
        original_signal = np.asarray(signal, dtype=np.float64).reshape(-1)
        coefficients = forward_transform(original_signal)
        sparse_target = topk_sparse(coefficients)
        sparse_signal = inverse_transform(sparse_target)
        algorithms = run_reconstruction(
            phi, sparse_target, original_signal, inverse_transform)
        sample_records.append({
            "name": name,
            "oracle_sparse_mse": mse(original_signal, sparse_signal),
            "oracle_sparse_snr_db": finite_metric(
                snr_db(original_signal, sparse_signal)),
            "algorithms": algorithms,
        })
    algorithm_summary = {}
    for algorithm in ALGORITHMS:
        records = [sample["algorithms"][algorithm] for sample in sample_records]
        finite_snrs = [float(record["fixed_vs_float_snr_db"])
                       for record in records
                       if isinstance(record["fixed_vs_float_snr_db"], float)]
        algorithm_summary[algorithm] = {
            "pass": all(record["pass"] for record in records),
            "samples_passed": sum(record["pass"] for record in records),
            "sample_count": len(records),
            "minimum_fixed_vs_float_snr_db": (
                min(finite_snrs) if finite_snrs else "inf"),
            "maximum_application_snr_gap_db": max(
                float(record["application_snr_gap_db"])
                for record in records),
            "maximum_application_mse_ratio": max(
                float(record["application_mse_ratio_fixed_over_float"])
                for record in records),
            "minimum_application_snr_float_db": min(
                float(record["application_snr_float_db"])
                for record in records),
            "minimum_application_snr_fixed_db": min(
                float(record["application_snr_fixed_db"])
                for record in records),
            "maximum_application_mse_float": max(
                float(record["application_mse_float"])
                for record in records),
            "maximum_application_mse_fixed": max(
                float(record["application_mse_fixed"])
                for record in records),
        }
    return {
        "pass": all(record["pass"] for record in algorithm_summary.values()),
        "sample_count": len(sample_records),
        "algorithms": algorithm_summary,
        "samples": sample_records,
    }


def frozen_golden_gate() -> dict:
    case = suite("smoke")[0]
    support = case["true_support"]
    restricted_phi = case["phi"][:, support]
    least_squares = np.linalg.lstsq(restricted_phi, case["y"], rcond=None)[0]
    sp_fixed = hardware.run(
        "SP", case["phi"], case["y"], case["policy"], PROFILE, REFINEMENT)
    arithmetic = hardware.Arithmetic(PROFILE, hardware.Events())
    expected_data = np.asarray([
        arithmetic.quantize_data(value) for value in case["x_true"]
    ])
    actual_data = np.asarray(sp_fixed.x, dtype=np.int64)
    expected_solver = expected_data.astype(np.int64) << (
        PROFILE.solver_f - PROFILE.data_f)
    ls_dense = np.zeros(case["n"], dtype=np.float64)
    ls_dense[support] = least_squares
    immutable_path = ROOT / "verification/v3/golden/m16_n24_k4_seed1.hardware.json.gz"
    immutable = json.loads(gzip.decompress(immutable_path.read_bytes()))
    immutable_sp = immutable["traces"]["SP"]
    return {
        "pass": bool(
            sp_fixed.support == support
            and np.array_equal(actual_data, expected_data)
            and immutable_sp["support"] == sp_fixed.support
            and immutable_sp["x"] == sp_fixed.x
            and np.allclose(least_squares, case["x_true"][support], atol=1e-12,
                            rtol=0.0)
        ),
        "geometry": {"m": case["m"], "n": case["n"], "k": case["k"],
                     "seed": case["seed"]},
        "support": support,
        "restricted_matrix_condition_number": float(np.linalg.cond(restricted_phi)),
        "least_squares_coefficients": list(least_squares),
        "expected_data_d18f14_raw": [int(expected_data[index]) for index in support],
        "expected_solver_s27f19_raw": [int(expected_solver[index]) for index in support],
        "fixed_data_d18f14_raw": [int(actual_data[index]) for index in support],
        "least_squares_vs_true_mse": mse(case["x_true"], ls_dense),
        "fixed_vs_true_mse": mse(
            case["x_true"], actual_data.astype(np.float64) / (1 << PROFILE.data_f)),
        "immutable_sha256": hashlib.sha256(immutable_path.read_bytes()).hexdigest(),
    }


def markdown(result: dict) -> str:
    frozen = result["frozen_sp"]
    lines = [
        "# v3 golden fixed-point quality gate",
        "",
        "The gate separates mathematical reference quality, fixed-point quality,",
        "and later RTL bit-exact conformance. Medical inputs are transformed into",
        "exact K-sparse transform-domain targets before sensing; application metrics",
        "include oracle sparsification loss, while fixed-vs-float metrics isolate",
        "numeric loss.",
        "",
        f'Overall: **{"PASS" if result["pass"] else "FAIL"}**',
        "",
        "## Frozen SP proof",
        "",
        f'- Result: **{"PASS" if frozen["pass"] else "FAIL"}**',
        f'- Geometry: `M={frozen["geometry"]["m"]}, '
        f'N={frozen["geometry"]["n"]}, K={frozen["geometry"]["k"]}`',
        f'- Restricted matrix condition number: '
        f'`{frozen["restricted_matrix_condition_number"]:.6f}`',
        f'- Expected S27F19 raw coefficients: '
        f'`{frozen["expected_solver_s27f19_raw"]}`',
        "",
        "## Oracle application quality",
        "",
        f'- Result: **{"PASS" if result["oracle_application"]["pass"] else "FAIL"}**',
        f'- MRI: SNR `{result["oracle_application"]["mri"]["snr_db"]:.3f} dB`, '
        f'PSNR `{result["oracle_application"]["mri"]["psnr_db"]:.3f} dB`, '
        f'MSE `{result["oracle_application"]["mri"]["mse"]:.6e}`.',
        f'- ECG: SNR `{result["oracle_application"]["ecg"]["snr_db"]:.3f} dB`, '
        f'MSE `{result["oracle_application"]["ecg"]["mse"]:.6e}`.',
        "",
        "## Medical quality",
        "",
        "| Domain | Result | Samples | Algorithms passed |",
        "| --- | --- | ---: | ---: |",
    ]
    for domain in ("mri", "ecg"):
        record = result[domain]
        lines.append(
            f'| {domain.upper()} | {"PASS" if record["pass"] else "FAIL"} | '
            f'{record["sample_count"]} | '
            f'{sum(value["pass"] for value in record["algorithms"].values())}/8 |')
    lines.extend([
        "",
        "| Domain | Algorithm | Result | Min float SNR | Min fixed SNR | Max float MSE | Max fixed MSE | Max SNR gap | Max MSE ratio |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for domain in ("mri", "ecg"):
        for algorithm, record in result[domain]["algorithms"].items():
            lines.append(
                f'| {domain.upper()} | {algorithm} | '
                f'{"PASS" if record["pass"] else "FAIL"} | '
                f'{record["minimum_application_snr_float_db"]:.6f} | '
                f'{record["minimum_application_snr_fixed_db"]:.6f} | '
                f'{record["maximum_application_mse_float"]:.6e} | '
                f'{record["maximum_application_mse_fixed"]:.6e} | '
                f'{record["maximum_application_snr_gap_db"]:.6f} | '
                f'{record["maximum_application_mse_ratio"]:.6f} |')
    lines.extend([
        "",
        "## Thresholds",
        "",
        f'- Application SNR degradation: `<= {APPLICATION_SNR_GAP_MAX_DB:.2f} dB`',
        f'- Application MSE fixed/float ratio: `<= {APPLICATION_MSE_RATIO_MAX:.2f}`',
        f'- MRI oracle: SNR `>= {MRI_ORACLE_SNR_MIN_DB:.1f} dB`, '
        f'PSNR `>= {MRI_ORACLE_PSNR_MIN_DB:.1f} dB`, MSE `<= {MRI_ORACLE_MSE_MAX:.1e}`.',
        f'- ECG oracle: SNR `>= {ECG_ORACLE_SNR_MIN_DB:.1f} dB`, '
        f'MSE `<= {ECG_ORACLE_MSE_MAX:.1e}`.',
        "- Numeric fault counters must be zero.",
        "- Support and coefficient SNR remain reported diagnostics; alternative",
        "  support is allowed only when application quality is not degraded.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("reports/v3/golden_quality_gate"))
    parser.add_argument("--mri-patches", type=int, default=8)
    parser.add_argument("--ecg-segments", type=int, default=8)
    args = parser.parse_args()
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    brain = np.asarray(data.brain())
    ecg = np.asarray(datasets.electrocardiogram())
    phi = phi_generator.matrix(PHI_SEED, M, N)
    frozen_sp = frozen_golden_gate()
    oracle_application = oracle_application_quality(brain, ecg)
    mri = benchmark_domain(
        high_variance_blocks(brain, args.mri_patches), phi,
        mri_dct_forward, mri_dct_inverse)
    ecg_result = benchmark_domain(
        high_variance_segments(ecg, args.ecg_segments), phi,
        ecg_wavelet_forward, ecg_wavelet_inverse)
    result = {
        "schema": "cscgra-v3-golden-quality-gate-v1",
        "pass": (frozen_sp["pass"] and oracle_application["pass"]
                 and mri["pass"] and ecg_result["pass"]),
        "numeric_profile": asdict(PROFILE),
        "refinement_policy": asdict(REFINEMENT),
        "geometry": {"m": M, "n": N, "k": K, "phi_seed": PHI_SEED},
        "thresholds": {
            "application_snr_gap_max_db": APPLICATION_SNR_GAP_MAX_DB,
            "application_mse_ratio_max": APPLICATION_MSE_RATIO_MAX,
            "mri_oracle_snr_min_db": MRI_ORACLE_SNR_MIN_DB,
            "mri_oracle_psnr_min_db": MRI_ORACLE_PSNR_MIN_DB,
            "mri_oracle_mse_max": MRI_ORACLE_MSE_MAX,
            "ecg_oracle_snr_min_db": ECG_ORACLE_SNR_MIN_DB,
            "ecg_oracle_mse_max": ECG_ORACLE_MSE_MAX,
        },
        "environment": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pywavelets": pywt.__version__,
            "scipy": scipy.__version__,
            "skimage": skimage.__version__,
        },
        "datasets": {
            "mri": {
                "loader": "skimage.data.brain",
                "transform": "orthonormal 8x8 DCT-II",
                "shape": list(brain.shape),
                "dtype": str(brain.dtype),
                "array_sha256": sha256_array(brain),
            },
            "ecg": {
                "loader": "scipy.datasets.electrocardiogram",
                "transform": "db4 periodized DWT level 3",
                "shape": list(ecg.shape),
                "dtype": str(ecg.dtype),
                "array_sha256": sha256_array(ecg),
            },
        },
        "frozen_sp": frozen_sp,
        "oracle_application": oracle_application,
        "mri": mri,
        "ecg": ecg_result,
    }
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    print(markdown(result))
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
