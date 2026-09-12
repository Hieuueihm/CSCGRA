from __future__ import annotations

from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from models.v4.fixed import Format, Profile
from models.v4.generated_operator import (
    GeneratedOperator,
    SignCache8Banks,
    bank_conflict_report,
    generated_matrix,
    phi_sign,
    phi_sign_word,
    quantized_scale,
    request_schedule,
    threefry2x32_20,
)


class GeneratedOperatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.profile = Profile(Format(18, 14), Format(18, 16), Format(27, 19), 64)

    def test_random123_known_answer_vectors(self) -> None:
        vectors = (
            ((0x00000000, 0x00000000), (0x00000000, 0x00000000), (0x6B200159, 0x99BA4EFE)),
            ((0xFFFFFFFF, 0xFFFFFFFF), (0xFFFFFFFF, 0xFFFFFFFF), (0x1CB996FC, 0xBB002BE7)),
            ((0x243F6A88, 0x85A308D3), (0x13198A2E, 0x03707344), (0xC4923A9C, 0x483DF7A0)),
        )
        for counter, key, expected in vectors:
            self.assertEqual(threefry2x32_20(counter, key), expected)

    def test_matrix_is_coordinate_addressable_and_scale_is_explicit(self) -> None:
        seed = 0x0123456789ABCDEF
        matrix = generated_matrix(seed, 37, 19, 0.125)
        self.assertEqual(matrix.shape, (37, 19))
        np.testing.assert_array_equal(np.unique(matrix), np.asarray([-0.125, 0.125]))
        for row, column in ((0, 0), (31, 3), (32, 3), (36, 18)):
            self.assertEqual(matrix[row, column], 0.125 * phi_sign(seed, row, column))

    def test_cache_geometry_padding_and_both_orientations(self) -> None:
        operator = GeneratedOperator(47, 70, 19, scale=0.125)
        cache = SignCache8Banks.build(operator)
        self.assertEqual(len(cache.banks), 8)
        self.assertEqual(cache.words_per_bank, 3 * 3)
        cache.validate()
        np.testing.assert_array_equal(cache.unpack_matrix("A"), operator.matrix())
        np.testing.assert_array_equal(cache.unpack_matrix("transpose_A"), operator.matrix().T)
        self.assertEqual(cache.lookup(3, 11), operator.matrix()[3, 11])
        self.assertEqual(cache.lookup(11, 3, orientation="transpose_A"), operator.matrix()[3, 11])
        self.assertTrue(all(word == 0 for word in cache.banks[3][6:]))
        self.assertEqual(cache.word(18, 2) & ~((1 << 6) - 1), 0)

    def test_pack_unpack_and_tamper_detection(self) -> None:
        operator = GeneratedOperator(101, 65, 17, scale=1 / 8)
        cache = SignCache8Banks.build(operator)
        restored = SignCache8Banks.unpack(operator, cache.pack())
        self.assertEqual(restored.pack(), cache.pack())
        bad = [list(bank) for bank in cache.pack()]
        bad[0][0] ^= 1
        with self.assertRaisesRegex(ValueError, "does not match"):
            SignCache8Banks.unpack(operator, bad)

    def test_support_order_and_common_quantization(self) -> None:
        operator = GeneratedOperator(23, 9, 13, scale=0.125)
        cache = operator.cache()
        support = (11, 2, 7)
        expected = operator.raw_matrix(self.profile)[:, support]
        np.testing.assert_array_equal(cache.support_matrix(support, self.profile), expected)
        self.assertEqual(quantized_scale(0.125, self.profile), 8192)
        self.assertEqual(set(np.unique(expected).tolist()), {-8192, 8192})

    def test_raw_gemv_matches_independent_integer_sums_and_transpose(self) -> None:
        operator = GeneratedOperator(23, 37, 19, scale=0.125)
        cache = operator.cache()
        x = [(-7 * index + 3) for index in range(operator.columns)]
        y = cache.raw_gemv(x, self.profile, accumulator_width=64)
        expected = np.asarray(
            [sum(operator.raw_coefficient(row, col, self.profile) * x[col]
                 for col in range(operator.columns)) for row in range(operator.rows)],
            dtype=object,
        )
        np.testing.assert_array_equal(y, expected)
        residual = [index - 17 for index in range(operator.rows)]
        yt = cache.raw_gemv(residual, self.profile, transpose=True, accumulator_width=64)
        expected_t = np.asarray(
            [sum(operator.raw_coefficient(row, col, self.profile) * residual[row]
                 for row in range(operator.rows)) for col in range(operator.columns)],
            dtype=object,
        )
        np.testing.assert_array_equal(yt, expected_t)

    def test_prefix_overflow_is_checked_before_final_narrowing(self) -> None:
        operator = GeneratedOperator(23, 1, 2, scale=1 / 8)
        cache = operator.cache()
        # Select a vector that produces a large first prefix and cancellation.
        vector = [100, -100]
        with self.assertRaises(OverflowError):
            cache.raw_gemv(vector, self.profile, accumulator_width=12)

    def test_r1_r4_tail_masks_and_conflict_report(self) -> None:
        r1 = request_schedule(70, 19, "R1forward32outputs")
        self.assertEqual(len(r1), 3 * 19)
        self.assertEqual(r1[-1]["row_mask"], (1 << 6) - 1)
        self.assertTrue(r1.conflict_report["conflict_free"])
        r4 = request_schedule(70, 19, "R4transpose8outputs4reductionlanes")
        self.assertTrue(r4.conflict_report["conflict_free"])
        tail = [request for request in r4 if request["row"] >= 64]
        self.assertTrue(tail)
        self.assertTrue(any(not request["row_valid"] for request in tail))
        self.assertEqual(tail[-1]["k"], 95)
        report = bank_conflict_report((
            {"cycle": 1, "bank": 0}, {"cycle": 1, "bank": 0},
        ))
        self.assertEqual(report["conflict_count"], 1)


if __name__ == "__main__":
    unittest.main()
