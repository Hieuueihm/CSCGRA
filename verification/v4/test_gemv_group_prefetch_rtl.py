"""A/B qualification for bounded GEMV output-group transport prefetch."""
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl
from verification.v4.test_stream_kernel_rtl import ROOT, SOURCES, SOURCE_EXTRAS, fixture

CASE_RE = re.compile(r"CASE (\d+) op=1 .* cycles=(\d+)")
TRANSPORT_RE = re.compile(r"TRANSPORT case=(\d+) frames=(\d+) matrix=(\d+) vector=(\d+)")


class GemvGroupPrefetchRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix="gemv_group_prefetch_", dir=ROOT / "work"))
        cls.off_tb = "verification/v4/stream/tb_stream_kernel_gemv_prefetch_off.sv"
        # The default remains the promoted live worker. A qualification run
        # may set GEMV_PANEL_SOURCE to a recorded immutable worker while its
        # independent owner edits a later feature; the override is optional
        # and its manifest is captured in source provenance.
        cls.panel_baseline = os.environ.get("GEMV_PANEL_SOURCE", "rtl/v4/dataflow/factor_panel_service.sv")
        cls.panel_manifest = os.environ.get("GEMV_PANEL_MANIFEST")
        cls.sources = [cls.panel_baseline if item == "rtl/v4/dataflow/factor_panel_service.sv" else item for item in SOURCES]
        cls.provenance = cls.sources + SOURCE_EXTRAS + [cls.off_tb, "verification/v4/test_gemv_group_prefetch_rtl.py"]
        if cls.panel_manifest:
            cls.provenance.append(cls.panel_manifest)
        cls.before = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in cls.provenance}
        cls.on_binary = cls.folder / "prefetch_on.xsim.json"
        cls.off_binary = cls.folder / "prefetch_off.xsim.json"
        on = compile_rtl(cls.on_binary, "tb_stream_kernel", cls.sources, root=ROOT, timeout=240)
        if on.returncode:
            raise AssertionError(on.stdout + on.stderr)
        off = compile_rtl(cls.off_binary, "tb_stream_kernel_gemv_prefetch_off", cls.sources + [cls.off_tb], root=ROOT, timeout=240)
        if off.returncode:
            raise AssertionError(off.stdout + off.stderr)
        cls.compile_commands = on.commands + off.commands

    def _run(self, binary, vectors, prefetch):
        args = ["vectors=" + vectors.as_posix()]
        if prefetch:
            args.append("require_prefetch=1")
        result = run_rtl(binary, args, root=ROOT, timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        cases = [(int(i), int(cycles)) for i, cycles in CASE_RE.findall(result.stdout)]
        transport = [(int(i), int(frames), int(matrix), int(vector))
                     for i, frames, matrix, vector in TRANSPORT_RE.findall(result.stdout)]
        self.assertEqual(len(cases), len(transport), result.stdout)
        self.assertIn("PASS stream_kernel", result.stdout)
        if prefetch:
            match = re.search(r"PREFETCH_GROUP_OBSERVATIONS (\d+)", result.stdout)
            self.assertIsNotNone(match, result.stdout)
            self.assertGreater(int(match.group(1)), 0, result.stdout)
        return result, cases, transport

    @staticmethod
    def _expected_frames(rows, cols, trans, rfour):
        outputs = cols if trans else rows
        reductions = rows if trans else cols
        group_width = 8 if rfour else 32
        groups = (outputs + group_width - 1) // group_width
        if not rfour:
            per_group = reductions
        else:
            per_group = sum(min(8, reductions - red) for red in range(0, reductions, 32))
        return groups * per_group

    def test_bounded_prefetch_matches_disabled_baseline(self):
        # Covers both directions and terminal modes.  The first two cases have
        # three R1 groups with reductions one and three, so the four-entry
        # queue can cross multiple output groups.  The final Phi case is
        # M128/N1024 transpose/R4: 128 groups x 32 frames.
        specs = [
            (65, 1, 1, 0, 0),
            (65, 3, 1, 0, 0),
            (33, 17, 1, 1, 0),
            (65, 33, 1, 0, 1),
            (65, 33, 1, 1, 1),
            (33, 17, 0, 0, 0),
            (33, 17, 0, 1, 0),
            (33, 17, 0, 0, 1),
            (33, 17, 0, 1, 1),
            (128, 1024, 0, 1, 1),
        ]
        cases = []
        expected = []
        for rows, cols, dense, trans, rfour in specs:
            length = rows if trans else cols
            cases.append(fixture(op=1, rows=rows, cols=cols, dense=dense, trans=trans,
                                 r4=rfour, length=length, destination=128))
            expected.append(self._expected_frames(rows, cols, trans, rfour))
        vectors = self.folder / "pair.txt"
        vectors.write_text(str(len(cases)) + "\n" + "\n".join(cases) + "\n")
        on, on_cycles, on_transport = self._run(self.on_binary, vectors, True)
        off, off_cycles, off_transport = self._run(self.off_binary, vectors, False)

        self.assertEqual([item[1] for item in on_transport], expected, on.stdout)
        self.assertEqual([item[1] for item in off_transport], expected, off.stdout)
        self.assertEqual([item[1] for item in on_transport], [item[1] for item in off_transport])
        # Completed commands make the same logical matrix/vector requests.
        self.assertEqual([item[2:] for item in on_transport], [item[2:] for item in off_transport])
        self.assertLess(on_cycles[-1][1], off_cycles[-1][1], (on.stdout, off.stdout))
        self.assertLess(sum(c for _, c in on_cycles), sum(c for _, c in off_cycles), (on.stdout, off.stdout))

        after = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in self.provenance}
        self.assertEqual(self.before, after)
        record = {
            "test": self.id(), "status": "PASS",
            "comparison": "prefetch_on_vs_parameter_disabled_exact_S27_outputs_faults_cancel_and_transport_counts",
            "expected_accepted_frames": expected,
            "prefetch_cycles": [c for _, c in on_cycles],
            "baseline_cycles": [c for _, c in off_cycles],
            "prefetch_total_cycles": sum(c for _, c in on_cycles),
            "baseline_total_cycles": sum(c for _, c in off_cycles),
            "source_sha256": self.before,
            "vectors_sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
            "commands": self.compile_commands + on.commands + off.commands,
            "prefetch_stdout": on.stdout,
            "baseline_stdout": off.stdout,
        }
        (self.folder / "qualification.json").write_text(json.dumps(record, indent=2) + "\n")

    @staticmethod
    def _fault_fixture(marker):
        case = fixture(op=1, rows=65, cols=33, dense=1, trans=1, r4=1,
                       length=65, destination=128)
        lines = case.splitlines()
        header = lines[0].split()
        header[16] = "7"
        header[18] = "0"
        header[19] = str(marker)
        reads = int(header[21])
        for item in range(-reads, 0):
            fields = lines[item].split()
            fields[2] = "2"
            fields[3] = "0"
            lines[item] = " ".join(fields)
        lines[0] = " ".join(header)
        return "\n".join(lines)

    def test_future_group_fault_cancel_reset_and_recovery(self):
        # Tag fault must wait behind a held active terminal. Markers19/20
        # cancel and reset with future payload present. Each is followed by a
        # normal command that proves queue flush and next-command recovery.
        recovery = fixture(op=1, rows=65, cols=3, dense=1, trans=0, r4=0,
                           length=3, destination=128)
        cases = [self._fault_fixture(18), recovery,
                 fixture(op=1, rows=65, cols=1, dense=1, trans=0, r4=0,
                         length=1, destination=128, cancel=19), recovery,
                 fixture(op=1, rows=65, cols=3, dense=1, trans=0, r4=0,
                         length=3, destination=128, cancel=20), recovery]
        vectors = self.folder / "future_fault_cancel.txt"
        vectors.write_text(str(len(cases)) + "\n" + "\n".join(cases) + "\n")
        result, cycles, transport = self._run(self.on_binary, vectors, True)
        self.assertEqual(len(cycles), len(cases), result.stdout)
        frames = [frames for _, frames, _, _ in transport]
        # Fault/cancel/reset stop before all command frames by construction;
        # each ordinary recovery command must still deliver its full 65x3 R1
        # stream after the held future payload is flushed.
        self.assertGreater(frames[0], 0, result.stdout)
        self.assertLess(frames[0], 85, result.stdout)
        self.assertGreater(frames[2], 0, result.stdout)
        self.assertLess(frames[2], 3, result.stdout)
        self.assertGreater(frames[4], 0, result.stdout)
        self.assertLess(frames[4], 9, result.stdout)
        self.assertEqual([frames[1], frames[3], frames[5]], [9, 9, 9], result.stdout)
        after = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in self.provenance}
        self.assertEqual(self.before, after)
        record = {"test": self.id(), "status": "PASS",
                  "comparison": "future_group_tag_fault_cancel_reset_no_publication_then_recovery",
                  "source_sha256": self.before,
                  "vectors_sha256": hashlib.sha256(vectors.read_bytes()).hexdigest(),
                  "commands": self.compile_commands + result.commands,
                  "stdout": result.stdout}
        (self.folder / "future_fault_cancel.json").write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main()
