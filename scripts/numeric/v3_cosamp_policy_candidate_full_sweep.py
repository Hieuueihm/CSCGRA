#!/usr/bin/env python3
"""Run the frozen 3888-case sweep with only CoSaMP on the new policy."""

from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import date
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware
from scripts.numeric import v3_candidate_heldout_sweep as heldout
from scripts.numeric import v3_cosamp_policy_candidate_experiment as candidate
SCHEMA = "cscgra-v3-cosamp-policy-full-sweep-v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_baseline(path: Path) -> dict[tuple[str, str, int, str], dict]:
    result = {}
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            batch = json.loads(line)
            for record in batch["algorithms"]:
                key = (
                    batch["volume"],
                    batch["block"],
                    int(batch["phi_seed"]),
                    record["algorithm"],
                )
                result[key] = record
    return result


def failure_and_control_cases(baseline: dict) -> tuple[list[dict], list[dict]]:
    failures = []
    controls = []
    for (volume, block, phi_seed, algorithm), record in baseline.items():
        if algorithm != "CoSaMP":
            continue
        item = {
            "volume": volume,
            "block": block,
            "phi_seed": phi_seed,
            "baseline": record,
        }
        (failures if not record["pass"] else controls).append(item)
    return failures, controls


def aggregate(records: list[dict]) -> dict:
    events = {name: 0 for name in asdict(hardware.Events())}
    snr = []
    mse = []
    ssim = []
    for record in records:
        for name, value in record["events"].items():
            events[name] += int(value)
        snr.append(float(record["snr_gap_db"]))
        mse.append(float(record["mse_ratio"]))
        ssim.append(float(record["ssim_drop"]))
    return {
        "passed": sum(bool(record["pass"]) for record in records),
        "total": len(records),
        "support_exact": sum(bool(record["support_match"]) for record in records),
        "rollback_count": sum(int(record["rollback_count"]) for record in records),
        "numeric_events": sum(events.values()),
        "events": events,
        "max_snr_gap_db": max(snr),
        "max_mse_ratio": max(mse),
        "max_ssim_drop": max(ssim),
    }


def baseline_record(volume: str, block: str, phi_seed: int, algorithm: str, record: dict) -> dict:
    return {
        "volume": volume,
        "block": block,
        "phi_seed": phi_seed,
        "algorithm": algorithm,
        "pass": bool(record["pass"]),
        "support_match": bool(record["support_match"]),
        "rollback_count": int(record["rollback_count"]),
        "events": record["events"],
        "snr_gap_db": float(record["snr_gap_db"]),
        "mse_ratio": float(record["mse_ratio_fixed_over_float"]),
        "ssim_drop": float(record["ssim_drop"]),
    }


def candidate_record(item: dict) -> dict:
    paper = item["paper_metrics"]
    fixed = item["fixed_metrics"]
    return {
        "volume": item["volume"],
        "block": item["block"],
        "phi_seed": int(item["phi_seed"]),
        "algorithm": "CoSaMP",
        "pass": bool(item["candidate_pass"]),
        "support_match": item["paper_support"] == item["fixed_support"],
        "rollback_count": int(item["rollback_count"]),
        "events": item["events"],
        "snr_gap_db": float(paper["snr_db"]) - float(fixed["snr_db"]),
        "mse_ratio": float(fixed["mse"]) / float(paper["mse"]),
        "ssim_drop": float(paper["ssim"]) - float(fixed["ssim"]),
    }


