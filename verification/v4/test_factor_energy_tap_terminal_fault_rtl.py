"""Early-DONE, terminal identity, and raw-fabric fault checks for op25."""
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
SPEC = importlib.util.spec_from_file_location('factor_energy_terminal_fixture_base', BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

WRAPPER = 'verification/v4/stream/tb_stream_kernel_factor_energy_tap_terminal_fault.sv'
TEST = 'verification/v4/test_factor_energy_tap_terminal_fault_rtl.py'
SOURCES = BASE.SOURCES + [WRAPPER]
EXTRAS = BASE.SOURCE_EXTRAS + [TEST]
FABRIC_FAULT = 3


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FactorEnergyTapTerminalFaultRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_energy_terminal_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'factor_energy_terminal.xsim.json'
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_stream_kernel_factor_energy_tap_terminal_fault',
                               SOURCES, root=ROOT, timeout=240)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def test_terminal_reply_faults_abort_then_fresh_energy_tap_recovers(self):
        early_cases, _ = BASE.factor_energy_tap_sequence(
            65, 17, False, 7, 0, 33, destination=192,
            marker=6, expected_fault=6)
        identity_cases, _ = BASE.factor_energy_tap_sequence(
            65, 65, True, 11, 3, 33, destination=256,
            marker=6, expected_fault=6)
        fabric_cases, _ = BASE.factor_energy_tap_sequence(
            65, 17, False, 7, 0, 33, destination=320,
            marker=6, expected_fault=FABRIC_FAULT)
        recovery_cases, _ = BASE.factor_energy_tap_sequence(
            33, 17, False, 7, 0, 33, destination=384)
        cases = early_cases + identity_cases + fabric_cases + recovery_cases
        vectors = self.folder / 'terminal_vectors.txt'
        vectors.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n',
                           encoding='utf-8')
        result = run_rtl(self.binary, [f'vectors={vectors.as_posix()}'],
                         root=ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout,
                         r'FACTOR_ENERGY_TAP_TERMINAL early_done_reached=1 fault=6')
        self.assertRegex(result.stdout,
                         r'FACTOR_ENERGY_TAP_TERMINAL terminal_identity_reached=1 fault=6')
        self.assertRegex(result.stdout,
                         rf'FACTOR_ENERGY_TAP_TERMINAL terminal_fabric_fault_reached=1 fault={FABRIC_FAULT}')
        self.assertRegex(result.stdout, r'FACTOR_ENERGY_TAP_TERMINAL recovery_reached=1')
        self.assertRegex(result.stdout,
                         r'PASS stream_kernel cycles=\d+ checks=\d+ commands=8 stalls=\d+')
        after = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        self.assertEqual(self.before, after)
        record = dict(test=self.id(), status='PASS',
                      scope='op25_early_terminal_identity_and_fabric_fault_abort_before_raw_or_candidate_publication',
                      commands=self.commands + result.commands,
                      stdout=result.stdout, vectors_sha256=sha(vectors),
                      source_sha256=self.before,
                      injections=['matching_early_done_while_panel_RUN',
                                  'wrong_terminal_tag_after_all_frames',
                                  'matching_terminal_with_fabric_fault'],
                      assertions=['fault6_identity_for_early_and_wrong_tag',
                                  'declared_fabric_fault_for_fabric_error',
                                  'raw_ACC64_count_and_candidate_validity_zero_on_fault',
                                  'fresh_INIT_then_exact_recovery'])
        (self.folder / 'test_terminal_reply_faults_abort_then_fresh_energy_tap_recovers.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    unittest.main()
