#!/usr/bin/env python3
"""Build an auditable optimization report from frozen RTL evidence only.

The primary table intentionally rejects natural-stop or mixed-iteration runs.
It is not a benchmark runner and never changes an evidence directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ALGORITHMS = ("MP", "GP", "IHT", "OMP", "GOMP", "CoSaMP", "SP", "HTP", "FISTA", "PDHG", "ADMM")


class EvidenceError(ValueError):
    """Raised when a report cannot support the fixed-eight comparison."""


def read_json(path: Path) -> dict[str, Any]:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"cannot read {path}: {exc}") from exc
    if not isinstance(result, dict):
        raise EvidenceError(f"{path} must contain a JSON object")
    return result


def first_json(directory: Path, names: tuple[str, ...]) -> tuple[Path, dict[str, Any]]:
    for name in names:
        candidate = directory / name
        if candidate.is_file():
            return candidate, read_json(candidate)
    raise EvidenceError(f"no one of {', '.join(names)} found under {directory}")


def integer(value: Any, label: str) -> int:
    if isinstance(value, bool):
        raise EvidenceError(f"{label} must be an integer")
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise EvidenceError(f"{label} must be an integer, got {value!r}") from exc


def clean_source(summary: dict[str, Any], source_path: Path) -> None:
    if summary.get("status") != "PASS":
        raise EvidenceError(f"{source_path}: status is not PASS")
    if integer(summary.get("failures", 0), f"{source_path}: failures") != 0:
        raise EvidenceError(f"{source_path}: failures are nonzero")
    if integer(summary.get("errors", 0), f"{source_path}: errors") != 0:
        raise EvidenceError(f"{source_path}: errors are nonzero")
    hashes = summary.get("source_sha256")
    if not isinstance(hashes, dict) or not hashes:
        raise EvidenceError(f"{source_path}: missing source_sha256 evidence")
    for field in ("changed_sources", "untracked_imports"):
        if field not in summary:
            raise EvidenceError(f"{source_path}: {field} proof is absent")
        value = summary[field]
        if not isinstance(value, list) or value:
            raise EvidenceError(f"{source_path}: {field} is not clean: {value!r}")


def algorithm_name(case: dict[str, Any]) -> str:
    value = case.get("algorithm")
    if not isinstance(value, str) or not value:
        raise EvidenceError("case has no algorithm name")
    return value


def case_outer(case: dict[str, Any]) -> int:
    return integer(case.get("outer_iterations", case.get("actual_outer")), f"{algorithm_name(case)} actual outer iterations")


def requested_outer(case: dict[str, Any]) -> int:
    return integer(case.get("requested_outer_iterations", case.get("requested_outer")), f"{algorithm_name(case)} requested outer iterations")


def value_or(case: dict[str, Any], *names: str, default: Any = 0) -> Any:
    for name in names:
        if name in case and case[name] is not None:
            return case[name]
    return default


def quality_snr(case: dict[str, Any]) -> Any:
    quality = case.get("quality", {})
    if isinstance(quality, dict):
        fixed = quality.get("fixed", {})
        if isinstance(fixed, dict):
            return fixed.get("snr_db", "n/a")
    return "n/a"


def format_value(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


def quality_number(value: Any, *, scientific: bool = False) -> str:
    if isinstance(value, float):
        return f"{value:.3e}" if scientific else f"{value:.6g}"
    return str(value)


QUALITY_TERMINATIONS = {
    "residual_tolerance", "max_iterations", "paper_iteration_limit",
    "no_new_atom", "stationary", "residual_not_decreased",
}
QUALITY_EVENT_FIELDS = ("saturation", "accumulator_overflow", "divide_by_zero")


def finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool):
        raise EvidenceError(f"{label} must be a finite number")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise EvidenceError(f"{label} must be a finite number") from exc
    if not math.isfinite(number):
        raise EvidenceError(f"{label} must be a finite number")
    return number


def source_snapshot_clean(summary: dict[str, Any], directory: Path, *, allow_documented_parent_failure: bool) -> None:
    hashes = summary.get("source_sha256")
    if not isinstance(hashes, dict) or not hashes or not all(isinstance(name, str) and isinstance(value, str) and value for name, value in hashes.items()):
        raise EvidenceError(f"{directory}: missing source_sha256 evidence")
    for field in ("changed_sources", "untracked_imports"):
        value = summary.get(field)
        if not isinstance(value, list) or value:
            raise EvidenceError(f"{directory}: {field} is not explicitly clean")
    snapshot = directory / "source_snapshot"
    if not snapshot.is_dir():
        raise EvidenceError(f"{directory}: source_snapshot is missing")
    for relative, expected in hashes.items():
        source = snapshot / relative
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            raise EvidenceError(f"{directory}: source snapshot mismatch for {relative}")
    if allow_documented_parent_failure:
        return
    if summary.get("status") != "PASS" or integer(summary.get("failures"), f"{directory}: failures") != 0 or integer(summary.get("errors"), f"{directory}: errors") != 0:
        raise EvidenceError(f"{directory}: quality parent is not source-clean PASS")


def documented_component_parent(summary: dict[str, Any], directory: Path) -> bool:
    """Recognize the archived FISTA component exception from evidence, never path name."""
    if summary.get("status") != "FAIL" or integer(summary.get("failures"), f"{directory}: failures") != 0 or integer(summary.get("errors"), f"{directory}: errors") != 1:
        return False
    cases = summary.get("cases")
    readme = directory / "README.md"
    if not isinstance(cases, list) or len(cases) != 1 or not isinstance(cases[0], dict) or cases[0].get("algorithm") != "FISTA" or not readme.is_file():
        return False
    text = readme.read_text(encoding="utf-8")
    return "HTP failed before simulation" in text and "single entry in `summary.json.cases`" in text and "valid component evidence" in text


def validate_quality_case(case: dict[str, Any], directory: Path) -> None:
    algorithm_name(case)
    if integer(case.get("returncode"), f"{directory}: returncode") != 0:
        raise EvidenceError(f"{directory}: quality case returncode is nonzero")
    stdout = case.get("stdout")
    if not isinstance(stdout, str) or "PASS" not in stdout:
        raise EvidenceError(f"{directory}: quality case lacks PASS stdout")
    if case.get("status") not in QUALITY_TERMINATIONS:
        raise EvidenceError(f"{directory}: unsupported quality termination {case.get('status')!r}")
    quality = case.get("quality")
    if not isinstance(quality, dict) or quality.get("threshold_pass") is not True:
        raise EvidenceError(f"{directory}: quality threshold did not pass")
    fixed = quality.get("fixed")
    floating = quality.get("floating")
    if not isinstance(fixed, dict) or not isinstance(floating, dict):
        raise EvidenceError(f"{directory}: fixed and floating quality metrics are required")
    fixed_snr = finite_number(fixed.get("snr_db"), f"{directory}: fixed SNR")
    floating_snr = finite_number(floating.get("snr_db"), f"{directory}: floating SNR")
    fixed_nmse = finite_number(fixed.get("nmse"), f"{directory}: fixed NMSE")
    floating_nmse = finite_number(floating.get("nmse"), f"{directory}: floating NMSE")
    snr_loss = finite_number(quality.get("snr_loss_db"), f"{directory}: SNR loss")
    nmse_ratio = finite_number(quality.get("nmse_ratio"), f"{directory}: NMSE ratio")
    if fixed_snr < 20 or floating_snr < 20:
        raise EvidenceError(f"{directory}: fixed and floating SNR must both be >=20 dB")
    if fixed_nmse < 0 or floating_nmse < 0:
        raise EvidenceError(f"{directory}: fixed and floating NMSE must both be >=0")
    if snr_loss > 0.5:
        raise EvidenceError(f"{directory}: SNR loss exceeds 0.5 dB")
    if nmse_ratio > 1.10:
        raise EvidenceError(f"{directory}: NMSE ratio exceeds 1.10")
    events = case.get("fixed_numeric_events")
    if not isinstance(events, dict):
        raise EvidenceError(f"{directory}: numeric event evidence is missing")
    for field in QUALITY_EVENT_FIELDS:
        if integer(events.get(field), f"{directory}: {field}") != 0:
            raise EvidenceError(f"{directory}: nonzero {field}")
    if integer(value_or(case, "job_cycles", "cycles"), f"{directory}: quality cycles") <= 0:
        raise EvidenceError(f"{directory}: quality cycles must be positive")
    if integer(case.get("outer_iterations"), f"{directory}: quality outer iterations") <= 0:
        raise EvidenceError(f"{directory}: quality outer iterations must be positive")


@dataclass(frozen=True)
class Geometry:
    path: Path
    summary_path: Path
    summary: dict[str, Any]
    comparison_path: Path | None
    comparison: dict[str, Any] | None
    rows: int
    columns: int
    sparsity: int
    phi_hash: str
    y_hash: str
    cases: dict[str, dict[str, Any]]
    case_artifacts: dict[str, dict[str, Any]]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def case_artifacts(summary: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Index the assembler's immutable artifact references by algorithm."""
    result: dict[str, dict[str, Any]] = {}
    provenance = summary.get("input_provenance")
    if provenance is None:
        return result
    if not isinstance(provenance, list):
        raise EvidenceError("input_provenance must be a list")
    for batch in provenance:
        artifacts = batch.get("case_artifacts") if isinstance(batch, dict) else None
        if not isinstance(artifacts, dict):
            raise EvidenceError("input provenance lacks case artifacts")
        for algorithm, value in artifacts.items():
            if algorithm in result or not isinstance(value, dict):
                raise EvidenceError(f"duplicate or malformed artifact provenance for {algorithm}")
            result[algorithm] = value
    return result


