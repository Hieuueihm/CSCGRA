"""Freeze v3 source bytes and bind command results to an unchanged snapshot."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = ("rtl/v3", "models/v3", "compiler/v3", "verification/v3",
                "scripts/numeric", "scripts/golden", "scripts/common", "scripts/maintenance", "constraints",
                "docs/v3", "reports/v3/context_images")
EXTRA_FILES = ("config/project.json", "config/rtl-v3.json", "requirements-v3.txt",
               "config/v3_brainweb_sweep_manifest.json", "config/v3_fastmri_source_manifest.json",
               "config/v3_p1_heldout_manifest.json",
               "scripts/run.ps1", "scripts/run_v3_m1_m6.ps1", "scripts/run_v3_m1_m7.ps1")


def digest_bytes(payload):
    return hashlib.sha256(payload).hexdigest()


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_files(root):
    paths = set()
    for relative in SOURCE_ROOTS:
        directory = root / relative
        if directory.exists():
            paths.update(path for path in directory.rglob("*") if path.is_file()
                         and "__pycache__" not in path.parts and path.suffix not in {".pyc", ".pyo"})
    paths.update(root / relative for relative in EXTRA_FILES if (root / relative).is_file())
    paths.update(path for path in (root / "reports/v3").glob("*.json") if path.is_file())
    for relative in ("models", "compiler", "scripts", "scripts/numeric", "scripts/maintenance", "verification"):
        initializer = root / relative / "__init__.py"
        if initializer.is_file():
            paths.add(initializer)
    for directory in ("sim", "synth", "impl", "formal"):
        for path in (root / "scripts" / directory).glob("*"):
            if path.is_file() and path.suffix in {".py", ".ps1", ".tcl"}:
                if "v3" in path.read_text(encoding="utf-8-sig").lower():
                    paths.add(path)
    return sorted(paths, key=lambda path: path.relative_to(root).as_posix())


def inventory(root):
    return {path.relative_to(root).as_posix(): digest_file(path) for path in source_files(root)}


def tree_digest(files):
    return digest_bytes(json.dumps(files, sort_keys=True, separators=(",", ":")).encode())


def environment():
    versions = {}
    for name in ("numpy", "scipy", "scikit-image", "PyWavelets", "pytest"):
        try:
            versions[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            versions[name] = None
    return {"python": sys.version, "executable": sys.executable, "platform": platform.platform(),
            "packages": versions, "thread_environment": {name: os.environ.get(name) for name in
            ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")}}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def freeze(root, output):
    if not (root / "rtl/v3/files.f").is_file():
        raise ValueError("v3 source root is missing")
    output.mkdir(parents=True, exist_ok=False)
    files = inventory(root)
    archive = output / "sources.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as stream:
        for name, expected in files.items():
            payload = (root / name).read_bytes()
            if digest_bytes(payload) != expected:
                raise ValueError(f"source changed while freezing: {name}")
            stream.writestr(name, payload)
    if inventory(root) != files:
        raise ValueError("source inventory changed while freezing")
    def git(*args):
        result = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)
        return {"exit_code": result.returncode, "output": result.stdout.strip()}
    manifest = {"schema": "cscgra-v3-frozen-baseline-v1", "root": str(root.resolve()),
                "created_utc": datetime.now(timezone.utc).isoformat(), "files": files,
                "source_tree_sha256": tree_digest(files), "archive_sha256": digest_file(archive),
                "git_head": git("rev-parse", "HEAD"), "git_status": git("status", "--porcelain=v1"),
                "environment": environment(), "release_validated": False}
    write_json(output / "manifest.json", manifest)
    return manifest


def verify(root, baseline):
    manifest = json.loads((baseline / "manifest.json").read_text(encoding="utf-8"))
    expected = manifest["files"]
    current = inventory(root)
    changed = sorted(name for name in expected.keys() | current.keys() if expected.get(name) != current.get(name))
    archive = baseline / "sources.zip"
    archive_ok = archive.is_file() and digest_file(archive) == manifest["archive_sha256"]
    if archive_ok:
        with zipfile.ZipFile(archive) as stream:
            archive_ok = (len(stream.namelist()) == len(expected) and set(stream.namelist()) == set(expected)
                          and all(digest_bytes(stream.read(name)) == digest for name, digest in expected.items()))
    manifest_ok = tree_digest(expected) == manifest["source_tree_sha256"]
    return {"pass": not changed and archive_ok and manifest_ok, "changed_files": changed,
            "archive_ok": archive_ok, "manifest_ok": manifest_ok, "source_tree_sha256": manifest["source_tree_sha256"]}


def run_bound(root, baseline, run_dir, command, evidence):
    before = verify(root, baseline)
    if not before["pass"]:
        raise ValueError(f"baseline drift before execution: {before}")
    if not command:
        raise ValueError("missing command")
    for path in evidence:
        resolved = path if path.is_absolute() else root / path
        if resolved.exists():
            raise ValueError(f"refusing pre-existing output evidence: {path}")
    run_dir.mkdir(parents=True, exist_ok=False)
    started = datetime.now(timezone.utc).isoformat()
    command_error = None
    with (run_dir / "stdout.log").open("wb") as stdout, (run_dir / "stderr.log").open("wb") as stderr:
        try:
            completed = subprocess.run(command, cwd=root, stdout=stdout, stderr=stderr)
            exit_code = completed.returncode
        except OSError as error:
            command_error, exit_code = str(error), None
    after = verify(root, baseline)
    artifacts, missing = {}, []
    for path in evidence:
        resolved = path if path.is_absolute() else root / path
        if not resolved.is_file():
            missing.append(str(path))
        else:
            artifacts[str(path)] = digest_file(resolved)
    record = {"schema": "cscgra-v3-bound-run-v1", "command": command, "cwd": str(root),
              "started_utc": started, "finished_utc": datetime.now(timezone.utc).isoformat(),
              "baseline_manifest_sha256": digest_file(baseline / "manifest.json"),
              "source_tree_sha256": before["source_tree_sha256"], "before": before, "after": after,
              "exit_code": exit_code, "command_error": command_error, "environment": environment(),
              "evidence_sha256": artifacts, "missing_evidence": missing,
              "stdout_sha256": digest_file(run_dir / "stdout.log"), "stderr_sha256": digest_file(run_dir / "stderr.log"),
              "pass": exit_code == 0 and after["pass"] and not missing}
    write_json(run_dir / "run.json", record)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("freeze", "verify", "run"))
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--evidence", type=Path, action="append", default=[])
    args, command = parser.parse_known_args()
    if command[:1] == ["--"]:
        command = command[1:]
    if args.mode == "freeze":
        if command:
            parser.error("unexpected command for freeze")
        result = freeze(args.root, args.baseline)
    elif args.mode == "verify":
        if command:
            parser.error("unexpected command for verify")
        result = verify(args.root, args.baseline)
    else:
        if args.run_dir is None:
            parser.error("run requires --run-dir")
        result = run_bound(args.root, args.baseline, args.run_dir, command, args.evidence)
    print(json.dumps(result, indent=2))
    return 0 if result.get("pass", True) else 1


if __name__ == "__main__":
    raise SystemExit(main())
