#!/usr/bin/env python3
"""Freeze candidate-independent BrainWeb held-out blocks and Phi seeds."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.numeric.v3_brainweb_sweep import load_manifest, load_volume
from scripts.numeric.v3_golden_quality_gate import (
    APPLICATION_MSE_RATIO_MAX,
    APPLICATION_SNR_GAP_MAX_DB,
)
from scripts.numeric.v3_mri_quality_common import (
    APPLICATION_NMSE_RATIO_MAX,
    APPLICATION_SSIM_DROP_MAX,
    BLOCK_M,
    BLOCK_N,
    BLOCK_SPARSITY,
    deterministic_content_blocks,
    sha256_array,
    sha256_file,
)

SCHEMA = "cscgra-v3-brainweb-heldout-manifest-v1"
DOMAIN = "cscgra-v3-p1-heldout-v1"
DEFAULT_SLICES = (67, 112)
DEFAULT_BLOCKS_PER_VOLUME = 3
DEFAULT_PHI_SEED_COUNT = 3
DEVELOPMENT_SLICE = 90
DEVELOPMENT_PHI_SEED = 37
BLOCK_NAME = re.compile(r"slice(?P<slice>\d+)_r(?P<row>\d+)_c(?P<column>\d+)")


def integer_csv(value: str) -> tuple[int, ...]:
    return tuple(int(item.strip()) for item in value.split(",") if item.strip())


def canonical_bytes(value: dict) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def derive_phi_seed(source_manifest_sha256: str, ordinal: int) -> int:
    payload = f"{DOMAIN}:phi:{source_manifest_sha256}:{ordinal}".encode("ascii")
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "little")


def parse_block_name(name: str) -> tuple[int, int, int]:
    match = BLOCK_NAME.fullmatch(name)
    if match is None:
        raise ValueError(f"unsupported block name: {name}")
    return tuple(int(match.group(field)) for field in ("slice", "row", "column"))


def relative_path(path: Path) -> str:
    resolved = path.resolve()
    return str(resolved.relative_to(ROOT) if resolved.is_relative_to(ROOT) else resolved)


def build_manifest(source_manifest_path: Path, cache_dir: Path,
                   slices: tuple[int, ...], blocks_per_volume: int,
                   phi_seed_count: int) -> dict:
    source_manifest = load_manifest(source_manifest_path)
    if source_manifest is None:
        raise FileNotFoundError(f"source manifest missing: {source_manifest_path}")
    if DEVELOPMENT_SLICE in slices:
        raise ValueError(f"held-out slices must exclude development slice {DEVELOPMENT_SLICE}")
    if not slices or len(set(slices)) != len(slices):
        raise ValueError("held-out slices must be non-empty and unique")
    if blocks_per_volume < 1 or phi_seed_count < 1:
        raise ValueError("block and Phi-seed counts must be positive")

    source_manifest_sha256 = sha256_file(source_manifest_path)
    phi_seeds = [
        derive_phi_seed(source_manifest_sha256, ordinal)
        for ordinal in range(phi_seed_count)
    ]
    if len(set(phi_seeds)) != len(phi_seeds) or DEVELOPMENT_PHI_SEED in phi_seeds:
        raise ValueError("held-out Phi seeds collide with each other or the development seed")

    volumes = []
    for identifier, source in sorted(source_manifest["volumes"].items()):
        source_path = cache_dir / Path(source["file"]).name
        if not source_path.is_file():
            raise FileNotFoundError(f"held-out source missing: {source_path}")
        actual_sha256 = sha256_file(source_path)
        if actual_sha256 != source["sha256"]:
            raise ValueError(f"held-out source checksum mismatch: {identifier}")
        volume, byte_order = load_volume(source_path)
        selected = deterministic_content_blocks(
            [(slice_index, volume[slice_index]) for slice_index in slices],
            blocks_per_volume,
        )
        blocks = []
        for name, block in selected:
            slice_index, row, column = parse_block_name(name)
            blocks.append({
                "id": name,
                "slice": slice_index,
                "row": row,
                "column": column,
                "block_sha256": sha256_array(block),
            })
        volumes.append({
            "id": identifier,
            "source_file": relative_path(source_path),
            "source_sha256": actual_sha256,
            "byte_order": byte_order,
            "blocks": blocks,
        })

    return {
        "schema": SCHEMA,
        "domain_separator": DOMAIN,
        "candidate_independent": True,
        "source_manifest": relative_path(source_manifest_path),
        "source_manifest_sha256": source_manifest_sha256,
        "development_exclusion": {
            "fixed_slice": DEVELOPMENT_SLICE,
            "phi_seed": DEVELOPMENT_PHI_SEED,
        },
        "selection": {
            "slices": list(slices),
            "blocks_per_volume": blocks_per_volume,
            "method": "variance_quantiles_over_nonconstant_central_roi_blocks",
            "roi": [64, 192, 64, 192],
            "block_shape": [8, 8],
        },
        "phi": {
            "seed_derivation": "little_endian_u64(sha256(domain:phi:source_manifest_sha256:ordinal)[0:8])",
            "seeds": phi_seeds,
        },
        "geometry": {"m": BLOCK_M, "n": BLOCK_N, "k": BLOCK_SPARSITY},
        "quality_thresholds": {
            "snr_gap_max_db": APPLICATION_SNR_GAP_MAX_DB,
            "mse_ratio_max": APPLICATION_MSE_RATIO_MAX,
            "nmse_ratio_max": APPLICATION_NMSE_RATIO_MAX,
            "ssim_drop_max": APPLICATION_SSIM_DROP_MAX,
            "numeric_event_totals_max": 0,
        },
        "volume_count": len(volumes),
        "block_count": sum(len(volume["blocks"]) for volume in volumes),
        "planned_algorithm_evaluations": (
            sum(len(volume["blocks"]) for volume in volumes) * len(phi_seeds) * 8
        ),
        "volumes": volumes,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("write", "check"))
    parser.add_argument(
        "--source-manifest", type=Path,
        default=Path("config/v3_brainweb_sweep_manifest.json"))
    parser.add_argument(
        "--cache-dir", type=Path,
        default=Path("reports/v3/datasets/brainweb_sweep"))
    parser.add_argument(
        "--output", type=Path,
        default=Path("config/v3_p1_heldout_manifest.json"))
    parser.add_argument("--slices", type=integer_csv, default=DEFAULT_SLICES)
    parser.add_argument("--blocks-per-volume", type=int, default=DEFAULT_BLOCKS_PER_VOLUME)
    parser.add_argument("--phi-seed-count", type=int, default=DEFAULT_PHI_SEED_COUNT)
    args = parser.parse_args()

    source_manifest = args.source_manifest if args.source_manifest.is_absolute() else ROOT / args.source_manifest
    cache_dir = args.cache_dir if args.cache_dir.is_absolute() else ROOT / args.cache_dir
    output = args.output if args.output.is_absolute() else ROOT / args.output
    manifest = build_manifest(
        source_manifest, cache_dir, args.slices,
        args.blocks_per_volume, args.phi_seed_count,
    )
    payload = canonical_bytes(manifest)

    if args.mode == "write":
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("xb") as stream:
            stream.write(payload)
    else:
        if not output.is_file():
            raise FileNotFoundError(f"held-out manifest missing: {output}")
        if output.read_bytes() != payload:
            raise ValueError("held-out manifest differs from deterministic regeneration")

    print(json.dumps({
        "pass": True,
        "mode": args.mode,
        "output": relative_path(output),
        "output_sha256": sha256_file(output),
        "volume_count": manifest["volume_count"],
        "block_count": manifest["block_count"],
        "phi_seeds": manifest["phi"]["seeds"],
        "planned_algorithm_evaluations": manifest["planned_algorithm_evaluations"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
