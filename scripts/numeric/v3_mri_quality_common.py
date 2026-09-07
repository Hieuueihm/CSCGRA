#!/usr/bin/env python3
"""Shared MRI quality and fixed-point evaluation helpers for V3."""

from __future__ import annotations

from dataclasses import asdict
import hashlib
import math
from pathlib import Path
import sys

import numpy as np
from scipy.fft import dctn, idctn
from skimage import transform
from skimage.metrics import structural_similarity


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, paper, phi_generator
from scripts.numeric.v3_golden_quality_gate import (
    APPLICATION_MSE_RATIO_MAX,
    APPLICATION_SNR_GAP_MAX_DB,
    M as BLOCK_M,
    N as BLOCK_N,
    PHI_SEED as BLOCK_PHI_SEED,
    PROFILE,
    REFINEMENT,
    mri_dct_forward,
    mri_dct_inverse,
    policy_for,
    topk_sparse,
)


BLOCK_SIZE = 8
BLOCK_SPARSITY = 8
SOURCE_SIZE = 256
APPLICATION_NMSE_RATIO_MAX = 1.10
APPLICATION_SSIM_DROP_MAX = 0.005


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_array(values: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(values).tobytes()).hexdigest()


def normalize_image(values: np.ndarray) -> np.ndarray:
    image = np.asarray(values, dtype=np.float64)
    image = image - float(np.min(image))
    peak = float(np.max(image))
    return image / peak if peak > 0.0 else image


def centered_square(values: np.ndarray) -> np.ndarray:
    image = np.asarray(values)
    side = min(image.shape[-2:])
    row = (image.shape[-2] - side) // 2
    column = (image.shape[-1] - side) // 2
    return image[row:row + side, column:column + side]


def resized(values: np.ndarray, size: int = SOURCE_SIZE) -> np.ndarray:
    return transform.resize(
        normalize_image(centered_square(values)),
        (size, size), anti_aliasing=True, preserve_range=True,
    )


def finite_metric(value: float) -> float | str:
    if math.isinf(value):
        return "inf" if value > 0 else "-inf"
    return float(value)


def image_metrics(reference: np.ndarray, estimate: np.ndarray) -> dict[str, float | str]:
    reference = np.asarray(reference, dtype=np.float64)
    estimate = np.asarray(estimate, dtype=np.float64)
    error = reference - estimate
    error_energy = float(np.sum(error * error))
    signal_energy = float(np.sum(reference * reference))
    mse = float(np.mean(error * error))
    nmse = error_energy / signal_energy if signal_energy > 0.0 else math.inf
    snr = math.inf if error_energy == 0.0 else (
        -math.inf if signal_energy == 0.0
        else 10.0 * math.log10(signal_energy / error_energy)
    )
    data_min = min(float(np.min(reference)), float(np.min(estimate)))
    data_max = max(float(np.max(reference)), float(np.max(estimate)))
    data_range = max(data_max - data_min, 1e-12)
    psnr = math.inf if mse == 0.0 else 10.0 * math.log10(data_range * data_range / mse)
    ssim = structural_similarity(reference, estimate, data_range=data_range)
    return {
        "mse": mse,
        "nmse": finite_metric(nmse),
        "snr_db": finite_metric(snr),
        "psnr_db": finite_metric(psnr),
        "ssim": float(ssim),
    }


def blockwise_dct_oracle(image: np.ndarray) -> dict:
    reference = resized(image)
    estimate = np.zeros_like(reference)
    for row in range(0, SOURCE_SIZE, BLOCK_SIZE):
        for column in range(0, SOURCE_SIZE, BLOCK_SIZE):
            block = reference[row:row + BLOCK_SIZE, column:column + BLOCK_SIZE]
            coefficients = dctn(block, norm="ortho").reshape(-1)
            indices = np.arange(coefficients.size)
            selected = np.lexsort((indices, -np.abs(coefficients)))[:BLOCK_SPARSITY]
            sparse = np.zeros_like(coefficients)
            sparse[selected] = coefficients[selected]
            estimate[row:row + BLOCK_SIZE, column:column + BLOCK_SIZE] = idctn(
                sparse.reshape(BLOCK_SIZE, BLOCK_SIZE), norm="ortho")
    return {
        **image_metrics(reference, estimate),
        "geometry": {
            "image": [SOURCE_SIZE, SOURCE_SIZE],
            "block": [BLOCK_SIZE, BLOCK_SIZE],
            "k_per_block": BLOCK_SPARSITY,
        },
        "reference_sha256": sha256_array(reference),
    }


def deterministic_content_blocks(
    slices: list[tuple[int, np.ndarray]], count: int,
) -> list[tuple[str, np.ndarray]]:
    candidates: list[tuple[float, str, np.ndarray]] = []
    for slice_index, image in slices:
        normalized = resized(image) - 0.5
        roi_start = SOURCE_SIZE // 4
        roi_stop = SOURCE_SIZE - roi_start
        for row in range(roi_start, roi_stop, BLOCK_SIZE):
            for column in range(roi_start, roi_stop, BLOCK_SIZE):
                block = normalized[row:row + BLOCK_SIZE, column:column + BLOCK_SIZE]
                if float(np.max(block) - np.min(block)) < 2.0 ** -12:
                    continue
                candidates.append((
                    float(np.var(block)),
                    f"slice{slice_index}_r{row}_c{column}",
                    block.copy(),
                ))
    if len(candidates) < count:
        raise ValueError(f"only {len(candidates)} non-constant blocks for requested count {count}")
    candidates.sort(key=lambda item: (item[0], item[1]))
    positions = ((np.arange(count, dtype=np.float64) + 0.5)
                 * len(candidates) / count).astype(int)
    positions = np.minimum(positions, len(candidates) - 1)
    return [
        (candidates[int(position)][1], candidates[int(position)][2])
        for position in positions
    ]


