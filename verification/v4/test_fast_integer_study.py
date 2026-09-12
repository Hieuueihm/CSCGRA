"""Conformance checks for guarded study-only integer acceleration."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v4.fixed import Arithmetic, Format, Profile  # noqa: E402
from models.v4 import proximal, recovery  # noqa: E402
from scripts.v4.fast_integer_study import accelerated_arithmetic  # noqa: E402


def profile() -> Profile:
    return Profile(Format(18, 14), Format(18, 16), Format(27, 19), 64)


def dot_reference(arithmetic, left, right):
    return Arithmetic.dot_raw(arithmetic, left, right)


class FastIntegerStudyTests(unittest.TestCase):
    def test_context_restores_class_primitives(self) -> None:
        original_round_shift = Arithmetic.round_shift
        original_dot_raw = Arithmetic.dot_raw
        original_matvec = Arithmetic.matvec
        original_unary = Arithmetic.__dict__["_unary_int_map"]
        original_binary = Arithmetic.__dict__["_binary_int_map"]
        with accelerated_arithmetic() as metadata:
            self.assertEqual(metadata["methods"], ["round_shift", "dot_raw", "matvec"])
            self.assertIsNot(Arithmetic.round_shift, original_round_shift)
            self.assertIsNot(Arithmetic.dot_raw, original_dot_raw)
            self.assertIsNot(Arithmetic.matvec, original_matvec)
            self.assertIsInstance(Arithmetic.__dict__["_unary_int_map"], classmethod)
            self.assertIsInstance(Arithmetic.__dict__["_binary_int_map"], classmethod)
        self.assertIs(Arithmetic.round_shift, original_round_shift)
        self.assertIs(Arithmetic.dot_raw, original_dot_raw)
        self.assertIs(Arithmetic.matvec, original_matvec)
        self.assertIs(Arithmetic.__dict__["_unary_int_map"], original_unary)
        self.assertIs(Arithmetic.__dict__["_binary_int_map"], original_binary)

    def test_scalar_dispatch_and_array_fallback_match_reference(self) -> None:
        unary = lambda value: value * 3 - 1
        binary = lambda left, right: left * right + left - right
        reference_unary = Arithmetic._unary_int_map
        reference_binary = Arithmetic._binary_int_map
        scalar_values = (3, np.int64(-4))
        with accelerated_arithmetic():
            for value in scalar_values:
                self.assertEqual(Arithmetic._unary_int_map(value, unary),
                                 reference_unary(value, unary))
                self.assertIsInstance(Arithmetic._unary_int_map(value, unary), int)
            self.assertEqual(Arithmetic._binary_int_map(np.int64(3), -4, binary),
                             reference_binary(np.int64(3), -4, binary))
            self.assertIsInstance(Arithmetic._binary_int_map(3, -4, binary), int)
            for value in (np.array(3, dtype=np.int64), np.array([3, -4], dtype=object)):
                np.testing.assert_array_equal(
                    Arithmetic._unary_int_map(value, unary), reference_unary(value, unary)
                )
            left = np.array([3, -4], dtype=object)
            right = np.array([[2], [5]], dtype=object)
            np.testing.assert_array_equal(
                Arithmetic._binary_int_map(left, right, binary),
                reference_binary(left, right, binary),
            )
            with self.assertRaises(TypeError):
                Arithmetic._unary_int_map(True, unary)
            with self.assertRaises(TypeError):
                Arithmetic._binary_int_map(1, np.bool_(False), binary)

    def test_round_shift_ties_signs_and_unsafe_fallback_match(self) -> None:
        arithmetic = Arithmetic(profile())
        values = np.array([-9, -7, -5, -3, -1, 0, 1, 3, 5, 7, 9], dtype=object)
        for shift in (-3, -1, 0, 1, 2, 3):
            expected = Arithmetic.round_shift(values, shift)
            with accelerated_arithmetic():
                got = Arithmetic.round_shift(values, shift)
            np.testing.assert_array_equal(got, expected)
        huge = np.array([1 << 100, -(1 << 100), 3], dtype=object)
        expected = Arithmetic.round_shift(huge, -4)
        with accelerated_arithmetic():
            got = Arithmetic.round_shift(huge, -4)
        np.testing.assert_array_equal(got, expected)
        self.assertEqual(int(arithmetic.round_shift(-3, 1)), -2)

    def test_dot_and_matvec_match_events_overflow_and_nonsquare_transpose(self) -> None:
        p = Profile(Format(8, 0), Format(8, 0), Format(8, 0), 8)
        left = np.array([100, 100], dtype=object)
        right = np.array([1, 1], dtype=object)
        baseline = Arithmetic(p)
        expected_dot = baseline.dot_raw(left, right)
        with accelerated_arithmetic():
            fast = Arithmetic(p)
            got_dot = fast.dot_raw(left, right)
        self.assertEqual(got_dot, expected_dot)
        self.assertEqual(fast.events, baseline.events)

        matrix = np.array([[100, 100, 0], [-100, -100, 0]], dtype=object)
        vector = np.array([1, 1, 0], dtype=object)
        baseline = Arithmetic(p)
        expected = baseline.matvec(matrix, vector, p.coefficient, p.state, p.state)
        with accelerated_arithmetic():
            fast = Arithmetic(p)
            got = fast.matvec(matrix, vector, p.coefficient, p.state, p.state)
        np.testing.assert_array_equal(got, expected)
        self.assertEqual(fast.events, baseline.events)

        matrix = np.array([[1, -2], [3, 4], [-5, 6]], dtype=object)
        vector = np.array([7, -8, 9], dtype=object)
        baseline = Arithmetic(p)
        expected = baseline.matvec(matrix, vector, p.coefficient, p.state, p.state, transpose=True)
        with accelerated_arithmetic():
            fast = Arithmetic(p)
            got = fast.matvec(matrix, vector, p.coefficient, p.state, p.state, transpose=True)
        np.testing.assert_array_equal(got, expected)
        self.assertEqual(fast.events, baseline.events)

    def test_unsafe_product_falls_back_without_wrap(self) -> None:
        p = Profile(Format(64, 0), Format(64, 0), Format(64, 0), 128)
        left = np.array([1 << 62, 1 << 62], dtype=object)
        right = np.array([2, 2], dtype=object)
        baseline = Arithmetic(p)
        expected = baseline.dot_raw(left, right)
        with accelerated_arithmetic():
            fast = Arithmetic(p)
            got = fast.dot_raw(left, right)
        self.assertEqual(got, expected)
        self.assertEqual(fast.events, baseline.events)

        matrix = np.array([[1 << 62, 1 << 62]], dtype=object)
        baseline = Arithmetic(p)
        expected = baseline.matvec(matrix, right, p.coefficient, p.state, p.state)
        with accelerated_arithmetic():
            fast = Arithmetic(p)
            got = fast.matvec(matrix, right, p.coefficient, p.state, p.state)
        np.testing.assert_array_equal(got, expected)
        self.assertEqual(fast.events, baseline.events)

    def test_lsqr_omp_and_fista_results_match(self) -> None:
        rng = np.random.default_rng(17)
        matrix = rng.normal(size=(8, 3))
        matrix /= np.linalg.norm(matrix, axis=0)
        measurement = matrix @ np.array([0.35, -0.2, 0.1])
        p = profile()
        ls_policy = recovery.Policy(
            sparsity=2, max_iterations=4, residual_atol=1e-6,
            ls_max_iterations=16, ls_normal_rtol=1e-3,
        )
        baseline = recovery.run(
            "OMP", matrix, measurement, ls_policy, p,
            ls_solver="lsqr", solution_format=Format(22, 18),
        )
        with accelerated_arithmetic():
            fast = recovery.run(
                "OMP", matrix, measurement, ls_policy, p,
                ls_solver="lsqr", solution_format=Format(22, 18),
            )
        self.assertEqual(fast.status, baseline.status)
        self.assertEqual(fast.support, baseline.support)
        np.testing.assert_array_equal(fast.x, baseline.x)
        np.testing.assert_array_equal(fast.residual, baseline.residual)
        self.assertEqual(fast.events, baseline.events)
        self.assertEqual(fast.raw_x, baseline.raw_x)

        prox_policy = proximal.Policy(
            regularization=0.01, max_iterations=3, step_size=0.1,
            inner_max_iterations=8, inner_rtol=1e-3,
        )
        baseline = proximal.run("FISTA", matrix, measurement, prox_policy, p)
        with accelerated_arithmetic():
            fast = proximal.run("FISTA", matrix, measurement, prox_policy, p)
        self.assertEqual(fast.status, baseline.status)
        self.assertEqual(fast.support, baseline.support)
        np.testing.assert_array_equal(fast.x, baseline.x)
        np.testing.assert_array_equal(fast.residual, baseline.residual)
        self.assertEqual(fast.events, baseline.events)
        self.assertEqual(fast.raw_x, baseline.raw_x)


if __name__ == "__main__":
    unittest.main()
