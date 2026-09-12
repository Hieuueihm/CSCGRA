"""Independent numerical checks for the v4 integer LSQR candidate."""

from pathlib import Path
import sys
import unittest

import numpy as np
from scipy.linalg import lstsq

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Format, Profile
from models.v4.lsqr import IntegerLSQRKernels
from models.v4.recovery import Policy


def profile():
    # Extra headroom here is an explicit numerical study choice; the baseline
    # remains the S format supplied by the caller.
    return Profile(Format(24, 18), Format(24, 18), Format(40, 24), 96)


class LSQRTests(unittest.TestCase):
    def test_positive_sqrt_rounding_is_exact_integer_nearest(self):
        self.assertEqual(IntegerLSQRKernels._nearest_sqrt_integer(0), 0)
        self.assertEqual(IntegerLSQRKernels._nearest_sqrt_integer(2), 1)
        self.assertEqual(IntegerLSQRKernels._nearest_sqrt_integer(3), 2)
        # sqrt(9/4)=1.5; ties round upward.
        self.assertEqual(IntegerLSQRKernels._nearest_sqrt_integer(9, 4), 2)
        self.assertEqual(IntegerLSQRKernels._nearest_sqrt_integer(16, 4), 2)

    def test_identity_terminates_on_happy_breakdown_and_reports_certificate(self):
        matrix = np.eye(4)
        measurement = np.array([0.75, 0.0, -0.5, 0.0])
        backend = IntegerLSQRKernels(
            matrix, measurement,
            Policy(sparsity=2, ls_max_iterations=8, ls_normal_rtol=1e-4),
            profile(),
        )
        result = backend.least_squares([0, 2])
        np.testing.assert_allclose(backend.decode(result), measurement[[0, 2]], atol=2e-6)
        report = backend.last_ls_report
        self.assertEqual(report["status"], "success")
        self.assertEqual(report["steps"], 1)
        self.assertTrue(report["certificate_history"][-1]["passed"])
        self.assertGreaterEqual(report["counts"]["sqrt"], 1)
        self.assertGreaterEqual(report["counts"]["div"], 1)

    def test_full_rank_noisy_case_matches_quantized_scipy_objective(self):
        rng = np.random.default_rng(31)
        matrix = rng.normal(size=(10, 4))
        matrix /= np.linalg.norm(matrix, axis=0)
        truth = rng.normal(size=4)
        measurement = matrix @ truth + 0.002 * rng.normal(size=10)
        backend = IntegerLSQRKernels(
            matrix, measurement,
            Policy(sparsity=4, ls_max_iterations=64, ls_normal_rtol=1e-3),
            profile(),
        )
        candidate = backend.least_squares(list(range(4)))
        got = backend.decode(candidate)
        quantized_matrix = backend.arithmetic.decode(backend.a[:, :4], backend.profile.coefficient)
        oracle = lstsq(quantized_matrix, backend.decode(backend.y))[0]
        # LSQR and the independent SVD-backed solve are compared by prediction
        # quality; D storage and fixed recurrence can perturb coefficients.
        got_objective = np.linalg.norm(quantized_matrix @ got - backend.decode(backend.y))
        oracle_objective = np.linalg.norm(quantized_matrix @ oracle - backend.decode(backend.y))
        self.assertLessEqual(got_objective, 1.02 * oracle_objective + 1e-5)
        self.assertTrue(backend.last_ls_report["certificate_history"][-1]["passed"])

    def test_rank_deficient_case_reports_fit_without_claiming_unique_coefficients(self):
        matrix = np.array([[1., 1., .2], [0., 0., .4], [.2, .2, .8], [.1, .1, .3]])
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = np.array([.3, -.2, .4, .1])
        backend = IntegerLSQRKernels(
            matrix, measurement,
            Policy(sparsity=3, ls_max_iterations=64, ls_normal_rtol=2e-3),
            profile(),
        )
        try:
            candidate = backend.least_squares([0, 1, 2])
        except ArithmeticError:
            self.assertEqual(backend.last_ls_report["status"], "ls_not_converged")
            self.assertIsNotNone(backend.last_candidate)
            return
        got = backend.decode(candidate)
        b = backend.arithmetic.decode(backend.a[:, [0, 1, 2]], backend.profile.coefficient)
        y = backend.decode(backend.y)
        oracle = lstsq(b, y)[0]
        self.assertLessEqual(np.linalg.norm(b @ got - y), np.linalg.norm(b @ oracle - y) + 2e-3)
        self.assertTrue(backend.last_ls_report["certificate_history"][-1]["passed"])

    def test_near_collinear_case_keeps_certificate_separate_from_coefficient_claim(self):
        matrix = np.array([
            [1., 1.000001, .2], [0., .000001, .4], [.2, .200001, .8],
            [.1, .100001, .3], [.3, .300001, .2], [.4, .400001, .1],
            [.2, .200001, .5], [.1, .100001, .9],
        ])
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = matrix @ np.array([.6, -.4, .8])
        backend = IntegerLSQRKernels(
            matrix, measurement,
            Policy(sparsity=3, ls_max_iterations=64, ls_normal_rtol=1e-3),
            profile(),
        )
        try:
            candidate = backend.least_squares([0, 1, 2])
        except ArithmeticError:
            # A narrow LSQR recurrence may honestly reject a difficult
            # conditioning case; a rejected candidate is never success.
            self.assertEqual(backend.last_ls_report["status"], "ls_not_converged")
            return
        self.assertEqual(backend.last_ls_report["status"], "success")
        self.assertTrue(backend.last_ls_report["certificate_history"][-1]["passed"])
        self.assertIsNotNone(backend.last_ls_report["last_pre_storage"])
        # The certificate says the stored prediction is acceptable; it does
        # not imply equality with the minimum-norm coefficient oracle.
        b = backend.arithmetic.decode(backend.a[:, [0, 1, 2]], backend.profile.coefficient)
        y = backend.decode(backend.y)
        oracle = lstsq(b, y)[0]
        self.assertTrue(np.isfinite(np.linalg.norm(backend.decode(candidate) - oracle)))

    def test_empty_and_zero_measurement_paths_are_safe(self):
        matrix = np.eye(3)
        backend = IntegerLSQRKernels(
            matrix, np.zeros(3),
            Policy(sparsity=1, ls_max_iterations=4), profile(),
        )
        result = backend.least_squares([])
        self.assertEqual(result.tolist(), [])
        backend.least_squares([0])
        self.assertEqual(backend.last_ls_report["status"], "success")

    def test_accumulator_overflow_rejects_without_false_success(self):
        narrow = Profile(Format(8, 4), Format(8, 4), Format(12, 6), 8)
        backend = IntegerLSQRKernels(
            np.ones((4, 1)), np.ones(4),
            Policy(sparsity=1, ls_max_iterations=4), narrow,
        )
        with self.assertRaises(ArithmeticError):
            backend.least_squares([0])
        self.assertEqual(backend.last_ls_report["status"], "numeric_fault")
        self.assertFalse(any(item["passed"] for item in backend.last_ls_report["certificate_history"]))


if __name__ == "__main__":
    unittest.main()
