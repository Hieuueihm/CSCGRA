"""Contract tests for per-job power-of-two input normalization."""

from __future__ import annotations

from dataclasses import FrozenInstanceError
from pathlib import Path
import sys
import unittest

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v4.normalization import (  # noqa: E402
    Normalization,
    derive_normalization,
    normalize,
    scale_lasso_lambda,
    scale_residual_atol,
    shift_raw,
)


class NormalizationContractTests(unittest.TestCase):
    def test_round_trip_signs_and_no_mean_subtraction(self) -> None:
        y = np.array([-1.0, 0.25, 0.0, 0.5], dtype=np.float64)
        metadata = derive_normalization(y)
        encoded = metadata.encode(y)

        self.assertTrue(np.allclose(metadata.decode(encoded), y))
        self.assertTrue(np.array_equal(np.sign(encoded), np.sign(y)))
        self.assertGreater(metadata.encoded_peak, 0.25)
        self.assertLessEqual(metadata.encoded_peak, 0.5)
        self.assertAlmostEqual(encoded[0] / encoded[-1], y[0] / y[-1])
        self.assertFalse(np.allclose(encoded, encoded - np.mean(encoded)))
        with self.assertRaises(FrozenInstanceError):
            metadata.exponent = 4  # type: ignore[misc]

    def test_power_of_two_scale_covariance(self) -> None:
        y = np.array([-0.75, 0.125, 0.5], dtype=np.float64)
        encoded_a, metadata_a = normalize(y)
        encoded_b, metadata_b = normalize(8.0 * y)

        self.assertEqual(metadata_b.exponent, metadata_a.exponent - 3)
        self.assertTrue(np.array_equal(encoded_a, encoded_b))
        self.assertTrue(np.allclose(metadata_b.decode(encoded_b), 8.0 * y))

    def test_exact_binary_boundaries_use_open_lower_edge(self) -> None:
        for peak in (0.25, 0.5, 1.0, 2.0):
            metadata = derive_normalization(np.array([peak]))
            self.assertGreater(metadata.encoded_peak, 0.25)
            self.assertLessEqual(metadata.encoded_peak, 0.5)
            self.assertEqual(metadata.encoded_peak, 0.5)

        custom = derive_normalization(np.array([1.0]), target_peak=1.0)
        self.assertGreater(custom.encoded_peak, 0.5)
        self.assertLessEqual(custom.encoded_peak, 1.0)

    def test_zero_and_invalid_inputs(self) -> None:
        zero = np.zeros(4, dtype=np.float64)
        metadata = derive_normalization(zero)
        self.assertEqual(metadata.exponent, 0)
        self.assertEqual(metadata.gain, 1.0)
        self.assertTrue(np.array_equal(metadata.encode(zero), zero))

        for values in ([], [np.nan], [np.inf], [-np.inf]):
            with self.assertRaises(ValueError):
                derive_normalization(values)
        with self.assertRaises(ValueError):
            derive_normalization([1.0], target_peak=0.3)

    def test_bounds_reject_without_clipping(self) -> None:
        with self.assertRaises(ValueError):
            derive_normalization([1e20], exponent_bounds=(-3, 3))
        with self.assertRaises(ValueError):
            derive_normalization([1e-20], exponent_bounds=(-3, 3))

        metadata = derive_normalization([0.1, -0.2])
        expected = np.array([0.1, -0.2]) * metadata.gain
        self.assertTrue(np.array_equal(metadata.encode([0.1, -0.2]), expected))
        self.assertGreater(abs(metadata.encode([0.1, -0.2])[1]), 0.0)

    def test_raw_shift_and_solver_tolerance_scaling(self) -> None:
        self.assertEqual(shift_raw([3, -3, 4, -4], -1).tolist(), [2, -2, 2, -2])
        self.assertEqual(shift_raw([3, -3], 2).tolist(), [12, -12])
        with self.assertRaises(ValueError):
            shift_raw([1.5], 1)

        metadata = derive_normalization([0.25])
        self.assertEqual(metadata.gain, 2.0)
        self.assertEqual(metadata.scale_residual_atol(0.1), 0.2)
        self.assertEqual(metadata.scale_lasso_lambda(0.3), 0.6)
        self.assertEqual(scale_residual_atol(0.1, 2.0), 0.2)
        self.assertEqual(scale_lasso_lambda(0.3, 2.0), 0.6)

    def test_nonfinite_results_are_rejected(self) -> None:
        metadata = Normalization(exponent=1, input_peak=1.0)
        largest = np.finfo(np.float64).max
        with self.assertRaises(ValueError):
            metadata.encode([largest])
        decode_metadata = Normalization(exponent=-1, input_peak=1.0)
        with self.assertRaises(ValueError):
            decode_metadata.decode([largest])
        with self.assertRaises(ValueError):
            scale_residual_atol(2.0, largest)
        with self.assertRaises(ValueError):
            scale_lasso_lambda(2.0, largest)
        with self.assertRaises(ValueError):
            Normalization(exponent=0, input_peak=1.0, target_exponent=1024)


if __name__ == "__main__":
    unittest.main()
