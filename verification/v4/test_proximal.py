"""Independent numerical tests for the three v4 proximal LASSO programs."""

from dataclasses import replace
from pathlib import Path
import sys
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Format, Profile
from models.v4.proximal import ALGORITHMS, Policy, run, soft_threshold


def objective(matrix, measurement, coefficients, regularization):
    residual = matrix @ coefficients - measurement
    return 0.5 * float(residual @ residual) + regularization * float(
        np.sum(np.abs(coefficients))
    )


def coordinate_descent(matrix, measurement, regularization, iterations=20_000):
    """Independent cyclic coordinate-descent LASSO reference."""
    coefficients = np.zeros(matrix.shape[1])
    residual = measurement.copy()
    energies = np.sum(matrix * matrix, axis=0)
    for _ in range(iterations):
        largest_change = 0.0
        for column_index, column in enumerate(matrix.T):
            residual += column * coefficients[column_index]
            correlation = float(column @ residual)
            shrunk = np.sign(correlation) * max(
                abs(correlation) - regularization, 0.0
            )
            updated = float(shrunk / energies[column_index])
            residual -= column * updated
            largest_change = max(
                largest_change, abs(updated - coefficients[column_index])
            )
            coefficients[column_index] = updated
        if largest_change < 1e-14:
            break
    return coefficients


def kkt_violation(matrix, measurement, coefficients, regularization):
    gradient = matrix.T @ (matrix @ coefficients - measurement)
    violations = []
    for value, derivative in zip(coefficients, gradient):
        if value > 1e-9:
            violations.append(abs(derivative + regularization))
        elif value < -1e-9:
            violations.append(abs(derivative - regularization))
        else:
            violations.append(max(abs(derivative) - regularization, 0.0))
    return max(violations, default=0.0)


