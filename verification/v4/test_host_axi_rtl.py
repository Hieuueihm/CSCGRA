"""Focused Vivado-XSim verification for the V4 AXI host wrapper."""
import hashlib
import json
import inspect
from pathlib import Path
import shutil
import tempfile
import unittest

from compiler.v4 import recovery_program as asm
from scripts.v4.xsim import compile_rtl, filelist_sources, run_rtl
from verification.v4.test_recovery_engine_rtl import base_package


ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "verification/v4/host/tb_csr_top.sv"


def packed_lanes(values, bits=27):
    return sum((int(value) & ((1 << bits) - 1)) << (bits * index)
               for index, value in enumerate(values))


def write_fixture(path):
    package = base_package(4)
    records = asm.load_records(package)
    values = [256, 512, 768, 1024]
    payload = packed_lanes(values)
    fields = [
        1,
        4,
        package["revision"],
        1,
        len(package["program"]),
        len(package["constants"]),
        len(package["templates"]),
        len(package["vectors"]),
        len(records),
    ]
    lines = [" ".join(str(value) for value in fields)]
    lines.extend(f"{kind:x} {index:04x} {word:032x} {last:x}"
                 for kind, index, word, last in records)
    lines.append("1")
    lines.append(f"0 0000000f {payload:0216x}")
    path.write_text("\n".join(lines) + "\n")
    return package, values


def source_hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def include_files(include_dirs):
    return [file for include_dir in include_dirs
            for file in sorted(include_dir.rglob("*"))
            if file.is_file() and file.suffix in (".vh", ".svh")]


def snapshot_sources(directory, paths, include_paths):
    snapshot = directory / "source_snapshot"
    copied = []
    for path in [*paths, *include_paths]:
        relative = path.relative_to(ROOT)
        target = snapshot / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied.append(target)
    return copied


class HostAxiRtlTests(unittest.TestCase):
    DMA = False

    @classmethod
    def setUpClass(cls):
        cls.path = Path(tempfile.mkdtemp(prefix="host_axi_", dir=ROOT / "work"))
        cls.fixture = cls.path / "base_package.fixture"
        cls.trace = cls.path / "csr_top.trace"
        cls.binary = cls.path / "csr_top.xsim.json"
        cls.package, cls.values = write_fixture(cls.fixture)
        cls.sources = [*filelist_sources(ROOT), TB]
        cls.include_dirs = [ROOT / "rtl/v4/include"]
        cls.include_paths = include_files(cls.include_dirs)
        cls.source_hashes_before = source_hashes(cls.sources)
        cls.include_hashes_before = source_hashes(cls.include_paths)
        cls.runner_path = Path(__file__).resolve()
        cls.runner_hash_before = hashlib.sha256(cls.runner_path.read_bytes()).hexdigest()
        cls.runner_paths = sorted({cls.runner_path, Path(inspect.getfile(cls)).resolve(),
                                   ROOT / "scripts/v4/xsim.py"})
        cls.runner_hashes_before = source_hashes(cls.runner_paths)
        cls.source_snapshot = snapshot_sources(cls.path, cls.sources, cls.include_paths)
        cls.compiled = compile_rtl(
            cls.binary,
            "tb_csr_top",
            cls.sources,
            root=ROOT,
            timeout=900,
        )
        cls.ran = None
        if cls.compiled.returncode == 0:
            cls.ran = run_rtl(
                cls.binary,
                [f"+fixture={cls.fixture.as_posix()}", f"+trace={cls.trace.as_posix()}"]
                + (["+dma"] if cls.DMA else []),
                root=ROOT,
                timeout=600,
            )
        evidence = {
            "test": "v4 csr_top AXI DMA integration" if cls.DMA else "v4 csr_top AXI host smoke",
            "simulator": "Vivado 2018.1 xvlog/xelab/xsim",
            "compile_timeout_seconds": 900,
            "simulation_timeout_seconds": 600,
            "work_directory": str(cls.path),
            "fixture": str(cls.fixture),
            "fixture_sha256": hashlib.sha256(cls.fixture.read_bytes()).hexdigest(),
            "trace": str(cls.trace),
            "sources": [str(path) for path in cls.sources],
            "source_hashes_before": cls.source_hashes_before,
            "source_hashes_after": source_hashes(cls.sources),
            "include_dirs": [str(path) for path in cls.include_dirs],
            "include_hashes_before": cls.include_hashes_before,
            "include_hashes_after": source_hashes(cls.include_paths),
            "source_snapshot": str(cls.path / "source_snapshot"),
            "source_snapshot_files": [str(path) for path in cls.source_snapshot],
            "runner": str(cls.runner_path),
            "runner_sha256_before": cls.runner_hash_before,
            "runner_sha256_after": hashlib.sha256(cls.runner_path.read_bytes()).hexdigest(),
            "runner_hashes_before": cls.runner_hashes_before,
            "runner_hashes_after": source_hashes(cls.runner_paths),
            "compile": {
                "returncode": cls.compiled.returncode,
                "stdout": cls.compiled.stdout,
                "stderr": cls.compiled.stderr,
                "commands": cls.compiled.commands,
            },
            "simulation": None if cls.ran is None else {
                "returncode": cls.ran.returncode,
                "stdout": cls.ran.stdout,
                "stderr": cls.ran.stderr,
                "commands": cls.ran.commands,
            },
        }
        evidence["source_hashes_unchanged"] = (
            evidence["source_hashes_before"] == evidence["source_hashes_after"])
        evidence["include_hashes_unchanged"] = (
            evidence["include_hashes_before"] == evidence["include_hashes_after"])
        evidence["runner_unchanged"] = (
            evidence["runner_hashes_before"] == evidence["runner_hashes_after"])
        (cls.path / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        if not evidence["source_hashes_unchanged"] or not evidence["include_hashes_unchanged"]:
            raise AssertionError("tracked RTL/include source changed during the run")
        if not evidence["runner_unchanged"]:
            raise AssertionError("test runner changed during the run")
        if cls.compiled.returncode:
            raise AssertionError(cls.compiled.stdout + cls.compiled.stderr)
        if cls.ran.returncode:
            raise AssertionError(cls.ran.stdout + cls.ran.stderr)

    def test_csr_top_axi_smoke_and_recovery(self):
        self.assertIn("PASS csr_top_axi", self.ran.stdout)
        self.assertTrue(self.trace.is_file())
        trace_text = self.trace.read_text()
        self.assertIn("PASS", trace_text)


if __name__ == "__main__":
    unittest.main()