def load_geometry(path: Path) -> Geometry:
    summary_path, summary = first_json(path, ("summary.json", "focused_summary.json", "audited_summary.json"))
    clean_source(summary, summary_path)
    config = summary.get("config")
    if not isinstance(config, dict):
        raise EvidenceError(f"{summary_path}: missing config")
    rows = integer(config.get("rows"), f"{summary_path}: rows")
    columns = integer(config.get("columns"), f"{summary_path}: columns")
    sparsity = integer(config.get("sparsity"), f"{summary_path}: sparsity")
    if sparsity != 8:
        raise EvidenceError(f"{summary_path}: expected truth K=8, got {sparsity}")
    raw_cases = summary.get("cases")
    if not isinstance(raw_cases, list):
        raise EvidenceError(f"{summary_path}: missing cases")
    selected: dict[str, dict[str, Any]] = {}
    for raw in raw_cases:
        if not isinstance(raw, dict):
            raise EvidenceError(f"{summary_path}: non-object case")
        algorithm = algorithm_name(raw)
        if algorithm not in ALGORITHMS or requested_outer(raw) != 8:
            continue
        if algorithm in selected:
            raise EvidenceError(f"{summary_path}: duplicate fixed-eight {algorithm} case")
        selected[algorithm] = raw
    missing = [name for name in ALGORITHMS if name not in selected]
    if missing:
        raise EvidenceError(f"{summary_path}: missing fixed-eight cases: {', '.join(missing)}")
    bad_outer = [name for name, case in selected.items() if case_outer(case) != 8]
    if bad_outer:
        raise EvidenceError(
            f"{summary_path}: primary ranking requires actual_outer=8; failed: {', '.join(bad_outer)}"
        )
    phi_hashes = {str(case.get("raw_phi_sha256", "")) for case in selected.values()}
    y_hashes = {str(case.get("raw_y_sha256", "")) for case in selected.values()}
    if len(phi_hashes) != 1 or "" in phi_hashes or len(y_hashes) != 1 or "" in y_hashes:
        raise EvidenceError(f"{summary_path}: fixed-eight cases do not share complete Phi/Y hashes")
    expected_phi = config.get("expected_phi_sha256")
    expected_y = config.get("expected_y_sha256")
    phi_hash = next(iter(phi_hashes))
    y_hash = next(iter(y_hashes))
    if expected_phi and expected_phi != phi_hash:
        raise EvidenceError(f"{summary_path}: Phi hash differs from config")
    if expected_y and expected_y != y_hash:
        raise EvidenceError(f"{summary_path}: Y hash differs from config")
    comparison_path: Path | None = None
    comparison: dict[str, Any] | None = None
    for name in ("comparison.json", "derived_comparison.json"):
        candidate = path / name
        if candidate.is_file():
            comparison_path, comparison = candidate, read_json(candidate)
            if comparison.get("status") != "PASS":
                raise EvidenceError(f"{candidate}: comparison status is not PASS")
            break
    return Geometry(path, summary_path, summary, comparison_path, comparison, rows, columns, sparsity,
                    phi_hash, y_hash, selected, case_artifacts(summary))


