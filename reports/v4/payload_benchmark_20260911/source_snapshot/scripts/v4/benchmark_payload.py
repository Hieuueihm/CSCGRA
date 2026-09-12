"""Matched PIO/DMA end-to-end XSim measurements from pinned fixed-eight images."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import tempfile

from scripts.v4 import report_outer_fusion as oracle
from scripts.v4 import report_resident_chain_comparison as artifacts
from scripts.v4.xsim import compile_rtl, filelist_sources, run_rtl

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "verification/v4/host/tb_payload_benchmark.sv"
MASK = (1 << 27) - 1


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def parse_native_fixture(text):
    lines = iter(text.splitlines())
    rows, columns, jobs = map(int, next(lines).split())
    if jobs != 2:
        raise ValueError("Expected qualified two-job fixture")
    result = []
    for _ in range(jobs):
        mode, exponent, active, cancel, fault, status = map(int, next(lines).split())
        program, templates, vectors, constants, count = map(int, next(lines).split())
        records = [next(lines) for _ in range(count)]
        blocks = [next(lines) for _ in range(int(next(lines))) ]
        residual_base, residual_count = map(int, next(lines).split())
        if exponent or cancel or fault:
            raise ValueError("Faulted/nonzero-exponent fixture not benchmark eligible")
        result.append(dict(mode=mode, active=active, status=status, program=program,
                           templates=templates, vectors=vectors, constants=constants,
                           records=records, blocks=blocks, residual_base=residual_base,
                           residual_count=residual_count))
    if list(lines):
        raise ValueError("Trailing native fixture data")
    return rows, columns, result[1]


def write_fixture(case, archive, config, target):
    _, package_dir, index = artifacts.load_digest(case, archive, case["algorithm"])
    native_path = package_dir.parent / f"case{index}.txt"
    rows, columns, job = parse_native_fixture(native_path.read_text())
    package = json.loads((package_dir / "package.json").read_text())
    if job["residual_count"] != rows or len(job["blocks"]) != (rows + 31) // 32:
        raise ValueError("Measurement/residual shape mismatch")
    measurement = []
    base = int(job["blocks"][0].split()[0])
    for block_index, block in enumerate(job["blocks"]):
        address, mask, packed = block.split()
        size = min(32, rows - block_index * 32)
        if int(address) != base + block_index or int(mask, 16) != (1 << size) - 1:
            raise ValueError("DMA requires contiguous measurement blocks")
        for lane in range(size):
            value = (int(packed, 16) >> (lane * 27)) & MASK
            value = value - (1 << 27) if value & (1 << 26) else value
            if value % 256:
                raise ValueError("Measurement not D18-to-S27 exact")
            measurement.append(value // 256)
    if oracle.raw_digest(measurement) != case["raw_y_sha256"]:
        raise ValueError("Measurement hash changed")
    support = case["accepted_support"] if job["active"] else []
    packed_support = sum(int(value) << (10 * index) for index, value in enumerate(support))
    lines = [f'{config["scale"]} {job["mode"]} {job["active"]} {job["status"]} {case["inner_iterations"]} {len(support)} {job["residual_base"]}',
             f'{rows} {columns} {package["revision"]} 1 {job["program"]} {job["constants"]} {job["templates"]} {job["vectors"]} {len(job["records"])}',
             *job["records"], str(len(job["blocks"])), *job["blocks"],
             *(f'{value & MASK:07x}' for value in case["_raw"]["vectors"]["X"]),
             f'{packed_support:0240x}',
             *(f'{value & MASK:07x}' for value in case["_raw"]["vectors"]["V"])]
    target.write_text("\n".join(lines) + "\n")
    return dict(native_fixture=str(native_path), native_sha256=digest(native_path),
                load_sha256=package["load_sha256"], fixture_sha256=digest(target),
                raw_phi_sha256=case["raw_phi_sha256"], raw_y_sha256=case["raw_y_sha256"])


def parse_trace(text, case):
    profiles = [line for line in text.splitlines() if line.startswith("PROFILE ")]
    if len(profiles) != 1 or "PASS payload_benchmark" not in text:
        raise ValueError("Incomplete benchmark trace")
    profile = {name: int(value) for name, value in
               (field.split("=") for field in profiles[0].split()[1:])}
    if profile["iterations"] != 8 or profile["total"] != sum(profile[key] for key in ("setup", "load", "compute", "writeback")):
        raise ValueError("Invalid iteration count or overlapping timing buckets")
    for kind, key in (("X", "output_raw_x_sha256"), ("V", "output_raw_r_sha256")):
        values = []
        for line in text.splitlines():
            fields = line.split()
            if fields[0] == kind:
                if int(fields[1]) != len(values):
                    raise ValueError("Noncontiguous output")
                value = int(fields[2], 16)
                values.append(value - (1 << 27) if value & (1 << 26) else value)
        if oracle.raw_digest(values) != case[key]:
            raise ValueError(f"{kind} mismatch against pinned integer oracle")
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", nargs="+", type=int, choices=(32, 64), default=[32, 64])
    parser.add_argument("--algorithms", nargs="+", choices=artifacts.ACTIVE, default=list(artifacts.ACTIVE))
    args = parser.parse_args()
    directory = Path(tempfile.mkdtemp(prefix="payload_benchmark_", dir=ROOT / "work"))
    print(directory, flush=True)
    sources = [*filelist_sources(ROOT), TB]
    tracked = sorted(set([*sources, *sorted((ROOT / "rtl/v4/include").glob("*.vh")),
                          Path(__file__).resolve(), ROOT / "scripts/v4/xsim.py",
                          ROOT / "scripts/v4/report_outer_fusion.py",
                          ROOT / "scripts/v4/report_resident_chain_comparison.py"]))
    before = {str(path): digest(path) for path in tracked}
    for path in tracked:
        target = directory / "source_snapshot" / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    evidence = dict(status="RUNNING", source_hashes_before=before, cases=[], commands=[],
                    scope="Single-clock AXI BFMs; not PS-VIP, physical DDR or software execution",
                    physical=dict(Fmax=None, LUT=None, FF=None, BRAM=None, DSP=None,
                                  status="NOT_RUN: cycle measurement gate precedes synthesis/implementation"))
    binary = directory / "benchmark.xsim.json"
    try:
        compiled = compile_rtl(binary, "tb_payload_benchmark", sources, root=ROOT,
                               timeout=900, debug="off", optimization=3)
        evidence["commands"] += compiled.commands
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)
        for rows in args.rows:
            archive = ROOT / f"reports/v4/outer_fusion_20260911/m{rows}_candidate"
            _, _, old_sources, config, cases = oracle.load(archive / "summary.json", rows)
            for relative, expected in old_sources.items():
                if relative.startswith("rtl/") and relative.endswith((".sv", ".v", ".vh", ".svh")) and relative != "rtl/v4/top/csr_top.sv" and digest(ROOT / relative) != expected:
                    raise ValueError(f"Compute baseline drift: {relative}")
            for algorithm in args.algorithms:
                case = cases[algorithm]
                folder = directory / f"m{rows}_{algorithm}"
                folder.mkdir()
                fixture = folder / "input.txt"
                identity = write_fixture(case, archive, config, fixture)
                pair = dict(algorithm=algorithm, rows=rows, columns=case["columns"], sparsity=8,
                            identity=identity, quality=case["quality"], policy=case["policy"], modes={},
                            reference_native_cycles=case["job_cycles"])
                evidence["cases"].append(pair)
                for mode in ("PIO", "DMA"):
                    trace = folder / f"{mode}.trace"
                    plusargs = [f"+fixture={fixture.as_posix()}", f"+trace={trace.as_posix()}"]
                    if mode == "DMA":
                        plusargs.append("+dma")
                    result = run_rtl(binary, plusargs, root=ROOT, timeout=900)
                    dump(folder / f"{mode}.json", dict(returncode=result.returncode, stdout=result.stdout,
                         stderr=result.stderr, commands=result.commands))
                    if result.returncode:
                        raise RuntimeError(result.stdout + result.stderr)
                    profile = parse_trace(trace.read_text(), case)
                    pair["modes"][mode] = dict(profile=profile, trace_sha256=digest(trace))
                    print(f'{rows} {algorithm} {mode} native={profile["native"]} total={profile["total"]}', flush=True)
                pio, dma = (pair["modes"][mode]["profile"] for mode in ("PIO", "DMA"))
                if pio["native"] != dma["native"]:
                    raise ValueError("DMA changed native compute cycles")
                pair["total_reduction_percent"] = 100 * (pio["total"] - dma["total"]) / pio["total"]
                dump(directory / "evidence.json", evidence)
        evidence["status"] = "PASS"
    except Exception as error:
        evidence["status"] = "FAIL"
        evidence["error"] = str(error)
        raise
    finally:
        evidence["source_hashes_after"] = {str(path): digest(path) for path in tracked}
        evidence["sources_unchanged"] = evidence["source_hashes_after"] == before
        if not evidence["sources_unchanged"]:
            evidence["status"] = "FAIL"
        dump(directory / "evidence.json", evidence)
    if evidence["status"] != "PASS":
        raise RuntimeError("Evidence failed source integrity")


if __name__ == "__main__":
    main()
