"""Application LS diagnostics cannot alter a solver return or failure."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from models.v4 import lsqr
from models.v4.fixed import Format, Profile
from models.v4.recovery import Policy
from scripts.v4.lfsr_application_fixed_validation import observe_ls


class ApplicationObserverTests(unittest.TestCase):
    def setUp(self):
        self.profile = Profile(Format(18, 14), Format(18, 16), Format(27, 22), 64)
        self.solution = Format(24, 20)
        self.policy = Policy(sparsity=2, ls_max_iterations=128, ls_normal_rtol=1e-5)
        self.reference_class = lsqr.IntegerLSQRKernels

    def backend(self, matrix, measurement, policy=None):
        return lsqr.IntegerLSQRKernels(
            matrix, measurement, policy or self.policy, self.profile,
            solution_format=self.solution,
        )

    def test_diagnostic_svd_exception_preserves_successful_raw_return(self):
        matrix, measurement, support = np.eye(2), np.array([0.25, 0.0]), [0]
        plain = self.backend(matrix, measurement)
        expected = plain.least_squares(support)
        audits = []
        with observe_ls(audits):
            observed = self.backend(matrix, measurement)
            with patch('numpy.linalg.lstsq', side_effect=np.linalg.LinAlgError('diagnostic-only failure')):
                actual = observed.least_squares(support)
        np.testing.assert_array_equal(actual, expected)
        self.assertEqual(observed.last_ls_report, plain.last_ls_report)
        self.assertEqual(len(audits), 1)
        self.assertTrue(audits[0]['runtime_returned'])
        self.assertEqual(audits[0]['status'], 'success')
        self.assertFalse(audits[0]['diagnostic_accepted'])
        self.assertEqual(audits[0]['diagnostic_exception'], {
            'type': 'LinAlgError', 'message': 'diagnostic-only failure',
        })
        self.assertIs(lsqr.IntegerLSQRKernels, self.reference_class)

    def test_actual_solver_failure_preserves_original_exception_and_observation(self):
        # A nontrivial two-column problem cannot finish its LS solve in one step.
        matrix = np.array([[1.0, 0.3], [0.2, 1.0]])
        measurement = np.array([0.1234, -0.3212])
        policy = Policy(sparsity=2, ls_max_iterations=1, ls_normal_rtol=1e-5)
        original_method = self.reference_class.least_squares
        actual_solver_exceptions = []
        def record_actual_failure(backend, support):
            try:
                return original_method(backend, support)
            except ArithmeticError as exc:
                actual_solver_exceptions.append(exc)
                raise
        audits = []
        with patch.object(self.reference_class, 'least_squares', record_actual_failure):
            with observe_ls(audits):
                observed = self.backend(matrix, measurement, policy)
                with patch('numpy.linalg.lstsq') as diagnostic_svd:
                    with self.assertRaises(ArithmeticError) as caught:
                        observed.least_squares([1, 0])
                    diagnostic_svd.assert_not_called()
        self.assertEqual(len(actual_solver_exceptions), 1)
        self.assertIs(caught.exception, actual_solver_exceptions[0])
        self.assertEqual(str(caught.exception), 'ls_not_converged')
        self.assertEqual(len(audits), 1)
        self.assertEqual(audits[0]['ordered_support'], [1, 0])
        self.assertFalse(audits[0]['runtime_returned'])
        self.assertFalse(audits[0]['diagnostic_accepted'])
        self.assertEqual(audits[0]['status'], 'ls_not_converged')
        self.assertIs(lsqr.IntegerLSQRKernels, self.reference_class)

    def test_passing_observation_preserves_return_and_ordered_coordinates(self):
        matrix, measurement, support = np.eye(2), np.array([0.125, 0.25]), [1, 0]
        plain = self.backend(matrix, measurement)
        expected = plain.least_squares(support)
        audits = []
        with observe_ls(audits):
            observed = self.backend(matrix, measurement)
            actual = observed.least_squares(support)
        np.testing.assert_array_equal(actual, expected)
        self.assertEqual(observed.last_ls_report, plain.last_ls_report)
        self.assertEqual(len(audits), 1)
        self.assertEqual(audits[0]['ordered_support'], support)
        self.assertTrue(audits[0]['runtime_returned'])
        self.assertTrue(audits[0]['diagnostic_accepted'])
        self.assertNotIn('diagnostic_exception', audits[0])
        self.assertIs(lsqr.IntegerLSQRKernels, self.reference_class)


if __name__ == '__main__':
    unittest.main()
