"""Measured R1/R4 mapping calibration; this test deliberately does not select a compiler policy."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl
from verification.v4.test_stream_kernel_rtl import ROOT, SOURCES, SOURCE_EXTRAS, fixture

CASE_RE = re.compile(r"CASE (\d+) op=1 rows=(\d+) cols=(\d+) dense=(\d+) trans=(\d+) r4=(\d+) cycles=(\d+)")
PASS_RE = re.compile(r"PASS stream_kernel cycles=(\d+) checks=(\d+) commands=(\d+) stalls=(\d+)")

# These are the dynamic dense-B widths reached by the fixed-eight QR-family
# policies: incremental/support K=8, grouped tails, SP 2K=16 and CoSaMP 3K=24.
# They are calibration labels only; no runtime algorithm classifier consumes them.
RESTRICTED_WIDTHS = (1, 2, 4, 8, 16, 24)
GEOMETRIES = ((32, 64), (64, 256))


class GemvMappingCalibrationRtlTests(unittest.TestCase):
    """Measure each legal mapping exactly; selection stays outside this gate."""

    @classmethod
    def setUpClass(cls):
        (ROOT / "work").mkdir(exist_ok=True)
        cls.folder = Path(tempfile.mkdtemp(prefix="gemv_mapping_calibration_", dir=ROOT / "work"))
        cls.binary = cls.folder / "kernel.xsim.json"
        cls.calibration_tb = "verification/v4/stream/tb_stream_kernel_mapping_calibration.sv"
        cls.sources = [cls.calibration_tb if item == "verification/v4/stream/tb_stream_kernel.sv" else item
                       for item in SOURCES]
        cls.provenance = [*cls.sources, *SOURCE_EXTRAS, "verification/v4/test_gemv_mapping_calibration_rtl.py"]
        cls.before = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                      for path in dict.fromkeys(cls.provenance)}
        cls.compiled = compile_rtl(cls.binary, "tb_stream_kernel_mapping_calibration", cls.sources, root=ROOT, timeout=240)
        if cls.compiled.returncode:
            raise AssertionError(cls.compiled.stdout + cls.compiled.stderr)
        cls.records = []

    @classmethod
    def tearDownClass(cls):
        after = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                 for path in dict.fromkeys(cls.provenance)}
        if after != cls.before:
            raise AssertionError("source changed during mapping calibration")
        complete = len(cls.records) == 2 and all(record.get("status") == "PASS" for record in cls.records)
        (cls.folder / "qualification.json").write_text(json.dumps({
            "status": "PASS" if complete else "INCOMPLETE",
            "scope": ("Measured R1/R4 stream-kernel GEMV calibration under the testbench's "
                      "command-relative deterministic stalls (`+command_stall_epoch=1`). This is a mapping measurement, not a compiler "
                      "selection, whole-program, timing, PPA or board claim."),
            "source_sha256": cls.before,
            "compile_commands": cls.compiled.commands,
            "records": cls.records,
            "dense_mapping_scope": "restricted dense forward only; dense transpose was not measured or selected",
            "restricted_width_provenance": {
                "1/2/4/8": "incremental and grouped fixed-eight support widths",
                "16": "SP 2K support width",
                "24": "CoSaMP 3K support width",
            },
            "arithmetic_bound": {
                "coefficient": "signed C18 maximum magnitude <= 2^17",
                "state": "signed S27 maximum magnitude <= 2^26",
                "reductions": "at most 1024",
                "acc64_bound": "abs(sum) <= 2^17 * 2^26 * 2^10 = 2^53 < 2^63",
                "conclusion": "legal R1/R4 accumulation cannot diverge through ACC64 prefix overflow; terminal rounding and all transaction faults remain separately exercised",
            },
        }, indent=2) + "\n", encoding="utf-8")

    def _run(self, name, cases, labels):
        vectors = self.folder / f"{name}.txt"
        vectors.write_text(str(len(cases)) + "\n" + "\n".join(cases) + "\n", encoding="utf-8")
        result = run_rtl(self.binary, ["vectors=" + vectors.as_posix(), "command_stall_epoch=1"], root=ROOT, timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = [tuple(map(int, row)) for row in CASE_RE.findall(result.stdout)]
        self.assertEqual(len(observed), len(labels), result.stdout)
        match = PASS_RE.search(result.stdout)
        self.assertIsNotNone(match, result.stdout)
        total_cycles, comparisons, commands, stalls = map(int, match.groups())
        self.assertEqual(commands, len(cases), result.stdout)
        self.assertGreater(stalls, 0, result.stdout)
        rows = []
        for label, row in zip(labels, observed):
            case_index, m, n, dense, trans, r4, cycles = row
            expected = label["shape"]
            self.assertEqual((m, n, dense, trans, r4), expected, result.stdout)
            rows.append({"label": label["label"], "mapping": "R4" if r4 else "R1",
                         "case": case_index, "cycles": cycles,
                         "shape": {"rows": m, "columns": n, "dense": bool(dense), "transpose": bool(trans)}})
        record = {
            "test": self.id(), "status": "PASS", "deterministic_stall_policy": "tb_stream_kernel command-relative epoch",
            "source_sha256": self.before, "vectors_sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
            "commands": self.compiled.commands + result.commands, "stdout": result.stdout,
            "total_cycles": total_cycles, "comparisons": comparisons, "stalls": stalls, "commands_executed": commands,
            "per_command": rows,
        }
        self.records.append(record)
        (self.folder / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        return rows

    def test_exact_live_phi_and_restricted_dense_measurements(self):
        cases, labels = [], []
        def append(label, *, rows, columns, dense, transpose, length):
            for r4 in (0, 1):
                cases.append(fixture(op=1, rows=rows, cols=columns, dense=int(dense), trans=int(transpose),
                                     r4=r4, length=length, destination=128))
                labels.append({"label": label, "shape": (rows, columns, int(dense), int(transpose), r4)})

        # Live Phi has both execution orientations. These are exact M/N target geometries.
        for rows, columns in GEOMETRIES:
            append(f"live_phi_M{rows}_N{columns}_forward", rows=rows, columns=columns,
                   dense=False, transpose=False, length=columns)
            append(f"live_phi_M{rows}_N{columns}_transpose", rows=rows, columns=columns,
                   dense=False, transpose=True, length=rows)
        # Restricted B is consumed forward by the existing QR support path. Use actual
        # support widths rather than a full-N estimate; no unmeasured dense transpose policy is implied.
        for rows, _ in GEOMETRIES:
            for width in RESTRICTED_WIDTHS:
                append(f"restricted_dense_M{rows}_S{width}_forward", rows=rows, columns=width,
                       dense=True, transpose=False, length=width)

        rows = self._run("measurements", cases, labels)
        paired = {}
        for row in rows:
            paired.setdefault(row["label"], {})[row["mapping"]] = row
        self.assertEqual(len(paired), 4 + len(GEOMETRIES) * len(RESTRICTED_WIDTHS))
        for label, choices in paired.items():
            self.assertEqual(set(choices), {"R1", "R4"}, label)

    def test_mapping_fault_and_cancel_semantics_pairwise(self):
        cases, labels = [], []
        def append(label, **kwargs):
            for r4 in (0, 1):
                cases.append(fixture(op=1, r4=r4, destination=128, **kwargs))
                labels.append({"label": label, "shape": (kwargs["rows"], kwargs["cols"],
                              int(kwargs.get("dense", 1)), int(kwargs.get("trans", 0)), r4)})

        # Matrix identity, payload and cancellation faults each run through both mappings.
        append("live_phi_M64_N256_forward_bad_generation", rows=64, cols=256, dense=0, trans=0,
               length=256, generation=4)
        append("live_phi_M64_N256_transpose_missing_source", rows=64, cols=256, dense=0, trans=1,
               length=64, source_missing=True)
        append("restricted_dense_M64_S24_missing_source", rows=64, cols=24, dense=1, trans=0,
               length=24, source_missing=True)
        append("restricted_dense_M64_S24_cancel", rows=64, cols=24, dense=1, trans=0,
               length=24, cancel=1)
        rows = self._run("faults", cases, labels)
        paired = {}
        for row in rows:
            paired.setdefault(row["label"], set()).add(row["mapping"])
        self.assertTrue(all(value == {"R1", "R4"} for value in paired.values()))


if __name__ == "__main__":
    unittest.main()

