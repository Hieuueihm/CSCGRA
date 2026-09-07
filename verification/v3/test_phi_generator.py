from __future__ import annotations

import unittest

import numpy as np

from models.v3 import hardware, paper, phi_generator


class PhiGeneratorTests(unittest.TestCase):
    def test_random123_known_answer_vectors(self) -> None:
        vectors = (
            ((0x00000000, 0x00000000), (0x00000000, 0x00000000),
             (0x6B200159, 0x99BA4EFE)),
            ((0xFFFFFFFF, 0xFFFFFFFF), (0xFFFFFFFF, 0xFFFFFFFF),
             (0x1CB996FC, 0xBB002BE7)),
            ((0x243F6A88, 0x85A308D3), (0x13198A2E, 0x03707344),
             (0xC4923A9C, 0x483DF7A0)),
        )
        for counter, key, expected in vectors:
            with self.subTest(counter=counter, key=key):
                self.assertEqual(phi_generator.threefry2x32_20(counter, key), expected)

    def test_coordinate_mapping_is_order_independent(self) -> None:
        coordinates = [(row, column) for column in (0, 3, 17, 1023)
                       for row in (0, 31, 32, 63, 64, 127, 255)]
        forward = {
            coordinate: phi_generator.phi_sign(0x0123456789ABCDEF, *coordinate)
            for coordinate in coordinates
        }
        reverse = {
            coordinate: phi_generator.phi_sign(0x0123456789ABCDEF, *coordinate)
            for coordinate in reversed(coordinates)
        }
        self.assertEqual(forward, reverse)

    def test_word_and_scalar_views_match(self) -> None:
        seed = 0xDEADBEEF12345678
        for column in (0, 11, 1023):
            for row_block in range(8):
                word = phi_generator.phi_sign_word(seed, column, row_block)
                for lane in range(32):
                    sign = 1 if ((word >> lane) & 1) else -1
                    self.assertEqual(
                        sign,
                        phi_generator.phi_sign(seed, 32 * row_block + lane, column),
                    )

    def test_materialized_golden_has_exact_bernoulli_amplitude(self) -> None:
        phi = phi_generator.matrix(7, 128, 64)
        np.testing.assert_array_equal(np.unique(phi), np.asarray([-0.125, 0.125]))
        np.testing.assert_allclose(np.sum(phi * phi, axis=0), 2.0, rtol=0, atol=0)

    def test_last_row_block_lane_mask(self) -> None:
        words = list(phi_generator.words_for_column(1, 0, 70))
        self.assertEqual(len(words), 3)
        self.assertEqual(words[0][0], 0xFFFFFFFF)
        self.assertEqual(words[1][0], 0xFFFFFFFF)
        self.assertEqual(words[2][0], 0x0000003F)

    def test_generated_phi_integrates_with_hardware_golden(self) -> None:
        phi = phi_generator.matrix(0x123456789ABCDEF0, 16, 24)
        x = np.zeros(24)
        x[[2, 7, 12, 19]] = [0.5, -0.5, 0.25, -0.25]
        y = phi @ x + np.linspace(-1.0e-4, 1.0e-4, 16)
        policy = paper.Policy(4, 2, residual_atol=0.0, step_size=0.25)
        for name in paper.ALGORITHMS:
            with self.subTest(name=name):
                first = hardware.run(name, phi, y, policy)
                second = hardware.run(name, phi, y, policy)
                self.assertEqual(first, second)

    def test_runtime_scale_rounding_and_saturation(self) -> None:
        cases = (
            (1 << 19, 1 << 17, -3, 1 << 16, False),
            (3, 1 << 17, -1, 2, False),
            (-3, 1 << 17, -1, -2, False),
            ((1 << 40), (1 << 17), 0, (1 << 26) - 1, True),
            (-(1 << 40), (1 << 17), 0, -(1 << 26), True),
        )
        for value, mantissa, exponent, expected, saturated in cases:
            with self.subTest(value=value, exponent=exponent):
                self.assertEqual(
                    phi_generator.runtime_scale_s27(value, mantissa, exponent),
                    (expected, saturated),
                )


if __name__ == "__main__":
    unittest.main()