def comparison_cases(geometry: Geometry) -> dict[str, dict[str, Any]]:
    if geometry.comparison is None:
        return {}
    raw_cases = geometry.comparison.get("cases")
    if not isinstance(raw_cases, list):
        raise EvidenceError(f"{geometry.comparison_path}: missing comparison cases")
    result: dict[str, dict[str, Any]] = {}
    for raw in raw_cases:
        if not isinstance(raw, dict) or algorithm_name(raw) not in ALGORITHMS:
            continue
        algorithm = algorithm_name(raw)
        if requested_outer(raw) != 8:
            continue
        if case_outer(raw) != 8:
            raise EvidenceError(f"{geometry.comparison_path}: {algorithm} has unequal actual outer count")
        if raw.get("exact_same_outputs") is False:
            raise EvidenceError(f"{geometry.comparison_path}: {algorithm} output equality failed")
        if algorithm in result:
            raise EvidenceError(f"{geometry.comparison_path}: duplicate {algorithm}")
        result[algorithm] = raw
    if result and set(result) != set(ALGORITHMS):
        missing = [name for name in ALGORITHMS if name not in result]
        raise EvidenceError(f"{geometry.comparison_path}: missing primary comparison cases: {', '.join(missing)}")
    return result


def counter_calls(total: Any, label: str) -> int:
    if not isinstance(total, dict) or "calls" not in total:
        raise EvidenceError(f"{label}: service total has no calls counter")
    calls = integer(total["calls"], f"{label}: calls")
    if calls < 0:
        raise EvidenceError(f"{label}: calls must be nonnegative")
    return calls


