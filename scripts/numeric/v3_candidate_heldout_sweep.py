#!/usr/bin/env python3
"""Run the frozen held-out BrainWeb block sweep for the D22 candidate."""

from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import date
from concurrent.futures import ProcessPoolExecutor
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, numerical_candidate, paper, phi_generator
from scripts.numeric.v3_brainweb_sweep import load_volume
from scripts.numeric.v3_mri_quality_common import (
    APPLICATION_NMSE_RATIO_MAX,
    APPLICATION_SSIM_DROP_MAX,
    BLOCK_M,
    BLOCK_N,
    BLOCK_SIZE,
    BLOCK_SPARSITY,
    image_metrics,
    mri_dct_forward,
    mri_dct_inverse,
    resized,
    sha256_array,
    sha256_file,
    topk_sparse,
)
from scripts.numeric.v3_golden_quality_gate import (
    APPLICATION_MSE_RATIO_MAX,
    APPLICATION_SNR_GAP_MAX_DB,
    policy_for,
)


ALGORITHMS = tuple(paper.ALGORITHMS)
MANIFEST_SCHEMA = "cscgra-v3-brainweb-heldout-manifest-v1"
RESULT_SCHEMA = "cscgra-v3-d22-heldout-sweep-v1"


def finite_metric(value: float) -> float | str:
    if math.isinf(value):
        return "inf" if value > 0 else "-inf"
    return float(value)


def ratio(numerator: float, denominator: float) -> float:
    if denominator > 0.0:
        return numerator / denominator
    return 1.0 if numerator == 0.0 else math.inf


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema") != MANIFEST_SCHEMA:
        raise ValueError(f"unsupported held-out manifest schema: {path}")
    return manifest


def block_from_volume(volume: np.ndarray, block: dict) -> np.ndarray:
    image = resized(volume[block["slice"]]) - 0.5
    row = block["row"]
    column = block["column"]
    selected = image[row:row + BLOCK_SIZE, column:column + BLOCK_SIZE]
    if selected.shape != (BLOCK_SIZE, BLOCK_SIZE):
        raise ValueError(f"held-out block is not {BLOCK_SIZE}x{BLOCK_SIZE}: {block['id']}")
    if sha256_array(selected) != block["block_sha256"]:
        raise ValueError(f"held-out block checksum mismatch: {block['id']}")
    return np.asarray(selected, dtype=np.float64).reshape(-1)


def _evaluate_block_seed(
    block_id: str,
    block: np.ndarray,
    phi_seed: int,
    profile_name: str,
) -> list[dict]:
    numeric_profile, refinement_policy = numerical_candidate.configuration(profile_name)
    phi = phi_generator.matrix(phi_seed, BLOCK_M, BLOCK_N)
    policy = policy_for(phi)
    original = np.asarray(block, dtype=np.float64).reshape(-1)
    sparse_target = topk_sparse(mri_dct_forward(original))
    target_peak = max(float(np.max(np.abs(sparse_target))), 1e-30)
    normalization_scale = 0.75 / target_peak
    measurement = phi @ (sparse_target * normalization_scale)
    records = []
    for algorithm in ALGORITHMS:
        floating = paper.run(algorithm, phi, measurement, policy)
        fixed = hardware.run(
            algorithm, phi, measurement, policy,
            numeric_profile, refinement_policy,
        )
        floating_x = np.asarray(floating.x, dtype=np.float64) / normalization_scale
        fixed_x = (
            np.asarray(fixed.x, dtype=np.float64)
            / (1 << numeric_profile.data_f)
            / normalization_scale
        )
        floating_image = mri_dct_inverse(floating_x).reshape(BLOCK_SIZE, BLOCK_SIZE)
        fixed_image = mri_dct_inverse(fixed_x).reshape(BLOCK_SIZE, BLOCK_SIZE)
        original_image = original.reshape(BLOCK_SIZE, BLOCK_SIZE)
        floating_metrics = image_metrics(original_image, floating_image)
        fixed_metrics = image_metrics(original_image, fixed_image)
        fixed_float_metrics = image_metrics(floating_image, fixed_image)
        snr_gap = float(floating_metrics["snr_db"]) - float(fixed_metrics["snr_db"])
        mse_ratio = ratio(float(fixed_metrics["mse"]), float(floating_metrics["mse"]))
        nmse_ratio = ratio(float(fixed_metrics["nmse"]), float(floating_metrics["nmse"]))
        ssim_drop = float(floating_metrics["ssim"]) - float(fixed_metrics["ssim"])
        events = asdict(fixed.events)
        rollback_count = sum(
            phase.name == "REFINEMENT_ROLLBACK" for phase in fixed.phases)
        passed = (
            snr_gap <= APPLICATION_SNR_GAP_MAX_DB
            and mse_ratio <= APPLICATION_MSE_RATIO_MAX
            and nmse_ratio <= APPLICATION_NMSE_RATIO_MAX
            and ssim_drop <= APPLICATION_SSIM_DROP_MAX
            and not any(events.values())
            and rollback_count == 0
        )
        records.append({
            "block": block_id,
            "phi_seed": int(phi_seed),
            "algorithm": algorithm,
            "pass": bool(passed),
            "support_match": floating.support == fixed.support,
            "paper_support": list(floating.support),
            "fixed_support": list(fixed.support),
            "paper_stop_reason": floating.stop_reason,
            "fixed_stop_reason": fixed.stop_reason,
            "rollback_count": rollback_count,
            "events": events,
            "floating": floating_metrics,
            "fixed": fixed_metrics,
            "fixed_vs_float": fixed_float_metrics,
            "snr_gap_db": finite_metric(snr_gap),
            "mse_ratio_fixed_over_float": finite_metric(mse_ratio),
            "nmse_ratio_fixed_over_float": finite_metric(nmse_ratio),
            "ssim_drop": float(ssim_drop),
        })
    return records


