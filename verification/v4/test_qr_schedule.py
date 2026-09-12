"""Compiler-only QR transport and exact per-invocation cache qualification."""
import hashlib
import json
from pathlib import Path
import unittest
import numpy as np
from compiler.v4.greedy_qr_emit import compile_greedy_qr
from compiler.v4.recovery_emit import PROFILE
from models.v4.fixed import Format
from models.v4.lfsr_operator import lfsr32_matrix
from models.v4.recovery import Policy, run
from verification.v4.recovery_program_vm import execute

ROOT = Path(__file__).resolve().parents[2]
RUNS = []


def fixture():
    matrix = lfsr32_matrix(0x12345678, 64, 256, scale=8192) / 65536.0
    rng = np.random.default_rng(1909 + 64 + 256)
    support = sorted(map(int, rng.choice(256, 8, replace=False)))
    x = np.zeros(256)
    x[support] = rng.uniform(.5, 1, 8) * rng.choice([-1, 1], 8)
    y = matrix @ x
    y = np.rint(y * (.5 / float(np.max(np.abs(y)))) * 16384) / 16384
    return matrix, y


class QrScheduleTests(unittest.TestCase):
    def test_all_five_k8_cache_depth_ablation_exact_retained_oracle(self):
        matrix, y = fixture()
        records = json.loads((ROOT / 'verification/v4/fixtures/k8_reference_oracles.json').read_text())
        for old in records:
            for depth in (0, 1, 2):
                with self.subTest(algorithm=old['algorithm'], depth=depth):
                    package = compile_greedy_qr(old['algorithm'], matrix, Policy(8, max_iterations=8),
                                               qr_cache_entries=depth, qr_schedule_compact=True)
                    actual = execute(package, matrix, y, limit=1000000)
                    for key, expected in (('x', 'output_raw_x_sha256'), ('residual', 'output_raw_r_sha256')):
                        self.assertEqual(hashlib.sha256(np.asarray(actual[key], dtype='<i4').tobytes()).hexdigest(), old[expected])
                    for key, expected in (('support', 'accepted_support'), ('status', 'status'),
                                          ('outer', 'outer_iterations'), ('inner', 'inner_iterations')):
                        self.assertEqual(actual[key], old[expected])
                    hits = sum(actual['trace'].count(pc) for name, pc in package['labels'].items() if name.startswith('qr_cache_hit_'))
                    misses = actual['trace'].count(package['labels'].get('qr_cache_miss', -1))
                    RUNS.append(dict(algorithm=old['algorithm'], cache_entries=depth,
                                     retired=len(actual['trace']), cache_hits=hits, cache_misses=misses,
                                     vectors=len(package['vectors']), words=len(package['program']),
                                     blocks=max(v['base']+(v['capacity']+31)//32 for v in package['vectors'])))
                    (ROOT / 'work/qr_schedule_model.json').write_text(json.dumps(RUNS, indent=2))

    def test_failed_certificates_and_zero_never_publish_cache(self):
        rng = np.random.default_rng(812)
        matrix = rng.choice([-1., 1.], (16, 32)) * .25
        measurement = rng.integers(-1024, 1024, 16) / 16384
        for refinements in (0, 2):
            policy = Policy(2, max_iterations=3, ls_normal_rtol=1e-8)
            expected = run('OMP', matrix, measurement, policy, PROFILE, ls_solver='qr',
                           solution_format=Format(24, 20), qr_max_refinements=refinements)
            package = compile_greedy_qr('OMP', matrix, policy, max_refinements=refinements,
                                       qr_cache_entries=2, qr_schedule_compact=True)
            actual = execute(package, matrix, measurement)
            self.assertEqual(actual['status'], 'ls_not_converged')
            self.assertEqual(actual['outer'], 1)
            self.assertEqual(actual['inner'], refinements + 1)
            self.assertEqual(list(actual['x']), [round(float(x)*2**22) for x in expected.x])
            self.assertEqual(actual['trace'].count(package['labels']['qr_cache_insert']), 1)
        for algorithm in ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'):
            package = compile_greedy_qr(algorithm, matrix, Policy(2, max_iterations=3), qr_cache_entries=2)
            actual = execute(package, matrix, np.zeros(16))
            self.assertEqual(actual['outer'], 0)
            self.assertNotIn(package['labels']['qr_cached'], actual['trace'])

    def test_maximum_geometry_liveness_and_entry_guards(self):
        matrix = lfsr32_matrix(0x12345678, 128, 1024, scale=4096) / 65536.0
        for algorithm in ('OMP', 'GOMP', 'CoSaMP', 'SP', 'HTP'):
            package = compile_greedy_qr(algorithm, matrix, Policy(16, max_iterations=16), qr_cache_entries=2)
            self.assertLessEqual(len(package['vectors']), 32)
            self.assertLessEqual(len(package['program']), 1024)
            self.assertLessEqual(max(v['base']+(v['capacity']+31)//32 for v in package['vectors']), 480)
        for value in (-1, 3, True):
            with self.assertRaises(ValueError):
                compile_greedy_qr('OMP', matrix, Policy(2, max_iterations=2), qr_cache_entries=value)


if __name__ == '__main__':
    unittest.main()
