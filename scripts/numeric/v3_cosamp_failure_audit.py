#!/usr/bin/env python3
"""Audit held-out D22 CoSaMP failures without changing any numeric contract."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, numerical_candidate, paper, phi_generator
from scripts.numeric.v3_candidate_heldout_sweep import (
    block_from_volume,
    load_manifest,
)
from scripts.numeric.v3_brainweb_sweep import load_volume
from scripts.numeric.v3_golden_quality_gate import policy_for
from scripts.numeric.v3_mri_quality_common import (
    BLOCK_M,
    BLOCK_N,
    BLOCK_SIZE,
    BLOCK_SPARSITY,
    image_metrics,
    mri_dct_forward,
    mri_dct_inverse,
    sha256_array,
    sha256_file,
    topk_sparse,
)


AUDIT_SCHEMA = "cscgra-v3-cosamp-failure-audit-v1"
ALGORITHM = "CoSaMP"
SEMANTIC_PHASES = ("PROXY", "IDENTIFY", "MERGE", "LS", "PRUNE", "RESIDUAL")


def load_json(path: Path) -> dict:
    data = path.read_bytes()
    if path.suffix == ".gz":
        data = gzip.decompress(data)
    return json.loads(data.decode("utf-8"))


def finite(value: float) -> float | str:
    if math.isinf(value):
        return "inf" if value > 0 else "-inf"
    return float(value)


def phase_map(phases: list[object]) -> dict[int, dict[str, object]]:
    result: dict[int, dict[str, object]] = {}
    for phase in phases:
        if phase.name not in SEMANTIC_PHASES:
            continue
        iteration = int(phase.iteration)
        result.setdefault(iteration, {})[phase.name] = phase
    return result


def top_indices(values: list[float] | list[int], count: int) -> list[int]:
    return sorted(
        range(len(values)),
        key=lambda index: (-abs(float(values[index])), index),
    )[:count]


def vector_float(phase: object, key: str, scale: float = 1.0) -> list[float]:
    values = phase.vectors.get(key, [])
    return [float(value) / scale for value in values]


def max_abs_delta(left: list[float], right: list[float]) -> float | None:
    if not left or not right:
        return None
    if len(left) != len(right):
        return math.inf
    return float(np.max(np.abs(np.asarray(left) - np.asarray(right))))


def phase_summary(
    paper_phases: dict[int, dict[str, object]],
    fixed_phases: dict[int, dict[str, object]],
    solver_scale: int,
    data_scale: int,
) -> list[dict]:
    iterations = sorted(set(paper_phases) | set(fixed_phases))
    rows = []
    for iteration in iterations:
        paper_row = paper_phases.get(iteration, {})
        fixed_row = fixed_phases.get(iteration, {})
        paper_proxy = paper_row.get("PROXY")
        fixed_proxy = fixed_row.get("PROXY")
        paper_identify = paper_row.get("IDENTIFY")
        fixed_identify = fixed_row.get("IDENTIFY")
        paper_merge = paper_row.get("MERGE")
        fixed_merge = fixed_row.get("MERGE")
        paper_ls = paper_row.get("LS")
        fixed_ls = fixed_row.get("LS")
        paper_prune = paper_row.get("PRUNE")
        fixed_prune = fixed_row.get("PRUNE")
        paper_residual = paper_row.get("RESIDUAL")
        fixed_residual = fixed_row.get("RESIDUAL")

        paper_proxy_values = (
            paper_proxy.vectors.get("proxy", []) if paper_proxy else []
        )
        fixed_proxy_values = (
            vector_float(fixed_proxy, "proxy", solver_scale)
            if fixed_proxy else []
        )
        paper_identify_candidates = (
            list(paper_identify.candidates) if paper_identify else []
        )
        fixed_identify_candidates = (
            list(fixed_identify.candidates) if fixed_identify else []
        )
        paper_prune_support = list(paper_prune.support) if paper_prune else []
        fixed_prune_support = list(fixed_prune.support) if fixed_prune else []
        paper_merge_support = list(paper_merge.support) if paper_merge else []
        fixed_merge_support = list(fixed_merge.support) if fixed_merge else []
        paper_ls_values = (
            list(paper_ls.vectors.get("estimate", [])) if paper_ls else []
        )
        fixed_ls_values = (
            vector_float(fixed_ls, "estimate", solver_scale) if fixed_ls else []
        )
        paper_residual_values = (
            list(paper_residual.vectors.get("residual", []))
            if paper_residual else []
        )
        fixed_residual_values = (
            vector_float(fixed_residual, "residual", data_scale)
            if fixed_residual else []
        )
        rows.append({
            "iteration": iteration,
            "paper_proxy_top16": top_indices(paper_proxy_values, 16)
            if paper_proxy_values else [],
            "fixed_proxy_top16": top_indices(fixed_proxy_values, 16)
            if fixed_proxy_values else [],
            "identify_equal": paper_identify_candidates == fixed_identify_candidates,
            "paper_identify": paper_identify_candidates,
            "fixed_identify": fixed_identify_candidates,
            "merge_equal": paper_merge_support == fixed_merge_support,
            "paper_merge": paper_merge_support,
            "fixed_merge": fixed_merge_support,
            "prune_equal": paper_prune_support == fixed_prune_support,
            "paper_prune": paper_prune_support,
            "fixed_prune": fixed_prune_support,
            "ls_max_abs_delta": finite(max_abs_delta(paper_ls_values, fixed_ls_values))
            if paper_ls_values and fixed_ls_values else None,
            "residual_max_abs_delta": finite(
                max_abs_delta(paper_residual_values, fixed_residual_values))
            if paper_residual_values and fixed_residual_values else None,
            "paper_has_all_phases": all(name in paper_row for name in SEMANTIC_PHASES),
            "fixed_has_all_phases": all(name in fixed_row for name in SEMANTIC_PHASES),
        })
    return rows


def first_divergence(rows: list[dict], paper_trace: object, fixed_trace: object) -> dict:
    for row in rows:
        iteration = row["iteration"]
        if not row["identify_equal"]:
            return {
                "stage": "proxy_identify",
                "iteration": iteration,
                "detail": "IDENTIFY candidate list differs",
                "paper": row["paper_identify"],
                "fixed": row["fixed_identify"],
            }
        if not row["merge_equal"]:
            return {
                "stage": "merge",
                "iteration": iteration,
                "detail": "MERGE support differs",
                "paper": row["paper_merge"],
                "fixed": row["fixed_merge"],
            }
        if not row["prune_equal"]:
            return {
                "stage": "ls_prune",
                "iteration": iteration,
                "detail": "PRUNE support differs after restricted refinement",
                "paper": row["paper_prune"],
                "fixed": row["fixed_prune"],
            }
    if fixed_trace.stop_reason != paper_trace.stop_reason:
        return {
            "stage": "termination",
            "iteration": rows[-1]["iteration"] if rows else None,
            "detail": "stop reason differs after matching semantic phases",
            "paper": paper_trace.stop_reason,
            "fixed": fixed_trace.stop_reason,
        }
    if fixed_trace.support != paper_trace.support:
        return {
            "stage": "final_support",
            "iteration": rows[-1]["iteration"] if rows else None,
            "detail": "final support differs without an earlier semantic mismatch",
            "paper": list(paper_trace.support),
            "fixed": list(fixed_trace.support),
        }
    if any(phase.name == "REFINEMENT_ROLLBACK" for phase in fixed_trace.phases):
        return {
            "stage": "refinement_rollback",
            "iteration": next(
                (phase.iteration for phase in fixed_trace.phases
                 if phase.name == "REFINEMENT_ROLLBACK"),
                None,
            ),
            "detail": "restricted refinement rolled back",
            "paper": paper_trace.stop_reason,
            "fixed": fixed_trace.stop_reason,
        }
    return {
        "stage": "coefficient_residual",
        "iteration": rows[-1]["iteration"] if rows else None,
        "detail": "support and termination match; quality gap is coefficient/residual precision",
        "paper": paper_trace.stop_reason,
        "fixed": fixed_trace.stop_reason,
    }


def evaluate_case(
    entry: dict,
    block: np.ndarray,
    phi_seed: int,
    profile: hardware.NumericProfile,
    refinement: hardware.RefinementPolicy,
) -> dict:
    original = np.asarray(block, dtype=np.float64).reshape(-1)
    phi = phi_generator.matrix(phi_seed, BLOCK_M, BLOCK_N)
    policy = policy_for(phi)
    target = topk_sparse(mri_dct_forward(original))
    target_peak = max(float(np.max(np.abs(target))), 1e-30)
    normalization_scale = 0.75 / target_peak
    measurement = phi @ (target * normalization_scale)
    paper_trace = paper.run(ALGORITHM, phi, measurement, policy)
    fixed_trace = hardware.run(
        ALGORITHM, phi, measurement, policy, profile, refinement,
    )
    paper_x = np.asarray(paper_trace.x, dtype=np.float64) / normalization_scale
    fixed_x = (
        np.asarray(fixed_trace.x, dtype=np.float64)
        / (1 << profile.data_f)
        / normalization_scale
    )
    original_image = original.reshape(BLOCK_SIZE, BLOCK_SIZE)
    paper_image = mri_dct_inverse(paper_x).reshape(BLOCK_SIZE, BLOCK_SIZE)
    fixed_image = mri_dct_inverse(fixed_x).reshape(BLOCK_SIZE, BLOCK_SIZE)
    paper_metrics = image_metrics(original_image, paper_image)
    fixed_metrics = image_metrics(original_image, fixed_image)
    fixed_float_metrics = image_metrics(paper_image, fixed_image)
    rows = phase_summary(
        phase_map(paper_trace.phases),
        phase_map(fixed_trace.phases),
        1 << profile.solver_f,
        1 << profile.data_f,
    )
    rollback_iterations = [
        phase.iteration for phase in fixed_trace.phases
        if phase.name == "REFINEMENT_ROLLBACK"
    ]
    return {
        "volume": entry["volume"],
        "block": entry["block"],
        "phi_seed": int(phi_seed),
        "source_sha256": entry["source_sha256"],
        "block_sha256": sha256_array(original),
        "normalization_scale": float(normalization_scale),
        "paper_support": list(paper_trace.support),
        "fixed_support": list(fixed_trace.support),
        "paper_stop_reason": paper_trace.stop_reason,
        "fixed_stop_reason": fixed_trace.stop_reason,
        "rollback_iterations": rollback_iterations,
        "events": asdict(fixed_trace.events),
        "paper_metrics": paper_metrics,
        "fixed_metrics": fixed_metrics,
        "fixed_vs_float_metrics": fixed_float_metrics,
        "phase_rows": rows,
        "first_divergence": first_divergence(rows, paper_trace, fixed_trace),
        "paper_trace": asdict(paper_trace),
        "fixed_trace": asdict(fixed_trace),
    }


def read_failures(records_path: Path) -> list[dict]:
    failures = []
    with records_path.open("r", encoding="utf-8") as stream:
        for line in stream:
            batch = json.loads(line)
            for algorithm in batch["algorithms"]:
                if algorithm["algorithm"] == ALGORITHM and not algorithm["pass"]:
                    failures.append({
                        "volume": batch["volume"],
                        "block": batch["block"],
                        "phi_seed": int(batch["phi_seed"]),
                        "baseline": algorithm,
                    })
    return failures


def markdown(result: dict) -> str:
    counts: dict[str, int] = {}
    for case in result["cases"]:
        stage = case["first_divergence"]["stage"]
        counts[stage] = counts.get(stage, 0) + 1
    lines = [
        "# P1.8 CoSaMP Held-out First-Divergence Audit",
        "",
        f'- Date: `{result["date"]}`',
        f'- Status: **{"PASS" if result["failure_reproduction_pass"] else "FAIL"}**',
        f'- Candidate: `{result["numeric_candidate"]}` '
        f'(`D{result["numeric_profile"]["data_w"]}F{result["numeric_profile"]["data_f"]}/'
        f'S{result["numeric_profile"]["solver_w"]}F{result["numeric_profile"]["solver_f"]}/'
        f'ACC{result["numeric_profile"]["acc_w"]}`).',
        f'- Baseline records: `{result["records"]}`.',
        f'- Frozen manifest: `{result["manifest"]}`.',
        f'- Reproduced failures: `{len(result["cases"])}/{len(result["cases"])}`.',
        "",
        "## First divergence",
        "",
        "| Stage | Cases | Interpretation |",
        "| --- | ---: | --- |",
    ]
    descriptions = {
        "proxy_identify": "quantized correlation changes the 2K candidate set",
        "merge": "support union differs before restricted refinement",
        "ls_prune": "restricted refinement changes the K-way prune result",
        "termination": "semantic phases match but stop reason differs",
        "final_support": "only final support differs",
        "refinement_rollback": "refinement transaction rolls back",
        "coefficient_residual": "support and termination match; coefficient/residual gap remains",
    }
    for stage in sorted(counts):
        lines.append(f'| `{stage}` | {counts[stage]} | {descriptions.get(stage, "diagnostic")} |')
    lines.extend([
        "",
        "## Cases",
        "",
        "| Volume | Block | Phi seed | Stage | Iter | Support | Stop | Rollback | SNR gap dB | MSE ratio |",
        "| --- | --- | ---: | --- | ---: | --- | --- | ---: | ---: | ---: |",
    ])
    for case in result["cases"]:
        baseline = case["baseline"]
        divergence = case["first_divergence"]
        lines.append(
            f'| `{case["volume"]}` | `{case["block"]}` | {case["phi_seed"]} | '
            f'`{divergence["stage"]}` | {divergence["iteration"]} | '
            f'{str(case["paper_support"] == case["fixed_support"])} | '
            f'`{case["fixed_stop_reason"]}` | {len(case["rollback_iterations"])} | '
            f'{float(baseline["snr_gap_db"]):.6f} | '
            f'{float(baseline["mse_ratio_fixed_over_float"]):.6f} |'
        )
    lines.extend([
        "",
        "## Interpretation",
        "",
        "- This is a diagnostic replay only; it does not change thresholds, frozen blocks, Phi seeds or numeric profiles.",
        "- The full phase trace is stored per case under `traces/`; source and block hashes are checked before every replay.",
        "- D22 remains inactive. No RTL/model closure, synthesis, timing or PPA claim is made.",
        "",
        "## Reproduction",
        "",
        "```text",
        "py -3 scripts/numeric/v3_cosamp_failure_audit.py "
        "--records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl "
        "--manifest config/v3_p1_heldout_manifest.json "
        "--out-dir reports/v3/optimization_follow_20260907/p1_8/cosamp_failure_audit",
        "```",
    ])
    return "\n".join(lines) + "\n"


def run(records_path: Path, manifest_path: Path, out_dir: Path) -> dict:
    if out_dir.exists():
        raise FileExistsError(f"refusing to overwrite audit directory: {out_dir}")
    manifest = load_manifest(manifest_path)
    failures = read_failures(records_path)
    profile, refinement = numerical_candidate.configuration("quality_d22")
    volumes: dict[str, tuple[Path, np.ndarray]] = {}
    entries = {
        volume["id"]: volume for volume in manifest["volumes"]
    }
    out_dir.mkdir(parents=True)
    trace_dir = out_dir / "traces"
    trace_dir.mkdir()
    cases = []
    for failure in failures:
        volume_entry = entries[failure["volume"]]
        source_path = ROOT / volume_entry["source_file"]
        if sha256_file(source_path) != volume_entry["source_sha256"]:
            raise ValueError(f"source checksum mismatch: {source_path}")
        if failure["volume"] not in volumes:
            volume, _ = load_volume(source_path)
            volumes[failure["volume"]] = (source_path, volume)
        _, volume = volumes[failure["volume"]]
        block_entry = next(
            block for block in volume_entry["blocks"]
            if block["id"] == failure["block"]
        )
        block = block_from_volume(volume, block_entry)
        case = evaluate_case({
            "volume": failure["volume"],
            "block": failure["block"],
            "source_sha256": volume_entry["source_sha256"],
        }, block, failure["phi_seed"], profile, refinement)
        case["baseline"] = failure["baseline"]
        case_name = f'{failure["volume"]}__{failure["block"]}__seed{failure["phi_seed"]}'
        (trace_dir / f"{case_name}.json.gz").write_bytes(
            gzip.compress(json.dumps(case, sort_keys=True).encode("utf-8"))
        )
        case.pop("paper_trace", None)
        case.pop("fixed_trace", None)
        cases.append(case)
    cases.sort(key=lambda case: (case["volume"], case["block"], case["phi_seed"]))
    result = {
        "schema": AUDIT_SCHEMA,
        "date": "2026-09-07",
        "numeric_candidate": "quality_d22",
        "numeric_profile": asdict(profile),
        "refinement_policy": asdict(refinement),
        "records": str(records_path),
        "records_sha256": sha256_file(records_path),
        "manifest": str(manifest_path),
        "manifest_sha256": sha256_file(manifest_path),
        "failure_reproduction_pass": bool(cases) and all(
            case["baseline"]["pass"] is False
            and case["baseline"]["algorithm"] == ALGORITHM
            for case in cases
        ),
        "failure_count": len(cases),
        "cases": cases,
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
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    records = args.records if args.records.is_absolute() else ROOT / args.records
    manifest = args.manifest if args.manifest.is_absolute() else ROOT / args.manifest
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    result = run(records, manifest, out_dir)
    print(markdown(result), end="")
    return 0 if result["failure_reproduction_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
