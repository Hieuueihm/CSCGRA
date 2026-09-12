"""Conformance tests for the bounded raw conversion cache."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v4 import proximal, recovery  # noqa: E402
from models.v4.fixed import Arithmetic, Format, Profile  # noqa: E402
from scripts.v4.fast_integer_study_cached import cached_accelerated_arithmetic  # noqa: E402


def profile() -> Profile:
    return Profile(Format(18, 14), Format(18, 16), Format(27, 19), 64)


class CachedFastIntegerTests(unittest.TestCase):
    def test_inplace_mutation_changes_pointer_key_and_result(self) -> None:
        p = profile()
        matrix = np.array([[1, 2], [3, 4]], dtype=object)
        vector = np.array([5, -6], dtype=object)
        reference = Arithmetic(p).matvec(matrix, vector, p.coefficient, p.state, p.state)
        with cached_accelerated_arithmetic() as metadata:
            arithmetic = Arithmetic(p)
            first = arithmetic.matvec(matrix, vector, p.coefficient, p.state, p.state)
            matrix[0, 0] = 7
            expected = Arithmetic(p).matvec(matrix, vector, p.coefficient, p.state, p.state)
            second = arithmetic.matvec(matrix, vector, p.coefficient, p.state, p.state)
            self.assertGreaterEqual(metadata["cache"]["stats"]["misses"], 2)
        np.testing.assert_array_equal(first, reference)
        np.testing.assert_array_equal(second, expected)

    def test_same_value_float_or_bool_replacement_does_not_hit_cache(self) -> None:
        p = profile()
        matrix = np.array([[1, 2], [3, 4]], dtype=object)
        vector = np.array([5, -6], dtype=object)
        with cached_accelerated_arithmetic() as metadata:
            arithmetic = Arithmetic(p)
            arithmetic.matvec(matrix, vector, p.coefficient, p.state, p.state)
            matrix[0, 0] = 1.0
            with self.assertRaises(TypeError):
                arithmetic.matvec(matrix, vector, p.coefficient, p.state, p.state)
            matrix[0, 0] = np.bool_(True)
            with self.assertRaises(TypeError):
                arithmetic.matvec(matrix, vector, p.coefficient, p.state, p.state)
            self.assertGreaterEqual(metadata["cache"]["stats"]["bypasses"], 2)

    def test_transpose_strides_and_arbitrary_precision_fallback(self) -> None:
        p = profile()
        source = np.arange(20, dtype=object).reshape(4, 5) - 7
        view = source[:, ::-1]
        vector = np.array([2, -3, 5, -7, 11], dtype=object)
        with cached_accelerated_arithmetic() as metadata:
            fast = Arithmetic(p)
            got = fast.matvec(view, vector, p.coefficient, p.state, p.state)
            expected = Arithmetic(p).matvec(view, vector, p.coefficient, p.state, p.state)
            np.testing.assert_array_equal(got, expected)

            transpose_vector = np.array([2, -3, 5, -7], dtype=object)
            got_t = fast.matvec(view, transpose_vector, p.coefficient, p.state, p.state,
                                transpose=True)
            expected_t = Arithmetic(p).matvec(view, transpose_vector, p.coefficient,
                                               p.state, p.state, transpose=True)
            np.testing.assert_array_equal(got_t, expected_t)
            self.assertGreaterEqual(metadata["cache"]["stats"]["hits"], 1)

        wide = Profile(Format(64, 0), Format(64, 0), Format(64, 0), 128)
        huge_matrix = np.array([[1 << 80, -(1 << 80)]], dtype=object)
        huge_vector = np.array([2, 3], dtype=object)
        expected = Arithmetic(wide).matvec(
            huge_matrix, huge_vector, wide.coefficient, wide.state, wide.state
        )
        with cached_accelerated_arithmetic():
            got = Arithmetic(wide).matvec(
                huge_matrix, huge_vector, wide.coefficient, wide.state, wide.state
            )
        np.testing.assert_array_equal(got, expected)

    def test_lru_eviction_retains_old_snapshot_until_evicted(self) -> None:
        p = profile()
        vector = np.array([1, 1], dtype=object)
        matrices = [
            np.array([[int(str(10000 + i)), int(str(20000 + i))]], dtype=object)
            for i in range(3)
        ]
        with cached_accelerated_arithmetic(cache_limit=2) as metadata:
            arithmetic = Arithmetic(p)
            for matrix in matrices:
                arithmetic.matvec(matrix, vector, p.coefficient, p.state, p.state)
            stats = metadata["cache"]["stats"]
            self.assertEqual(stats["evictions"], 1)
            self.assertEqual(metadata["cache"]["limit"], 2)
            misses_before = stats["misses"]
            arithmetic.matvec(matrices[0], vector, p.coefficient, p.state, p.state)
            self.assertEqual(stats["misses"], misses_before + 1)

    def test_model_results_match_inside_cached_context(self) -> None:
        rng = np.random.default_rng(91)
        matrix = rng.normal(size=(8, 3))
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = matrix @ np.array([0.35, -0.2, 0.1])
        p = profile()
        ls_policy = recovery.Policy(
            sparsity=2, max_iterations=3, residual_atol=1e-6,
            ls_max_iterations=8, ls_normal_rtol=1e-3,
        )
        baseline = recovery.run(
            "OMP", matrix, measurement, ls_policy, p,
            ls_solver="lsqr", solution_format=Format(22, 18),
        )
        prox_policy = proximal.Policy(
            regularization=0.01, max_iterations=2, step_size=0.1,
            admm_rho=1.0, inner_max_iterations=4, inner_rtol=1e-3,
        )
        baseline_prox = proximal.run("ADMM", matrix, measurement, prox_policy, p)
        with cached_accelerated_arithmetic(cache_limit=8):
            fast = recovery.run(
                "OMP", matrix, measurement, ls_policy, p,
                ls_solver="lsqr", solution_format=Format(22, 18),
            )
            fast_prox = proximal.run("ADMM", matrix, measurement, prox_policy, p)
        self.assertEqual((fast.status, fast.support, fast.raw_x),
                         (baseline.status, baseline.support, baseline.raw_x))
        np.testing.assert_array_equal(fast.x, baseline.x)
        np.testing.assert_array_equal(fast.residual, baseline.residual)
        self.assertEqual(fast.events, baseline.events)
        self.assertEqual((fast_prox.status, fast_prox.support, fast_prox.raw_x),
                         (baseline_prox.status, baseline_prox.support, baseline_prox.raw_x))
        np.testing.assert_array_equal(fast_prox.x, baseline_prox.x)
        np.testing.assert_array_equal(fast_prox.residual, baseline_prox.residual)
        self.assertEqual(fast_prox.events, baseline_prox.events)

    def test_cache_limit_validation(self) -> None:
        for value in (0, -1, True, 1.5):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    with cached_accelerated_arithmetic(value):
                        pass


if __name__ == "__main__":
    unittest.main()
