"""Exact QR schedule using generic bound-scalar PE results and result memoization."""
import hashlib
import json
from pathlib import Path
import unittest
import numpy as np
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from models.v4.recovery import Policy
from verification.v4.recovery_program_vm import execute
from verification.v4.test_qr_schedule import fixture, QrScheduleTests

ROOT = Path(__file__).resolve().parents[2]
DEPTH = {'OMP': 0, 'GOMP': 0, 'CoSaMP': 2, 'SP': 2, 'HTP': 1}


class QrScalarScheduleTests(unittest.TestCase):
    def test_named_balanced_profile_is_exact_explicit_schedule(self):
        matrix, _ = fixture()
        for algorithm, depth in DEPTH.items():
            explicit = compile_greedy_qr(algorithm, matrix, Policy(8, max_iterations=8),
                qr_cache_entries=depth, qr_schedule_compact=True, qr_scalar_template=True)
            named = compile_greedy_qr(algorithm, matrix, Policy(8, max_iterations=8), qr_profile='balanced')
            for field in ('program', 'templates', 'vectors', 'constants'):
                self.assertEqual(named[field], explicit[field])
            self.assertEqual(named['required_kernel_revision'], 2)
            self.assertEqual(named['qr_result_cache_entries'], depth)
        default = compile_greedy_qr('OMP', matrix, Policy(8, max_iterations=8))
        self.assertEqual(default['required_kernel_revision'], 1)
        self.assertFalse(default['qr_scalar_template'])
        with self.assertRaises(ValueError):
            compile_greedy_qr('OMP', matrix, Policy(8, max_iterations=8), qr_profile='unknown')

    def test_five_k8_exact_archived_oracles(self):
        matrix, y = fixture()
        records = json.loads((ROOT / 'verification/v4/fixtures/k8_reference_oracles.json').read_text())
        output = []
        for old in records:
            with self.subTest(algorithm=old['algorithm']):
                package = compile_greedy_qr(old['algorithm'], matrix, Policy(8, max_iterations=8),
                    qr_cache_entries=DEPTH[old['algorithm']], qr_schedule_compact=True, qr_scalar_template=True)
                actual = execute(package, matrix, y, limit=1000000)
                for key, expected in (('x', 'output_raw_x_sha256'), ('residual', 'output_raw_r_sha256')):
                    self.assertEqual(hashlib.sha256(np.asarray(actual[key], dtype='<i4').tobytes()).hexdigest(), old[expected])
                for key, expected in (('support', 'accepted_support'), ('status', 'status'),
                                      ('outer', 'outer_iterations'), ('inner', 'inner_iterations')):
                    self.assertEqual(actual[key], old[expected])
                output.append(dict(algorithm=old['algorithm'], cache_entries=DEPTH[old['algorithm']],
                                   retired=len(actual['trace']), words=len(package['program']),
                                   vectors=len(package['vectors']), templates=len(package['templates'])))
                (ROOT / 'work/qr_scalar_model.json').write_text(json.dumps(output, indent=2))


if __name__ == '__main__':
    unittest.main()