def checked_factor_opcode(artifacts: dict[str, Any], algorithm: str) -> int:
    """Read the archived ABI and executed T words for a physical op count."""
    package = artifacts.get("package")
    trace = artifacts.get("trace")
    if not isinstance(package, dict) or not isinstance(trace, dict):
        raise EvidenceError(f"{algorithm}: physical service profile lacks package/trace provenance")
    package_path = Path(str(package.get("path", "")))
    trace_path = Path(str(trace.get("path", "")))
    if (not package_path.is_file() or not trace_path.is_file()
            or sha256(package_path) != package.get("sha256")
            or sha256(trace_path) != trace.get("sha256")):
        raise EvidenceError(f"{algorithm}: package/trace provenance digest is unavailable")
    # The assembler records the source-snapshot root beside every batch artifact.
    snapshot_root = artifacts.get("source_snapshot_root")
    if not isinstance(snapshot_root, str):
        raise EvidenceError(f"{algorithm}: source ABI provenance is unavailable")
    abi_path = Path(snapshot_root) / "config/v4_kernel_interface.json"
    if not abi_path.is_file():
        raise EvidenceError(f"{algorithm}: archived kernel ABI is unavailable")
    abi = read_json(abi_path)
    factor_opcode = abi.get("operations", {}).get("FACTOR_INIT") if isinstance(abi.get("operations"), dict) else None
    if integer(factor_opcode, f"{algorithm}: FACTOR_INIT ABI") != 13:
        raise EvidenceError(f"{algorithm}: archived kernel ABI does not define FACTOR_INIT as op13")
    retired_factor = 0
    for line in trace_path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[:2] == ["T", "1"]:
            word = int(fields[3], 16)
            if (word & 0x1F) == 1 and ((word >> 5) & 0x3F) == factor_opcode:
                retired_factor += 1
    return retired_factor


