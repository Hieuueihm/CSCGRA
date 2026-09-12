"""Independent behavioral tests for the v4 recovery programs.

The v3 module imported here is an independent NumPy test oracle.  Production
v4 code has no dependency on it.
"""

from pathlib import Path
import sys
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Format, Profile
from models.v4.recovery import ALGORITHMS, Policy, run
from verification.v3.independent_float_oracle import run as oracle_run


def normalized_random(rows, columns, seed):
    rng = np.random.default_rng(seed)
    matrix = rng.normal(size=(rows, columns))
    return matrix / np.linalg.norm(matrix, axis=0)


class RecoveryTests(unittest.TestCase):
    def assert_matches_oracle(self, algorithm, matrix, measurement, policy):
        actual = run(algorithm, matrix, measurement, policy)
        expected = oracle_run(algorithm, matrix, measurement, policy)
        self.assertEqual(actual.support, list(expected.support), algorithm)
        self.assertEqual(actual.status, expected.stop_reason, algorithm)
        np.testing.assert_allclose(actual.x, expected.x, rtol=2e-13, atol=2e-13)
        np.testing.assert_allclose(
            actual.residual, expected.residual, rtol=2e-13, atol=2e-13
        )
        np.testing.assert_allclose(
            actual.residual, measurement - matrix @ actual.x, rtol=2e-13, atol=2e-13
        )

    def test_all_float_algorithms_match_oracle_on_identity(self):
        matrix = np.eye(6)
        truth = np.array([0.0, 0.75, 0.0, 0.0, -0.5, 0.0])
        policy = Policy(
            sparsity=2, max_iterations=8, residual_atol=1e-10, step_size=0.5
        )
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                self.assert_matches_oracle(
                    algorithm, matrix, matrix @ truth, policy
                )

    def test_all_float_algorithms_match_oracle_on_normalized_random_matrix(self):
        matrix = normalized_random(8, 12, seed=41)
        # The row-space condition number is bounded, avoiding an accidental
        # ill-conditioned regression fixture.
        self.assertLess(np.linalg.cond(matrix @ matrix.T), 8.0)
        truth = np.zeros(12)
        truth[[1, 6]] = [1.1, -0.8]
        policy = Policy(
            sparsity=2, max_iterations=8, residual_atol=1e-10, step_size=0.5
        )
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                self.assert_matches_oracle(
                    algorithm, matrix, matrix @ truth, policy
                )

    def test_zero_measurement_is_a_no_op_for_all_algorithms(self):
        matrix = normalized_random(5, 8, seed=7)
        measurement = np.zeros(5)
        policy = Policy(sparsity=2, max_iterations=4)
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                result = run(algorithm, matrix, measurement, policy)
                self.assertEqual(result.status, "residual_tolerance")
                self.assertEqual(result.support, [])
                np.testing.assert_array_equal(result.x, np.zeros(8))
                np.testing.assert_array_equal(result.residual, measurement)
                self.assertFalse(any(item["phase"] == "COMMIT" for item in result.trace))

    def test_rank_deficient_float_least_squares_matches_oracle(self):
        # Columns zero and one are identical, and CoSaMP sends both to lstsq.
        matrix = np.array(
            [[1.0, 1.0, 0.0, 0.2], [0.0, 0.0, 1.0, 0.3], [0.0, 0.0, 0.0, 0.9]]
        )
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = np.array([0.7, -0.2, 0.4])
        policy = Policy(sparsity=2, max_iterations=2, residual_atol=0.0)
        result = run("CoSaMP", matrix, measurement, policy)
        self.assertTrue(any(len(item.get("support", [])) == 4
                            for item in result.trace if item["phase"] == "LS"))
        self.assert_matches_oracle("CoSaMP", matrix, measurement, policy)

    def test_cosamp_does_not_refit_after_pruning(self):
        matrix = np.eye(6)
        measurement = np.array([0.8, -0.5, 0.1, 0.05, 0.0, 0.0])
        result = run(
            "CoSaMP", matrix, measurement,
            Policy(sparsity=2, max_iterations=1, residual_atol=0.0),
        )
        phases = [item["phase"] for item in result.trace]
        self.assertEqual(phases, ["LS", "PRUNE", "COMMIT"])
        self.assertEqual(len(result.trace[0]["support"]), 4)
        self.assertEqual(len(result.trace[1]["support"]), 2)

    def test_sp_rolls_back_atomically_and_honors_disabled_stop(self):
        rng = np.random.default_rng(0)
        matrix = rng.normal(size=(5, 8))
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = rng.normal(size=5)
        one_iteration = run(
            "SP", matrix, measurement,
            Policy(sparsity=2, max_iterations=1, residual_atol=0.0),
        )
        rollback = run(
            "SP", matrix, measurement,
            Policy(sparsity=2, max_iterations=6, residual_atol=0.0),
        )
        self.assertEqual(rollback.status, "residual_not_decreased")
        self.assertEqual(rollback.trace[-1]["phase"], "ROLLBACK")
        self.assertEqual(rollback.support, one_iteration.support)
        np.testing.assert_array_equal(rollback.x, one_iteration.x)
        np.testing.assert_array_equal(rollback.residual, one_iteration.residual)

        disabled = run(
            "SP", matrix, measurement,
            Policy(
                sparsity=2, max_iterations=6, residual_atol=0.0,
                sp_stop_on_non_decrease=False,
            ),
        )
        self.assertNotIn("ROLLBACK", [item["phase"] for item in disabled.trace])
        self.assertEqual(disabled.status, "max_iterations")

    def test_integer_fault_preserves_last_committed_state(self):
        rng = np.random.default_rng(3)
        matrix = rng.normal(size=(5, 7))
        matrix /= np.linalg.norm(matrix, axis=0)
        truth = np.zeros(7)
        truth[[1, 4]] = [rng.uniform(0.2, 1.5), rng.uniform(-1.5, -0.2)]
        measurement = matrix @ truth
        profile = Profile(Format(8, 6), Format(8, 6), Format(8, 6), 18)
        common = dict(
            sparsity=2, residual_atol=0.0, step_size=0.8,
            ls_max_iterations=32, ls_normal_rtol=1e-2,
        )
        committed = run("GP", matrix, measurement, Policy(max_iterations=6, **common), profile)
        faulted = run("GP", matrix, measurement, Policy(max_iterations=10, **common), profile)
        self.assertEqual(committed.status, "max_iterations")
        self.assertEqual(faulted.status, "numeric_fault")
        self.assertEqual(faulted.trace[-1]["phase"], "FAULT")
        self.assertEqual(faulted.support, committed.support)
        np.testing.assert_array_equal(faulted.x, committed.x)
        np.testing.assert_array_equal(faulted.residual, committed.residual)
        self.assertGreater(faulted.events["saturation"], 0)

    def test_strict_integer_ls_failure_is_reported(self):
        matrix = normalized_random(5, 7, seed=0)
        truth = np.zeros(7)
        truth[[1, 4]] = [0.7, -0.5]
        profile = Profile(Format(10, 6), Format(8, 6), Format(10, 6), 18)
        result = run(
            "OMP", matrix, matrix @ truth,
            Policy(
                sparsity=2, max_iterations=10, residual_atol=1e-4,
                ls_max_iterations=2, ls_normal_rtol=1e-8,
            ),
            profile,
        )
        self.assertEqual(result.status, "ls_not_converged")
        self.assertEqual(result.trace[-1], {"phase": "FAULT", "reason": "ls_not_converged"})
        self.assertFalse(any(result.events.values()))

    def test_mp_and_gp_allow_reselection_and_match_oracle(self):
        rng = np.random.default_rng(0)
        matrix = rng.normal(size=(5, 8))
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = rng.normal(size=5)
        policy = Policy(sparsity=2, max_iterations=12, residual_atol=0.0, step_size=0.4)
        for algorithm in ("MP", "GP"):
            with self.subTest(algorithm=algorithm):
                result = run(algorithm, matrix, measurement, policy)
                commits = [item for item in result.trace if item["phase"] == "COMMIT"]
                self.assertLess(len(result.support), len(commits))
                self.assert_matches_oracle(algorithm, matrix, measurement, policy)

    def test_gomp_stops_at_paper_capacity(self):
        matrix = normalized_random(5, 10, seed=12)
        measurement = np.random.default_rng(91).normal(size=5)
        policy = Policy(
            sparsity=4, group_size=2, max_iterations=20, residual_atol=0.0
        )
        result = run("GOMP", matrix, measurement, policy)
        capacity = policy.group_size * min(
            policy.sparsity, matrix.shape[0] // policy.group_size
        )
        self.assertEqual(result.status, "paper_iteration_limit")
        self.assertEqual(len(result.support), capacity)
        self.assertEqual(len(set(result.support)), capacity)
        self.assert_matches_oracle("GOMP", matrix, measurement, policy)

    def test_all_integer_algorithms_are_sane_on_exact_identity_case(self):
        matrix = np.eye(4)
        measurement = np.array([0.75, 0.0, -0.5, 0.0])
        profile = Profile(
            data=Format(24, 18), coefficient=Format(24, 18),
            state=Format(32, 20), accumulator_width=64,
        )
        policy = Policy(
            sparsity=2, max_iterations=8, residual_atol=1e-5,
            step_size=0.5, ls_max_iterations=64,
        )
        initial_energy = float(measurement @ measurement)
        for algorithm in ALGORITHMS:
            with self.subTest(algorithm=algorithm):
                result = run(algorithm, matrix, measurement, policy, profile)
                self.assertNotIn(result.status, {"numeric_fault", "ls_not_converged"})
                self.assertFalse(any(result.events.values()))
                self.assertTrue(np.all(np.isfinite(result.x)))
                self.assertLessEqual(float(result.residual @ result.residual), initial_energy)
                self.assertEqual(len(result.raw_x), matrix.shape[1])
                self.assertTrue(all(profile.data.minimum <= value <= profile.data.maximum
                                    for value in result.raw_x))


if __name__ == "__main__":
    unittest.main()
