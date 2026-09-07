#!/usr/bin/env python3
"""Run one isolated CoSaMP policy candidate on frozen failure controls."""

from __future__ import annotations

import argparse
from dataclasses import asdict, replace
from datetime import date
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware
from scripts.numeric import v3_candidate_heldout_sweep as heldout
from scripts.numeric import v3_cosamp_failure_audit as audit

SCHEMA = "cscgra-v3-cosamp-policy-candidate-experiment-v4"
CANDIDATE = "cosamp_data_d27_shift18_r32"


def configuration() -> tuple[hardware.NumericProfile, hardware.RefinementPolicy]:
    return (
        replace(
            hardware.NumericProfile(),
            data_w=27,
            data_f=23,
            solver_w=31,
            solver_f=23,
            acc_w=70,
        ),
        replace(
            hardware.RefinementPolicy(),
            strict_normal_residual_shift=18,
            reliable_recompute_interval=32,
        ),
    )


def read_cases(path: Path, control_count: int) -> tuple[list[dict], list[dict]]:
    failures = []
    controls = []
    with path.open("r", encoding="utf-8") as stream:
        for line in stream:
            batch = json.loads(line)
            for record in batch["algorithms"]:
                if record["algorithm"] != "CoSaMP":
                    continue
                item = {
                    "volume": batch["volume"],
                    "block": batch["block"],
                    "phi_seed": int(batch["phi_seed"]),
                    "baseline": record,
                }
                (failures if not record["pass"] else controls).append(item)
    if len(failures) != 15:
        raise ValueError(f"expected 15 frozen failures, found {len(failures)}")
    return failures, controls[:control_count]


def evaluate(cases: list[dict], manifest_path: Path) -> list[dict]:
    manifest = heldout.load_manifest(manifest_path)
    entries = {item["id"]: item for item in manifest["volumes"]}
    volumes = {}
    profile, refinement = configuration()
    results = []
    for case in cases:
        entry = entries[case["volume"]]
        source_path = ROOT / entry["source_file"]
        if case["volume"] not in volumes:
            volumes[case["volume"]] = heldout.load_volume(source_path)[0]
        block_entry = next(item for item in entry["blocks"] if item["id"] == case["block"])
        block = heldout.block_from_volume(volumes[case["volume"]], block_entry)
        result = audit.evaluate_case(
            {
                "volume": case["volume"],
                "block": case["block"],
                "source_sha256": entry["source_sha256"],
            },
            block,
            case["phi_seed"],
            profile,
            refinement,
        )
        candidate_pass = bool(
            float(result["paper_metrics"]["snr_db"])
            - float(result["fixed_metrics"]["snr_db"]) <= 0.5
            and float(result["fixed_metrics"]["mse"])
            / float(result["paper_metrics"]["mse"]) <= 1.1
            and float(result["paper_metrics"]["ssim"])
            - float(result["fixed_metrics"]["ssim"]) <= 0.005
            and not any(result["events"].values())
            and not result["rollback_iterations"]
        )
        results.append({
            "volume": case["volume"],
            "block": case["block"],
            "phi_seed": case["phi_seed"],
            "baseline_pass": bool(case["baseline"]["pass"]),
            "candidate_pass": candidate_pass,
            "first_divergence": result["first_divergence"],
            "paper_support": result["paper_support"],
            "fixed_support": result["fixed_support"],
            "fixed_stop_reason": result["fixed_stop_reason"],
            "rollback_count": len(result["rollback_iterations"]),
            "events": result["events"],
            "paper_metrics": result["paper_metrics"],
            "fixed_metrics": result["fixed_metrics"],
        })
    return results