def _source_path(manifest_path: Path, source_file: str) -> Path:
    candidate_path = Path(source_file)
    if candidate_path.is_absolute():
        return candidate_path
    return ROOT / candidate_path


def _stats(values: list[float]) -> dict[str, float | int]:
    array = np.asarray(values, dtype=np.float64)
    return {
        "count": int(array.size),
        "mean": float(np.mean(array)),
        "median": float(np.median(array)),
        "p95": float(np.percentile(array, 95)),
        "maximum": float(np.max(array)),
    }


def aggregate_records(records: list[dict]) -> dict:
    def numeric(field: str) -> list[float]:
        return [float(record[field]) for record in records
                if not isinstance(record[field], str)]

    events = {
        name: sum(int(record["events"].get(name, 0)) for record in records)
        for name in asdict(hardware.Events())
    }
    per_algorithm = {}
    for algorithm in ALGORITHMS:
        selected = [record for record in records if record["algorithm"] == algorithm]
        per_algorithm[algorithm] = {
            "pass": sum(record["pass"] for record in selected) == len(selected),
            "passed": sum(record["pass"] for record in selected),
            "total": len(selected),
            "support_exact": sum(record["support_match"] for record in selected),
            "rollback_count": sum(record["rollback_count"] for record in selected),
            "snr_gap_db": _stats(numeric_for(selected, "snr_gap_db")),
            "mse_ratio_fixed_over_float": _stats(
                numeric_for(selected, "mse_ratio_fixed_over_float")),
            "nmse_ratio_fixed_over_float": _stats(
                numeric_for(selected, "nmse_ratio_fixed_over_float")),
            "ssim_drop": _stats(numeric_for(selected, "ssim_drop")),
        }
    return {
        "passed": sum(record["pass"] for record in records),
        "total": len(records),
        "support_exact": sum(record["support_match"] for record in records),
        "rollback_count": sum(record["rollback_count"] for record in records),
        "events": events,
        "snr_gap_db": _stats(numeric("snr_gap_db")),
        "mse_ratio_fixed_over_float": _stats(numeric("mse_ratio_fixed_over_float")),
        "nmse_ratio_fixed_over_float": _stats(
            numeric("nmse_ratio_fixed_over_float")),
        "ssim_drop": _stats(numeric("ssim_drop")),
        "per_algorithm": per_algorithm,
    }


def numeric_for(records: list[dict], field: str) -> list[float]:
    return [float(record[field]) for record in records
            if not isinstance(record[field], str)]


