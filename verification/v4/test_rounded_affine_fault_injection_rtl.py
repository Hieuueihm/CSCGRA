"""Directed XSim fault injection for opcode-23 terminal/publication boundaries."""

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl


ROOT = Path(__file__).resolve().parents[2]
BASE_PATH = ROOT / "verification/v4/test_stream_kernel_rtl.py"
SPEC = importlib.util.spec_from_file_location("kernel_fixture_base", BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

WRAPPER = "verification/v4/stream/tb_stream_kernel_affine_fault.sv"
TEST = "verification/v4/test_rounded_affine_fault_injection_rtl.py"
SOURCES = BASE.SOURCES + [WRAPPER]
EXTRAS = BASE.SOURCE_EXTRAS + [TEST]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _fault_case(case):
    """Expect a no-publication identity fault and invalid destination reads."""
    rows = case.splitlines()
    header = rows[0].split()
    header[16] = "6"  # expected kernel identity fault
    header[17] = "0"
    header[18] = "0"
    writes = int(header[20])
    reads = int(header[21])
    for index in range(1 + writes, 1 + writes + reads):
        fields = rows[index].split()
        fields[2] = "2"
        fields[3] = "0"
        rows[index] = " ".join(fields)
    rows[0] = " ".join(header)
    return "\n".join(rows)


def _prepublish_destination(case):
    """Make cancellation prove destination invalidation rather than absence."""
    rows = case.splitlines()
    header = rows[0].split()
    length = int(header[6])
    destination = int(header[24])
    writes = int(header[20])
    for block in range((length + 31) // 32):
        lanes = min(32, length - block * 32)
        rows.insert(1 + writes + block,
                    f"{destination + block} {(1 << lanes) - 1:x} {BASE.pack([17] * lanes):x}")
    header[20] = str(writes + (length + 31) // 32)
    rows[0] = " ".join(header)
    return "\n".join(rows)


def _retain_prior_command(case):
    """Use the shared driver's existing no-reset marker without cancelling."""
    rows = case.splitlines()
    header = rows[0].split()
    header[19] = "6"
    rows[0] = " ".join(header)
    return "\n".join(rows)


class RoundedAffineFaultInjectionRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix="rounded_affine_fault_", dir=ROOT / "work"))
        cls.binary = cls.folder / "rounded_affine_fault.xsim.json"
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, "tb_stream_kernel_affine_fault", SOURCES,
                               root=ROOT, timeout=240)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def test_terminal_faults_cancel_and_recovery(self):
        # Case 1 is a committed ordinary result at a distinct destination.
        ordinary = BASE.fixture(op=0, length=1, destination=400, values=[73])
        # Cases 2/3 are externally faulted by the wrapper.  Case 4 is canceled
        # after private scratch, then the wrapper reissues its retained request.
        early = _retain_prior_command(_fault_case(_prepublish_destination(
            BASE.rounded_affine_fixture(33, destination=128))))
        terminal = _retain_prior_command(_fault_case(_prepublish_destination(
            BASE.rounded_affine_fixture(33, subtract=True, destination=160))))
        canceled_then_reissued = _retain_prior_command(_prepublish_destination(
            BASE.rounded_affine_fixture(33, destination=192)))
        cases = [ordinary, early, terminal, canceled_then_reissued]
        vectors = self.folder / "fault_vectors.txt"
        vectors.write_text(str(len(cases)) + "\n" + "\n".join(cases) + "\n", encoding="utf-8")
        result = run_rtl(self.binary, [f"vectors={vectors.as_posix()}"], root=ROOT, timeout=300)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"AFFINE_FAULT early_done_reached=1 fault=6")
        self.assertRegex(result.stdout, r"AFFINE_FAULT terminal_identity_reached=1 fault=6")
        self.assertRegex(result.stdout, r"AFFINE_FAULT cancel_after_scratch_reached=1 recovery_reissued=1")
        self.assertRegex(result.stdout, r"PASS stream_kernel cycles=\d+ checks=\d+ commands=4 stalls=\d+")
        after = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        self.assertEqual(self.before, after)
        record = {
            "test": self.id(),
            "status": "PASS",
            "scope": "opcode23_early_done_affine_wait_identity_cancel_after_private_scratch_and_recovery",
            "commands": self.commands + result.commands,
            "stdout": result.stdout,
            "vectors_sha256": sha(vectors),
            "source_sha256": self.before,
            "fixture_driver": "tb_stream_kernel",
            "injections": [
                "matching_identity_done_while_RUN",
                "wrong_terminal_tag_while_AFFINE_WAIT",
                "cancel_after_private_scratch_then_reissue",
            ],
        }
        (self.folder / "test_terminal_faults_cancel_and_recovery.json").write_text(
            json.dumps(record, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
