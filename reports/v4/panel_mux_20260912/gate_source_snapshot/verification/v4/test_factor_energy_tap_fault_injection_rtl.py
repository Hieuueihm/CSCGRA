"""Held final-reply integrity checks for FACTOR_ENERGY_TAP (opcode 25)."""
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
SPEC = importlib.util.spec_from_file_location('factor_energy_fault_fixture_base', BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

WRAPPER = 'verification/v4/stream/tb_stream_kernel_factor_energy_tap_fault.sv'
TEST = 'verification/v4/test_factor_energy_tap_fault_injection_rtl.py'
SOURCES = BASE.SOURCES + [WRAPPER]
EXTRAS = BASE.SOURCE_EXTRAS + [TEST]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FactorEnergyTapFaultInjectionRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_energy_fault_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'factor_energy_fault.xsim.json'
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_stream_kernel_factor_energy_tap_fault',
                               SOURCES, root=ROOT, timeout=240)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def test_count_and_length_mismatch_abort_private_candidate_then_recover(self):
        # The wrapper injects after candidate traffic reached SUPPORT_WAIT.  The
        # two fault headers suppress expected host reads; case six is a normal
        # fresh INIT/op25 recovery and checks exact candidate/raw data.
        count_cases, _ = BASE.factor_energy_tap_sequence(
            65, 17, False, 7, 0, 33, destination=192,
            marker=6, expected_fault=6)
        length_cases, _ = BASE.factor_energy_tap_sequence(
            65, 65, True, 11, 3, 33, destination=256,
            marker=6, expected_fault=6)
        recovery_cases, _ = BASE.factor_energy_tap_sequence(
            33, 17, False, 7, 0, 33, destination=320)
        cases = count_cases + length_cases + recovery_cases
        vectors = self.folder / 'response_integrity_vectors.txt'
        vectors.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n',
                           encoding='utf-8')
        result = run_rtl(self.binary, [f'vectors={vectors.as_posix()}'],
                         root=ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout,
                         r'FACTOR_ENERGY_TAP_FAULT count_mismatch_reached=1 fault=6')
        self.assertRegex(result.stdout,
                         r'FACTOR_ENERGY_TAP_FAULT length_mismatch_reached=1 fault=6')
        self.assertRegex(result.stdout, r'FACTOR_ENERGY_TAP_FAULT recovery_reached=1')
        self.assertRegex(result.stdout,
                         r'PASS stream_kernel cycles=\d+ checks=\d+ commands=6 stalls=\d+')
        after = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        self.assertEqual(self.before, after)
        record = dict(test=self.id(), status='PASS',
                      scope='op25_held_reply_count_boolean_and_full_length_validation_then_fresh_recovery',
                      commands=self.commands + result.commands,
                      stdout=result.stdout, vectors_sha256=sha(vectors),
                      source_sha256=self.before,
                      injections=['rsp_count_two_after_private_candidates',
                                  'rsp_length_short_after_private_candidates'],
                      assertions=['fault6_no_raw_scalar_or_count',
                                  'all_owned_public_blocks_invalidated',
                                  'fresh_INIT_then_exact_op25_recovery'])
        (self.folder / 'test_count_and_length_mismatch_abort_private_candidate_then_recover.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    unittest.main()