def _ratio(numerator: float, denominator: float) -> float:
    if denominator > 0.0:
        return numerator / denominator
    return 1.0 if numerator == 0.0 else math.inf


def evaluate_fixed_float_blocks(samples: list[tuple[str, np.ndarray]],
                                numeric_profile=None, refinement_policy=None) -> dict:
    numeric_profile = PROFILE if numeric_profile is None else numeric_profile
    refinement_policy = REFINEMENT if refinement_policy is None else refinement_policy
    phi = phi_generator.matrix(BLOCK_PHI_SEED, BLOCK_M, BLOCK_N)
    policy = policy_for(phi)
    sample_records = []
    for sample_name, block in samples:
        original = np.asarray(block, dtype=np.float64).reshape(-1)
        sparse_target = topk_sparse(mri_dct_forward(original))
        target_peak = max(float(np.max(np.abs(sparse_target))), 1e-30)
        normalization_scale = 0.75 / target_peak
        scaled_target = sparse_target * normalization_scale
        measurement = phi @ scaled_target
        algorithms = {}
        for algorithm in paper.ALGORITHMS:
            floating = paper.run(algorithm, phi, measurement, policy)
            fixed = hardware.run(
                algorithm, phi, measurement, policy, numeric_profile, refinement_policy)
            floating_x = np.asarray(floating.x, dtype=np.float64) / normalization_scale
            fixed_x = (
                np.asarray(fixed.x, dtype=np.float64)
                / (1 << numeric_profile.data_f) / normalization_scale)
            floating_signal = mri_dct_inverse(floating_x).reshape(BLOCK_SIZE, BLOCK_SIZE)
            fixed_signal = mri_dct_inverse(fixed_x).reshape(BLOCK_SIZE, BLOCK_SIZE)
            original_image = original.reshape(BLOCK_SIZE, BLOCK_SIZE)
            floating_metrics = image_metrics(original_image, floating_signal)
            fixed_metrics = image_metrics(original_image, fixed_signal)
            fixed_float_metrics = image_metrics(floating_signal, fixed_signal)
            snr_gap = float(floating_metrics["snr_db"]) - float(fixed_metrics["snr_db"])
            mse_ratio = _ratio(float(fixed_metrics["mse"]), float(floating_metrics["mse"]))
            nmse_ratio = _ratio(float(fixed_metrics["nmse"]), float(floating_metrics["nmse"]))
            ssim_drop = float(floating_metrics["ssim"]) - float(fixed_metrics["ssim"])
            events = asdict(fixed.events)
            passed = (
                snr_gap <= APPLICATION_SNR_GAP_MAX_DB
                and mse_ratio <= APPLICATION_MSE_RATIO_MAX
                and nmse_ratio <= APPLICATION_NMSE_RATIO_MAX
                and ssim_drop <= APPLICATION_SSIM_DROP_MAX
                and not any(events.values())
            )
            algorithms[algorithm] = {
                "pass": passed,
                "support_match": fixed.support == floating.support,
                "floating_support": list(floating.support),
                "fixed_support": list(fixed.support),
                "floating": floating_metrics,
                "fixed": fixed_metrics,
                "fixed_vs_float": fixed_float_metrics,
                "snr_gap_db": finite_metric(snr_gap),
                "mse_ratio_fixed_over_float": finite_metric(mse_ratio),
                "nmse_ratio_fixed_over_float": finite_metric(nmse_ratio),
                "ssim_drop": float(ssim_drop),
                "events": events,
            }
        sample_records.append({
            "name": sample_name,
            "normalization_scale": normalization_scale,
            "algorithms": algorithms,
            "pass": all(record["pass"] for record in algorithms.values()),
        })
    flattened = [
        record
        for sample in sample_records
        for record in sample["algorithms"].values()
    ]
    return {
        "pass": all(record["pass"] for record in flattened),
        "sample_count": len(sample_records),
        "algorithm_evaluations": len(flattened),
        "evaluations_passed": sum(record["pass"] for record in flattened),
        "thresholds": {
            "application_snr_gap_max_db": APPLICATION_SNR_GAP_MAX_DB,
            "application_mse_ratio_max": APPLICATION_MSE_RATIO_MAX,
            "application_nmse_ratio_max": APPLICATION_NMSE_RATIO_MAX,
            "application_ssim_drop_max": APPLICATION_SSIM_DROP_MAX,
            "fixed_vs_float_ssim": "reported only; unstable as an absolute gate on 8x8 patches",
        },
        "samples": sample_records,
    }


def distribution(values: list[float]) -> dict[str, float]:
    array = np.asarray(values, dtype=np.float64)
    return {
        "count": int(array.size),
        "mean": float(np.mean(array)),
        "median": float(np.median(array)),
        "std": float(np.std(array)),
        "p05": float(np.percentile(array, 5)),
        "p95": float(np.percentile(array, 95)),
        "minimum": float(np.min(array)),
        "maximum": float(np.max(array)),
    }


def fixed_float_statistics(cases: list[dict]) -> dict:
    records = [
        algorithm
        for case in cases
        for sample in case["fixed_float"]["samples"]
        for algorithm in sample["algorithms"].values()
    ]
    return {
        "snr_gap_db": distribution([float(record["snr_gap_db"]) for record in records]),
        "mse_ratio": distribution([
            float(record["mse_ratio_fixed_over_float"]) for record in records]),
        "nmse_ratio": distribution([
            float(record["nmse_ratio_fixed_over_float"]) for record in records]),
        "ssim_drop": distribution([float(record["ssim_drop"]) for record in records]),
        "fixed_vs_float_ssim": distribution([
            float(record["fixed_vs_float"]["ssim"]) for record in records]),
    }
