#!/usr/bin/env python3
"""Run a reproducible BrainWeb normal/MS source-domain quality sweep."""

from __future__ import annotations

import argparse
import csv
from dataclasses import asdict
import gzip
import json
import math
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import numpy as np


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
    sha256_file,
)
from models.v3 import numerical_candidate


BRAINWEB_SHAPE = (181, 217, 181)
DEFAULT_MODELS = ("normal", "ms")
DEFAULT_MODALITIES = ("T1", "T2", "PD")
DEFAULT_NOISES = ("pn0", "pn3", "pn9")
DEFAULT_FIELDS = ("rf0", "rf20", "rf40")
DEFAULT_SOURCE_SLICES = (45, 67, 90, 112, 135)
DEFAULT_FIXED_SLICES = (90,)
MODEL_CONFIG = {
    "normal": {
        "endpoint": "https://brainweb.bic.mni.mcgill.ca/cgi/brainweb1",
        "protocol": "ICBM",
        "phantom": "normal",
    },
    "ms": {
        "endpoint": "https://brainweb.bic.mni.mcgill.ca/cgi/brainweb2",
        "protocol": "AI",
        "phantom": "msles2",
    },
}


def csv_values(value: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in value.split(",") if item.strip())


def integer_csv(value: str) -> tuple[int, ...]:
    return tuple(int(item) for item in csv_values(value))


def case_id(model: str, modality: str, noise: str, field: str) -> str:
    return f"{model}_{modality.lower()}_1mm_{noise}_{field}"


def alias_for(model: str, modality: str, noise: str, field: str) -> str:
    config = MODEL_CONFIG[model]
    return f'{modality} {config["protocol"]} {config["phantom"]} 1mm {noise} {field}'


def filename_for(identifier: str) -> str:
    return re.sub(r"[^a-z0-9_.-]+", "_", identifier.lower()) + ".raws.gz"


def download_volume(
    cache_dir: Path, model: str, modality: str, noise: str, field: str,
    expected_sha256: str | None, offline: bool,
) -> tuple[Path, str]:
    identifier = case_id(model, modality, noise, field)
    destination = cache_dir / filename_for(identifier)
    if destination.exists():
        actual_sha256 = sha256_file(destination)
        if expected_sha256 is None or actual_sha256 == expected_sha256:
            return destination, actual_sha256
        if offline:
            raise ValueError(f"BrainWeb checksum mismatch for {identifier}")
    if offline:
        raise FileNotFoundError(f"BrainWeb cache missing: {destination}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    request_data = urlencode({
        "do_download_alias": alias_for(model, modality, noise, field),
        "format_value": "raw_short",
        "zip_value": "gnuzip",
        "who_name": "",
        "who_institution": "",
        "who_email": "",
        "download_for_real": "[Start download!]",
    }).encode("ascii")
    request = Request(MODEL_CONFIG[model]["endpoint"], data=request_data, method="POST")
    with tempfile.NamedTemporaryFile(
        dir=cache_dir, prefix=destination.name, suffix=".part", delete=False,
    ) as temporary:
        temporary_path = Path(temporary.name)
        with urlopen(request, timeout=180) as response:
            while chunk := response.read(1024 * 1024):
                temporary.write(chunk)
    try:
        with gzip.open(temporary_path, "rb") as stream:
            payload_size = len(stream.read())
        expected_size = math.prod(BRAINWEB_SHAPE) * 2
        if payload_size != expected_size:
            raise ValueError(
                f"unexpected BrainWeb payload size {payload_size} for {identifier}")
        actual_sha256 = sha256_file(temporary_path)
        if expected_sha256 is not None and actual_sha256 != expected_sha256:
            raise ValueError(f"BrainWeb checksum mismatch for {identifier}")
        temporary_path.replace(destination)
        return destination, actual_sha256
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def load_volume(path: Path) -> tuple[np.ndarray, str]:
    with gzip.open(path, "rb") as stream:
        payload = stream.read()
    expected_size = math.prod(BRAINWEB_SHAPE) * 2
    if len(payload) != expected_size:
        raise ValueError(f"unexpected BrainWeb payload size {len(payload)}")
    little = np.frombuffer(payload, dtype="<u2")
    big = np.frombuffer(payload, dtype=">u2")
    if int(np.max(little)) <= 4095:
        return little.reshape(BRAINWEB_SHAPE), "little"
    if int(np.max(big)) <= 4095:
        return big.reshape(BRAINWEB_SHAPE), "big"
    raise ValueError("BrainWeb raw-short values exceed the documented 12-bit range")


