"""Validate and archive the full matched payload benchmark without XSim binaries."""
import argparse
import csv
import json
from pathlib import Path
import shutil

from scripts.v4 import benchmark_payload as benchmark

ROOT = benchmark.ROOT


def validate(directory):
    evidence = json.loads((directory / "evidence.json").read_text())
    if evidence["status"] != "PASS" or not evidence["sources_unchanged"]:
        raise ValueError("Benchmark did not complete cleanly")
    if evidence["source_hashes_before"] != evidence["source_hashes_after"]:
        raise ValueError("Source mutation during measurement")
    for filename, expected in evidence["source_hashes_after"].items():
        source = ROOT / Path(filename).relative_to(ROOT)
        snapshot = directory / "source_snapshot" / source.relative_to(ROOT)
        if benchmark.digest(source) != expected or benchmark.digest(snapshot) != expected:
            raise ValueError(f"Source drift: {source}")
    expected_pairs = {(rows, name) for rows in (32, 64) for name in benchmark.artifacts.ACTIVE}
    observed = set()
    pinned = {}
    for rows in (32, 64):
        archive = ROOT / f"reports/v4/outer_fusion_20260911/m{rows}_candidate/summary.json"
        pinned[rows] = benchmark.oracle.load(archive, rows)[4]
    for case in evidence["cases"]:
        identity = (case["rows"], case["algorithm"])
        if identity not in expected_pairs or identity in observed or set(case["modes"]) != {"PIO", "DMA"}:
            raise ValueError("Missing, duplicate or unexpected pair")
        observed.add(identity)
        folder = directory / f'm{case["rows"]}_{case["algorithm"]}'
        if benchmark.digest(folder / "input.txt") != case["identity"]["fixture_sha256"]:
            raise ValueError("Input fixture drift")
        profiles = []
        for mode in ("PIO", "DMA"):
            measured = case["modes"][mode]
            trace = folder / f"{mode}.trace"
            if benchmark.digest(trace) != measured["trace_sha256"]:
                raise ValueError("Trace drift")
            log = json.loads((folder / f"{mode}.json").read_text())
            if log["returncode"] != 0 or "PASS payload_benchmark" not in log["stdout"]:
                raise ValueError("Missing XSim PASS")
            if not log["commands"] or any(command["returncode"] for command in log["commands"]):
                raise ValueError("Failed simulator command")
            profile = measured["profile"]
            actual_profile = benchmark.parse_trace(trace.read_text(), pinned[case["rows"]][case["algorithm"]])
            if profile != actual_profile:
                raise ValueError("Profile metadata differs from recorded trace")
            if profile["mode"] != int(mode == "DMA") or profile["iterations"] != 8:
                raise ValueError("Mode/iteration mismatch")
            if min(profile.values()) < 0 or profile["total"] != sum(profile[key] for key in ("setup", "load", "compute", "writeback")):
                raise ValueError("Invalid cycle accounting")
            if profile["native"] != case["reference_native_cycles"]:
                raise ValueError("Native compute differs from qualified baseline")
            if profile["dma_stall"] > profile["dma_active"]:
                raise ValueError("DMA stall exceeds active cycles")
            profiles.append(profile)
        if profiles[0]["setup"] != profiles[1]["setup"]:
            raise ValueError("Mismatched PIO program/Phi setup")
    if observed != expected_pairs:
        raise ValueError("Full 20-pair/40-simulation suite required")
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    directory, output = args.work.resolve(), args.output.resolve()
    if directory.parent != ROOT / "work" or output.parent != ROOT / "reports/v4":
        parser.error("Expected direct work child and reports/v4 output child")
    if output.exists():
        parser.error("Refusing to replace an existing evidence archive")
    evidence = validate(directory)
    output.mkdir()
    shutil.copytree(directory / "source_snapshot", output / "source_snapshot")
    for filename in ("evidence.json",):
        shutil.copy2(directory / filename, output / filename)
    rows = []
    for case in evidence["cases"]:
        name = f'm{case["rows"]}_{case["algorithm"]}'
        (output / name).mkdir()
        for source in (directory / name).iterdir():
            if source.is_file() and source.suffix in (".json", ".trace", ".txt"):
                shutil.copy2(source, output / name / source.name)
        for mode in ("PIO", "DMA"):
            rows.append(dict(algorithm=case["algorithm"], rows=case["rows"], columns=case["columns"],
                             transport=mode, **case["modes"][mode]["profile"]))
    with (output / "measurements.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    lines = ["# Payload benchmark: September 11, 2026", "", "## Qualified result", "",
             "40 XSim simulations PASS: ten algorithms, two sizes, PIO and DMA, K=8 and actual eight outer iterations.",
             "Raw X/residual/support/status/inner+outer counters match the immutable qualified oracle; native compute cycles match both transport modes and the prior qualified native run.", "",
             "| M/N | Algorithm | Native cycles | PIO total | DMA total | Reduction |",
             "|---|---|---:|---:|---:|---:|"]
    for case in evidence["cases"]:
        pio, dma = (case["modes"][mode]["profile"] for mode in ("PIO", "DMA"))
        reduction = 100 * (pio["total"] - dma["total"]) / pio["total"]
        lines.append(f'| {case["rows"]}/{case["columns"]} | {case["algorithm"]} | {pio["native"]:,} | {pio["total"]:,} | {dma["total"]:,} | {reduction:.2f}% |')
    lines += ["", "## Measurement limits", "",
              "See docs/v4/architecture/PAYLOAD_BENCHMARK.md for precise boundaries. setup includes program/context and Phi; load is payload; compute is host-observed START/DONE; writeback includes all result elements and support/metadata. total is their exact sum.",
              "DMA active/stall counters overlap those buckets and are not additive. Internal compute-stall attribution is unavailable; the recorded DMA stall counter is not a whole-core stall metric.",
              "This is a specified AXI BFM latency comparison, not PS software, physical DDR throughput, CPU cache maintenance or board qualification. DDR initialization/CPU result consumption are excluded; post-timing residual validation is excluded.",
              "SNR/NMSE diagnostics are inherited from the unchanged qualified inputs/outputs. Fixtures below the quality target remain below it; faster transport does not improve algorithm quality.",
              "Physical measurements are a separate source-matched run. The simulator evidence retains physical fields as NOT_RUN; any later actual synthesis/route outcome is recorded in physical/ rather than rewriting simulator provenance.", "",
              "## Reproduce", "", "python -m scripts.v4.benchmark_payload", "",
              "python -m unittest verification.v4.test_payload_benchmark -v", "",
              "No RTL, golden images, compiler defaults, PE count, interconnect or mesh changed for these measurements.",
              "The report archive omits XSim executables and preserves source snapshots, input fixtures, logs, traces and SHA256 metadata."]
    (output / "README.md").write_text("\n".join(lines) + "\n")
    benchmark.dump(output / "artifact_hashes.json", {
        path.relative_to(output).as_posix(): benchmark.digest(path)
        for path in sorted(output.rglob("*")) if path.is_file()})
    print(output)


if __name__ == "__main__":
    main()
