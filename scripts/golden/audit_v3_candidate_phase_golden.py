#!/usr/bin/env python3
"""Audit candidate phase goldens against provenance and the canonical models."""

from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import date
import gzip
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import hardware, numerical_candidate, paper
from scripts.golden import generate_v3_candidate_phase_golden as candidate
from scripts.golden.generate_v3_phase_golden import valid_macro_grammar
from scripts.golden.compare_v3_phase_trace import first_difference


SUITES = ("smoke", "scale", "correctness")
KINDS = ("paper", "hardware")
INTERNAL_REFINEMENT_PHASES = {"REFINEMENT_COMMIT", "REFINEMENT_ROLLBACK"}
EXPECTED_MODEL_DIVERGENCES = {
    ("m32_n1024_k8_seed31", "CoSaMP", "support"),
    ("m32_n1024_k8_seed31", "CoSaMP", "stop_reason"),
}


def load_json(path: Path) -> dict:
    if path.suffix == ".gz":
        data = gzip.decompress(path.read_bytes())
    else:
        data = path.read_bytes()
    return json.loads(data.decode("utf-8"))


def canonical_payload(payload: dict) -> dict:
    return json.loads(candidate.json_bytes(payload).decode("utf-8"))


def trace_names(trace: dict, kind: str) -> list[str]:
    return [
        phase["name"]
        for phase in trace["phases"]
        if kind == "paper"
        or (not phase["name"].startswith("REFINEMENT_")
            and phase["name"] not in INTERNAL_REFINEMENT_PHASES)
    ]


def as_hardware_trace(trace: dict) -> hardware.Trace:
    return hardware.Trace(
        algorithm=trace["algorithm"],
        x=list(trace["x"]),
        residual=list(trace["residual"]),
        support=list(trace["support"]),
        phases=[hardware.Phase(**phase) for phase in trace["phases"]],
        stop_reason=trace["stop_reason"],
        events=hardware.Events(**trace["events"]),
    )


def source_paths() -> dict[str, Path]:
    return {
        "models/v3/paper.py": ROOT / "models" / "v3" / "paper.py",
        "models/v3/phi_generator.py": ROOT / "models" / "v3" / "phi_generator.py",
        "models/v3/hardware.py": ROOT / "models" / "v3" / "hardware.py",
        "models/v3/numerical_candidate.py": ROOT / "models" / "v3" / "numerical_candidate.py",
        "compiler/v3/reconstruction_graphs.py": ROOT / "compiler" / "v3" / "reconstruction_graphs.py",
        "compiler/v3/context_isa.py": ROOT / "compiler" / "v3" / "context_isa.py",
        "compiler/v3/run_configuration.py": ROOT / "compiler" / "v3" / "run_configuration.py",
        "generator": Path(__file__).with_name("generate_v3_candidate_phase_golden.py"),
    }


def structural_trace_checks(
    case: dict, kind: str, algorithm: str, trace: dict,
) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if trace.get("algorithm") != algorithm:
        failures.append("algorithm field mismatch")
    phases = trace.get("phases", [])
    if [phase.get("seq") for phase in phases] != list(range(len(phases))):
        failures.append("phase sequence is not contiguous")
    support = trace.get("support", [])
    if len(support) != len(set(support)):
        failures.append("duplicate final support")
    if any(index < 0 or index >= case["n"] for index in support):
        failures.append("support index out of range")
    if len(trace.get("x", [])) != case["n"]:
        failures.append("dense output length mismatch")
    if len(trace.get("residual", [])) != case["m"]:
        failures.append("residual length mismatch")
    if not trace.get("stop_reason"):
        failures.append("missing stop reason")
    if not phases:
        failures.append("empty phase trace")

    names = trace_names(trace, kind)
    if kind == "paper":
        if not valid_macro_grammar(algorithm, names):
            failures.append("invalid paper macro grammar")
    else:
        events = trace.get("events")
        if not isinstance(events, dict):
            failures.append("missing hardware event counters")
        elif any(value != 0 for value in events.values()):
            failures.append("non-zero hardware numeric event")
        try:
            candidate.validate_candidate_trace(
                case, algorithm, as_hardware_trace(trace))
        except RuntimeError as error:
            failures.append(str(error))
    return not failures, failures


