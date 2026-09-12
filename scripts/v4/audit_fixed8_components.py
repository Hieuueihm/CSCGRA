"""Audit completed rows from an interrupted fixed-eight benchmark without rerunning RTL.

It can prove frozen files and persisted simulator artifacts. It deliberately
does not claim post-termination Python import coverage that was never saved.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message):
    raise SystemExit(f"audit failed: {message}")


def signed27(word):
    return word - (1 << 27) if word & (1 << 26) else word


def i32_sha(values):
    return hashlib.sha256(struct.pack(f"<{len(values)}i", *values)).hexdigest()


def artifact(path):
    if not path.is_file():
        fail(f"missing artifact: {path}")
    return {"path": str(path.resolve()), "sha256": digest(path)}


def verify_record(evidence_dir, index, record):
    algorithm = record.get("algorithm", f"case{index}")
    if record.get("requested_outer_iterations") != 8 or record.get("outer_iterations") != 8:
        fail(f"{algorithm}: actual/requested outer count is not eight")
    if record.get("fixed_iteration_benchmark") is not True or record.get("returncode") != 0:
        fail(f"{algorithm}: missing fixed benchmark flag or xsim failure")
    paths = {
        "trace": evidence_dir / f"trace{index}.txt",
        "fixture": evidence_dir / f"case{index}.txt",
        "package": evidence_dir / f"package{index}" / "package.json",
        "simulation": evidence_dir / f"simulation{index}.json",
    }
    for path in paths.values():
        if not path.is_file():
            fail(f"{algorithm}: missing {path.name}")
    if digest(paths["trace"]) != record.get("trace_sha256"):
        fail(f"{algorithm}: trace digest mismatch")
    if digest(paths["fixture"]) != record.get("fixture_sha256"):
        fail(f"{algorithm}: fixture digest mismatch")
    if digest(paths["package"]) != record.get("package_sha256"):
        fail(f"{algorithm}: package digest mismatch")
    simulation = json.loads(paths["simulation"].read_text(encoding="utf-8"))
    if simulation.get("returncode") != 0 or simulation.get("stdout") != record.get("stdout"):
        fail(f"{algorithm}: simulation record differs from persisted evidence")
    commands = record.get("commands", [])
    if not commands or commands[-1:] != simulation.get("commands", []):
        fail(f"{algorithm}: executed xsim command provenance is incomplete")
    if "PASS cycles=" not in record.get("stdout", ""):
        fail(f"{algorithm}: xsim PASS marker missing")
    x_values, r_values, done = [], [], []
    retired = []
    lines = paths["trace"].read_text(encoding="utf-8").splitlines()
    for line in lines:
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "X" and fields[1] == "1":
            x_values.append(signed27(int(fields[3], 16)))
        elif fields[0] == "V" and fields[1] == "1":
            r_values.append(signed27(int(fields[3], 16)))
        elif fields[0] == "D" and fields[1] == "1":
            done.append(tuple(map(int, fields[1:])))
        elif fields[0] == "T" and fields[1] == "1":
            retired.append((int(fields[2]), int(fields[3], 16)))
    tail = lines[-1].split() if lines else []
    if len(tail) != 6 or tail[0] != "END":
        fail(f"{algorithm}: trace has no valid completion END marker")
    if i32_sha(x_values) != record.get("output_raw_x_sha256"):
        fail(f"{algorithm}: X digest cannot be recomputed from trace")
    if i32_sha(r_values) != record.get("output_raw_r_sha256"):
        fail(f"{algorithm}: residual digest cannot be recomputed from trace")
    if len(done) != 1 or done[0][1] != 0 or done[0][4] != 1 or done[0][5] != 8:
        fail(f"{algorithm}: RTL done record lacks successful eight-outer completion")
    if done[0][6] != record.get("inner_iterations") or done[0][7] != record.get("job_cycles"):
        fail(f"{algorithm}: RTL done counters differ from recorded counters")
    program = json.loads(paths["package"].read_text(encoding="utf-8")).get("program")
    if not isinstance(program, list) or [program[pc] for pc, _ in retired] != [word for _, word in retired]:
        fail(f"{algorithm}: retired RTL instructions do not match package.json")
    if len(retired) != record.get("retired_instructions"):
        fail(f"{algorithm}: retired instruction counter differs from trace")
    commits = [step for step in record.get("fixed_model_trace", []) if step.get("phase") == "COMMIT"]
    if len(commits) != 8:
        fail(f"{algorithm}: fixed model commit counter is not eight")
    return {name: artifact(path) for name, path in paths.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--expected", required=True, help="ordered comma-separated algorithms")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root = args.run_root.resolve()
    expected = tuple(x.strip() for x in args.expected.split(",") if x.strip())
    if not expected or len(expected) != len(set(expected)):
        fail("expected algorithms must be nonempty and unique")
    config = json.loads((root / "benchmark_config.json").read_text(encoding="utf-8"))
    if not config.get("fixed_iteration_benchmark") or config.get("qr_profile") != "balanced":
        fail("run is not the balanced fixed-iteration benchmark")
    manifest_path = root / "snapshot_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_hashes = manifest.get("sources", {})
    changed = [name for name, expected_hash in source_hashes.items()
               if not (root / name).is_file() or digest(root / name) != expected_hash]
    if changed:
        fail("frozen source changed or disappeared: " + ", ".join(changed))
    evidence_files = sorted((root / "work").glob("recovery_algorithms*/evidence.json"))
    if len(evidence_files) != 1:
        fail(f"expected exactly one component evidence file, found {len(evidence_files)}")
    evidence_path = evidence_files[0]
    records = json.loads(evidence_path.read_text(encoding="utf-8"))
    if [record.get("algorithm") for record in records] != list(expected):
        fail("completed record order does not exactly match --expected")
    artifacts = {record["algorithm"]: verify_record(evidence_path.parent, index, record)
                 for index, record in enumerate(records)}
    if len({record.get("raw_phi_sha256") for record in records}) != 1 or len({record.get("raw_y_sha256") for record in records}) != 1:
        fail("completed components do not share one Phi/Y fixture")
    result = {
        "status": "COMPONENT_PARTIAL_IMPORT_COVERAGE_UNKNOWN",
        "parent_status": "INTERRUPTED_NO_AGGREGATE_PASS",
        "scope": "Completed fixed-eight rows with persisted source, command, fixture, package, trace, X/R digest, and RTL-counter checks. This is not an all-algorithm run.",
        "config": config, "source_sha256": source_hashes,
        "source_manifest": artifact(manifest_path),
        "source_manifest_check": "all listed frozen files recomputed after termination",
        "import_coverage": "unknown after termination; no persisted untracked-import check exists",
        "evidence_path": str(evidence_path.resolve()), "evidence_sha256": digest(evidence_path),
        "artifacts": artifacts, "cases": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"COMPONENT_PARTIAL_IMPORT_COVERAGE_UNKNOWN {len(records)} rows -> {args.output}")


if __name__ == "__main__":
    main()
