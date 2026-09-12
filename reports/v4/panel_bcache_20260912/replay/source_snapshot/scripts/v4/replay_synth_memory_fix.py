"""Replay immutable full-program PIO/DMA traces for the synthesis memory/cache fix."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from scripts.v4.xsim import compile_rtl, filelist_sources, run_rtl

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "reports/v4/payload_benchmark_20260911"
CHANGED = {ROOT / "rtl/v4/dataflow/factor_panel_service.sv", ROOT / "rtl/v4/memory/factor_store.sv"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    baseline = json.loads((BASE / "evidence.json").read_text())
    if baseline["status"] != "PASS" or not baseline["sources_unchanged"] or len(baseline["cases"]) != 20:
        raise ValueError("Unqualified full-suite baseline")
    drift = []
    for name, expected in baseline["source_hashes_after"].items():
        source = Path(name)
        snapshot = BASE / "source_snapshot" / source.relative_to(ROOT)
        if sha(snapshot) != expected:
            raise ValueError(f"Historical snapshot drift: {name}")
        if source.suffix in (".sv", ".v", ".vh", ".svh") and sha(source) != expected:
            drift.append(source)
    if set(drift) != CHANGED:
        raise ValueError(f"Expected only declared factor-store and panel RTL changes, found {drift}")
    directory = Path(tempfile.mkdtemp(prefix="synth_memory_replay_", dir=ROOT / "work"))
    print(directory, flush=True)
    sources = [*filelist_sources(ROOT), ROOT / "verification/v4/host/tb_payload_benchmark.sv"]
    watched = [*sources, *sorted((ROOT / "rtl/v4/include").glob("*.vh")),
               Path(__file__).resolve(), ROOT / "scripts/v4/xsim.py"]
    hashes = {str(path): sha(path) for path in watched}
    for path in watched:
        target = directory / "source_snapshot" / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    evidence = dict(status="RUNNING", source_hashes_before=hashes, baseline=str(BASE),
                    baseline_evidence_sha256=sha(BASE / "evidence.json"),
                    changed_sources=[dict(path=str(path), before=baseline["source_hashes_after"][str(path)], after=sha(path)) for path in sorted(CHANGED)],
                    runs=[], commands=[])
    def save():
        (directory / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    try:
        binary = directory / "replay.xsim.json"
        compiled = compile_rtl(binary, "tb_payload_benchmark", sources, root=ROOT,
                               timeout=900, debug="off", optimization=3)
        evidence["commands"] = compiled.commands
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        seen = set()
        for case in baseline["cases"]:
            key = (case["rows"], case["algorithm"])
            if key in seen or case["rows"] not in (32, 64) or set(case["modes"]) != {"PIO", "DMA"}:
                raise ValueError("Duplicate/malformed baseline pair")
            seen.add(key)
            name = f'm{case["rows"]}_{case["algorithm"]}'
            folder = directory / name
            folder.mkdir()
            fixture = BASE / name / "input.txt"
            if sha(fixture) != case["identity"]["fixture_sha256"]:
                raise ValueError("Immutable fixture drift")
            shutil.copy2(fixture, folder / "input.txt")
            for mode in ("PIO", "DMA"):
                prior = BASE / name / f"{mode}.trace"
                if sha(prior) != case["modes"][mode]["trace_sha256"]:
                    raise ValueError("Immutable reference trace drift")
                trace = folder / f"{mode}.trace"
                arguments = [f'+fixture={(folder / "input.txt").as_posix()}', f'+trace={trace.as_posix()}']
                if mode == "DMA":
                    arguments.append("+dma")
                result = run_rtl(binary, arguments, root=ROOT, timeout=900)
                equal = trace.exists() and trace.read_bytes() == prior.read_bytes()
                record = dict(rows=case["rows"], columns=case["columns"], algorithm=case["algorithm"], mode=mode,
                              returncode=result.returncode, trace_exact=equal,
                              trace_sha256=sha(trace) if trace.exists() else None,
                              reference_sha256=sha(prior), profile=case["modes"][mode]["profile"],
                              stdout=result.stdout, stderr=result.stderr, commands=result.commands)
                evidence["runs"].append(record)
                save()
                if result.returncode or not equal or "PASS payload_benchmark" not in result.stdout:
                    raise RuntimeError(f"Replay failed {name}/{mode}: " + result.stdout + result.stderr)
                print(f"PASS {name}/{mode}: byte-identical trace including all cycle buckets", flush=True)
        if len(evidence["runs"]) != 40:
            raise ValueError("Incomplete forty-run replay")
        evidence["status"] = "PASS"
    except Exception as error:
        evidence["status"] = "FAIL"
        evidence["error"] = str(error)
        raise
    finally:
        evidence["source_hashes_after"] = {str(path): sha(path) for path in watched}
        evidence["sources_unchanged"] = evidence["source_hashes_after"] == hashes
        if not evidence["sources_unchanged"]:
            evidence["status"] = "FAIL"
        save()
    if evidence["status"] != "PASS":
        raise RuntimeError("Source integrity gate failed")


if __name__ == "__main__":
    main()
