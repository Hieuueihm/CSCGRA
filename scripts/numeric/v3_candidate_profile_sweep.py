#!/usr/bin/env python3
"""Screen previously-defined numeric candidates on the frozen held-out set."""

from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import date
import json
import os
from pathlib import Path
import sys
from concurrent.futures import ProcessPoolExecutor


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import numerical_candidate
from scripts.numeric import v3_candidate_heldout_sweep as heldout


SCHEMA = "cscgra-v3-candidate-profile-sweep-v1"


def load_failure_keys(records_path: Path) -> set[tuple[str, str, int]]:
    failures = set()
    with records_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            batch = json.loads(line)
            for record in batch["algorithms"]:
                if record["algorithm"] == "CoSaMP" and not record["pass"]:
                    failures.add((
                        batch["volume"], batch["block"], int(batch["phi_seed"]),
                    ))
    return failures


def source_blocks(manifest_path: Path, manifest: dict) -> tuple[list[dict], list[dict]]:
    sources = []
    blocks = []
    for volume in manifest["volumes"]:
        source_path = heldout._source_path(manifest_path, volume["source_file"])
        if not source_path.is_file():
            raise FileNotFoundError(source_path)
        actual_hash = heldout.sha256_file(source_path)
        if actual_hash != volume["source_sha256"]:
            raise ValueError(f"source hash mismatch: {volume['id']}")
        loaded, byte_order = heldout.load_volume(source_path)
        if byte_order != volume["byte_order"]:
            raise ValueError(f"byte order mismatch: {volume['id']}")
        sources.append({
            "id": volume["id"],
            "source_file": volume["source_file"],
            "source_sha256": actual_hash,
        })
        for block in volume["blocks"]:
            blocks.append({
                "volume": volume["id"],
                "block": block["id"],
                "values": heldout.block_from_volume(loaded, block),
            })
    return sources, blocks


def evaluate_candidate(
    blocks: list[dict],
    seeds: list[int],
    candidate: str,
    selected: set[tuple[str, str, int]] | None,
    workers: int,
) -> list[dict]:
    pending = [
        (item["volume"], item["block"], item["values"], int(seed))
        for item in blocks
        for seed in seeds
        if selected is None or (item["volume"], item["block"], int(seed)) in selected
    ]
    if not pending:
        return []
    worker_count = min(max(1, workers), max(1, os.cpu_count() or 1))
    if worker_count == 1:
        batches = [
            heldout._evaluate_block_seed(block, values, seed, candidate)
            for _, block, values, seed in pending
        ]
    else:
        with ProcessPoolExecutor(max_workers=worker_count) as executor:
            batches = list(executor.map(
                heldout._evaluate_block_seed,
                [item[1] for item in pending],
                [item[2] for item in pending],
                [item[3] for item in pending],
                [candidate] * len(pending),
            ))
    records = []
    for item, batch in zip(pending, batches):
        volume, block, _, seed = item
        for record in batch:
            record["volume"] = volume
            record["block"] = block
            record["phi_seed"] = int(seed)
            records.append(record)
    return records


def aggregate(records: list[dict]) -> dict:
    selected = [record for record in records if record["algorithm"] == "CoSaMP"]
    if not selected:
        raise ValueError("candidate screen produced no CoSaMP records")
    numeric = lambda field: [float(record[field]) for record in selected
                             if not isinstance(record[field], str)]
    def stats(field: str) -> dict[str, float | int]:
        values = numeric(field)
        return {
            "count": len(values),
            "maximum": max(values) if values else None,
            "mean": sum(values) / len(values) if values else None,
        }
    events = {}
    for record in selected:
        for name, value in record["events"].items():
            events[name] = events.get(name, 0) + int(value)
    return {
        "passed": sum(bool(record["pass"]) for record in selected),
        "total": len(selected),
        "support_exact": sum(bool(record["support_match"]) for record in selected),
        "rollback_count": sum(int(record["rollback_count"]) for record in selected),
        "events": events,
        "snr_gap_db": stats("snr_gap_db"),
        "mse_ratio_fixed_over_float": stats("mse_ratio_fixed_over_float"),
        "nmse_ratio_fixed_over_float": stats("nmse_ratio_fixed_over_float"),
        "ssim_drop": stats("ssim_drop"),
    }


def candidate_passes(summary: dict) -> bool:
    return (
        summary["passed"] == summary["total"]
        and summary["support_exact"] == summary["total"]
        and summary["rollback_count"] == 0
        and sum(summary["events"].values()) == 0
        and summary["snr_gap_db"]["maximum"] <= heldout.APPLICATION_SNR_GAP_MAX_DB
        and summary["mse_ratio_fixed_over_float"]["maximum"] <= heldout.APPLICATION_MSE_RATIO_MAX
        and summary["nmse_ratio_fixed_over_float"]["maximum"] <= heldout.APPLICATION_NMSE_RATIO_MAX
        and summary["ssim_drop"]["maximum"] <= heldout.APPLICATION_SSIM_DROP_MAX
    )


