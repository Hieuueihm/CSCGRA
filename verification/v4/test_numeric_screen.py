"""Synthetic-only tests for the calibration dataset/operator contract."""

from pathlib import Path
import sys
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.v4.numeric_screen import LASSO_OBJECTIVE, cases, problem, restored


class NumericScreenContractTests(unittest.TestCase):
    def test_synthetic_case_operator_and_restoration_contract(self):
        case = cases('synthetic')[0]
        self.assertEqual(case['name'], 'synthetic')
        self.assertEqual(case['manifest']['split'], 'calibration_only')
        self.assertFalse(case['manifest']['oracle_sparsified_before_measurement'])
        self.assertEqual(case['manifest']['lasso_objective'], LASSO_OBJECTIVE)
        np.testing.assert_allclose(
            np.linalg.norm(case['a'], axis=0), np.ones(case['a'].shape[1]),
            rtol=0.0, atol=2e-15,
        )

        centered_scaled = (case['truth'] - case['mean']) * case['scale']
        basis_coefficients = case['basis'].T @ centered_scaled
        operator_coefficients = case['column_norm'] * basis_coefficients
        np.testing.assert_allclose(
            restored(case, operator_coefficients), case['truth'],
            rtol=0.0, atol=1e-15,
        )

        noiseless = case['a'] @ operator_coefficients
        noise = case['y'] - noiseless
        measured_snr = 20 * np.log10(
            np.linalg.norm(noiseless) / np.linalg.norm(noise)
        )
        self.assertAlmostEqual(measured_snr, 30.0, places=12)

    def test_problem_restores_nonzero_mean_and_rejects_invalid_basis(self):
        signal = np.array([2.0, 3.0, 5.0, 4.0])
        case = problem(
            'centered_fixture', signal, np.eye(4), 3, 2, 17,
            {'kind': 'synthetic_test'},
        )
        centered_scaled = (signal - case['mean']) * case['scale']
        operator_coefficients = case['column_norm'] * centered_scaled
        np.testing.assert_allclose(
            restored(case, operator_coefficients), signal,
            rtol=0.0, atol=5e-16,
        )
        self.assertNotEqual(case['mean'], 0.0)
        with self.assertRaisesRegex(ValueError, 'orthonormal basis'):
            problem(
                'bad_basis', signal, np.diag([1.0, 1.0, 1.0, 2.0]),
                3, 2, 17, {'kind': 'synthetic_test'},
            )
        with self.assertRaisesRegex(ValueError, 'square basis'):
            problem(
                'bad_shape', signal, np.eye(3), 3, 2, 17,
                {'kind': 'synthetic_test'},
            )


if __name__ == '__main__':
    unittest.main()
