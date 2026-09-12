"""Combine independently completed, source-clean fixed-eight batches.

Interrupted parents and batches lacking persisted import coverage are rejected.
Every accepted case retains a hash-addressable fixture/package/trace reference.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


HARNESS_ONLY = {"benchmark_config.json", "scripts/v4/benchmark_k8.py"}
ALGORITHMS = ("MP", "GP", "IHT", "OMP", "GOMP", "CoSaMP", "SP", "HTP", "FISTA", "PDHG", "ADMM")


def fail(message):
    raise SystemExit(f"assemble failed: {message}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signed27(word):
    return word - (1 << 27) if word & (1 << 26) else word


def i32_sha(values):
    return hashlib.sha256(struct.pack(f"<{len(values)}i", *values)).hexdigest()


def reference(path):
    if not path.is_file():
        fail(f"missing evidence artifact: {path}")
    return {"path": str(path.resolve()), "sha256": digest(path)}


def verify_source_snapshot(report_dir, sources):
    """Re-hash the archived execution inputs, not merely their manifest."""
    root = report_dir / "source_snapshot"
    if not root.is_dir():
        fail(f"{report_dir}: archived source_snapshot is missing")
    missing_or_changed = [name for name, expected in sources.items()
                          if not (root / name).is_file() or digest(root / name) != expected]
    if missing_or_changed:
        fail("archived source snapshot mismatch: " + ", ".join(sorted(missing_or_changed)))
    return {"root": str(root.resolve()), "file_count": len(sources),
            "sources": sources}


def clean_summary(path):
    if not path.is_file():
        fail(f"missing batch input: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("status") != "PASS":
        fail(f"{path}: only a completed PASS batch can be assembled")
    if data.get("failures") != 0 or data.get("errors") != 0:
        fail(f"{path}: completed batch reports failures or errors")
    config = data.get("config")
    if not isinstance(config, dict) or config.get("fixed_iteration_benchmark") is not True or config.get("qr_profile") != "balanced":
        fail(f"{path}: batch is not the balanced fixed-iteration configuration")
    for field in ("changed_sources", "untracked_imports"):
        if field not in data or not isinstance(data[field], list) or data[field]:
            fail(f"{path}: {field} is missing or nonempty")
    if not isinstance(data.get("source_sha256"), dict) or not data["source_sha256"]:
        fail(f"{path}: source hash manifest is missing")
    return data


def verify_case(report_dir, index, record):
    name = record.get("algorithm", f"case{index}")
    if record.get("fixed_iteration_benchmark") is not True:
        fail(f"{name}: record does not carry the fixed-iteration marker")
    evidence_files = sorted(report_dir.glob("recovery_algorithms*/evidence.json"))
    if len(evidence_files) != 1:
        fail(f"{report_dir}: need exactly one copied execution evidence file")
    evidence = evidence_files[0]
    records = json.loads(evidence.read_text(encoding="utf-8"))
    if index >= len(records) or records[index].get("algorithm") != name:
        fail(f"{name}: copied execution evidence ordering differs from summary")
    evidence_record = records[index]
    for key in ("fixture_sha256", "package_sha256", "trace_sha256", "output_raw_x_sha256", "output_raw_r_sha256", "outer_iterations", "job_cycles"):
        if evidence_record.get(key) != record.get(key):
            fail(f"{name}: copied execution evidence differs at {key}")
    paths = {"fixture": evidence.parent / f"case{index}.txt", "trace": evidence.parent / f"trace{index}.txt",
             "package": evidence.parent / f"package{index}" / "package.json", "simulation": evidence.parent / f"simulation{index}.json"}
    expected_hashes = {"fixture": record.get("fixture_sha256"), "trace": record.get("trace_sha256"), "package": record.get("package_sha256")}
    for artifact_name in ("fixture", "trace", "package"):
        if not paths[artifact_name].is_file() or digest(paths[artifact_name]) != expected_hashes[artifact_name]:
            fail(f"{name}: {artifact_name} artifact cannot be verified")
    if not paths["simulation"].is_file():
        fail(f"{name}: simulation artifact is missing")
    lines = paths["trace"].read_text(encoding="utf-8").splitlines()
    x_values = [signed27(int(line.split()[3], 16)) for line in lines if line.startswith("X 1 ")]
    r_values = [signed27(int(line.split()[3], 16)) for line in lines if line.startswith("V 1 ")]
    done = [tuple(map(int, line.split()[1:])) for line in lines if line.startswith("D 1 ")]
    retired = [(int(line.split()[2]), int(line.split()[3], 16)) for line in lines if line.startswith("T 1 ")]
    if i32_sha(x_values) != record.get("output_raw_x_sha256") or i32_sha(r_values) != record.get("output_raw_r_sha256"):
        fail(f"{name}: trace does not reproduce output digests")
    if len(done) != 1 or done[0][1] != 0 or done[0][4] != 1 or done[0][5] != 8 or done[0][7] != record.get("job_cycles"):
        fail(f"{name}: trace does not prove successful eight-outer RTL completion")
    tail = lines[-1].split() if lines else []
    if len(tail) != 6 or tail[0] != "END":
        fail(f"{name}: trace has no valid completion END marker")
    program = json.loads(paths["package"].read_text(encoding="utf-8")).get("program")
    if (not isinstance(program, list) or any(pc < 0 or pc >= len(program) for pc, _ in retired)
            or [program[pc] for pc, _ in retired] != [word for _, word in retired]
            or len(retired) != record.get("retired_instructions")):
        fail(f"{name}: trace/program instruction provenance is inconsistent")
    simulation = json.loads(paths["simulation"].read_text(encoding="utf-8"))
    if simulation.get("returncode") != 0 or simulation.get("stdout") != record.get("stdout"):
        fail(f"{name}: simulation artifact is inconsistent")
    commands = record.get("commands", [])
    if not commands or commands[-1:] != simulation.get("commands", []):
        fail(f"{name}: executed xsim command provenance is incomplete")
    if "PASS cycles=" not in record.get("stdout", ""):
        fail(f"{name}: xsim PASS marker is missing")
    commits = [step for step in record.get("fixed_model_trace", []) if step.get("phase") == "COMMIT"]
    if len(commits) != 8:
        fail(f"{name}: fixed-model trace does not contain eight commits")
    return {"evidence": reference(evidence), **{key: reference(value) for key, value in paths.items()}}


def load_batch(path):
    absolute = path.resolve()
    data = clean_summary(absolute)
    report_dir = absolute.parent
    cases = data.get("cases")
    if not isinstance(cases, list) or not cases:
        fail(f"{absolute}: cases are missing")
    artifacts = {case.get("algorithm", f"case{index}"): verify_case(report_dir, index, case)
                 for index, case in enumerate(cases)}
    manifest = report_dir / "executed_manifest.json"
    executed = json.loads(manifest.read_text(encoding="utf-8")) if manifest.is_file() else None
    if not isinstance(executed, dict) or executed.get("sources") != data["source_sha256"]:
        fail(f"{absolute}: executed manifest is missing or differs from summary sources")
    snapshot = verify_source_snapshot(report_dir, data["source_sha256"])
    for value in artifacts.values():
        value["source_snapshot_root"] = snapshot["root"]
    return data, {"input_json": reference(absolute), "executed_manifest": reference(manifest),
                  "source_snapshot": snapshot, "case_artifacts": artifacts}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", action="append", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    loaded = [load_batch(path) for path in args.batch]
    batches = [item[0] for item in loaded]
    provenance = [item[1] for item in loaded]
    anchor = batches[0]
    for batch in batches[1:]:
        for key in ("rows", "columns", "scale", "sparsity", "outer", "inner_limit", "qr_refinements", "fixed_iteration_benchmark", "qr_profile"):
            if batch["config"].get(key) != anchor["config"].get(key):
                fail(f"configuration mismatch for {key}")
        all_names = set(anchor["source_sha256"]) | set(batch["source_sha256"])
        mismatched = [name for name in all_names - HARNESS_ONLY if anchor["source_sha256"].get(name) != batch["source_sha256"].get(name)]
        if mismatched:
            fail("non-harness frozen source mismatch: " + ", ".join(sorted(mismatched)))
    cases = [case for batch in batches for case in batch["cases"]]
    names = [case.get("algorithm") for case in cases]
    if set(names) != set(ALGORITHMS) or len(names) != len(ALGORITHMS):
        fail("batches must contain each of the eleven algorithms exactly once")
    for case in cases:
        if case.get("requested_outer_iterations") != 8 or case.get("outer_iterations") != 8:
            fail(f"{case.get('algorithm')}: unequal actual outer count")
    if len({case.get("raw_phi_sha256") for case in cases}) != 1 or len({case.get("raw_y_sha256") for case in cases}) != 1:
        fail("all rows must share complete Phi/Y hashes")
    cases.sort(key=lambda case: ALGORITHMS.index(case["algorithm"]))
    result = {
        "status": "PASS", "parent_status": "COMPOSED_FROM_COMPLETED_SOURCE_CLEAN_BATCHES",
        "scope": "All eleven source-identical fixed-eight rows came from completed source-clean batches. Harness subset selection is the only allowed source difference.",
        "config": anchor["config"], "source_sha256": anchor["source_sha256"],
        "changed_sources": [], "untracked_imports": [], "cases": cases,
        "input_provenance": provenance,
        "source_manifests": [{"input_json": item["input_json"], "sources": batch["source_sha256"]} for batch, item in zip(batches, provenance)],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"PASS assembled {len(cases)} rows -> {args.output}")


if __name__ == "__main__":
    main()
