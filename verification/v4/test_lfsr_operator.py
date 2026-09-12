import unittest

import numpy as np

from models.v4.lfsr_operator import (
    DEFAULT_SEED,
    LFSR32_MAX_STREAM_INDEX,
    TAPS,
    galois_step,
    generator_quality,
    indexed_sign,
    lfsr32_advance,
    lfsr32_matrix,
    operator_identity,
)


class LfsrOperatorTests(unittest.TestCase):
    def test_v2_step_and_zero_seed_substitution(self):
        self.assertEqual(galois_step(0x1), 0x80200003)
        self.assertEqual(galois_step(0x0), 0x0)
        np.testing.assert_array_equal(
            lfsr32_matrix(0, 3, 5), lfsr32_matrix(DEFAULT_SEED, 3, 5)
        )
        self.assertEqual(TAPS, 0x80200003)

    def test_indexed_jump_matches_sequential_stream(self):
        seeds = (0, 1, DEFAULT_SEED, 0x12345678, 0xFFFFFFFF)
        shapes = ((1, 1), (3, 5), (37, 67), (128, 1024))
        for seed in seeds:
            for rows, columns in shapes:
                matrix = lfsr32_matrix(seed, rows, columns)
                state = DEFAULT_SEED if seed == 0 else seed
                selected = {
                    (0, 0),
                    (rows - 1, columns - 1),
                    (rows // 2, columns // 2),
                    (0, columns - 1),
                    (rows - 1, 0),
                }
                if rows * columns <= 256:
                    selected.update(
                        (row, column)
                        for column in range(columns)
                        for row in range(rows)
                    )
                for column in range(columns):
                    for row in range(rows):
                        if (row, column) in selected:
                            expected = 1 if state & 1 else -1
                            self.assertEqual(indexed_sign(seed, rows, row, column), expected)
                            self.assertEqual(matrix[row, column], expected)
                        state = galois_step(state)

    def test_jump_ahead_matches_direct_steps(self):
        for seed in (0, 1, 0x12345678, 0xFFFFFFFF):
            for steps in (0, 1, 2, 31, 32, 63, 64, 127, 1000):
                expected = DEFAULT_SEED if seed == 0 else seed
                for _ in range(steps):
                    expected = galois_step(expected)
                self.assertEqual(lfsr32_advance(seed, steps), expected)

    def test_shape_identity_scale_and_quality(self):
        matrix = lfsr32_matrix(7, 9, 11, scale=0.25)
        self.assertEqual(matrix.shape, (9, 11))
        self.assertEqual(matrix.dtype, np.float64)
        self.assertTrue(np.all(np.isin(matrix, (-0.25, 0.25))))
        identity = operator_identity(0, 9, 11, 0.25)
        self.assertEqual(identity["shape"], [9, 11])
        self.assertEqual(identity["seed"], DEFAULT_SEED)
        self.assertEqual(identity["seed_input"], 0)
        self.assertEqual(identity["stream_index"], "column * rows + row")
        quality = generator_quality(matrix)
        self.assertEqual(quality["shape"], [9, 11])
        self.assertIn("mutual_coherence", quality)
        self.assertIn("duplicate_column_count", quality)
        self.assertIn("negated_column_count", quality)

    def test_scale_validation(self):
        for scale in (0, -1, float("nan"), float("inf"), True):
            with self.subTest(scale=scale):
                with self.assertRaises((TypeError, ValueError)):
                    lfsr32_matrix(1, 2, 2, scale=scale)

    def test_counter_limit_rejects_wrap(self):
        with self.assertRaises(ValueError):
            lfsr32_matrix(1, LFSR32_MAX_STREAM_INDEX + 1, 1)
        with self.assertRaises(ValueError):
            indexed_sign(1, LFSR32_MAX_STREAM_INDEX + 1, 0, 1)
        with self.assertRaises(ValueError):
            indexed_sign(1, 1, 0, LFSR32_MAX_STREAM_INDEX + 1)


if __name__ == "__main__":
    unittest.main()
