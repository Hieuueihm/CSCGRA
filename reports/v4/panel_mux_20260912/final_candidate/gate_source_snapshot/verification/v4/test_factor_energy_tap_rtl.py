"""Integer-oracle XSim entry point for feature-10 FACTOR_ENERGY_TAP.

The shared kernel fixture owns B loading, factor-store bank rotation, retained
candidate publication and public readback.  This module supplies only op25
cases so the square/raw-ACC/tail-stat contract remains independently visible.
Root owns execution of this test; its records bind every compiled source hash.
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
SPEC = importlib.util.spec_from_file_location('factor_energy_fixture_base', BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)

TEST = 'verification/v4/test_factor_energy_tap_rtl.py'
SOURCES = BASE.SOURCES
EXTRAS = BASE.SOURCE_EXTRAS + [TEST]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FactorEnergyTapRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = Path(tempfile.mkdtemp(prefix='factor_energy_tap_', dir=ROOT / 'work'))
        cls.binary = cls.folder / 'factor_energy_tap.xsim.json'
        cls.before = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        compiled = compile_rtl(cls.binary, 'tb_stream_kernel', SOURCES,
                               root=ROOT, timeout=240)
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.commands = compiled.commands

    def replay(self, cases, scope):
        vectors = self.folder / f'{self._testMethodName}.txt'
        vectors.write_text(str(len(cases)) + '\n' + '\n'.join(cases) + '\n',
                           encoding='utf-8')
        result = run_rtl(self.binary, [f'vectors={vectors.as_posix()}'],
                         root=ROOT, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        match = re.search(r'PASS stream_kernel cycles=(\d+) checks=(\d+) commands=(\d+) stalls=(\d+)',
                          result.stdout)
        self.assertIsNotNone(match, result.stdout)
        cycles, checks, commands, stalls = map(int, match.groups())
        self.assertEqual(commands, len(cases))
        self.assertGreater(stalls, 0)
        after = {name: sha(ROOT / name) for name in SOURCES + EXTRAS}
        self.assertEqual(self.before, after)
        record = dict(test=self.id(), status='PASS', scope=scope,
                      cycles=cycles, comparisons=checks, commands_executed=commands,
                      stalls=stalls,
                      comparison_kind='exact_private_C18_to_S27_factor_tap_and_integer_ACC64_square_sum',
                      commands=self.commands + result.commands,
                      vectors_sha256=sha(vectors), source_sha256=self.before,
                      stdout=result.stdout)
        (self.folder / f'{self._testMethodName}.json').write_text(
            json.dumps(record, indent=2) + '\n', encoding='utf-8')

    def test_energy_tap_axes_offsets_tails_and_import_extrema(self):
        cases = []
        # L1 deliberately has a nonzero tap but no tail: rsp_nonzero=1 and
        # rsp_count=0 are independent result fields.
        for args in [
            (1, 1, False, 0, 0, 1, 0),
            (33, 17, False, 7, 31, 2, 128),
            (65, 17, False, 7, 0, 32, 160),
            (65, 65, True, 11, 7, 31, 192),
            (65, 65, True, 11, 7, 33, 224),
            (128, 96, False, 95, 0, 128, 256),
        ]:
            sequence, oracle = BASE.factor_energy_tap_sequence(*args)
            self.assertEqual(oracle['raw_acc'], sum(value * value for value in oracle['tap']))
            self.assertEqual(oracle['tail_nonzero'], int(any(oracle['tap'][1:])))
            cases.extend(sequence)
        # C18 import endpoints map to signed S27 values before both MAC inputs;
        # the ACC64 oracle stays exact across 128 terms without per-frame round.
        for raw, destination in ((-(1 << 17), 320), ((1 << 17) - 1, 352)):
            sequence, oracle = BASE.factor_energy_tap_sequence(
                128, 1, False, 0, 0, 128, destination=destination,
                raw_value=raw)
            self.assertEqual(oracle['tap'][0], raw << 6)
            self.assertEqual(oracle['raw_acc'], 128 * (raw << 6) ** 2)
            cases.extend(sequence)
        # A zero head is legal and keeps both normal-tap nonzero and the tail
        # flag clear; it is distinct from the nonzero L1/tail-zero case above.
        sequence, oracle = BASE.factor_energy_tap_sequence(
            1, 1, False, 0, 0, 1, destination=384, raw_value=0)
        self.assertEqual((oracle['raw_acc'], oracle['tail_nonzero'], int(any(oracle['tap']))),
                         (0, 0, 0))
        cases.extend(sequence)
        self.replay(cases,
                    'column_and_row_axes_offsets_L1_L2_L31_L32_L33_L128_and_signed_C18_import_endpoints')

    def test_energy_tap_full_candidate_private_factor_readback_and_block_zero(self):
        cases = []
        sequence, oracle = BASE.factor_energy_tap_sequence(
            128, 96, True, 127, 31, 65, destination=0)
        cases.extend(sequence)
        # The op25 candidate uses public block zero, but must leave its factor
        # source unpatched.  A subsequent private FACTOR_READ compares all 96
        # retained row values after the energy command has committed.
        cases.append(BASE.factor_range_readback(
            128, 96, True, 127, oracle['factor'], destination=384))
        self.replay(cases,
                    'full_unpatched_tap_public_block_zero_and_private_factor_readback_after_energy')

    def test_energy_tap_private_response_mask_fault_has_no_candidate_or_stat(self):
        # Marker21 corrupts a held private factor response after INIT.  The
        # shared fixture observes fault6, zero scalar/nonzero/count, and does
        # not accept a candidate readback for the faulting op25 command.
        sequence, _ = BASE.factor_energy_tap_sequence(
            65, 17, False, 7, 0, 33, destination=416,
            marker=21, expected_fault=6)
        self.replay(sequence,
                    'malformed_private_factor_response_mask_before_raw_ACC_or_candidate_publication')

    def test_energy_tap_cancel_after_private_candidate_then_fresh_init_recovery(self):
        # Marker25 waits for a committed private candidate block, cancels the
        # live factor/public transaction, verifies every destination block is
        # invalid, then lets a fresh B+INIT/op25 pair run normally.
        canceled, _ = BASE.factor_energy_tap_sequence(
            65, 17, False, 7, 0, 33, destination=416, marker=25)
        recovery, _ = BASE.factor_energy_tap_sequence(
            65, 65, True, 11, 3, 33, destination=448)
        self.replay(canceled + recovery,
                    'cancel_after_private_candidate_invalidates_two_block_destination_then_fresh_INIT_recovers')


if __name__ == '__main__':
    unittest.main()
