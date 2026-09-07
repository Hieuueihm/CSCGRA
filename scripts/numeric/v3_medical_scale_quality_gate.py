#!/usr/bin/env python3
"""Validate production-scale fixed-point quality on MRI and ECG signals."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import numpy as np
import pywt
from scipy import datasets
from scipy.fft import dctn, idctn
from skimage import data, transform


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, paper, phi_generator


N = 1024
M = 128
K = 32
PHI_SEED = 23
APPLICATION_SNR_GAP_MAX_DB = 0.5
APPLICATION_MSE_RATIO_MAX = 1.10
PROFILE = hardware.NumericProfile()
REFINEMENT = hardware.RefinementPolicy(profile="strict_paper")


def sha256_array(values: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(values).tobytes()).hexdigest()


def metrics(reference: np.ndarray, estimate: np.ndarray) -> tuple[float, float]:
    error = np.asarray(reference, dtype=np.float64) - np.asarray(
        estimate, dtype=np.float64)
    error_energy = float(np.sum(error * error))
    mse = float(np.mean(error * error))
    if error_energy == 0.0:
        return mse, math.inf
    signal_energy = float(np.sum(np.asarray(reference, dtype=np.float64) ** 2))
    return mse, 10.0 * math.log10(signal_energy / error_energy)


def policy(phi: np.ndarray) -> paper.Policy:
    spectral_sq = float(np.linalg.norm(phi, ord=2) ** 2)
    return paper.Policy(
        sparsity=K,
        max_iterations=K,
        residual_atol=2.0**-14,
        step_size=0.9 / spectral_sq,
        group_size=2,
    )


def sparse_target(coefficients: np.ndarray) -> tuple[np.ndarray, float]:
    values = np.asarray(coefficients, dtype=np.float64).reshape(-1)
    indices = np.arange(values.size)
    selected = np.lexsort((indices, -np.abs(values)))[:K]
    sparse = np.zeros_like(values)
    sparse[selected] = values[selected]
    scale = 0.75 / max(float(np.max(np.abs(sparse))), 1e-30)
    return sparse * scale, scale


def run_case(
    name: str,
    signal: np.ndarray,
    forward_transform,
    inverse_transform,
    phi: np.ndarray,
) -> dict:
    target, scale = sparse_target(forward_transform(signal))
    oracle_signal = inverse_transform(target / scale)
    oracle_mse, oracle_snr = metrics(signal, oracle_signal)
    measurement = phi @ target
    run_policy = policy(phi)
    algorithms = {}
    for algorithm in paper.ALGORITHMS:
        started = time.perf_counter()
        floating = paper.run(algorithm, phi, measurement, run_policy)
        fixed = hardware.run(
            algorithm, phi, measurement, run_policy, PROFILE, REFINEMENT)
        floating_coefficients = np.asarray(floating.x, dtype=np.float64) / scale
        fixed_coefficients = (
            np.asarray(fixed.x, dtype=np.float64)
            / (1 << PROFILE.data_f) / scale)
        floating_mse, floating_snr = metrics(
            signal, inverse_transform(floating_coefficients))
        fixed_mse, fixed_snr = metrics(
            signal, inverse_transform(fixed_coefficients))
        mse_ratio = (fixed_mse / floating_mse if floating_mse > 0.0
                     else (1.0 if fixed_mse == 0.0 else math.inf))
        snr_gap = floating_snr - fixed_snr
        events = asdict(fixed.events)
        algorithms[algorithm] = {
            "pass": (
                snr_gap <= APPLICATION_SNR_GAP_MAX_DB
                and mse_ratio <= APPLICATION_MSE_RATIO_MAX
                and not any(events.values())
            ),
            "elapsed_seconds": time.perf_counter() - started,
            "support_match": fixed.support == floating.support,
            "floating_support_size": len(floating.support),
            "fixed_support_size": len(fixed.support),
            "floating_mse": floating_mse,
            "fixed_mse": fixed_mse,
            "mse_ratio_fixed_over_float": mse_ratio,
            "floating_snr_db": floating_snr,
            "fixed_snr_db": fixed_snr,
            "snr_gap_db": snr_gap,
            "events": events,
        }
    return {
        "name": name,
        "pass": all(record["pass"] for record in algorithms.values()),
        "normalization_scale": scale,
        "oracle_mse": oracle_mse,
        "oracle_snr_db": oracle_snr,
        "algorithms": algorithms,
    }


def markdown(result: dict) -> str:
    lines = [
        "# v3 production-scale MRI/ECG quality gate",
        "",
        f'Overall: **{"PASS" if result["pass"] else "FAIL"}**',
        "",
        "Geometry: `M=128, N=1024, K=32`, D18F14/S27F19/A62.",
        "The oracle metric measures transform sparsification loss. The algorithm",
        "gate measures only fixed-point degradation relative to floating-point.",
        "",
        "| Domain | Oracle SNR | Oracle MSE | Algorithms passed |",
        "| --- | ---: | ---: | ---: |",
    ]
    for case in result["cases"]:
        lines.append(
            f'| {case["name"]} | {case["oracle_snr_db"]:.6f} | '
            f'{case["oracle_mse"]:.6e} | '
            f'{sum(record["pass"] for record in case["algorithms"].values())}/8 |')
    lines.extend([
        "",
        "| Domain | Algorithm | Result | Float SNR | Fixed SNR | SNR gap | Float MSE | Fixed MSE | MSE ratio |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for case in result["cases"]:
        for algorithm, record in case["algorithms"].items():
            lines.append(
                f'| {case["name"]} | {algorithm} | '
                f'{"PASS" if record["pass"] else "FAIL"} | '
                f'{record["floating_snr_db"]:.6f} | '
                f'{record["fixed_snr_db"]:.6f} | '
                f'{record["snr_gap_db"]:.6f} | '
                f'{record["floating_mse"]:.6e} | '
                f'{record["fixed_mse"]:.6e} | '
                f'{record["mse_ratio_fixed_over_float"]:.6f} |')
    lines.extend([
        "",
        f'- Maximum permitted SNR degradation: `{APPLICATION_SNR_GAP_MAX_DB:.2f} dB`.',
        f'- Maximum permitted fixed/float MSE ratio: `{APPLICATION_MSE_RATIO_MAX:.2f}`.',
        "- All numeric fault counters must remain zero.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("reports/v3/medical_scale_quality_gate"))
    args = parser.parse_args()
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    brain_stack = np.asarray(data.brain())
    brain = brain_stack[5].astype(np.float64)
    brain /= max(float(np.max(brain)), 1.0)
    brain = transform.resize(
        brain, (32, 32), anti_aliasing=True, preserve_range=True).reshape(-1)

    ecg_source = np.asarray(datasets.electrocardiogram(), dtype=np.float64)
    starts = range(0, len(ecg_source) - N + 1, N)
    ecg_start = max(starts, key=lambda start: np.var(ecg_source[start:start + N]))
    ecg = ecg_source[ecg_start:ecg_start + N].copy()
    ecg -= float(np.mean(ecg))
    ecg *= 0.75 / max(float(np.max(np.abs(ecg))), 1e-30)

    wavelet_template = pywt.wavedec(
        np.zeros(N), "db4", mode="periodization", level=5)
    _, wavelet_slices = pywt.coeffs_to_array(wavelet_template)
    phi = phi_generator.matrix(PHI_SEED, M, N)
    cases = [
        run_case(
            "MRI",
            brain,
            lambda values: dctn(
                np.asarray(values).reshape(32, 32), norm="ortho").reshape(-1),
            lambda values: idctn(
                np.asarray(values).reshape(32, 32), norm="ortho").reshape(-1),
            phi,
        ),
        run_case(
            "ECG",
            ecg,
            lambda values: pywt.coeffs_to_array(pywt.wavedec(
                values, "db4", mode="periodization", level=5))[0],
            lambda values: pywt.waverec(pywt.array_to_coeffs(
                np.asarray(values), wavelet_slices, output_format="wavedec"),
                "db4", mode="periodization")[:N],
            phi,
        ),
    ]
    result = {
        "schema": "cscgra-v3-medical-scale-quality-gate-v1",
        "pass": all(case["pass"] for case in cases),
        "geometry": {"m": M, "n": N, "k": K, "phi_seed": PHI_SEED},
        "numeric_profile": asdict(PROFILE),
        "refinement_policy": asdict(REFINEMENT),
        "thresholds": {
            "application_snr_gap_max_db": APPLICATION_SNR_GAP_MAX_DB,
            "application_mse_ratio_max": APPLICATION_MSE_RATIO_MAX,
        },
        "datasets": {
            "mri": {
                "loader": "skimage.data.brain",
                "array_sha256": sha256_array(brain_stack),
                "slice": 5,
                "resize": [32, 32],
                "transform": "orthonormal 32x32 DCT-II",
            },
            "ecg": {
                "loader": "scipy.datasets.electrocardiogram",
                "array_sha256": sha256_array(ecg_source),
                "start": ecg_start,
                "length": N,
                "transform": "db4 periodized DWT level 5",
            },
        },
        "cases": cases,
    }
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    print(markdown(result))
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