def load_manifest(path: Path) -> dict | None:
    if not path.exists():
        return None
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "cscgra-v3-brainweb-sweep-manifest-v1":
        raise ValueError("unsupported BrainWeb manifest schema")
    return manifest


def manifest_entry(manifest: dict | None, identifier: str) -> dict | None:
    if manifest is None:
        return None
    return manifest.get("volumes", {}).get(identifier)


def aggregate_source(slice_records: list[dict]) -> dict:
    return {
        metric: distribution([float(record[metric]) for record in slice_records])
        for metric in ("snr_db", "psnr_db", "mse", "nmse", "ssim")
    }


def markdown(result: dict) -> str:
    stats = result["fixed_float_statistics"]
    source = result["source_statistics"]
    lines = [
        "# V3 BrainWeb source-domain sweep",
        "",
        f'- Result: **{"PASS" if result["pass"] else "FAIL"}**',
        f'- Provenance manifest verified: **{"YES" if result["manifest_verified"] else "NO"}**',
        f'- Volumes: `{result["volume_count"]}`; source slices: `{result["source_slice_count"]}`.',
        f'- Fixed-point checks: `{result["fixed_evaluations_passed"]}/{result["fixed_evaluations"]}`.',
        "- Scope: BrainWeb magnitude-image source domain with the V3 real Bernoulli operator.",
        "- This is not direct Fourier/raw-k-space RTL reconstruction and not clinical validation.",
        "",
        "## Aggregate Source Oracle",
        "",
        "| Metric | Mean | Median | P05 | P95 | Worst |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
        f'| SNR (dB) | {source["snr_db"]["mean"]:.6f} | {source["snr_db"]["median"]:.6f} | {source["snr_db"]["p05"]:.6f} | {source["snr_db"]["p95"]:.6f} | {source["snr_db"]["minimum"]:.6f} |',
        f'| PSNR (dB) | {source["psnr_db"]["mean"]:.6f} | {source["psnr_db"]["median"]:.6f} | {source["psnr_db"]["p05"]:.6f} | {source["psnr_db"]["p95"]:.6f} | {source["psnr_db"]["minimum"]:.6f} |',
        f'| MSE | {source["mse"]["mean"]:.6e} | {source["mse"]["median"]:.6e} | {source["mse"]["p05"]:.6e} | {source["mse"]["p95"]:.6e} | {source["mse"]["maximum"]:.6e} |',
        f'| NMSE | {source["nmse"]["mean"]:.6e} | {source["nmse"]["median"]:.6e} | {source["nmse"]["p05"]:.6e} | {source["nmse"]["p95"]:.6e} | {source["nmse"]["maximum"]:.6e} |',
        f'| SSIM | {source["ssim"]["mean"]:.6f} | {source["ssim"]["median"]:.6f} | {source["ssim"]["p05"]:.6f} | {source["ssim"]["p95"]:.6f} | {source["ssim"]["minimum"]:.6f} |',
        "",
        "## Fixed Versus Floating",
        "",
        f'- Worst SNR loss: `{stats["snr_gap_db"]["maximum"]:.6f} dB`.',
        f'- Worst MSE ratio: `{stats["mse_ratio"]["maximum"]:.6f}`.',
        f'- Worst NMSE ratio: `{stats["nmse_ratio"]["maximum"]:.6f}`.',
        f'- Worst SSIM drop: `{stats["ssim_drop"]["maximum"]:.6f}`.',
        f'- Minimum fixed-vs-float SSIM: `{stats["fixed_vs_float_ssim"]["minimum"]:.6f}`.',
        "",
        "## Coverage",
        "",
        "| Model | Modality | Noise | RF/INU | Volumes | Fixed checks |",
        "| --- | --- | --- | --- | ---: | ---: |",
    ]
    for row in result["coverage"]:
        lines.append(
            f'| {row["model"]} | {row["modality"]} | {row["noise"]} | '
            f'{row["field"]} | {row["volumes"]} | {row["fixed_evaluations"]} |')
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--numeric-candidate", choices=numerical_candidate.NAMES, default="production")
    parser.add_argument("--out-dir", type=Path, default=Path("reports/v3/brainweb_sweep"))
    parser.add_argument(
        "--cache-dir", type=Path, default=Path("reports/v3/datasets/brainweb_sweep"))
    parser.add_argument(
        "--manifest", type=Path, default=Path("config/v3_brainweb_sweep_manifest.json"))
    parser.add_argument("--models", default=",".join(DEFAULT_MODELS))
    parser.add_argument("--modalities", default=",".join(DEFAULT_MODALITIES))
    parser.add_argument("--noises", default=",".join(DEFAULT_NOISES))
    parser.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    parser.add_argument(
        "--source-slices", type=integer_csv,
        default=DEFAULT_SOURCE_SLICES)
    parser.add_argument(
        "--fixed-slices", type=integer_csv,
        default=DEFAULT_FIXED_SLICES)
    parser.add_argument("--fixed-blocks-per-volume", type=int, default=1)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--write-manifest", action="store_true")
    parser.add_argument("--require-manifest", action="store_true")
    args = parser.parse_args()
    numeric_profile, refinement_policy = numerical_candidate.configuration(args.numeric_candidate)

    models = csv_values(args.models)
    modalities = csv_values(args.modalities)
    noises = csv_values(args.noises)
    fields = csv_values(args.fields)
    unknown_models = set(models) - set(MODEL_CONFIG)
    if unknown_models:
        parser.error(f"unknown BrainWeb models: {sorted(unknown_models)}")
    for slice_index in (*args.source_slices, *args.fixed_slices):
        if not 0 <= slice_index < BRAINWEB_SHAPE[0]:
            parser.error(f"slice index out of range: {slice_index}")
    if args.fixed_blocks_per_volume < 1:
        parser.error("--fixed-blocks-per-volume must be positive")

    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    cache_dir = args.cache_dir if args.cache_dir.is_absolute() else ROOT / args.cache_dir
    manifest_path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(manifest_path)
    if args.require_manifest and manifest is None:
        raise FileNotFoundError(f"required BrainWeb manifest missing: {manifest_path}")

    cases = []
    captured_volumes = {}
    source_rows = []
    fixed_rows = []
    coverage = []
    for model in models:
        for modality in modalities:
            for noise in noises:
                for field in fields:
                    identifier = case_id(model, modality, noise, field)
                    expected = manifest_entry(manifest, identifier)
                    if args.require_manifest and expected is None:
                        raise ValueError(f"manifest entry missing: {identifier}")
                    expected_sha256 = expected.get("sha256") if expected else None
                    print(f"BrainWeb {identifier}", flush=True)
                    path, actual_sha256 = download_volume(
                        cache_dir, model, modality, noise, field,
                        expected_sha256, args.offline)
                    volume, byte_order = load_volume(path)
                    source_records = []
                    for slice_index in args.source_slices:
                        record = {
                            "slice_index": slice_index,
                            **blockwise_dct_oracle(volume[slice_index]),
                        }
                        source_records.append(record)
                        source_rows.append({
                            "case": identifier,
                            "model": model,
                            "modality": modality,
                            "noise": noise,
                            "field": field,
                            **{key: record[key] for key in (
                                "slice_index", "snr_db", "psnr_db", "mse", "nmse", "ssim")},
                        })
                    fixed_slices = [
                        (slice_index, volume[slice_index]) for slice_index in args.fixed_slices]
                    fixed_float = evaluate_fixed_float_blocks(
                        deterministic_content_blocks(
                            fixed_slices, args.fixed_blocks_per_volume),
                        numeric_profile, refinement_policy)
                    for sample in fixed_float["samples"]:
                        for algorithm, record in sample["algorithms"].items():
                            fixed_rows.append({
                                "case": identifier,
                                "sample": sample["name"],
                                "algorithm": algorithm,
                                "pass": record["pass"],
                                "snr_gap_db": record["snr_gap_db"],
                                "mse_ratio": record["mse_ratio_fixed_over_float"],
                                "nmse_ratio": record["nmse_ratio_fixed_over_float"],
                                "ssim_drop": record["ssim_drop"],
                                "fixed_vs_float_ssim": record["fixed_vs_float"]["ssim"],
                            })
                    provenance = {
                        "provider": "BrainWeb Simulated Brain Database, McGill University",
                        "alias": alias_for(model, modality, noise, field),
                        "endpoint": MODEL_CONFIG[model]["endpoint"],
                        "file": str(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path),
                        "sha256": actual_sha256,
                        "shape": list(BRAINWEB_SHAPE),
                        "byte_order": byte_order,
                        "intensity_range": [int(np.min(volume)), int(np.max(volume))],
                    }
                    captured_volumes[identifier] = provenance
                    cases.append({
                        "id": identifier,
                        "model": model,
                        "modality": modality,
                        "noise": noise,
                        "field": field,
                        "provenance": provenance,
                        "source_oracle": {
                            "slices": source_records,
                            "statistics": aggregate_source(source_records),
                        },
                        "fixed_float": fixed_float,
                    })
                    coverage.append({
                        "model": model,
                        "modality": modality,
                        "noise": noise,
                        "field": field,
                        "volumes": 1,
                        "fixed_evaluations": fixed_float["algorithm_evaluations"],
                    })

    selection = {
        "models": list(models),
        "modalities": list(modalities),
        "slice_thickness": "1mm",
        "noises": list(noises),
        "fields": list(fields),
        "source_slices": list(args.source_slices),
        "fixed_slices": list(args.fixed_slices),
        "fixed_blocks_per_volume": args.fixed_blocks_per_volume,
    }
    if args.write_manifest:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps({
            "schema": "cscgra-v3-brainweb-sweep-manifest-v1",
            "selection": selection,
            "volumes": captured_volumes,
        }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        manifest = load_manifest(manifest_path)

    manifest_verified = manifest is not None and all(
        (entry := manifest_entry(manifest, case["id"])) is not None
        and entry.get("sha256") == case["provenance"]["sha256"]
        for case in cases
    )
    fixed_evaluations = sum(case["fixed_float"]["algorithm_evaluations"] for case in cases)
    fixed_passed = sum(case["fixed_float"]["evaluations_passed"] for case in cases)
    source_records = [
        record for case in cases for record in case["source_oracle"]["slices"]]
    result = {
        "schema": "cscgra-v3-brainweb-sweep-v1",
        "pass": (
            fixed_passed == fixed_evaluations
            and (manifest_verified if args.require_manifest else True)
        ),
        "manifest_verified": manifest_verified,
        "manifest_required": args.require_manifest,
        "manifest": str(manifest_path.relative_to(ROOT) if manifest_path.is_relative_to(ROOT) else manifest_path),
        "selection": selection,
        "volume_count": len(cases),
        "source_slice_count": len(source_records),
        "fixed_evaluations": fixed_evaluations,
        "fixed_evaluations_passed": fixed_passed,
        "source_statistics": aggregate_source(source_records),
        "fixed_float_statistics": fixed_float_statistics(cases),
        "numeric_candidate": args.numeric_candidate,
        "numeric_profile": asdict(numeric_profile),
        "refinement_policy": asdict(refinement_policy),
        "geometry": {
            "m": BLOCK_M,
            "n": BLOCK_N,
            "k": BLOCK_SPARSITY,
            "phi_seed": BLOCK_PHI_SEED,
        },
        "claim_scope": "simulated-MRI source-domain fixed-point fidelity",
        "direct_raw_kspace_rtl_claim_ready": False,
        "coverage": coverage,
        "cases": cases,
    }
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    with (out_dir / "source_metrics.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(source_rows[0]))
        writer.writeheader()
        writer.writerows(source_rows)
    with (out_dir / "fixed_float_metrics.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(fixed_rows[0]))
        writer.writeheader()
        writer.writerows(fixed_rows)
    print(markdown(result))
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
