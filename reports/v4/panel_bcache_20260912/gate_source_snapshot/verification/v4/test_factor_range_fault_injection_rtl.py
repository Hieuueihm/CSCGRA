"""Directed XSim faults around opcode-24 raw terminal/candidate publication.

This wrapper reuses the stream-kernel fixture driver.  It is intentionally
separate from the shared broad suite and from panel-owned leaf testbenches.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl

ROOT = Path(__file__).resolve().parents[2]
BASE_PATH = ROOT / 'verification/v4/test_stream_kernel_rtl.py'
SPEC = importlib.util.spec_from_file_location('kernel_fixture_base', BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

WRAPPER = 'verification/v4/stream/tb_stream_kernel_factor_range_fault.sv'
TEST = 'verification/v4/test_factor_range_fault_injection_rtl.py'
SOURCES = BASE.SOURCES + [WRAPPER]
EXTRAS = BASE.SOURCE_EXTRAS + [TEST]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def retain_factor(case):
    rows = case.splitlines(); header = rows[0].split(); header[19] = '6'; rows[0] = ' '.join(header)
    return '\n'.join(rows)


def fault_case(case):
    """Expect a fault response with no candidate publication/readback."""
    rows = case.splitlines(); header = rows[0].split(); header[16] = '6'; header[17] = '0'; header[18] = '0'
    writes = int(header[20]); reads = int(header[21])
    for index in range(1 + writes, 1 + writes + reads):
        fields = rows[index].split(); fields[2] = '2'; fields[3] = '0'; rows[index] = ' '.join(fields)
    rows[0] = ' '.join(header)
    return '\n'.join(rows)


def prepublish_destination(case):
    """Supply destination data so each failure proves full invalidation."""
    rows = case.splitlines(); header = rows[0].split()
    length, destination, writes = int(header[6]), int(header[24]), int(header[20])
    extra = (length + 31) // 32
    for block in range(extra):
        lanes = min(32, length - block * 32)
        rows.insert(1 + writes + block,
                    f'{destination + block} {(1 << lanes) - 1:x} {BASE.pack([17] * lanes):x}')
    header[20] = str(writes + extra); rows[0] = ' '.join(header)
    return '\n'.join(rows)


def factor_pair(*, destination, patch, offset=1, length=32):
    init, op = BASE.factor_range_template_sequence(
        33, 17, False, 7, offset, length, head_only=False, patch=patch,
        destination=destination)[0]
    # Case one has already performed the real reset and published the ordinary
    # control result.  Retain that result while this INIT loads a fresh B image,
    # then retain the immediately following op24's private factor ownership.
    return retain_factor(init), retain_factor(op)


class FactorRangeFaultInjectionRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_range_fault_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'factor_range_fault.xsim.json'
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_stream_kernel_factor_range_fault', SOURCES,
                               root=ROOT, timeout=240)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def test_raw_terminal_faults_candidate_commit_cancel_and_recovery(self):
        ordinary = BASE.fixture(op=0, length=1, destination=400, values=[73])
        early_init, early = factor_pair(destination=128, patch=-(1 << 20) + 17)
        terminal_init, terminal = factor_pair(destination=160, patch=(1 << 20) - 13)
        metadata_init, metadata = factor_pair(destination=224, patch=-(1 << 19) + 5)
        # This command spans two public blocks, so cancellation proves that the
        # complete requested destination—not merely the first private block—is
        # invalidated before factor ownership is rebuilt.
        cancel_init, canceled = factor_pair(destination=192, patch=(1 << 20) + 17,
                                             offset=0, length=33)
        cases = [ordinary, early_init, fault_case(prepublish_destination(early)),
                 terminal_init, fault_case(prepublish_destination(terminal)),
                 metadata_init, fault_case(prepublish_destination(metadata)),
                 cancel_init, prepublish_destination(canceled)]
        vectors = self.folder / 'fault_vectors.txt'
        vectors.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n', encoding='utf-8')
        result = run_rtl(self.binary, [f'vectors={vectors.as_posix()}'], root=ROOT, timeout=360)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ('early_done_reached', 'terminal_identity_reached', 'metadata_after_raw_reached'):
            self.assertRegex(result.stdout, rf'FACTOR_RANGE_FAULT {name}=1 fault=6')
        self.assertRegex(result.stdout,
                         r'FACTOR_RANGE_FAULT cancel_after_candidate_reached=1 recovery_reissued=1')
        self.assertRegex(result.stdout, r'PASS stream_kernel cycles=\d+ checks=\d+ commands=9 stalls=\d+')
        after = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        self.assertEqual(self.before, after)
        record = dict(test=self.id(), status='PASS',
                      scope='opcode24_early_done_terminal_identity_metadata_after_raw_candidate_cancel_and_reinit_recovery',
                      commands=self.commands + result.commands, stdout=result.stdout,
                      vectors_sha256=sha(vectors), source_sha256=self.before,
                      fixture_driver='tb_stream_kernel',
                      injections=['matching_done_while_panel_run', 'wrong_terminal_identity_after_feed',
                                  'metadata_fault_after_raw_done_held_candidate',
                                  'cancel_after_private_candidate_then_factor_init_same_tag_reissue'])
        (self.folder / 'test_raw_terminal_faults_candidate_commit_cancel_and_recovery.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    unittest.main()