def physical_counts(geometry: Geometry, algorithm: str, source: dict[str, Any]) -> tuple[Any, Any]:
    profile = source.get("cycle_profile")
    totals = profile.get("service_totals") if isinstance(profile, dict) else None
    if totals is None:
        return "unknown", "unknown"
    if not isinstance(totals, dict):
        raise EvidenceError(f"{algorithm}: service_totals is malformed")
    factor = counter_calls(totals["KERNEL:13"], f"{algorithm}: KERNEL:13") if "KERNEL:13" in totals else 0
    builds = sum(counter_calls(total, f"{algorithm}: {name}")
                 for name, total in totals.items() if isinstance(name, str) and name.startswith("BUILD:"))
    artifacts = geometry.case_artifacts.get(algorithm)
    if artifacts is None:
        raise EvidenceError(f"{algorithm}: executed service profile has no artifact provenance")
    trace_factor = checked_factor_opcode(artifacts, algorithm)
    if trace_factor != factor:
        raise EvidenceError(f"{algorithm}: KERNEL:13 service count ({factor}) differs from retired FACTOR_INIT ({trace_factor})")
    return factor, builds


def support_counts(source: dict[str, Any]) -> tuple[Any, Any]:
    published = value_or(source, "published_support_size", "accepted_support_size", default=None)
    if published is None:
        accepted = source.get("accepted_support")
        published = len(accepted) if isinstance(accepted, list) else "unknown"
    nonzeros = source["actual_nonzero_coefficients"] if "actual_nonzero_coefficients" in source else "unknown"
    return published, nonzeros


def row_for(geometry: Geometry, algorithm: str, comparison: dict[str, dict[str, Any]]) -> dict[str, Any]:
    source = geometry.cases[algorithm]
    derived = comparison.get(algorithm, {})
    cycles = value_or(derived, "balanced_cycles", "combined_cycles", default=value_or(source, "job_cycles", "cycles", default=None))
    if cycles is None:
        raise EvidenceError(f"{algorithm}: cycles are absent")
    actual_support, nonzeros = support_counts(source)
    max_qr_support = source["maximum_ls_support"] if "maximum_ls_support" in source else "unknown"
    factor_init = value_or(derived, "actual_factor_initializations", "measured_factor_initializations", default=None)
    build_calls = value_or(derived, "actual_build_calls", "measured_build_calls", default=None)
    if factor_init is None or build_calls is None:
        profile_factor, profile_builds = physical_counts(geometry, algorithm, source)
        factor_init = profile_factor if factor_init is None else factor_init
        build_calls = profile_builds if build_calls is None else build_calls
    logical_ls = value_or(derived, "model_logical_ls_requests", "logical_model_ls_requests", default=None)
    if logical_ls is None:
        logical_ls = source["solver_invocations"] if "solver_invocations" in source else "unknown"
    total_cg = source["total_committed_inner_iterations"] if "total_committed_inner_iterations" in source else "unknown"
    return {
        "algorithm": algorithm,
        "cycles": integer(cycles, f"{algorithm} cycles"),
        "actual_outer": case_outer(source),
        "support": actual_support,
        "nonzeros": nonzeros,
        "max_qr_support": max_qr_support,
        "factor_init": factor_init,
        "build_calls": build_calls,
        "logical_ls": logical_ls,
        "total_cg": total_cg,
        "snr": quality_snr(source),
        "status": source.get("status", "unknown"),
        "policy": source.get("policy", {}),
    }


