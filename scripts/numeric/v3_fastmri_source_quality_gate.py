#!/usr/bin/env python3
"""Evaluate official fastMRI HDF5 files in the V3 source-domain flow."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
from dataclasses import asdict
import json
from pathlib import Path
import sys

import numpy as np
from scipy.fft import fftshift, ifft2, ifftshift


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.numeric.v3_mri_quality_common import (
    BLOCK_M,
    BLOCK_N,
    BLOCK_PHI_SEED,
    BLOCK_SPARSITY,
    PROFILE,
    REFINEMENT,
    blockwise_dct_oracle,
    deterministic_content_blocks,
    distribution,
    evaluate_fixed_float_blocks,
    fixed_float_statistics,
    image_metrics,
    normalize_image,
    sha256_file,
)


MANIFEST_SCHEMA = "cscgra-v3-fastmri-source-manifest-v1"


def center_crop(values: np.ndarray, shape: tuple[int, int]) -> np.ndarray:
    image = np.asarray(values)
    if image.shape[-2] < shape[0] or image.shape[-1] < shape[1]:
        raise ValueError(f"cannot crop {image.shape[-2:]} to {shape}")
    row = (image.shape[-2] - shape[0]) // 2
    column = (image.shape[-1] - shape[1]) // 2
    return image[row:row + shape[0], column:column + shape[1]]


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema") != MANIFEST_SCHEMA:
        raise ValueError("unsupported fastMRI manifest schema")
    if not isinstance(manifest.get("entries"), list):
        raise ValueError("fastMRI manifest must contain an entries list")
    return manifest


def required_entry_fields(entry: dict) -> None:
    required = {
        "id", "path", "sha256", "anatomy", "acquisition", "split",
        "slices", "official_download_attested",
    }
    missing = sorted(required - set(entry))
    if missing:
        raise ValueError(f'fastMRI entry {entry.get("id", "<unknown>")} missing {missing}')
    if not entry["official_download_attested"]:
        raise ValueError(f'fastMRI entry {entry["id"]} is not officially attested')
    if not entry["sha256"] or len(entry["sha256"]) != 64:
        raise ValueError(f'fastMRI entry {entry["id"]} has no frozen SHA-256')
    if not entry["slices"]:
        raise ValueError(f'fastMRI entry {entry["id"]} has no frozen slices')


def h5_header_present(dataset) -> bool:
    return "ismrmrd_header" in dataset or "ismrmrd_header" in dataset.attrs


def reference_key(dataset) -> str:
    for key in ("reconstruction_rss", "reconstruction_esc"):
        if key in dataset:
            return key
    raise ValueError("fastMRI HDF5 file has no reference reconstruction")


def derived_image(raw_slice: np.ndarray) -> tuple[np.ndarray, str]:
    coil_images = fftshift(
        ifft2(ifftshift(raw_slice, axes=(-2, -1)), norm="ortho", axes=(-2, -1)),
        axes=(-2, -1),
    )
    if coil_images.ndim == 3:
        return np.sqrt(np.sum(np.abs(coil_images) ** 2, axis=0)), "multicoil_rss"
    if coil_images.ndim == 2:
        return np.abs(coil_images), "singlecoil_magnitude"
    raise ValueError(f"unsupported fastMRI k-space slice shape {raw_slice.shape}")


def evaluate_entry(entry: dict, data_root: Path, fixed_blocks: int) -> dict:
    required_entry_fields(entry)
    path = Path(entry["path"])
    if not path.is_absolute():
        path = data_root / path
    if not path.exists():
        raise FileNotFoundError(f"fastMRI file missing: {path}")
    actual_sha256 = sha256_file(path)
    if actual_sha256 != entry["sha256"].lower():
        raise ValueError(f'fastMRI checksum mismatch for {entry["id"]}')
    try:
        import h5py
    except ImportError as error:
        raise RuntimeError("h5py is required for fastMRI evaluation") from error

    slice_records = []
    fixed_sources = []
    with h5py.File(path, "r") as dataset:
        if "kspace" not in dataset:
            raise ValueError(f'fastMRI entry {entry["id"]} has no kspace dataset')
        if not h5_header_present(dataset):
            raise ValueError(f'fastMRI entry {entry["id"]} has no ISMRMRD header')
        reconstruction_key = reference_key(dataset)
        kspace = dataset["kspace"]
        reference = dataset[reconstruction_key]
        for slice_index in entry["slices"]:
            if not 0 <= int(slice_index) < len(kspace):
                raise ValueError(
                    f'fastMRI slice {slice_index} out of range for {entry["id"]}')
            raw_slice = np.asarray(kspace[int(slice_index)])
            official = np.asarray(reference[int(slice_index)])
            if np.iscomplexobj(official):
                official = np.abs(official)
            derived, derivation = derived_image(raw_slice)
            derived = center_crop(derived, official.shape[-2:])
            official_normalized = normalize_image(official)
            derived_normalized = normalize_image(derived)
            agreement = image_metrics(official_normalized, derived_normalized)
            source_oracle = blockwise_dct_oracle(derived)
            slice_records.append({
                "slice_index": int(slice_index),
                "kspace_shape": list(raw_slice.shape),
                "reference_shape": list(official.shape),
                "derivation": derivation,
                "reference_dataset": reconstruction_key,
                "derived_vs_official": agreement,
                "source_oracle": source_oracle,
            })
            fixed_sources.append((int(slice_index), derived))

    fixed_float = evaluate_fixed_float_blocks(
        deterministic_content_blocks(fixed_sources, fixed_blocks))
    return {
        "id": entry["id"],
        "anatomy": entry["anatomy"],
        "acquisition": entry["acquisition"],
        "split": entry["split"],
        "provenance": {
            "provider": "NYU fastMRI official download, user-attested",
            "file": str(path),
            "sha256": actual_sha256,
            "official_download_attested": True,
        },
        "slice_count": len(slice_records),
        "slices": slice_records,
        "fixed_float": fixed_float,
        "pass": fixed_float["pass"],
    }


def source_statistics(cases: list[dict]) -> dict:
    records = [
        slice_record["source_oracle"]
        for case in cases
        for slice_record in case["slices"]
    ]
    return {
        metric: distribution([float(record[metric]) for record in records])
        for metric in ("snr_db", "psnr_db", "mse", "nmse", "ssim")
    }


def agreement_statistics(cases: list[dict]) -> dict:
    records = [
        slice_record["derived_vs_official"]
        for case in cases
        for slice_record in case["slices"]
    ]
    return {
        metric: distribution([float(record[metric]) for record in records])
        for metric in ("snr_db", "psnr_db", "mse", "nmse", "ssim")
    }


def paper_coverage(manifest: dict, cases: list[dict]) -> dict:
    policy = manifest.get("paper_coverage_policy", {})
    minimum_files = int(policy.get("minimum_files", 20))
    minimum_slices = int(policy.get("minimum_slices", 100))
    required_anatomies = set(policy.get("required_anatomies", ["knee", "brain"]))
    observed_anatomies = {case["anatomy"] for case in cases}
    slice_count = sum(case["slice_count"] for case in cases)
    return {
        "pass": (
            len(cases) >= minimum_files
            and slice_count >= minimum_slices
            and required_anatomies <= observed_anatomies
        ),
        "minimum_files": minimum_files,
        "observed_files": len(cases),
        "minimum_slices": minimum_slices,
        "observed_slices": slice_count,
        "required_anatomies": sorted(required_anatomies),
        "observed_anatomies": sorted(observed_anatomies),
    }


def markdown(result: dict) -> str:
    lines = [
        "# V3 fastMRI source-domain quality gate",
        "",
        f'- Status: **{result["status"]}**',
        f'- Engineering gate: **{"PASS" if result["pass"] else "NOT PASS"}**',
        f'- Paper coverage ready: **{"YES" if result["paper_claim_ready"] else "NO"}**',
        "- Direct raw-k-space RTL claim ready: **NO**.",
        "- Raw k-space is inverse-transformed only to derive a real magnitude/RSS source image.",
        "",
    ]
    if result["status"] == "NOT_RUN":
        lines.extend([
            "No official fastMRI HDF5 entry is frozen in the manifest. This is",
            "reported as `NOT_RUN`, never converted into a PASS with synthetic data.",
            "",
            "Populate `config/v3_fastmri_source_manifest.json` with official files,",
            "SHA-256 values, deterministic slice indices, acquisition metadata and",
            "`official_download_attested=true`, then rerun with `--require-data`.",
            "",
        ])
        return "\n".join(lines)
    stats = result["fixed_float_statistics"]
    coverage = result["paper_coverage"]
    lines.extend([
        f'- Files: `{result["file_count"]}`; slices: `{result["slice_count"]}`.',
        f'- Fixed checks: `{result["fixed_evaluations_passed"]}/{result["fixed_evaluations"]}`.',
        f'- Worst SNR loss: `{stats["snr_gap_db"]["maximum"]:.6f} dB`.',
        f'- Worst MSE ratio: `{stats["mse_ratio"]["maximum"]:.6f}`.',
        f'- Worst SSIM drop: `{stats["ssim_drop"]["maximum"]:.6f}`.',
        "",
        "## Paper Coverage",
        "",
        f'- Files: `{coverage["observed_files"]}/{coverage["minimum_files"]}`.',
        f'- Slices: `{coverage["observed_slices"]}/{coverage["minimum_slices"]}`.',
        f'- Required anatomies: `{", ".join(coverage["required_anatomies"])}`.',
        f'- Observed anatomies: `{", ".join(coverage["observed_anatomies"])}`.',
        "",
        "## Strata",
        "",
        "| Anatomy | Acquisition | Split | Files | Slices |",
        "| --- | --- | --- | ---: | ---: |",
    ])
    for stratum in result["strata"]:
        lines.append(
            f'| {stratum["anatomy"]} | {stratum["acquisition"]} | '
            f'{stratum["split"]} | {stratum["files"]} | {stratum["slices"]} |')
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest", type=Path,
        default=Path("config/v3_fastmri_source_manifest.json"))
    parser.add_argument("--data-root", type=Path, default=Path("."))
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("reports/v3/fastmri_source_quality_gate"))
    parser.add_argument("--fixed-blocks-per-file", type=int, default=2)
    parser.add_argument("--require-data", action="store_true")
    args = parser.parse_args()
    if args.fixed_blocks_per_file < 1:
        parser.error("--fixed-blocks-per-file must be positive")

    manifest_path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    data_root = args.data_root if args.data_root.is_absolute() else ROOT / args.data_root
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(manifest_path)
    entries = manifest["entries"]
    if not entries:
        result = {
            "schema": "cscgra-v3-fastmri-source-quality-gate-v1",
            "status": "NOT_RUN",
            "pass": False,
            "paper_claim_ready": False,
            "direct_raw_kspace_rtl_claim_ready": False,
            "reason": "no official fastMRI entries in frozen manifest",
            "manifest": str(manifest_path),
        }
        (out_dir / "results.json").write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
        print(markdown(result))
        if args.require_data:
            raise SystemExit(1)
        return

    cases = [
        evaluate_entry(entry, data_root, args.fixed_blocks_per_file)
        for entry in entries
    ]
    coverage = paper_coverage(manifest, cases)
    fixed_evaluations = sum(case["fixed_float"]["algorithm_evaluations"] for case in cases)
    fixed_passed = sum(case["fixed_float"]["evaluations_passed"] for case in cases)
    strata_counts = Counter(
        (case["anatomy"], case["acquisition"], case["split"])
        for case in cases)
    strata_slices = Counter()
    for case in cases:
        strata_slices[(case["anatomy"], case["acquisition"], case["split"])] += case["slice_count"]
    strata = [
        {
            "anatomy": key[0],
            "acquisition": key[1],
            "split": key[2],
            "files": count,
            "slices": strata_slices[key],
        }
        for key, count in sorted(strata_counts.items())
    ]
    result = {
        "schema": "cscgra-v3-fastmri-source-quality-gate-v1",
        "status": "PASS" if fixed_passed == fixed_evaluations else "FAIL",
        "pass": fixed_passed == fixed_evaluations,
        "paper_claim_ready": fixed_passed == fixed_evaluations and coverage["pass"],
        "paper_claim_scope": "real-MRI source-domain fixed-point fidelity only",
        "direct_raw_kspace_rtl_claim_ready": False,
        "manifest": str(manifest_path),
        "file_count": len(cases),
        "slice_count": sum(case["slice_count"] for case in cases),
        "fixed_evaluations": fixed_evaluations,
        "fixed_evaluations_passed": fixed_passed,
        "source_statistics": source_statistics(cases),
        "derived_vs_official_statistics": agreement_statistics(cases),
        "fixed_float_statistics": fixed_float_statistics(cases),
        "paper_coverage": coverage,
        "strata": strata,
        "numeric_profile": asdict(PROFILE),
        "refinement_policy": asdict(REFINEMENT),
        "geometry": {
            "m": BLOCK_M,
            "n": BLOCK_N,
            "k": BLOCK_SPARSITY,
            "phi_seed": BLOCK_PHI_SEED,
        },
        "cases": cases,
    }
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    rows = [
        {
            "id": case["id"],
            "anatomy": case["anatomy"],
            "acquisition": case["acquisition"],
            "split": case["split"],
            "slice_index": slice_record["slice_index"],
            **{f"oracle_{key}": slice_record["source_oracle"][key]
               for key in ("snr_db", "psnr_db", "mse", "nmse", "ssim")},
            **{f"derived_official_{key}": slice_record["derived_vs_official"][key]
               for key in ("snr_db", "psnr_db", "mse", "nmse", "ssim")},
        }
        for case in cases
        for slice_record in case["slices"]
    ]
    with (out_dir / "slice_metrics.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(markdown(result))
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
