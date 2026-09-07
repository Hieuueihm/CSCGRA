#!/usr/bin/env python3
"""Validate paper-grade MRI source quality and fixed-point degradation."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import numpy as np
from scipy.fft import dctn, fftshift, idctn, ifft2, ifftshift
from skimage import data, transform


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import phi_generator
from scripts.numeric.v3_golden_quality_gate import (
    M as BLOCK_M,
    N as BLOCK_N,
    PHI_SEED as BLOCK_PHI_SEED,
    benchmark_domain,
    high_variance_blocks,
    mri_dct_forward,
    mri_dct_inverse,
)
from scripts.numeric.v3_medical_scale_quality_gate import (
    APPLICATION_MSE_RATIO_MAX,
    APPLICATION_SNR_GAP_MAX_DB,
    K,
    M,
    N,
    PHI_SEED,
    PROFILE,
    REFINEMENT,
    run_case,
)


BRAINWEB_ALIAS = "T1 ICBM normal 1mm pn3 rf20"
BRAINWEB_ENDPOINT = "https://brainweb.bic.mni.mcgill.ca/cgi/brainweb1"
BRAINWEB_FILENAME = "t1_icbm_normal_1mm_pn3_rf20.raws.gz"
BRAINWEB_SHA256 = "73c918e4f7ae56521e16054c77bd811d691b3ba6220bc9b1f48f953250f982c0"
BRAINWEB_SHAPE = (181, 217, 181)
BRAINWEB_SLICE = 90
BLOCK_SIZE = 8
BLOCK_SPARSITY = 8
SOURCE_SIZE = 256
DEFAULT_PATCHES = 16
SOURCE_THRESHOLDS = {
    "Shepp-Logan": {"snr_min_db": 13.0, "psnr_min_db": 25.0, "mse_max": 3.0e-3},
    "BrainWeb-T1": {"snr_min_db": 25.0, "psnr_min_db": 32.0, "mse_max": 5.0e-4},
    "fastMRI": {"snr_min_db": 15.0, "psnr_min_db": 25.0, "mse_max": 3.0e-3},
}


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


def resized(values: np.ndarray, size: int) -> np.ndarray:
    return transform.resize(
        normalize_image(centered_square(values)),
        (size, size), anti_aliasing=True, preserve_range=True)


def metrics(reference: np.ndarray, estimate: np.ndarray) -> dict[str, float]:
    reference = np.asarray(reference, dtype=np.float64)
    error = reference - np.asarray(estimate, dtype=np.float64)
    error_energy = float(np.sum(error * error))
    signal_energy = float(np.sum(reference * reference))
    mse = float(np.mean(error * error))
    snr = math.inf if error_energy == 0.0 else 10.0 * math.log10(
        signal_energy / error_energy)
    psnr = math.inf if mse == 0.0 else 10.0 * math.log10(1.0 / mse)
    return {"mse": mse, "snr_db": snr, "psnr_db": psnr}


def blockwise_oracle(name: str, image: np.ndarray) -> dict:
    reference = resized(image, SOURCE_SIZE)
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
    result = metrics(reference, estimate)
    thresholds = SOURCE_THRESHOLDS[name]
    result.update({
        "pass": (
            result["snr_db"] >= thresholds["snr_min_db"]
            and result["psnr_db"] >= thresholds["psnr_min_db"]
            and result["mse"] <= thresholds["mse_max"]
        ),
        "geometry": {
            "image": [SOURCE_SIZE, SOURCE_SIZE],
            "block": [BLOCK_SIZE, BLOCK_SIZE],
            "k_per_block": BLOCK_SPARSITY,
        },
        "thresholds": thresholds,
        "reference_sha256": sha256_array(reference),
    })
    return result


def download_brainweb(cache_dir: Path, offline: bool) -> Path:
    destination = cache_dir / BRAINWEB_FILENAME
    if destination.exists() and sha256_file(destination) == BRAINWEB_SHA256:
        return destination
    if offline:
        raise FileNotFoundError(
            f"BrainWeb cache is missing or invalid: {destination}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    request_data = urlencode({
        "do_download_alias": BRAINWEB_ALIAS,
        "format_value": "raw_short",
        "zip_value": "gnuzip",
        "who_name": "",
        "who_institution": "",
        "who_email": "",
        "download_for_real": "[Start download!]",
    }).encode("ascii")
    request = Request(BRAINWEB_ENDPOINT, data=request_data, method="POST")
    with tempfile.NamedTemporaryFile(
        dir=cache_dir, prefix=BRAINWEB_FILENAME, suffix=".part", delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)
        with urlopen(request, timeout=120) as response:
            while chunk := response.read(1024 * 1024):
                temporary.write(chunk)
    if sha256_file(temporary_path) != BRAINWEB_SHA256:
        temporary_path.unlink(missing_ok=True)
        raise ValueError("BrainWeb download checksum mismatch")
    temporary_path.replace(destination)
    return destination


def load_brainweb(cache_dir: Path, offline: bool) -> tuple[np.ndarray, dict]:
    path = download_brainweb(cache_dir, offline)
    with gzip.open(path, "rb") as stream:
        payload = stream.read()
    voxel_count = math.prod(BRAINWEB_SHAPE)
    if len(payload) != voxel_count * 2:
        raise ValueError(f"unexpected BrainWeb payload size {len(payload)}")
    little = np.frombuffer(payload, dtype="<u2")
    big = np.frombuffer(payload, dtype=">u2")
    if int(np.max(little)) <= 4095:
        volume = little.reshape(BRAINWEB_SHAPE)
        byte_order = "little"
    elif int(np.max(big)) <= 4095:
        volume = big.reshape(BRAINWEB_SHAPE)
        byte_order = "big"
    else:
        raise ValueError("BrainWeb raw-short values exceed the documented 12-bit range")
    image = volume[BRAINWEB_SLICE]
    return image, {
        "provider": "BrainWeb Simulated Brain Database, McGill University",
        "alias": BRAINWEB_ALIAS,
        "cache_file": str(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path),
        "compressed_sha256": sha256_file(path),
        "shape": list(BRAINWEB_SHAPE),
        "raw_dtype": "uint16",
        "detected_byte_order": byte_order,
        "intensity_range": [int(np.min(volume)), int(np.max(volume))],
        "slice_axis": 0,
        "slice_index": BRAINWEB_SLICE,
    }


def fastmri_image(
    path: Path,
    requested_slice: int | None,
    expected_sha256: str | None,
) -> tuple[np.ndarray, dict]:
    try:
        import h5py
    except ImportError as error:
        raise RuntimeError("h5py is required for --fastmri-h5") from error
    file_sha256 = sha256_file(path)
    if expected_sha256 is not None and file_sha256 != expected_sha256.lower():
        raise ValueError("fastMRI HDF5 checksum mismatch")
    with h5py.File(path, "r") as dataset:
        if "kspace" not in dataset:
            raise ValueError("fastMRI HDF5 file has no 'kspace' dataset")
        if ("ismrmrd_header" not in dataset
                and "ismrmrd_header" not in dataset.attrs):
            raise ValueError("fastMRI HDF5 file has no ISMRMRD header")
        reconstruction_keys = [
            key for key in ("reconstruction_rss", "reconstruction_esc")
            if key in dataset
        ]
        if not reconstruction_keys:
            raise ValueError("fastMRI HDF5 file has no reference reconstruction")
        kspace = dataset["kspace"]
        slice_index = requested_slice if requested_slice is not None else len(kspace) // 2
        if not 0 <= slice_index < len(kspace):
            raise ValueError(f"fastMRI slice {slice_index} is out of range")
        raw_slice = np.asarray(kspace[slice_index])
    coil_images = fftshift(
        ifft2(ifftshift(raw_slice, axes=(-2, -1)), norm="ortho", axes=(-2, -1)),
        axes=(-2, -1),
    )
    if coil_images.ndim == 3:
        image = np.sqrt(np.sum(np.abs(coil_images) ** 2, axis=0))
        acquisition = "multicoil raw k-space; root-sum-of-squares reference"
    elif coil_images.ndim == 2:
        image = np.abs(coil_images)
        acquisition = "single-coil raw k-space; magnitude reference"
    else:
        raise ValueError(f"unsupported fastMRI k-space shape {raw_slice.shape}")
    return image, {
        "provider": "user-supplied fastMRI-format HDF5",
        "file": path.name,
        "file_sha256": file_sha256,
        "reference_dataset": reconstruction_keys[0],
        "kspace_slice_shape": list(raw_slice.shape),
        "slice_index": slice_index,
        "reference_reconstruction": acquisition,
    }


def production_case(name: str, image: np.ndarray, phi: np.ndarray) -> dict:
    signal = resized(image, 32).reshape(-1)
    return run_case(
        name,
        signal,
        lambda values: dctn(
            np.asarray(values).reshape(32, 32), norm="ortho").reshape(-1),
        lambda values: idctn(
            np.asarray(values).reshape(32, 32), norm="ortho").reshape(-1),
        phi,
    )


def blockwise_fixed_quality(image: np.ndarray, patches: int) -> dict:
    reference = resized(image, SOURCE_SIZE)
    phi = phi_generator.matrix(BLOCK_PHI_SEED, BLOCK_M, BLOCK_N)
    return benchmark_domain(
        high_variance_blocks(reference[None, :, :], patches),
        phi,
        mri_dct_forward,
        mri_dct_inverse,
    )


def markdown(result: dict) -> str:
    lines = [
        "# v3 paper-grade MRI quality gate",
        "",
        f'- Baseline result: **{"PASS" if result["baseline_pass"] else "FAIL"}**',
        f'- Paper claim ready: **{"YES" if result["paper_claim_ready"] else "NO"}**',
        "- The V3 acquisition operator remains a real Bernoulli matrix. fastMRI raw",
        "  k-space is used to derive a real-image reference, not as a direct RTL input.",
        "",
        "| Dataset | Source oracle | SNR | PSNR | MSE | Blockwise fixed/float | Global stress |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for case in result["cases"]:
        oracle = case["source_oracle"]
        blockwise = case["blockwise_fixed_quality"]
        production = case["production_scale_stress"]
        global_result = (
            f'{sum(item["pass"] for item in production["algorithms"].values())}/8'
            if production["status"] == "run" else "not run"
        )
        lines.append(
            f'| {case["name"]} | {"PASS" if oracle["pass"] else "FAIL"} | '
            f'{oracle["snr_db"]:.6f} | {oracle["psnr_db"]:.6f} | '
            f'{oracle["mse"]:.6e} | '
            f'{sum(item["pass"] for item in blockwise["algorithms"].values())}/8 | '
            f'{global_result} |')
    lines.extend([
        "",
        "## Interpretation",
        "",
        "- Source oracle metrics measure blockwise DCT sparsification loss.",
        "- Blockwise `8x8/K8` is the MRI quality path and is the pass/fail authority.",
        "- Global `N1024/K32` is retained as a non-authoritative stress diagnostic",
        "  because retaining 3.125% of one whole-image DCT is not the quality mode.",
        "- A paper-grade real-MRI source claim additionally requires an official fastMRI",
        "  HDF5 file, a frozen checksum, `--attest-official-fastmri`, and",
        "  `--require-fastmri`; absence does not invalidate the synthetic and",
        "  simulated-phantom baseline.",
        "- Direct raw-k-space RTL reconstruction cannot be claimed by this gate.",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("reports/v3/mri_paper_quality_gate"))
    parser.add_argument(
        "--cache-dir", type=Path,
        default=Path("reports/v3/datasets/brainweb"))
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--fastmri-h5", type=Path)
    parser.add_argument("--fastmri-sha256")
    parser.add_argument("--fastmri-slice", type=int)
    parser.add_argument("--attest-official-fastmri", action="store_true")
    parser.add_argument("--require-fastmri", action="store_true")
    parser.add_argument("--patches", type=int, default=DEFAULT_PATCHES)
    parser.add_argument("--skip-global-stress", action="store_true")
    args = parser.parse_args()
    if args.attest_official_fastmri and args.fastmri_h5 is None:
        parser.error("--attest-official-fastmri requires --fastmri-h5")

    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    cache_dir = args.cache_dir if args.cache_dir.is_absolute() else ROOT / args.cache_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    brainweb, brainweb_provenance = load_brainweb(cache_dir, args.offline)
    sources = [
        (
            "Shepp-Logan",
            data.shepp_logan_phantom(),
            {
                "provider": "scikit-image analytical Shepp-Logan phantom",
                "loader": "skimage.data.shepp_logan_phantom",
            },
        ),
        ("BrainWeb-T1", brainweb, brainweb_provenance),
    ]
    if args.fastmri_h5 is not None:
        fastmri_path = args.fastmri_h5
        if not fastmri_path.is_absolute():
            fastmri_path = ROOT / fastmri_path
        fastmri, fastmri_provenance = fastmri_image(
            fastmri_path, args.fastmri_slice, args.fastmri_sha256)
        fastmri_provenance["expected_sha256_provided"] = (
            args.fastmri_sha256 is not None)
        fastmri_provenance["official_download_attested"] = (
            args.attest_official_fastmri)
        if args.attest_official_fastmri:
            fastmri_provenance["provider"] = (
                "fastMRI official download, user-attested")
        sources.append(("fastMRI", fastmri, fastmri_provenance))

    phi = phi_generator.matrix(PHI_SEED, M, N)
    cases = []
    for name, image, provenance in sources:
        cases.append({
            "name": name,
            "provenance": provenance,
            "source_oracle": blockwise_oracle(name, image),
            "blockwise_fixed_quality": blockwise_fixed_quality(image, args.patches),
            "production_scale_stress": (
                {"status": "not_run", "pass": None, "algorithms": {}}
                if args.skip_global_stress
                else {"status": "run", **production_case(name, image, phi)}
            ),
        })

    baseline_cases = [case for case in cases if case["name"] != "fastMRI"]
    baseline_pass = all(
        case["source_oracle"]["pass"]
        and case["blockwise_fixed_quality"]["pass"]
        for case in baseline_cases)
    fastmri_pass = any(
        case["name"] == "fastMRI"
        and case["source_oracle"]["pass"]
        and case["blockwise_fixed_quality"]["pass"]
        and case["provenance"]["expected_sha256_provided"]
        and case["provenance"]["official_download_attested"]
        for case in cases)
    paper_claim_ready = baseline_pass and fastmri_pass
    result = {
        "schema": "cscgra-v3-mri-paper-quality-gate-v1",
        "pass": baseline_pass and (paper_claim_ready if args.require_fastmri else True),
        "baseline_pass": baseline_pass,
        "paper_claim_ready": paper_claim_ready,
        "paper_claim_scope": "real-MRI source-domain fixed-point fidelity only",
        "direct_raw_kspace_rtl_claim_ready": False,
        "fastmri_required": args.require_fastmri,
        "acquisition_scope": {
            "rtl_operator": "real Bernoulli MxN matrix generated by phi_generator",
            "source_transforms": "orthonormal 2D DCT-II",
            "fastmri_use": (
                "raw complex k-space is inverse-transformed to a magnitude/RSS image; "
                "the RTL is not claimed to implement direct Fourier k-space recovery"
            ),
        },
        "geometry": {
            "mri_quality": {
                "m": BLOCK_M,
                "n": BLOCK_N,
                "k": BLOCK_SPARSITY,
                "phi_seed": BLOCK_PHI_SEED,
                "patches_per_dataset": args.patches,
            },
            "global_stress": {"m": M, "n": N, "k": K, "phi_seed": PHI_SEED},
        },
        "numeric_profile": asdict(PROFILE),
        "refinement_policy": asdict(REFINEMENT),
        "thresholds": {
            "application_snr_gap_max_db": APPLICATION_SNR_GAP_MAX_DB,
            "application_mse_ratio_max": APPLICATION_MSE_RATIO_MAX,
            "source_oracle": SOURCE_THRESHOLDS,
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