def markdown_geometry(geometry: Geometry) -> str:
    comparison = comparison_cases(geometry)
    mode = "balanced candidate cycles" if comparison else "frozen execution cycles"
    lines = [
        f"## M={geometry.rows}, N={geometry.columns}, K={geometry.sparsity}",
        "",
        f"Evidence: `{geometry.path}`. Source-clean PASS evidence: `{geometry.summary_path.name}`. "
        f"Phi SHA256 `{geometry.phi_hash}`; Y SHA256 `{geometry.y_hash}`.",
        f"The table uses {mode}; every row executed exactly eight outer iterations. "
        "The original benchmark policy is shown as recorded by the evidence, not retuned for this report.",
        "",
        "| Algorithm | Cycles | Actual outer | Published support | Nonzero coefficients | Max QR support | Physical FACTOR_INIT | Physical BUILD | Logical LS requests | Total CG | Fixed SNR (dB) | Status |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for algorithm in ALGORITHMS:
        row = row_for(geometry, algorithm, comparison)
        lines.append(
            f"| {row['algorithm']} | {row['cycles']:,} | {row['actual_outer']} | "
            f"{format_value(row['support'])} | {format_value(row['nonzeros'])} | {format_value(row['max_qr_support'])} | "
            f"{format_value(row['factor_init'])} | {format_value(row['build_calls'])} | {format_value(row['logical_ls'])} | "
            f"{format_value(row['total_cg'])} | {format_value(row['snr'])} | {row['status']} |"
        )
    lines.extend([
        "",
        "`Published support` is the active support publication; `Nonzero coefficients` is reported separately because proximal programs can publish no support while retaining nonzero X values. `Logical LS requests` are model-level requests. `Physical FACTOR_INIT` is KERNEL:13 calls from the complete accepted-service profile, cross-checked against retired T words using the archived FACTOR_INIT=13 kernel ABI. `Physical BUILD` sums BUILD:* calls. A missing profile remains `unknown`; a complete profile with no KERNEL:13 and no retired factor opcode proves zero. "
        "Equal outer counts do not imply equal internal work: SP has an initial solve, GOMP can retain support 16 at eight iterations, and ADMM reports its committed inner CG total when that counter exists.",
        "",
    ])
    return "\n".join(lines)


def load_quality(directory: Path) -> list[dict[str, Any]]:
    path, summary = first_json(directory, ("summary.json", "focused_summary.json"))
    cases = summary.get("cases")
    if not isinstance(cases, list):
        raise EvidenceError(f"{path}: quality cases missing")
    component_parent = documented_component_parent(summary, directory)
    source_snapshot_clean(summary, directory, allow_documented_parent_failure=component_parent)
    if component_parent:
        parent_status = "component PASS; parent FAIL retained"
    else:
        parent_status = "PASS"
    result = []
    for case in cases:
        if not isinstance(case, dict):
            raise EvidenceError(f"{path}: quality case must be an object")
        validate_quality_case(case, directory)
        quality = case["quality"]
        fixed = quality["fixed"]
        floating = quality["floating"]
        events = case["fixed_numeric_events"]
        result.append({
            "algorithm": algorithm_name(case), "rows": integer(case.get("rows"), f"{directory}: rows"), "columns": integer(case.get("columns"), f"{directory}: columns"),
            "cycles": integer(value_or(case, "job_cycles", "cycles"), f"{directory}: quality cycles"),
            "outer": integer(case.get("outer_iterations"), f"{directory}: quality outer iterations"), "snr": fixed["snr_db"],
            "float_snr": floating["snr_db"], "snr_loss": quality["snr_loss_db"],
            "fixed_nmse": fixed["nmse"], "float_nmse": floating["nmse"],
            "nmse_ratio": quality["nmse_ratio"],
            "events": "/".join(str(events[name]) for name in QUALITY_EVENT_FIELDS),
            "status": case["status"], "parent_status": parent_status,
            "path": directory.name,
        })
    return result


def markdown_quality(paths: list[Path]) -> str:
    rows: list[dict[str, Any]] = []
    for path in paths:
        if path.exists():
            rows.extend(load_quality(path))
    lines = [
        "## Quality validations (separate from cycle ranking)",
        "",
        "These validations use distinct convergence policies and termination counts. They are numerical/RTL quality evidence only and are never ranked by cycle beside the fixed-eight table.",
        "",
        "| Evidence | M/N | Algorithm | Cycles | Actual outer | Fixed/float SNR (dB) | Loss (dB) | Fixed/float NMSE | NMSE ratio | sat/overflow/div0 | Termination | Evidence status |",
        "|---|---|---|---:|---:|---|---:|---|---:|---|---|---|",
    ]
    for row in rows:
        status = row["parent_status"]
        lines.append("| {path} | {rows}/{columns} | {algorithm} | {cycles:,} | {outer} | {snr}/{float_snr} | {snr_loss} | {fixed_nmse}/{float_nmse} | {nmse_ratio} | {events} | {status_case} | {status} |".format(
            path=row["path"], rows=row["rows"], columns=row["columns"], algorithm=row["algorithm"], cycles=integer(row["cycles"], "quality cycles"),
            outer=format_value(row["outer"]), snr=quality_number(row["snr"]), float_snr=quality_number(row["float_snr"]),
            snr_loss=quality_number(row["snr_loss"]), fixed_nmse=quality_number(row["fixed_nmse"], scientific=True),
            float_nmse=quality_number(row["float_nmse"], scientific=True), nmse_ratio=quality_number(row["nmse_ratio"]), events=row["events"],
            status_case=row["status"], status=status))
    lines.extend([
        "",
        "The FISTA component is valid only as documented in `quality_htp_fista_m64_20260909`: its parent invocation remains FAIL because the HTP harness raised a TypeError before simulation; the corrected HTP gate is `quality_htp_m64_20260909`. "
        "PDHG appears only from its completed report. Held-out numerical studies and native RTL evidence are distinct; each table row reports only the archive supplied to this generator.",
        "",
    ])
    return "\n".join(lines)


def render(geometries: list[Geometry], quality_paths: list[Path]) -> str:
    sections = [
        "# Fixed-eight optimization report", "",
        "This is the only cross-algorithm cycle comparison in this report. Each row has the same M/N/K, identical raw Phi/Y hashes within its geometry, source-clean frozen evidence, and exactly eight **actual** outer iterations. "
        "It does not establish equal internal work, application qualification, timing closure, Fmax, area, or a production bit lock.", "",
        "The original benchmark policy is retained as evidence. Residual early stopping is disabled for this benchmark and SP non-decrease stopping is disabled; quality-policy runs are listed separately.", "",
    ]
    sections.extend(markdown_geometry(geometry) for geometry in geometries)
    sections.append(markdown_quality(quality_paths))
    sections.extend([
        "## References and limits", "",
        "Legacy V2/V3 numbers are historical configuration references only: [K8_COMPARISON.md](K8_COMPARISON.md) and [k8_legacy_configuration_20260909.md](k8_legacy_configuration_20260909.md). "
        "They use different Phi/data, solver, arithmetic, iteration behavior, and/or counting boundaries, so this report deliberately contains no legacy speedup column or raw-ratio fairness claim.", "",
        "## Within-algorithm architecture ablations", "",
        "The before/after pairs are [qr_balanced_m64_n256_rtl_20260909](qr_balanced_m64_n256_rtl_20260909) and [compute_balanced_k8_m32_n64_20260909](compute_balanced_k8_m32_n64_20260909). Each row in those reports compares matching X/R/hash and policy within one algorithm. They remain an appendix, not a cross-algorithm cycle table, because the natural SP run does not have eight outer iterations.", "",
        "HTP's fixed-eight cycles can be low when the program reuses unchanged support. That proves an exact architecture optimization for this fixture, not that the low-SNR baseline recovered correctly: the M64/M32 fixed-eight HTP SNR values are about 6.57/4.14 dB. The separately tuned HTP quality gate is 40,445 cycles, two outer iterations, 86.10 dB, two physical QR initializations, and no cache hits. CoSaMP likewise has six physical FACTOR_INIT calls for eight logical LS requests at M64, but eight/eight at M32; neither observation is a general novelty or quality claim.", "",
        "## Qualification limits", "",
        "[k8_quality_policy_20260909](k8_quality_policy_20260909) records held-out failures and scope boundaries: low-M IHT is unsupported, NIHT is not IHT, no qualified real-application dataset result exists, and there is no production bit lock. The promoted architecture description is [OPTIMIZATION_FINALIZATION.md](../../docs/v4/architecture/OPTIMIZATION_FINALIZATION.md).", "",
        "The promoted compute structure is hierarchical: terminal ACC uses existing PEACC and fixed registered reduction links; scalar opcode16 uses existing lane0 without RAM; compiler-emitted QR reuse uses generic instructions and vector-pool state keyed by immutable Phi/Y and exact ordered support. It caches certified packed X and exact residual only after QR certificate success, never a QR factorization. These statements add no array, general programmable mesh, area, Fmax, or timing claim.", "",
    ])
    return "\n".join(sections)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--geometry", action="append", required=True, type=Path, help="frozen report directory; provide once per geometry")
    parser.add_argument("--quality", action="append", default=[], type=Path, help="optional quality report directory")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        geometries = [load_geometry(path) for path in args.geometry]
        rendered = render(geometries, args.quality)
    except EvidenceError as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
