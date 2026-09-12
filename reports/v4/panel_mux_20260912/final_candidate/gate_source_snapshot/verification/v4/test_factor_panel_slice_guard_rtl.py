"""Exhaustive R1/R4 packed-output indexing and nonzero flag regression."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]


class FactorPanelSliceGuardTests(unittest.TestCase):
    def test_all_source_lanes_and_valid_widths(self):
        folder = Path(tempfile.mkdtemp(prefix="factor_panel_slice_", dir=ROOT / "work"))
        sources = [ROOT / "rtl/v4/dataflow/factor_panel_service.sv",
                   ROOT / "verification/v4/program/tb_factor_panel_slice_guard.sv"]
        watched = sources + [Path(__file__).resolve(), ROOT / "scripts/v4/xsim.py"]
        watched += sorted((ROOT / "rtl/v4/include").glob("*.vh"))
        def hashes():
            return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
        before = hashes()
        compiled = compile_rtl(folder / "sim.json", "tb_factor_panel_slice_guard", sources,
                               root=ROOT, timeout=180)
        evidence = dict(source_hashes_before=before, compile=compiled.commands, status="FAIL")
        try:
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = run_rtl(folder / "sim.json", [], root=ROOT, timeout=120)
            evidence.update(run=result.commands, stdout=result.stdout, returncode=result.returncode)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS factor_panel_slice_guard checks=3841", result.stdout)
            self.assertEqual(before, hashes())
            evidence["status"] = "PASS"
        finally:
            evidence["source_hashes_after"] = hashes()
            (folder / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
            print(folder, flush=True)


if __name__ == "__main__":
    unittest.main()