def aggregate(results: list[dict]) -> dict:
    snr = [
        float(item["paper_metrics"]["snr_db"])
        - float(item["fixed_metrics"]["snr_db"])
        for item in results
    ]
    mse = [
        float(item["fixed_metrics"]["mse"])
        / float(item["paper_metrics"]["mse"])
        for item in results
    ]
    ssim = [
        float(item["paper_metrics"]["ssim"])
        - float(item["fixed_metrics"]["ssim"])
        for item in results
    ]
    events = {
        name: sum(int(item["events"].get(name, 0)) for item in results)
        for name in asdict(hardware.Events())
    }
    return {
        "passed": sum(item["candidate_pass"] for item in results),
        "total": len(results),
        "support_exact": sum(item["paper_support"] == item["fixed_support"] for item in results),
        "rollback_count": sum(item["rollback_count"] for item in results),
        "numeric_events": sum(events.values()),
        "max_snr_gap_db": max(snr),
        "max_mse_ratio": max(mse),
        "max_ssim_drop": max(ssim),
    }


def run(args: argparse.Namespace) -> dict:
    manifest = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    records = args.records if args.records.is_absolute() else ROOT / args.records
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    if out_dir.exists():
        raise FileExistsError(f"refusing to overwrite: {out_dir}")
    failures, controls = read_cases(records, args.controls)
    profile, refinement = configuration()
    failure_results = evaluate(failures, manifest)
    control_results = evaluate(controls, manifest)
    result = {
        "schema": SCHEMA,
        "date": date.today().isoformat(),
        "candidate": CANDIDATE,
        "manifest": str(manifest),
        "records": str(records),
        "numeric_profile": asdict(profile),
        "refinement_policy": asdict(refinement),
        "failure_set": aggregate(failure_results),
        "control_set": aggregate(control_results),
        "failures": failure_results,
        "controls": control_results,
    }
    out_dir.mkdir(parents=True)
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    lines = [
        "# CoSaMP Numeric Policy Candidate Experiment",
        "",
        f"- Date: `{result['date']}`",
        f"- Candidate: `{CANDIDATE}`.",
        "- Scope: frozen 15 failures plus 15 passing controls.",
        "- This is a software-model experiment; D22 RTL remains inactive.",
        "",
        "## Policy",
        "",
        "- Data/residual path: `D27/F23` instead of `D22/F18`.",
        "- Solver: `S31/F23`; accumulator: `ACC70`.",
        "- Strict certificate residual shift: `18`; reliable recompute interval: `32`.",
        "- Iteration budget, rounding, saturation, raw-proxy ranking and lowest-index tie break are unchanged.",
        "",
        "## Result",
        "",
        "| Set | Quality pass | Exact support | Rollbacks | Numeric events | Max SNR gap | Max MSE ratio | Max SSIM drop |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for label, summary in (("Failures", result["failure_set"]), ("Controls", result["control_set"])):
        lines.append(
            f"| `{label}` | {summary['passed']}/{summary['total']} | "
            f"{summary['support_exact']}/{summary['total']} | "
            f"{summary['rollback_count']} | {summary['numeric_events']} | "
            f"{summary['max_snr_gap_db']:.6f} | {summary['max_mse_ratio']:.6f} | "
            f"{summary['max_ssim_drop']:.6f} |"
        )
    lines += [
        "",
        "## Decision",
        "",
        "- Diagnostic improvement only; not promoted to RTL.",
        "- Required failure-set gate is `15/15`; this candidate does not close it.",
        "- Full `3888` sweep, candidate golden regeneration and RTL implementation are deferred.",
        "- D22 remains inactive.",
        "",
        "## Reproduction",
        "",
        "```text",
        "py -3 scripts/numeric/v3_cosamp_policy_candidate_experiment.py "
        "--records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl "
        "--manifest config/v3_p1_heldout_manifest.json --controls 15 "
        "--out-dir reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_d27_r32",
        "```",
    ]
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--controls", type=int, default=15)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.controls < 1:
        raise SystemExit("controls must be positive")
    result = run(args)
    print(json.dumps({
        "candidate": result["candidate"],
        "failure_set": result["failure_set"],
        "control_set": result["control_set"],
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
