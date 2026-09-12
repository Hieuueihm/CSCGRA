import math
import unittest
from fractions import Fraction
from pathlib import Path
import sys

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Arithmetic, Format, Profile


class FixedArithmeticTests(unittest.TestCase):
    def setUp(self):
        self.data = Format(8, 4)
        self.coefficient = Format(7, 5)
        self.state = Format(10, 6)
        self.profile = Profile(self.data, self.coefficient, self.state, 20)
        self.arithmetic = Arithmetic(self.profile)

    def test_format_bounds_validation_and_profile_name(self):
        self.assertEqual(self.data.scale, 16)
        self.assertEqual(self.data.minimum, -128)
        self.assertEqual(self.data.maximum, 127)
        self.assertEqual(self.profile.name, "D8F4_C7F5_S10F6_A20")
        for args in ((0, 0), (-1, 0), (8, -1)):
            with self.assertRaises(ValueError):
                Format(*args)
        with self.assertRaises(TypeError):
            Format(8.0, 4)
        with self.assertRaises(ValueError):
            Profile(self.data, self.coefficient, self.state, 0)

    def test_quantize_ties_signed_min_saturation_and_nonfinite(self):
        raw = self.arithmetic.quantize(
            [Fraction(1, 32), Fraction(-1, 32), Fraction(3, 32), Fraction(-3, 32)],
            self.data,
        )
        self.assertEqual(raw.tolist(), [1, -1, 2, -2])
        extremes = self.arithmetic.quantize([-8, 8], self.data)
        self.assertEqual(extremes.tolist(), [-128, 127])
        self.assertEqual(self.arithmetic.events["saturation"], 1)
        self.assertEqual(self.arithmetic.decode([-128, 127], self.data).tolist(), [-8.0, 7.9375])
        for value in (math.inf, -math.inf, math.nan):
            with self.assertRaises(ValueError):
                self.arithmetic.quantize([value], self.data)

    def test_round_shift_rescale_and_arithmetic(self):
        self.assertEqual(self.arithmetic.round_shift([1, -1, 3, -3], 1).tolist(), [1, -1, 2, -2])
        self.assertEqual(self.arithmetic.round_shift(-3, -2), -12)
        self.assertEqual(self.arithmetic.rescale(24, 5, self.data), 12)
        self.assertEqual(self.arithmetic.add(120, 20, self.data), 127)
        self.assertEqual(self.arithmetic.sub(-120, 20, self.data), -128)
        self.assertEqual(self.arithmetic.mul(-3, 5, Format(5, 1), Format(5, 2), Format(8, 2)), -8)

    def test_array_broadcasting_uses_object_integers(self):
        result = self.arithmetic.add(np.array([1, 2], dtype=object), 3, self.data)
        self.assertEqual(result.dtype, object)
        self.assertEqual(result.tolist(), [4, 5])
        huge = 1 << 80
        wide = Format(100, 0)
        self.assertEqual(self.arithmetic.mul(huge, 2, wide, wide, wide), 1 << 81)

    def test_dot_accumulates_exactly_and_narrows_once(self):
        # The large positive and negative terms cancel before accumulator narrowing.
        raw = self.arithmetic.dot_raw(
            np.array([1 << 30, 1 << 30], dtype=object),
            np.array([1 << 30, -(1 << 30)], dtype=object),
        )
        self.assertEqual(raw, 0)
        self.assertEqual(self.arithmetic.events["accumulator_overflow"], 0)
        self.assertEqual(self.arithmetic.dot([3, -5], [7, 2], Format(8, 2), Format(8, 3), Format(12, 4)), 6)

    def test_long_dot_saturates_accumulator_without_wrap(self):
        narrow = Arithmetic(Profile(self.data, self.coefficient, self.state, 8))
        self.assertEqual(narrow.dot_raw([100] * 20, [100] * 20), 127)
        self.assertEqual(narrow.events["accumulator_overflow"], 1)
        self.assertEqual(narrow.dot_raw([-100] * 20, [100] * 20), -128)
        self.assertEqual(narrow.events["accumulator_overflow"], 2)

    def test_ratio_fraction_scaling_ties_saturation_and_zero(self):
        out = Format(8, 3)
        # source_frac=2 means the raw quotient already represents quarters.
        self.assertEqual(self.arithmetic.ratio(3, 2, 2, out), 3)
        self.assertEqual(self.arithmetic.ratio(-3, 2, 2, out), -3)
        self.assertEqual(self.arithmetic.ratio(1, 3, -1, out), 5)
        self.assertEqual(self.arithmetic.ratio(10_000, 1, 0, out), out.maximum)
        self.assertEqual(self.arithmetic.ratio(7, 0, 0, out), 0)
        self.assertEqual(self.arithmetic.events["divide_by_zero"], 1)

    def test_matvec_and_transpose(self):
        matrix = np.array([[2, -1], [3, 4]], dtype=object)
        vector = np.array([5, 2], dtype=object)
        fmt = Format(12, 0)
        self.assertEqual(
            self.arithmetic.matvec(matrix, vector, fmt, fmt, fmt).tolist(),
            [8, 23],
        )
        self.assertEqual(
            self.arithmetic.matvec(matrix, vector, fmt, fmt, fmt, transpose=True).tolist(),
            [16, 3],
        )


if __name__ == "__main__":
    unittest.main()