def audit_suite(
    golden_dir: Path,
    suite_name: str,
    profile_name: str,
    current_source_hashes: dict[str, str],
    expected_payload_cache: dict[tuple[str, str], dict],
) -> dict:
    manifest_path = golden_dir / f"manifest.{suite_name}.json"
    failures: list[str] = []
    if not manifest_path.is_file():
        return {
            "suite": suite_name,
            "manifest_pass": False,
            "failures": [f"missing manifest: {manifest_path}"],
        }
    manifest = load_json(manifest_path)
    cases = {case["name"]: case for case in candidate.suite(suite_name)}
    expected_entries = {
        (case_name, kind)
        for case_name in cases
        for kind in KINDS
    }
    actual_entries = {
        (entry.get("case"), entry.get("kind"))
        for entry in manifest.get("files", [])
    }
    manifest_pass = (
        manifest.get("schema") == "cscgra-v3-candidate-phase-manifest-v1"
        and manifest.get("suite") == suite_name
        and manifest.get("numeric_candidate") == profile_name
        and actual_entries == expected_entries
        and len(manifest.get("files", [])) == len(expected_entries)
    )
    if not manifest_pass:
        failures.append("manifest schema/suite/profile/file set mismatch")
    if manifest.get("source_sha256") != current_source_hashes:
        failures.append("manifest source hash mismatch")

    hash_pass = True
    payload_schema_pass = True
    model_exact = 0
    model_total = 0
    trace_pass = 0
    trace_total = 0
    payloads: dict[tuple[str, str], dict] = {}
    entries_by_key = {}
    for entry in manifest.get("files", []):
        key = (entry.get("case"), entry.get("kind"))
        entries_by_key[key] = entry
        relative_path = entry.get("path", "")
        path = golden_dir / relative_path
        try:
            path.relative_to(golden_dir)
        except ValueError:
            failures.append(f"unsafe artifact path: {relative_path}")
            continue
        if not path.is_file():
            failures.append(f"missing artifact: {relative_path}")
            hash_pass = False
            continue
        actual_hash = candidate.sha256(path)
        if actual_hash != entry.get("sha256"):
            failures.append(f"artifact hash mismatch: {relative_path}")
            hash_pass = False
        try:
            payload = load_json(path)
        except Exception as error:
            failures.append(f"cannot decode {relative_path}: {error}")
            payload_schema_pass = False
            continue
        payloads[key] = payload
        expected_case = cases.get(entry.get("case"))
        if expected_case is None or entry.get("kind") not in KINDS:
            failures.append(f"unexpected manifest entry: {key}")
            payload_schema_pass = False
            continue
        cache_key = (entry["case"], entry["kind"])
        if cache_key not in expected_payload_cache:
            expected_payload_cache[cache_key] = canonical_payload(
                candidate.phase_payload(expected_case, entry["kind"], profile_name))
        expected_payload = expected_payload_cache[cache_key]
        model_total += 1
        difference = first_difference(expected_payload, payload)
        if difference is None:
            model_exact += 1
        else:
            failures.append(f"model mismatch {relative_path}: {difference}")

        if (
            payload.get("schema") != "cscgra-v3-candidate-phase-golden-v1"
            or payload.get("kind") != entry.get("kind")
            or payload.get("numeric_candidate") != profile_name
            or payload.get("case", {}).get("name") != entry.get("case")
        ):
            failures.append(f"payload metadata mismatch: {relative_path}")
            payload_schema_pass = False
        for algorithm in paper.ALGORITHMS:
            trace_total += 1
            trace = payload.get("traces", {}).get(algorithm)
            if trace is None:
                failures.append(f"missing {algorithm} trace: {relative_path}")
                continue
            passed, trace_failures = structural_trace_checks(
                expected_case, entry["kind"], algorithm, trace)
            if passed:
                trace_pass += 1
            else:
                failures.extend(
                    f"{relative_path}/{algorithm}: {failure}"
                    for failure in trace_failures
                )

    for key in sorted(expected_entries - set(entries_by_key)):
        failures.append(f"missing manifest entry: {key}")

    return {
        "suite": suite_name,
        "manifest_pass": manifest_pass,
        "expected_cases": len(cases),
        "expected_artifacts": len(expected_entries),
        "artifact_hash_pass": hash_pass,
        "payload_schema_pass": payload_schema_pass,
        "model_exact": model_exact,
        "model_total": model_total,
        "trace_pass": trace_pass,
        "trace_total": trace_total,
        "payloads": payloads,
        "failures": failures,
    }


