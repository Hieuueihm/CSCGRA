#!/usr/bin/env python3
"""Fail when canonical project ownership or manifests diverge."""

from __future__ import annotations

import json
import pathlib
import re
import sys


REQUIRED_STATUS_LINK = "reports/v2/CURRENT_STATUS.md"
REQUIRED_DEVELOPMENT_STATUS_LINK = "reports/v3/GOLDEN_STATUS.md"
ACTIVE_DOCS = (
    "README.md",
    "docs/PROJECT_STATUS.md",
    "docs/REFERENCE_FLOW.md",
    "rtl/v2/README.md",
    "verification/v2/README.md",
    "reports/README.md",
)
V3_REVISION_DOCS = {
    "reports/v3/GOLDEN_STATUS.md": (
        "Architecture revision {architecture_revision}; "
        "RTL minor revision {rtl_minor_revision}.",
        "Context ISA revision {context_format_revision};",
    ),
    "docs/v3/05_RECONSTRUCTION_REGISTER_MAP.md": (
        "architecture revision = {architecture_revision}",
        "RTL minor revision = {rtl_minor_revision}",
        "context format revision = {context_format_revision}",
    ),
}


def load_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read JSON {path}: {exc}") from exc


def main() -> int:
    repo = pathlib.Path(__file__).resolve().parents[2]
    errors: list[str] = []

    project_path = repo / "config/project.json"
    project = load_json(project_path)
    if project.get("schema_version") != 1:
        errors.append("config/project.json must use schema_version 1")
    if project.get("active_rtl_version") != "v2":
        errors.append("active_rtl_version must be v2")
    if project.get("current_status") != REQUIRED_STATUS_LINK:
        errors.append(f"current_status must be {REQUIRED_STATUS_LINK}")
    if project.get("development_rtl_version") != "v3":
        errors.append("development_rtl_version must be v3")
    if project.get("development_status") != REQUIRED_DEVELOPMENT_STATUS_LINK:
        errors.append(
            f"development_status must be {REQUIRED_DEVELOPMENT_STATUS_LINK}")

    config_rel = project.get("active_config", "")
    config_path = repo / config_rel
    config = load_json(config_path)
    if config.get("version") != project.get("active_rtl_version"):
        errors.append("active config version does not match project.json")
    if config.get("active") is not True:
        errors.append("active RTL config must set active=true")
    if config.get("baseline") is not None:
        errors.append("dynamic baseline metrics do not belong in rtl-v2.json")

    filelist_rel = config.get("rtl_filelist", "")
    filelist_path = repo / filelist_rel
    if not filelist_path.is_file():
        errors.append(f"missing active RTL filelist: {filelist_rel}")
        entries: list[str] = []
    else:
        entries = [
            line.strip().replace("\\", "/")
            for line in filelist_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]

    if len(entries) != len(set(entries)):
        errors.append("active RTL filelist contains duplicate entries")
    for entry in entries:
        if not entry.startswith("rtl/v2/"):
            errors.append(f"active filelist escapes rtl/v2: {entry}")
        if not (repo / entry).is_file():
            errors.append(f"missing filelist source: {entry}")

    disk_v = sorted(
        path.relative_to(repo).as_posix() for path in (repo / "rtl/v2").rglob("*.v")
    )
    listed_v = sorted(entry for entry in entries if entry.endswith(".v"))
    for missing in sorted(set(disk_v) - set(listed_v)):
        errors.append(f"RTL source not listed in files.f: {missing}")
    for stale in sorted(set(listed_v) - set(disk_v)):
        errors.append(f"files.f entry is not an RTL .v source: {stale}")

    module_owners: dict[str, pathlib.Path] = {}
    module_re = re.compile(r"(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b")
    for path in sorted((repo / "rtl/v2").rglob("*.v")) + sorted(
        (repo / "rtl/v2").rglob("*.vh")
    ):
        for module in module_re.findall(path.read_text(encoding="utf-8", errors="ignore")):
            previous = module_owners.get(module)
            if previous is not None:
                errors.append(
                    f"duplicate active module {module}: "
                    f"{previous.relative_to(repo)} and {path.relative_to(repo)}"
                )
            module_owners[module] = path

    required_paths = (
        config.get("verification_root", ""),
        config.get("default_testbench", ""),
        config.get("provenance", {}).get("formal_manifest", ""),
        project.get("current_status", ""),
    )
    for rel in required_paths:
        if not rel or not (repo / rel).exists():
            errors.append(f"missing canonical project path: {rel!r}")

    for doc_rel in ACTIVE_DOCS:
        text = (repo / doc_rel).read_text(encoding="utf-8")
        if REQUIRED_STATUS_LINK not in text and "CURRENT_STATUS.md" not in text:
            errors.append(f"active documentation does not link current status: {doc_rel}")

    development_rel = project.get("development_config", "")
    development_path = repo / development_rel
    development = load_json(development_path)
    if development.get("version") != project.get("development_rtl_version"):
        errors.append("development config version does not match project.json")
    if development.get("active") is not False or development.get("development") is not True:
        errors.append("v3 config must be explicitly development-only until datapath completion")
    development_filelist_rel = development.get("rtl_filelist", "")
    development_filelist = repo / development_filelist_rel
    if not development_filelist.is_file():
        errors.append(f"missing development RTL filelist: {development_filelist_rel}")
        development_entries: list[str] = []
    else:
        development_entries = [
            line.strip().replace("\\", "/")
            for line in development_filelist.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#") and
            not line.lstrip().startswith("+incdir+")
        ]
    if len(development_entries) != len(set(development_entries)):
        errors.append("development RTL filelist contains duplicate entries")
    for entry in development_entries:
        if not entry.startswith("rtl/v3/"):
            errors.append(f"development filelist escapes rtl/v3: {entry}")
        if not (repo / entry).is_file():
            errors.append(f"missing development source: {entry}")
    disk_v3 = sorted(
        path.relative_to(repo).as_posix() for path in (repo / "rtl/v3").rglob("*.v")
    )
    listed_v3 = sorted(entry for entry in development_entries if entry.endswith(".v"))
    for missing in sorted(set(disk_v3) - set(listed_v3)):
        errors.append(f"v3 RTL source not listed in files.f: {missing}")
    for stale in sorted(set(listed_v3) - set(disk_v3)):
        errors.append(f"v3 files.f entry is not an RTL .v source: {stale}")
    development_modules: dict[str, pathlib.Path] = {}
    for path in sorted((repo / "rtl/v3").rglob("*.v")) + sorted(
            (repo / "rtl/v3").rglob("*.vh")):
        for module in module_re.findall(path.read_text(encoding="utf-8", errors="ignore")):
            previous = development_modules.get(module)
            if previous is not None:
                errors.append(
                    f"duplicate development module {module}: "
                    f"{previous.relative_to(repo)} and {path.relative_to(repo)}")
            development_modules[module] = path
    authority_rel = "compiler/v3/architecture_configuration.json"
    authority = load_json(repo / authority_rel)
    for doc_rel, templates in V3_REVISION_DOCS.items():
        text = (repo / doc_rel).read_text(encoding="utf-8")
        for template in templates:
            expected = template.format(**authority)
            if expected not in text:
                errors.append(
                    f"v3 revision authority mismatch in {doc_rel}: expected {expected!r}")

    generated_parameters = (
        repo / "rtl/v3/include/architecture_parameters.vh"
    ).read_text(encoding="utf-8")
    generated_revision_defines = {
        "RECON_ARCHITECTURE_REVISION": authority["architecture_revision"],
        "RECON_RTL_MINOR_REVISION": authority["rtl_minor_revision"],
        "RECON_CONTEXT_FORMAT_REVISION": authority["context_format_revision"],
    }
    for name, value in generated_revision_defines.items():
        pattern = rf"(?m)^`define\s+{name}\s+\d+'d{value}\s*$"
        if re.search(pattern, generated_parameters) is None:
            errors.append(
                f"generated architecture parameter {name} is stale; expected {value}")

    active_synth_scripts = sorted((repo / "scripts/synth").glob("*.tcl"))
    forbidden_directive = re.compile(
        r"(?im)^\s*(?:synth_design|opt_design|place_design|phys_opt_design|"
        r"route_design)\b[^\n]*\s-directive\b")
    for path in active_synth_scripts:
        if forbidden_directive.search(path.read_text(encoding="utf-8", errors="ignore")):
            errors.append(
                f"active Vivado flow must not pass -directive: {path.relative_to(repo)}")

    budget = load_json(repo / "reports/v3/m11_m12_resource_budget.json")
    capacity = budget["device_clb_lut_capacity"]
    baseline = budget["m11_integrated"]["clb_lut"]
    m12_delta = budget["budgets"]["m12_result_writer_delta_clb_lut"]
    projected = baseline + m12_delta
    ceiling = budget["hard_ceiling"]["clb_lut"]
    if budget["budgets"]["m12_projected_total_clb_lut"] != projected:
        errors.append("M11/M12 projected CLB LUT budget arithmetic is stale")
    if ceiling != int(capacity * budget["hard_ceiling"]["utilization_percent"] / 100):
        errors.append("M11/M12 hard CLB LUT ceiling arithmetic is stale")
    if projected > ceiling:
        errors.append("M11/M12 projected CLB LUT budget exceeds hard ceiling")
    if budget["policy"].get("synthesis_directives") is not False or \
            budget["policy"].get("implementation_directives") is not False:
        errors.append("M11/M12 resource policy must prohibit Vivado directives")

    program_library = load_json(repo / "reports/v3/m11_program_images.json")
    readiness = load_json(repo / "reports/v3/m11_program_readiness.json")
    qualified_ids = program_library.get("implemented_program_ids")
    if qualified_ids != [0, 1, 2, 3, 4, 5, 6, 7] or \
            readiness.get("implemented_program_ids") != qualified_ids:
        errors.append(
            "M11 qualified program IDs must be generated as [0, 1, 2, 3, 4, 5, 6, 7]")
    packaged_ids = [item.get("program_id") for item in
                    program_library.get("programs", [])]
    if len(packaged_ids) != len(set(packaged_ids)) or \
            not set(qualified_ids or []).issubset(packaged_ids):
        errors.append("M11 packaged programs must uniquely include all qualified IDs")
    readiness_programs = {item.get("program_id"): item for item in
                          readiness.get("programs", [])}
    for program_id in packaged_ids:
        record = readiness_programs.get(program_id, {})
        if not record.get("phase_image_packaged"):
            errors.append(f"M11 packaged program ID{program_id} lacks readiness image")
        if program_id not in (qualified_ids or []) and \
                (record.get("status") != "BLOCKED" or not record.get("blockers")):
            errors.append(
                f"M11 unqualified packaged program ID{program_id} must remain BLOCKED")
    for program_id in qualified_ids or []:
        record = readiness_programs.get(program_id, {})
        if record.get("status") != "READY" or not record.get("phase_image_packaged"):
            errors.append(f"M11 program ID{program_id} lacks READY packaged status")
        for evidence in record.get("qualification_evidence", []):
            if not (repo / evidence).is_file():
                errors.append(
                    f"M11 program ID{program_id} lacks qualification evidence: {evidence}")
    iht_memory = repo / "reports/v3/context_images/program_02_phase.mem"
    if not iht_memory.is_file() or len(iht_memory.read_text(
            encoding="utf-8").splitlines()) != 23:
        errors.append("M11 IHT phase MEM must contain 23 instructions")
    cosamp_memory = repo / "reports/v3/context_images/program_01_phase.mem"
    if not cosamp_memory.is_file() or len(cosamp_memory.read_text(
            encoding="utf-8").splitlines()) != 41:
        errors.append("M11 CoSaMP phase MEM must contain 41 instructions")
    htp_memory = repo / "reports/v3/context_images/program_03_phase.mem"
    if not htp_memory.is_file() or len(htp_memory.read_text(
            encoding="utf-8").splitlines()) != 41:
        errors.append("M11 HTP phase MEM must contain 41 instructions")
    sp_memory = repo / "reports/v3/context_images/program_04_phase.mem"
    if not sp_memory.is_file() or len(sp_memory.read_text(
            encoding="utf-8").splitlines()) != 103:
        errors.append("M11 SP phase MEM must contain 103 instructions")
    gp_memory = repo / "reports/v3/context_images/program_05_phase.mem"
    if not gp_memory.is_file() or len(gp_memory.read_text(
            encoding="utf-8").splitlines()) != 29:
        errors.append("M11 GP phase MEM must contain 29 instructions")
    gomp_memory = repo / "reports/v3/context_images/program_06_phase.mem"
    if not gomp_memory.is_file() or len(gomp_memory.read_text(
            encoding="utf-8").splitlines()) != 39:
        errors.append("M11 gOMP phase MEM must contain 39 instructions")
    mp_memory = repo / "reports/v3/context_images/program_07_phase.mem"
    if not mp_memory.is_file() or len(mp_memory.read_text(
            encoding="utf-8").splitlines()) != 29:
        errors.append("M11 MP phase MEM must contain 29 instructions")

    m8_summary_path = repo / "reports/v3/m8_vivado/summary.txt"
    summary_values = {}
    if m8_summary_path.is_file():
        for line in m8_summary_path.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                summary_values[key] = value
    if summary_values.get("top") != "m8_operator_harness" or \
            summary_values.get("wns_gate_pass") != "1":
        errors.append("M11 qualification requires a passing M8 OOC summary")
    try:
        if float(summary_values.get("post_synth_wns_ns", "-inf")) < 1.0:
            errors.append("M11 qualification requires M8 WNS >= +1.0 ns")
    except ValueError:
        errors.append("M8 OOC WNS summary is not numeric")
    utilization = (repo / "reports/v3/m8_vivado/utilization.rpt").read_text(
        encoding="utf-8", errors="ignore")
    expected_lut = budget["m11_integrated"]["clb_lut"]
    if re.search(rf"\| CLB LUTs\*\s+\|\s*{expected_lut}\s*\|", utilization) is None:
        errors.append("M11 integrated CLB LUT budget differs from Vivado evidence")
    for table in ("tile_operations", "resource_operations", "compiler_operations"):
        for record in authority.get(table, []):
            name = record.get("name", "<unnamed>")
            status = record.get("status")
            owner = record.get("rtl_owner")
            evidence = record.get("evidence")
            if status == "implemented":
                if owner not in development_modules:
                    errors.append(
                        f"implemented capability {name} owner absent from files.f: {owner}")
                if not evidence or not (repo / evidence).is_file():
                    errors.append(
                        f"implemented capability {name} lacks evidence: {evidence}")
            if record.get("timing_status") == "measured":
                timing_evidence = record.get("timing_evidence")
                if not timing_evidence or not (repo / timing_evidence).is_file():
                    errors.append(
                        f"measured timing {name} lacks evidence: {timing_evidence}")
    for record in [authority.get("execution_context", {}),
                   *authority.get("matrix_modes", [])]:
        if record.get("status") == "implemented":
            evidence = record.get("evidence")
            if not evidence or not (repo / evidence).is_file():
                errors.append(
                    f"capability {record.get('name', 'execution context')} lacks evidence: {evidence}")

    development_paths = (
        development.get("verification_root", ""),
        development.get("default_testbench", ""),
        development.get("provenance", {}).get("current_status", ""),
        development.get("provenance", {}).get("architecture_manifest", ""),
        development.get("provenance", {}).get("formal_intent", ""),
    )
    for rel in development_paths:
        if not rel or not (repo / rel).exists():
            errors.append(f"missing development project path: {rel!r}")

    if errors:
        print("PROJECT CONSISTENCY: FAIL", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("PROJECT CONSISTENCY: PASS")
    print(f"active_config={config_rel}")
    print(f"rtl_sources={len(listed_v)} modules={len(module_owners)}")
    print(f"current_status={project['current_status']}")
    print(f"development_config={development_rel}")
    print(f"development_rtl_sources={len(listed_v3)} modules={len(development_modules)}")
    print(f"development_status={project['development_status']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
