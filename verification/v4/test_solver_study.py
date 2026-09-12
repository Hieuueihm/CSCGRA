"""Independent checks for the solver isolation evidence and rounding bound."""
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4.fixed import Format
from models.v4.recovery import IntegerKernels, Policy
from scripts.v4.solver_study import (
    ITERATION_BUDGET, NORMAL_RTOL, ObservedCGLS, PROFILES, cases,
    data_rounding_bound, isolate_cgls, relative_norm,
)


class SolverStudyTests(unittest.TestCase):
    def test_rounding_bound_covers_all_hypercube_vertices(self):
        a = np.array([[1., -.4, .2], [.1, .7, -.3], [-.2, .3, .8]])
        fmt = Format(16, 12)
        bound = data_rounding_bound(a, fmt)
        for mask in range(1 << a.shape[1]):
            delta = np.array([1. if mask & (1 << j) else -1.
                              for j in range(a.shape[1])])/(2*fmt.scale)
            self.assertTrue(np.all(np.abs(a.T@a@delta) <= bound+1e-15))

    def test_observation_preserves_existing_kernel_result_and_events(self):
        c = cases()[0]
        policy = Policy(sparsity=len(c['support']), ls_normal_rtol=NORMAL_RTOL,
                        ls_max_iterations=ITERATION_BUDGET)
        args = (c['a'], c['y'], policy, PROFILES['dsp_candidate'])
        original, observed = IntegerKernels(*args), ObservedCGLS(*args)
        np.testing.assert_array_equal(original.least_squares(c['support']),
                                      observed.least_squares(c['support']))
        self.assertEqual(original.events, observed.events)
        self.assertEqual(original.ls_steps, observed.ls_steps)

    def test_data_storage_floor_can_fail_while_synthetic_quality_is_close(self):
        row = isolate_cgls(cases()[0], PROFILES['compact'])
        self.assertFalse(row['accepted'])
        self.assertEqual(row['status'], 'ls_not_converged')
        self.assertFalse(any(row['events'].values()))
        last = row['last_candidate']
        self.assertTrue(last['diagnostic_only_if_failed'])
        self.assertLess(last['pre_storage_normal']['normal_relative'], NORMAL_RTOL)
        self.assertGreater(last['normal_relative'], NORMAL_RTOL)
        self.assertTrue(last['synthetic_coefficient_quality']['arithmetic_quality_pass'])
        self.assertIsNone(last['synthetic_coefficient_quality']['application_quality_pass'])
        self.assertTrue(row['oracle_rounded_to_D']['bound_holds'])

    def test_normal_certificate_is_not_coefficient_accuracy_guarantee(self):
        row = isolate_cgls(cases()[1], PROFILES['dsp_candidate'])
        self.assertTrue(row['accepted'])
        self.assertGreater(row['condition_quantized'], 1000.)
        self.assertLess(row['last_candidate']['normal_relative'], NORMAL_RTOL)
        self.assertGreater(row['last_candidate']['coefficient_error_vs_quantized_svd'], .9)

    def test_rank_deficiency_uses_minimum_norm_oracle_without_plain_qr_solve(self):
        c = cases()[2]
        row = isolate_cgls(c, PROFILES['dsp_candidate'])
        self.assertEqual(row['rank_original'], len(c['support'])-1)
        self.assertEqual(row['rank_quantized'], len(c['support'])-1)
        self.assertIsNone(row['oracle']['qr_relative_difference'])

    def test_zero_denominator_is_not_replaced_by_a_floor(self):
        self.assertEqual(relative_norm([0.], [0.]), 0.)
        self.assertEqual(relative_norm([1.], [0.]), float('inf'))


if __name__ == '__main__':
    unittest.main()