def run(args: argparse.Namespace) -> dict:
    records_path = args.records if args.records.is_absolute() else ROOT / args.records
    manifest_path = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    if out_dir.exists():
        raise FileExistsError(f"refusing to overwrite: {out_dir}")
    baseline = read_baseline(records_path)
    if len(baseline) != 3888:
        raise ValueError(f"expected 3888 baseline records, found {len(baseline)}")
    failures, controls = failure_and_control_cases(baseline)
    candidate_results = candidate.evaluate(failures + controls, manifest_path)
    by_key = {
        (item["volume"], item["block"], int(item["phi_seed"])): item
        for item in candidate_results
    }
    combined = []
    for (volume, block, phi_seed, algorithm), record in baseline.items():
        if algorithm == "CoSaMP":
            combined.append(candidate_record(by_key[(volume, block, phi_seed)]))
        else:
            combined.append(baseline_record(volume, block, phi_seed, algorithm, record))
    algorithms = sorted({record["algorithm"] for record in combined})
    per_algorithm = {
        algorithm: aggregate([record for record in combined if record["algorithm"] == algorithm])
        for algorithm in algorithms
    }
    result = {
        "schema": SCHEMA,
        "date": date.today().isoformat(),
        "candidate": candidate.CANDIDATE,
        "manifest": str(manifest_path),
        "manifest_sha256": sha256_file(manifest_path),
        "baseline_records": str(records_path),
        "baseline_records_sha256": sha256_file(records_path),
        "coverage": {
            "blocks": 162,
            "phi_seeds": 3,
            "algorithms": len(algorithms),
            "evaluations": len(combined),
        },
        "profile": asdict(candidate.configuration()[0]),
        "refinement_policy": asdict(candidate.configuration()[1]),
        "aggregate": aggregate(combined),
        "per_algorithm": per_algorithm,
        "cosamp_candidate": aggregate([
            record for record in combined if record["algorithm"] == "CoSaMP"
        ]),
        "non_cosamp_baseline": aggregate([
            record for record in combined if record["algorithm"] != "CoSaMP"
        ]),
    }
    result["quality_pass"] = (
        result["aggregate"]["passed"] == result["aggregate"]["total"]
        and result["aggregate"]["rollback_count"] == 0
        and result["aggregate"]["numeric_events"] == 0
    )
    result["pass"] = (
        result["quality_pass"]
        and result["cosamp_candidate"]["support_exact"]
        == result["cosamp_candidate"]["total"]
    )
    out_dir.mkdir(parents=True)
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    lines = [
        "# CoSaMP Policy Candidate Frozen Full Sweep",
        "",
        f"- Date: `{result['date']}`",
        f"- Quality result: **{'PASS' if result['quality_pass'] else 'FAIL'}**.",
        f"- Candidate closure result: **{'PASS' if result['pass'] else 'OPEN'}**.",
        f"- Candidate: `{result['candidate']}`.",
        "- Frozen coverage: `162` blocks × `3` Phi seeds × `8` algorithms = `3888` evaluations.",
        "- Only CoSaMP uses the new policy; seven other algorithms use the unchanged quality_d22 baseline records.",
        "- Global exact-support count is reported separately because five known non-CoSaMP baseline cases remain support-mismatched.",
        "- D22 RTL remains inactive; this is software-model evidence only.",
        "",
        "## Gate",
        "",
        "| Scope | Pass | Support | Rollbacks | Numeric events | Max SNR gap | Max MSE ratio | Max SSIM drop |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for label, summary in (
        ("All 8 algorithms", result["aggregate"]),
        ("CoSaMP candidate", result["cosamp_candidate"]),
        ("Other algorithms baseline", result["non_cosamp_baseline"]),
    ):
        lines.append(
            f"| `{label}` | {summary['passed']}/{summary['total']} | "
            f"{summary['support_exact']}/{summary['total']} | {summary['rollback_count']} | "
            f"{summary['numeric_events']} | {summary['max_snr_gap_db']:.6f} | "
            f"{summary['max_mse_ratio']:.6f} | {summary['max_ssim_drop']:.6f} |"
        )
    lines += [
        "",
        "## Decision",
        "",
        "- The candidate is eligible for the next candidate-golden/model closure step only if the aggregate gate is PASS.",
        "- No production model, golden, RTL file or D22 activation is changed by this sweep.",
        "",
        "## Reproduction",
        "",
        "```text",
        "py -3 scripts/numeric/v3_cosamp_policy_candidate_full_sweep.py "
        "--records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl "
        "--manifest config/v3_p1_heldout_manifest.json "
        "--out-dir reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_full_v2",
        "```",
    ]
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    result = run(args)
    print(json.dumps({
        "pass": result["pass"],
        "aggregate": result["aggregate"],
        "cosamp_candidate": result["cosamp_candidate"],
    }, indent=2, sort_keys=True))
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