def pair_audit(results: list[dict]) -> dict:
    pairs = {}
    for result in results:
        pairs.update(result.get("payloads", {}))
    correctness_cases = {
        case["name"] for case in candidate.suite("correctness")
    }
    support_match = 0
    stop_match = 0
    pair_total = 0
    divergences: list[dict] = []
    failures: list[str] = []
    for case_name in sorted(correctness_cases):
        paper_payload = pairs.get((case_name, "paper"))
        hardware_payload = pairs.get((case_name, "hardware"))
        if paper_payload is None or hardware_payload is None:
            failures.append(f"missing paper/hardware pair: {case_name}")
            continue
        paper_case = paper_payload.get("case", {})
        hardware_case = hardware_payload.get("case", {})
        if paper_case != hardware_case:
            failures.append(f"case metadata differs between pair: {case_name}")
        for algorithm in paper.ALGORITHMS:
            pair_total += 1
            paper_trace = paper_payload.get("traces", {}).get(algorithm, {})
            hardware_trace = hardware_payload.get("traces", {}).get(algorithm, {})
            if paper_trace.get("support") == hardware_trace.get("support"):
                support_match += 1
            else:
                divergence = {
                    "case": case_name,
                    "algorithm": algorithm,
                    "kind": "support",
                    "paper": paper_trace.get("support"),
                    "hardware": hardware_trace.get("support"),
                    "controlled": (case_name, algorithm, "support")
                    in EXPECTED_MODEL_DIVERGENCES,
                }
                divergences.append(divergence)
                if not divergence["controlled"]:
                    failures.append(f"support mismatch: {case_name}/{algorithm}")
            if paper_trace.get("stop_reason") == hardware_trace.get("stop_reason"):
                stop_match += 1
            else:
                divergence = {
                    "case": case_name,
                    "algorithm": algorithm,
                    "kind": "stop_reason",
                    "paper": paper_trace.get("stop_reason"),
                    "hardware": hardware_trace.get("stop_reason"),
                    "controlled": (case_name, algorithm, "stop_reason")
                    in EXPECTED_MODEL_DIVERGENCES,
                }
                divergences.append(divergence)
                if not divergence["controlled"]:
                    failures.append(
                        f"stop-reason mismatch: {case_name}/{algorithm}")
    return {
        "pair_total": pair_total,
        "support_match": support_match,
        "stop_match": stop_match,
        "divergences": divergences,
        "failures": failures,
    }


def audit(golden_dir: Path, profile_name: str) -> dict:
    source_hashes = {}
    source_failures = []
    for name, path in source_paths().items():
        if not path.is_file():
            source_failures.append(f"missing source: {name}")
            continue
        source_hashes[name] = candidate.sha256(path)

    expected_payload_cache: dict[tuple[str, str], dict] = {}
    results = [
        audit_suite(
            golden_dir, suite_name, profile_name, source_hashes,
            expected_payload_cache,
        )
        for suite_name in SUITES
    ]
    pair = pair_audit(results)
    for result in results:
        result.pop("payloads", None)
    failures = source_failures + [
        failure for result in results for failure in result["failures"]
    ] + pair["failures"]
    aggregate = {
        "cases": sum(result.get("expected_cases", 0) for result in results),
        "artifacts": sum(result.get("expected_artifacts", 0) for result in results),
        "model_exact": sum(result.get("model_exact", 0) for result in results),
        "model_total": sum(result.get("model_total", 0) for result in results),
        "trace_pass": sum(result.get("trace_pass", 0) for result in results),
        "trace_total": sum(result.get("trace_total", 0) for result in results),
    }
    return {
        "schema": "cscgra-v3-candidate-phase-audit-v1",
        "date": date.today().isoformat(),
        "profile": profile_name,
        "golden_dir": str(golden_dir.relative_to(ROOT)
                           if golden_dir.is_relative_to(ROOT) else golden_dir),
        "source_hashes": source_hashes,
        "source_pass": not source_failures,
        "suites": results,
        "pair_audit": pair,
        "aggregate": aggregate,
        "failures": failures,
        "pass": not failures and all(
            result.get("manifest_pass")
            and result.get("artifact_hash_pass")
            and result.get("payload_schema_pass")
            and result.get("model_exact") == result.get("model_total")
            and result.get("trace_pass") == result.get("trace_total")
            for result in results
        ) and pair["pair_total"] == (
            len(candidate.suite("correctness")) * len(paper.ALGORITHMS)
        ),
    }