class ProximalTests(unittest.TestCase):
    def test_soft_threshold_including_exact_edges(self):
        values = np.array([-0.5, -0.25, 0.0, 0.25, 0.5])
        np.testing.assert_array_equal(
            soft_threshold(values, 0.25),
            np.array([-0.25, 0.0, 0.0, 0.0, 0.25]),
        )

    def test_all_algorithms_match_diagonal_lasso_solution(self):
        diagonal = np.array([0.5, 1.0, 1.5, 2.0])
        matrix = np.diag(diagonal)
        measurement = np.array([1.0, 0.08, -0.9, 1.2])
        regularization = 0.1
        expected = np.sign(diagonal * measurement) * np.maximum(
            np.abs(diagonal * measurement) - regularization, 0.0
        ) / (diagonal * diagonal)
        policy = Policy(
            regularization=regularization,
            max_iterations=500,
            step_size=0.2,
            pd_sigma=1.0,
            inner_max_iterations=32,
            inner_rtol=1e-12,
        )
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                result = run(algorithm, matrix, measurement, policy)
                self.assertEqual(result.status, "max_iterations")
                self.assertEqual(len(result.trace), policy.max_iterations)
                np.testing.assert_allclose(result.x, expected, rtol=0.0, atol=1e-8)
                np.testing.assert_allclose(
                    result.residual, measurement - matrix @ result.x,
                    rtol=0.0, atol=1e-14,
                )

    def test_dense_strongly_convex_case_matches_coordinate_descent_and_kkt(self):
        rng = np.random.default_rng(43)
        matrix = rng.normal(size=(20, 5)) / np.sqrt(20.0)
        measurement = rng.normal(size=20)
        self.assertLess(np.linalg.cond(matrix), 1.7)
        regularization = 0.12
        reference = coordinate_descent(matrix, measurement, regularization)
        reference_objective = objective(
            matrix, measurement, reference, regularization
        )
        lipschitz = float(np.linalg.norm(matrix, 2) ** 2)
        policy = Policy(
            regularization=regularization,
            max_iterations=400,
            step_size=0.9 / lipschitz,
            pd_sigma=0.9,
            inner_max_iterations=16,
            inner_rtol=1e-12,
        )
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                result = run(algorithm, matrix, measurement, policy)
                self.assertEqual(result.status, "max_iterations")
                np.testing.assert_allclose(result.x, reference, rtol=0.0, atol=2e-9)
                self.assertLessEqual(
                    objective(matrix, measurement, result.x, regularization),
                    reference_objective + 2e-13,
                )
                self.assertLess(
                    kkt_violation(
                        matrix, measurement, result.x, regularization
                    ),
                    2e-9,
                )

    def test_finite_iteration_and_stability_validation(self):
        matrix = np.eye(2)
        measurement = np.array([1.0, -0.5])
        with self.assertRaises(ValueError):
            run("FISTA", matrix, np.array([np.nan, 0.0]), Policy())
        with self.assertRaises(ValueError):
            run("FISTA", np.array([[np.inf, 0.0], [0.0, 1.0]]), measurement, Policy())
        with self.assertRaises(ValueError):
            run("FISTA", matrix, measurement, Policy(regularization=np.nan))
        with self.assertRaises(ValueError):
            run("FISTA", matrix, measurement, Policy(regularization=-0.1))
        with self.assertRaises(ValueError):
            run("FISTA", matrix, measurement, Policy(max_iterations=1.5))
        with self.assertRaises(ValueError):
            run("ADMM", matrix, measurement, Policy(inner_max_iterations=True))
        with self.assertRaisesRegex(ValueError, "FISTA requires"):
            run("FISTA", matrix, measurement, Policy(step_size=1.01))
        with self.assertRaisesRegex(ValueError, "PDHG requires"):
            run("PDHG", matrix, measurement, Policy(step_size=1.0, pd_sigma=1.0))
        # Equality is permitted for the FISTA bound and forbidden for PDHG.
        self.assertEqual(
            run("FISTA", matrix, measurement, Policy(max_iterations=1, step_size=1.0)).status,
            "max_iterations",
        )

    def test_active_quantized_configuration_edges(self):
        matrix = np.eye(2)
        measurement = np.array([0.5, -0.25])
        profile = Profile(Format(8, 4), Format(8, 4), Format(8, 4), 24)
        with self.assertRaisesRegex(ValueError, "step_size quantized to zero"):
            run("FISTA", matrix, measurement, Policy(step_size=0.01), profile)
        with self.assertRaisesRegex(ValueError, "pd_sigma quantized to zero"):
            run(
                "PDHG", matrix, measurement,
                Policy(step_size=0.5, pd_sigma=0.01), profile,
            )
        with self.assertRaisesRegex(ValueError, "admm_rho quantized to zero"):
            run("ADMM", matrix, measurement, Policy(admm_rho=0.01), profile)
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                with self.assertRaisesRegex(
                    ValueError, "regularization threshold quantized to zero"
                ):
                    run(
                        algorithm, matrix, measurement,
                        Policy(
                            regularization=0.01, max_iterations=1,
                            step_size=0.5, pd_sigma=0.5, admm_rho=1.0,
                        ),
                        profile,
                    )
        # Inactive parameters need not be representable by the selected kernel.
        result = run(
            "FISTA", matrix, measurement,
            Policy(
                regularization=0.0, max_iterations=1, step_size=0.5,
                pd_sigma=0.001, admm_rho=0.001,
            ),
            profile,
        )
        self.assertEqual(result.status, "max_iterations")

    def test_admm_strict_inner_cg_failure_does_not_commit(self):
        rng = np.random.default_rng(43)
        matrix = rng.normal(size=(20, 5)) / np.sqrt(20.0)
        measurement = rng.normal(size=20)
        result = run(
            "ADMM", matrix, measurement,
            Policy(
                regularization=0.1, max_iterations=5,
                inner_max_iterations=1, inner_rtol=1e-14,
            ),
        )
        self.assertEqual(result.status, "inner_not_converged")
        self.assertEqual(
            result.trace, [{"phase": "FAULT", "reason": "inner_not_converged"}]
        )
        np.testing.assert_array_equal(result.x, np.zeros(matrix.shape[1]))
        np.testing.assert_array_equal(result.residual, measurement)

    def test_integer_fault_preserves_last_committed_admm_state(self):
        rng = np.random.default_rng(4)
        matrix = rng.normal(size=(5, 4))
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = rng.uniform(-1.0, 1.0, size=5)
        profile = Profile(Format(10, 8), Format(10, 8), Format(10, 8), 23)
        lipschitz = float(np.linalg.norm(matrix, 2) ** 2)
        policy = Policy(
            regularization=0.05, max_iterations=12,
            step_size=0.7 / lipschitz, pd_sigma=0.5,
            inner_max_iterations=32, inner_rtol=1e-2,
        )
        committed = run("ADMM", matrix, measurement, replace(policy, max_iterations=1), profile)
        faulted = run("ADMM", matrix, measurement, policy, profile)
        self.assertEqual(committed.status, "max_iterations")
        self.assertEqual(faulted.status, "numeric_fault")
        self.assertEqual(faulted.trace[-1]["phase"], "FAULT")
        np.testing.assert_array_equal(faulted.x, committed.x)
        np.testing.assert_array_equal(faulted.residual, committed.residual)
        self.assertGreater(faulted.events["saturation"], 0)

    def test_all_integer_algorithms_match_identity_solution(self):
        matrix = np.eye(4)
        measurement = np.array([0.75, 0.05, -0.5, 0.0])
        expected = np.array([0.65, 0.0, -0.4, 0.0])
        profile = Profile(
            Format(24, 18), Format(24, 18), Format(32, 20), 64
        )
        policy = Policy(
            regularization=0.1, max_iterations=100,
            step_size=0.5, pd_sigma=0.5,
            inner_max_iterations=16, inner_rtol=1e-5,
        )
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                result = run(algorithm, matrix, measurement, policy, profile)
                self.assertEqual(result.status, "max_iterations")
                self.assertEqual(len(result.trace), policy.max_iterations)
                self.assertFalse(any(result.events.values()))
                np.testing.assert_allclose(result.x, expected, rtol=0.0, atol=4e-6)
                self.assertEqual(result.support, [0, 2])
                self.assertTrue(
                    all(profile.data.minimum <= raw <= profile.data.maximum
                        for raw in result.raw_x)
                )


if __name__ == "__main__":
    unittest.main()