def markdown(result: dict) -> str:
    lines = [
        "# P1.8 CoSaMP Candidate Profile Screen",
        "",
        f'- Date: `{result["date"]}`',
        f'- Scope: `{result["scope"]}` on the frozen manifest.',
        f'- Candidate count: `{len(result["candidates"])}`.',
        f'- Candidate-independent input: **{result["candidate_independent"]}**.',
        "",
        "## Results",
        "",
        "| Candidate | Profile | Pass | Support | Rollback | Max SNR gap dB | Max MSE ratio | Max SSIM drop |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for name, record in result["candidates"].items():
        profile = record["numeric_profile"]
        summary = record["aggregate"]
        lines.append(
            f'| `{name}` | `D{profile["data_w"]}F{profile["data_f"]}/'
            f'S{profile["solver_w"]}F{profile["solver_f"]}/ACC{profile["acc_w"]}` | '
            f'**{"PASS" if record["pass"] else "FAIL"}** | '
            f'{summary["passed"]}/{summary["total"]} | '
            f'{summary["rollback_count"]} | '
            f'{summary["snr_gap_db"]["maximum"]:.6f} | '
            f'{summary["mse_ratio_fixed_over_float"]["maximum"]:.6f} | '
            f'{summary["ssim_drop"]["maximum"]:.6f} |'
        )
    lines.extend([
        "",
        "## Contract",
        "",
        "- Candidates are the existing entries in `models/v3/numerical_candidate.py`; no new profile or threshold is introduced.",
        "- All evaluations use the frozen blocks, Phi seeds and source hashes from `config/v3_p1_heldout_manifest.json`.",
        "- This is a diagnostic screen. It does not activate D22 or modify production RTL/goldens.",
        "",
        "## Reproduction",
        "",
        "```text",
        "py -3 scripts/numeric/v3_candidate_profile_sweep.py "
        "--records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl "
        "--manifest config/v3_p1_heldout_manifest.json "
        "--scope failures "
        "--out-dir reports/v3/optimization_follow_20260907/p1_8/candidate_profile_screen",
        "```",
    ])
    return "\n".join(lines) + "\n"


def run(args: argparse.Namespace) -> dict:
    manifest_path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    if out_dir.exists():
        raise FileExistsError(f"refusing to overwrite: {out_dir}")
    manifest = heldout.load_manifest(manifest_path)
    if manifest.get("candidate_independent") is not True:
        raise ValueError("held-out manifest must be candidate-independent")
    records_path = args.records if args.records.is_absolute() else ROOT / args.records
    sources, blocks = source_blocks(manifest_path, manifest)
    selected = None
    if args.scope == "failures":
        selected = load_failure_keys(records_path)
        if not selected:
            raise ValueError("no frozen CoSaMP failures found")
    names = tuple(args.candidates) if args.candidates else numerical_candidate.NAMES
    for name in names:
        numerical_candidate.configuration(name)
    out_dir.mkdir(parents=True)
    candidates = {}
    for name in names:
        records = evaluate_candidate(
            blocks, [int(seed) for seed in manifest["phi"]["seeds"]],
            name, selected, args.workers,
        )
        summary = aggregate(records)
        profile, refinement = numerical_candidate.configuration(name)
        failures = [
            {
                "volume": record["volume"],
                "block": record["block"],
                "phi_seed": record["phi_seed"],
                "support_match": record["support_match"],
                "pass": record["pass"],
                "stop_reason": record["fixed_stop_reason"],
                "rollback_count": record["rollback_count"],
                "snr_gap_db": record["snr_gap_db"],
                "mse_ratio_fixed_over_float": record["mse_ratio_fixed_over_float"],
                "ssim_drop": record["ssim_drop"],
            }
            for record in records
            if record["algorithm"] == "CoSaMP"
            and (not record["pass"] or not record["support_match"]
                 or record["rollback_count"] != 0)
        ]
        candidates[name] = {
            "pass": candidate_passes(summary),
            "numeric_profile": asdict(profile),
            "refinement_policy": asdict(refinement),
            "aggregate": summary,
            "failures": failures,
        }
    result = {
        "schema": SCHEMA,
        "date": date.today().isoformat(),
        "scope": args.scope,
        "candidate_independent": True,
        "manifest": str(manifest_path),
        "manifest_sha256": heldout.sha256_file(manifest_path),
        "records": str(records_path),
        "records_sha256": heldout.sha256_file(records_path),
        "source_count": len(sources),
        "block_count": len(blocks),
        "seed_count": len(manifest["phi"]["seeds"]),
        "selected_case_count": len(selected) if selected is not None else len(blocks) * len(manifest["phi"]["seeds"]),
        "candidates": candidates,
        "thresholds": {
            "snr_gap_max_db": heldout.APPLICATION_SNR_GAP_MAX_DB,
            "mse_ratio_max": heldout.APPLICATION_MSE_RATIO_MAX,
            "nmse_ratio_max": heldout.APPLICATION_NMSE_RATIO_MAX,
            "ssim_drop_max": heldout.APPLICATION_SSIM_DROP_MAX,
            "rollback_count_max": 0,
            "numeric_event_totals_max": 0,
        },
    }
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (out_dir / "summary.md").write_text(markdown(result), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--scope", choices=("failures", "full"), default="failures")
    parser.add_argument("--candidates", nargs="*", choices=numerical_candidate.NAMES)
    parser.add_argument("--workers", type=int, default=min(8, max(1, os.cpu_count() or 1)))
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.workers < 1:
        raise SystemExit("workers must be positive")
    result = run(args)
    print(markdown(result), end="")
    return 0 if all(item["pass"] for item in result["candidates"].values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