def markdown(result: dict) -> str:
    aggregate = result["aggregate"]
    lines = [
        "# P1.8 Candidate Golden Audit",
        "",
        f'- Date: `{result["date"]}`',
        f'- Status: **{"PASS" if result["pass"] else "FAIL"}**',
        f'- Candidate: `{result["profile"]}` (`D22F18/S31F23/ACC70`).',
        f'- Golden directory: `{result["golden_dir"]}`.',
        "- Scope: canonical paper -> candidate hardware model -> serialized golden.",
        "",
        "## Gates",
        "",
        "| Gate | Result |",
        "| --- | --- |",
        f'| Source hashes | {"PASS" if result["source_pass"] else "FAIL"} |',
        f'| Cases | `{aggregate["cases"]}` across smoke/scale/correctness |',
        f'| Artifacts | `{aggregate["artifacts"]}` paper/hardware payloads |',
        f'| Model exact payloads | `{aggregate["model_exact"]}/{aggregate["model_total"]}` |',
        f'| Structural traces | `{aggregate["trace_pass"]}/{aggregate["trace_total"]}` |',
        f'| Paper/D22 support equality (diagnostic) | `{result["pair_audit"]["support_match"]}/{result["pair_audit"]["pair_total"]}` |',
        f'| Paper/D22 stop equality (diagnostic) | `{result["pair_audit"]["stop_match"]}/{result["pair_audit"]["pair_total"]}` |',
        "",
        "## Suite Detail",
        "",
        "| Suite | Cases | Artifacts | Hash | Model exact | Trace checks | Result |",
        "| --- | ---: | ---: | --- | ---: | ---: | --- |",
    ]
    for suite in result["suites"]:
        suite_pass = (
            suite.get("manifest_pass")
            and suite.get("artifact_hash_pass")
            and suite.get("payload_schema_pass")
            and suite.get("model_exact") == suite.get("model_total")
            and suite.get("trace_pass") == suite.get("trace_total")
        )
        lines.append(
            f'| `{suite["suite"]}` | {suite.get("expected_cases", 0)} | '
            f'{suite.get("expected_artifacts", 0)} | '
            f'{"PASS" if suite.get("artifact_hash_pass") else "FAIL"} | '
            f'{suite.get("model_exact", 0)}/{suite.get("model_total", 0)} | '
            f'{suite.get("trace_pass", 0)}/{suite.get("trace_total", 0)} | '
            f'{"PASS" if suite_pass else "FAIL"} |'
        )
    lines += [
        "",
        "## Controlled Terminal",
        "",
        "- One controlled candidate trace ends with `solver_max_iterations` and "
        "exactly one `REFINEMENT_ROLLBACK`: `m32_n1024_k8_seed31/CoSaMP`.",
        "- This is an explicit solver-limit termination, with zero numeric fault "
        "events; it is not treated as convergence or hidden by tolerance.",
        "- The paper-vs-D22 support/termination divergence for this controlled "
        "solver-limit case is recorded as a diagnostic; it does not weaken the "
        "serialized candidate-model or future RTL bit-exact gate.",
        "",
        "## Non-claims",
        "",
        "- D22/S31/ACC70 remains inactive in production `rtl/v3/files.f`.",
        "- This checkpoint does not claim candidate end-to-end RTL/model bit-exact "
        "closure, held-out quality closure, synthesis, timing or PPA.",
        "",
        "## Reproduction",
        "",
        "```text",
        "py -3 scripts/golden/generate_v3_candidate_phase_golden.py --suite smoke --profile quality_d22 --out-dir reports/v3/optimization_follow_20260907/p1_8/candidate_golden --check",
        "py -3 scripts/golden/generate_v3_candidate_phase_golden.py --suite scale --profile quality_d22 --out-dir reports/v3/optimization_follow_20260907/p1_8/candidate_golden --check",
        "py -3 scripts/golden/generate_v3_candidate_phase_golden.py --suite correctness --profile quality_d22 --out-dir reports/v3/optimization_follow_20260907/p1_8/candidate_golden --check",
        "py -3 scripts/golden/audit_v3_candidate_phase_golden.py --golden-dir reports/v3/optimization_follow_20260907/p1_8/candidate_golden --out-dir reports/v3/optimization_follow_20260907/p1_8",
        "```",
    ]
    if result["failures"]:
        lines += ["", "## Failures", ""]
        lines.extend(f"- `{failure}`" for failure in result["failures"])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--golden-dir", type=Path,
        default=Path("reports/v3/optimization_follow_20260907/p1_8/candidate_golden"),
    )
    parser.add_argument("--profile", default="quality_d22")
    parser.add_argument("--out-dir", type=Path)
    args = parser.parse_args()
    golden_dir = args.golden_dir if args.golden_dir.is_absolute() else ROOT / args.golden_dir
    out_dir = args.out_dir if args.out_dir else golden_dir.parent
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    result = audit(golden_dir, args.profile)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "P18_CANDIDATE_GOLDEN_AUDIT.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "P18_CANDIDATE_GOLDEN_AUDIT.md").write_text(
        markdown(result), encoding="utf-8")
    print(markdown(result), end="")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
