"""Source-bound Vivado gates for the staged factor panel and private bridge."""
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]
CASES = {
    "panel": ("tb_factor_panel_service", [
        "rtl/v4/dataflow/factor_panel_service.sv",
        "verification/v4/program/tb_factor_panel_service.sv",
    ]),
    "bridge": ("tb_factor_panel_bridge", [
        "rtl/v4/memory/factor_store.sv",
        "rtl/v4/dataflow/factor_service.sv",
        "verification/v4/program/tb_factor_panel_bridge.sv",
    ]),
}
SOURCE_EXTRAS = (
    "config/v4_kernel_interface.json",
    "config/v4_program_interface.json",
    "rtl/v4/include/kernel_interface.vh",
    "rtl/v4/include/program_interface.vh",
    "rtl/v4/include/stream_interface.vh",
    "rtl/v4/include/memory_defs.vh",
    "scripts/v4/xsim.py",
    "verification/v4/test_factor_panel_service_rtl.py",
    "docs/v4/architecture/NARROW_PANEL_MAPPING.md",
)


class FactorPanelRtl(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix="factor_panel_gate_", dir=ROOT / "work"))
        cls.evidence = []

    def gate(self, name, *, evidence_name=None, parameters=None):
        top, sources = CASES[name]
        watched = tuple(sources) + SOURCE_EXTRAS
        before = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in watched}
        evidence_name = evidence_name or name
        binary = self.folder / f"{evidence_name}.xsim.json"
        compiled = compile_rtl(binary, top, sources, root=ROOT, parameters=parameters, timeout=120)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = run_rtl(binary, [], root=ROOT, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS factor_panel{'_bridge' if name == 'bridge' else ''}", result.stdout)
        self.assertEqual(before, {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in watched})
        self.evidence.append({"name": evidence_name, "status": "PASS", "parameters": parameters or {},
            "sources": {path: before[path] for path in sources},
            "source_extras": {path: before[path] for path in SOURCE_EXTRAS},
            "compile_commands": compiled.commands, "run_commands": result.commands,
            "stdout": result.stdout})
        (self.folder / "evidence.json").write_text(json.dumps(self.evidence, indent=2) + "\n")
        return result

    def test_panel_matvec_rank1_fault_and_stalls(self):
        before = self.gate("panel", evidence_name="panel_wide_baseline",
                           parameters={"NARROW_PANEL_MAPPING": 0})
        after = self.gate("panel", evidence_name="panel_narrow_mapping",
                          parameters={"NARROW_PANEL_MAPPING": 1})
        before_cycles = int(re.search(r"PASS factor_panel cycles=(\d+)", before.stdout).group(1))
        after_cycles = int(re.search(r"PASS factor_panel cycles=(\d+)", after.stdout).group(1))
        self.assertLess(after_cycles, before_cycles,
                        f"narrow mapping must improve identical panel corpus: {after_cycles} >= {before_cycles}")

    def test_exclusive_factor_bridge_identity_and_hold(self):
        self.gate("bridge")


if __name__ == "__main__":
    unittest.main()