def markdown(result: dict) -> str:
    aggregate = result["aggregate"]
    lines = [
        "# V3 D22 Held-out Candidate Sweep",
        "",
        f'- Date: `{result["date"]}`',
        f'- Result: **{"PASS" if result["pass"] else "FAIL"}**',
        f'- Candidate: `{result["numeric_candidate"]}` (`D22F18/S31F23/ACC70`).',
        f'- Frozen manifest: `{result["manifest"]}`.',
        f'- Coverage: `{result["block_count"]}` blocks × '
        f'`{result["phi_seed_count"]}` Phi seeds × `{len(ALGORITHMS)}` algorithms '
        f'= `{aggregate["total"]}` evaluations.',
        "- Scope: held-out BrainWeb source-domain 8x8 blocks with the V3 real "
        "Bernoulli operator; this is not raw-k-space RTL or clinical validation.",
        "",
        "## Gate",
        "",
        "| Metric | Result |",
        "| --- | ---: |",
        f'| Evaluations | `{aggregate["passed"]}/{aggregate["total"]}` |',
        f'| Exact support | `{aggregate["support_exact"]}/{aggregate["total"]}` |',
        f'| Rollbacks | `{aggregate["rollback_count"]}` |',
        f'| Numeric events | `{sum(aggregate["events"].values())}` |',
        f'| Worst SNR loss | `{aggregate["snr_gap_db"]["maximum"]:.6f} dB` |',
        f'| Worst MSE ratio | `{aggregate["mse_ratio_fixed_over_float"]["maximum"]:.6f}` |',
        f'| Worst NMSE ratio | `{aggregate["nmse_ratio_fixed_over_float"]["maximum"]:.6f}` |',
        f'| Worst SSIM drop | `{aggregate["ssim_drop"]["maximum"]:.6f}` |',
        "",
        "## By Algorithm",
        "",
        "| Algorithm | Passed | Support | Rollback | Max SNR loss | Max MSE ratio | Max SSIM drop |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for algorithm in ALGORITHMS:
        row = aggregate["per_algorithm"][algorithm]
        lines.append(
            f'| `{algorithm}` | {row["passed"]}/{row["total"]} | '
            f'{row["support_exact"]}/{row["total"]} | {row["rollback_count"]} | '
            f'{row["snr_gap_db"]["maximum"]:.6f} | '
            f'{row["mse_ratio_fixed_over_float"]["maximum"]:.6f} | '
            f'{row["ssim_drop"]["maximum"]:.6f} |'
        )
    lines += [
        "",
        "## Thresholds",
        "",
        f'- SNR loss <= `{APPLICATION_SNR_GAP_MAX_DB:.3f} dB`.',
        f'- MSE ratio <= `{APPLICATION_MSE_RATIO_MAX:.3f}`; NMSE ratio <= '
        f'`{APPLICATION_NMSE_RATIO_MAX:.3f}`.',
        f'- SSIM drop <= `{APPLICATION_SSIM_DROP_MAX:.3f}`.',
        "- Numeric events and refinement rollbacks must both be zero.",
        "",
        "## Non-claims",
        "",
        "- A PASS here closes candidate fixed-point held-out quality only; it does "
        "not close candidate end-to-end RTL/model bit-exact behavior.",
        "- D22 remains inactive in production `rtl/v3/files.f`; synthesis, timing, "
        "LUT/FF/BRAM/DSP and 100 MHz claims are not made.",
        "",
        "## Reproduction",
        "",
        "```text",
        "py -3 scripts/numeric/v3_freeze_heldout_manifest.py check",
        "py -3 scripts/numeric/v3_candidate_heldout_sweep.py --numeric-candidate quality_d22 --workers 8 --out-dir reports/v3/optimization_follow_20260907/p1_8/heldout_d22",
        "```",
    ]
    return "\n".join(lines) + "\n"


def run(args: argparse.Namespace) -> dict:
    manifest_path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    manifest = load_manifest(manifest_path)
    if manifest.get("candidate_independent") is not True:
        raise ValueError("held-out manifest must be candidate-independent")
    numeric_profile, refinement_policy = numerical_candidate.configuration(
        args.numeric_candidate)
    if args.numeric_candidate != "quality_d22":
        raise ValueError("P1.8 held-out sweep is reserved for quality_d22")
    if args.workers < 1:
        raise ValueError("workers must be positive")

    out_dir.mkdir(parents=True, exist_ok=True)
    records_path = out_dir / "records.jsonl"
    source_records = []
    blocks = []
    for volume in manifest["volumes"]:
        source_path = _source_path(manifest_path, volume["source_file"])
        if not source_path.is_file():
            raise FileNotFoundError(f"held-out source missing: {source_path}")
        actual_source_hash = sha256_file(source_path)
        if actual_source_hash != volume["source_sha256"]:
            raise ValueError(f"held-out source hash mismatch: {volume['id']}")
        loaded, byte_order = load_volume(source_path)
        if byte_order != volume["byte_order"]:
            raise ValueError(f"held-out byte order mismatch: {volume['id']}")
        source_records.append({
            "id": volume["id"],
            "source_file": volume["source_file"],
            "source_sha256": actual_source_hash,
        })
        for block in volume["blocks"]:
            blocks.append((
                volume["id"], block["id"], block_from_volume(loaded, block), block,
            ))

    existing = {}
    if args.resume and records_path.is_file():
        with records_path.open("r", encoding="utf-8") as stream:
            for line in stream:
                record = json.loads(line)
                existing[(record["volume"], record["block"], record["phi_seed"])] = record
    ordered_records = []
    pending = []
    for volume_id, block_id, block_values, _ in blocks:
        for phi_seed in manifest["phi"]["seeds"]:
            key = (volume_id, block_id, int(phi_seed))
            if key in existing:
                ordered_records.extend(existing[key]["algorithms"])
            else:
                pending.append((volume_id, block_id, block_values, int(phi_seed)))

    worker_count = min(args.workers, max(1, os.cpu_count() or 1))
    if pending:
        executor = ProcessPoolExecutor(max_workers=worker_count) if worker_count > 1 else None
        try:
            if executor is None:
                batches = [
                    _evaluate_block_seed(block_id, block_values, phi_seed,
                                         args.numeric_candidate)
                    for _, block_id, block_values, phi_seed in pending
                ]
            else:
                batches = list(executor.map(
                    _evaluate_block_seed,
                    [item[1] for item in pending],
                    [item[2] for item in pending],
                    [item[3] for item in pending],
                    [args.numeric_candidate] * len(pending),
                ))
        finally:
            if executor is not None:
                executor.shutdown()
        by_key = {}
        for item, batch in zip(pending, batches):
            volume_id, block_id, _, phi_seed = item
            for record in batch:
                record["volume"] = volume_id
                by_key.setdefault((volume_id, block_id, phi_seed), []).append(record)
        with records_path.open("w", encoding="utf-8") as stream:
            for volume_id, block_id, _, phi_seed in blocks:
                for seed in manifest["phi"]["seeds"]:
                    key = (volume_id, block_id, int(seed))
                    batch = by_key.get(key)
                    if batch is None:
                        batch = existing[key]["algorithms"]
                    stream.write(json.dumps({
                        "volume": volume_id,
                        "block": block_id,
                        "phi_seed": int(seed),
                        "algorithms": batch,
                    }, sort_keys=True) + "\n")

    grouped = {}
    with records_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            group = json.loads(line)
            grouped[(group["volume"], group["block"], group["phi_seed"])] = group
    all_records = [
        record
        for volume_id, block_id, _, _ in blocks
        for phi_seed in manifest["phi"]["seeds"]
        for record in grouped[(volume_id, block_id, int(phi_seed))]["algorithms"]
    ]
    aggregate = aggregate_records(all_records)
    expected_total = manifest["planned_algorithm_evaluations"]
    if aggregate["total"] != expected_total:
        raise RuntimeError(
            f"held-out evaluation count mismatch: {aggregate['total']} != {expected_total}")
    result = {
        "schema": RESULT_SCHEMA,
        "date": date.today().isoformat(),
        "pass": aggregate["passed"] == aggregate["total"]
        and aggregate["rollback_count"] == 0
        and sum(aggregate["events"].values()) == 0,
        "numeric_candidate": args.numeric_candidate,
        "numeric_profile": asdict(numeric_profile),
        "refinement_policy": asdict(refinement_policy),
        "manifest": str(manifest_path.relative_to(ROOT)
                         if manifest_path.is_relative_to(ROOT) else manifest_path),
        "manifest_sha256": sha256_file(manifest_path),
        "source_manifest_sha256": manifest["source_manifest_sha256"],
        "volume_count": manifest["volume_count"],
        "block_count": manifest["block_count"],
        "phi_seed_count": len(manifest["phi"]["seeds"]),
        "phi_seeds": manifest["phi"]["seeds"],
        "algorithm_count": len(ALGORITHMS),
        "sources": source_records,
        "aggregate": aggregate,
        "thresholds": {
            "snr_gap_max_db": APPLICATION_SNR_GAP_MAX_DB,
            "mse_ratio_max": APPLICATION_MSE_RATIO_MAX,
            "nmse_ratio_max": APPLICATION_NMSE_RATIO_MAX,
            "ssim_drop_max": APPLICATION_SSIM_DROP_MAX,
            "numeric_event_totals_max": 0,
            "rollback_count_max": 0,
        },
        "records_file": "records.jsonl",
        "claim_scope": "held-out BrainWeb source-domain candidate fixed-point fidelity",
        "candidate_rtl_bit_exact_claim_ready": False,
    }
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    print(markdown(result), end="")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--numeric-candidate", choices=numerical_candidate.NAMES,
                        default="quality_d22")
    parser.add_argument("--manifest", type=Path,
                        default=Path("config/v3_p1_heldout_manifest.json"))
    parser.add_argument("--out-dir", type=Path,
                        default=Path("reports/v3/optimization_follow_20260907/p1_8/heldout_d22"))
    parser.add_argument("--workers", type=int,
                        default=min(8, max(1, os.cpu_count() or 1)))
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    result = run(args)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
