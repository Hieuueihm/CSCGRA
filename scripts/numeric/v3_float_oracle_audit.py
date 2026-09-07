#!/usr/bin/env python3
"""Audit all floating-point correctness goldens against an independent oracle."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import paper
from scripts.golden.generate_v3_phase_golden import suite
from verification.v3 import independent_float_oracle


ABS_TOL = 1.0e-12
REL_TOL = 1.0e-12


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative_error(reference: np.ndarray, observed: np.ndarray) -> float:
    return float(
        np.linalg.norm(observed - reference)
        / max(float(np.linalg.norm(reference)), 1.0e-30)
    )


def audit_case(case: dict) -> dict:
    records = {}
    for algorithm in paper.ALGORITHMS:
        authoritative = paper.run(
            algorithm, case["phi"], case["y"], case["policy"])
        independent = independent_float_oracle.run(
            algorithm, case["phi"], case["y"], case["policy"])
        authoritative_x = np.asarray(authoritative.x, dtype=np.float64)
        authoritative_residual = np.asarray(
            authoritative.residual, dtype=np.float64)
        residual_identity = (
            np.asarray(case["y"]) - np.asarray(case["phi"]) @ authoritative_x
        )
        x_match = bool(np.allclose(
            authoritative_x, independent.x, atol=ABS_TOL, rtol=REL_TOL))
        residual_match = bool(np.allclose(
            authoritative_residual, independent.residual,
            atol=ABS_TOL, rtol=REL_TOL))
        residual_identity_match = bool(np.allclose(
            authoritative_residual, residual_identity,
            atol=ABS_TOL, rtol=REL_TOL))
        support_match = tuple(authoritative.support) == independent.support
        stop_reason_match = authoritative.stop_reason == independent.stop_reason
        passed = (
            x_match and residual_match and residual_identity_match
            and support_match and stop_reason_match
        )
        records[algorithm] = {
            "pass": passed,
            "support_match": support_match,
            "stop_reason_match": stop_reason_match,
            "x_match": x_match,
            "residual_match": residual_match,
            "residual_identity_match": residual_identity_match,
            "x_relative_error": relative_error(independent.x, authoritative_x),
            "residual_relative_error": relative_error(
                independent.residual, authoritative_residual),
            "residual_identity_relative_error": relative_error(
                residual_identity, authoritative_residual),
            "support": list(authoritative.support),
            "stop_reason": authoritative.stop_reason,
        }
    return {
        "name": case["name"],
        "geometry": {
            "m": case["m"], "n": case["n"], "k": case["k"],
            "seed": case["seed"],
            "outer_iteration_limit": case["policy"].max_iterations,
        },
        "pass": all(record["pass"] for record in records.values()),
        "algorithms": records,
    }


def markdown(result: dict) -> str:
    lines = [
        "# V3 floating-point oracle audit",
        "",
        "This is the first correctness gate. It compares `models/v3/paper.py`",
        "against a separately implemented NumPy oracle and checks the residual",
        "identity `r = y - Phi*x`. Fixed-point and RTL are outside this gate.",
        "",
        f'Overall: **{"PASS" if result["pass"] else "FAIL"}**',
        "",
        "| Geometry | Result | Algorithms | Max x rel. error | Max residual rel. error |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for case in result["cases"]:
        records = list(case["algorithms"].values())
        lines.append(
            f'| {case["name"]} | {"PASS" if case["pass"] else "FAIL"} | '
            f'{sum(record["pass"] for record in records)}/{len(records)} | '
            f'{max(record["x_relative_error"] for record in records):.3e} | '
            f'{max(record["residual_relative_error"] for record in records):.3e} |'
        )
    lines += [
        "",
        f'Total: **{result["passed"]}/{result["total"]}** algorithm cases.',
        f'Tolerances: absolute `{ABS_TOL:.1e}`, relative `{REL_TOL:.1e}`.',
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("reports/v3/float_oracle_audit"))
    args = parser.parse_args()
    cases = [audit_case(case) for case in suite("correctness")]
    records = [record for case in cases for record in case["algorithms"].values()]
    result = {
        "schema": "cscgra-v3-float-oracle-audit-v1",
        "pass": all(record["pass"] for record in records),
        "passed": sum(record["pass"] for record in records),
        "total": len(records),
        "tolerances": {"absolute": ABS_TOL, "relative": REL_TOL},
        "source_sha256": {
            "models/v3/paper.py": sha256(ROOT / "models/v3/paper.py"),
            "verification/v3/independent_float_oracle.py": sha256(
                ROOT / "verification/v3/independent_float_oracle.py"),
            "scripts/golden/generate_v3_phase_golden.py": sha256(
                ROOT / "scripts/golden/generate_v3_phase_golden.py"),
        },
        "cases": cases,
    }
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "results.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    report = markdown(result)
    (out_dir / "summary.md").write_text(report, encoding="utf-8")
    print(report)
    if not result["pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
