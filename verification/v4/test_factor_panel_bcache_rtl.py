"""Exhaustive B-cache read windows and real panel feed muxes in XSim."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]


class FactorPanelBcacheTests(unittest.TestCase):
    def test_signed_windows_and_all_legal_feed_widths(self):
        folder = Path(tempfile.mkdtemp(prefix="factor_panel_bcache_", dir=ROOT / "work"))
        sources = [ROOT / "rtl/v4/dataflow/factor_panel_service.sv",
                   ROOT / "verification/v4/program/tb_factor_panel_bcache.sv"]
        watched = sources + [Path(__file__).resolve(), ROOT / "scripts/v4/xsim.py"]
        watched += sorted((ROOT / "rtl/v4/include").glob("*.vh"))
        def hashes():
            return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in watched}
        before = hashes()
        evidence = dict(status="FAIL", source_hashes_before=before)
        try:
            binary = folder / "sim.json"
            compiled = compile_rtl(binary, "tb_factor_panel_bcache", sources, root=ROOT, timeout=240)
            evidence["compile"] = compiled.commands
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = run_rtl(binary, [], root=ROOT, timeout=180)
            evidence.update(run=result.commands, stdout=result.stdout)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS factor_panel_bcache reads=524160 feeds=4732", result.stdout)
            self.assertEqual(before, hashes())
            evidence["status"] = "PASS"
        finally:
            evidence["source_hashes_after"] = hashes()
            (folder / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
            print(folder, flush=True)


if __name__ == "__main__":
    unittest.main()
