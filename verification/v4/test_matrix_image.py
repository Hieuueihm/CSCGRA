"""Contract tests for host construction and resident matrix images."""
from dataclasses import replace
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from compiler.v4.mapping import MatrixLayout
from compiler.v4.matrix_image import (
    build_composed_matrix_image,
    build_matrix_image,
    compose_operator,
    parse_signed_hex,
    read_matrix_image,
    signed_hex,
    unpack_orientation,
)
from models.v4.fixed import Arithmetic, Format, Profile


class MatrixImageTests(unittest.TestCase):
    def setUp(self):
        self.profile = Profile(Format(12, 4), Format(8, 4), Format(16, 6), 32)
        self.physical = np.array([
            [0.5, -0.25, 0.125, -0.375, 0.0625],
            [-0.5, 0.3125, -0.1875, 0.25, -0.125],
            [0.25, 0.4375, -0.3125, 0.1875, 0.5],
        ])

    def test_composed_a_matches_raw_measurement_identity_and_quantizes_once(self):
        phi = np.eye(3)
        psi = self.physical
        self.assertTrue(np.array_equal(compose_operator(phi, psi), psi))
        image = build_composed_matrix_image(
            phi, psi, self.profile, source_domain="raw_measurement",
            source_tag="identity-phi",
        )
        expected = Arithmetic(self.profile).quantize(psi, self.profile.coefficient)
        self.assertEqual(image.raw_matrix, tuple(tuple(row) for row in expected.tolist()))
        self.assertEqual(image.unpack("A"), image.raw_matrix)

    def test_exact_transpose_and_both_signs_non_power_of_two_shape(self):
        image = build_matrix_image(
            self.physical, self.profile, source_domain="physical", source_tag="case-3x5"
        )
        self.assertEqual(image.rows, 3)
        self.assertEqual(image.columns, 5)
        self.assertEqual(image.unpack("transpose_A"), tuple(zip(*image.raw_matrix)))
        self.assertTrue(any(value < 0 for value in image.raw_matrix[0]))
        self.assertTrue(any(value > 0 for value in image.raw_matrix[0]))
        image.validate()

    def test_signed_hex_roundtrip_and_width_rejection(self):
        fmt = self.profile.coefficient
        for value in (fmt.minimum, -1, 0, 1, fmt.maximum):
            self.assertEqual(parse_signed_hex(signed_hex(value, fmt), fmt), value)
        with self.assertRaises(ValueError):
            signed_hex(fmt.maximum + 1, fmt)
        with self.assertRaises(ValueError):
            parse_signed_hex("000", fmt)

    def test_saturation_and_zero_column_are_load_errors(self):
        with self.assertRaisesRegex(ValueError, "saturated"):
            build_matrix_image(
                np.array([[100.0, 0.25], [0.5, -0.25]]), self.profile,
                source_domain="raw", source_tag="saturated",
            )
        zero_column = self.physical.copy()
        zero_column[:, 2] = 0.0
        with self.assertRaisesRegex(ValueError, "zero column"):
            build_matrix_image(
                zero_column, self.profile, source_domain="raw", source_tag="zero-col"
            )
        tiny_column = self.physical.copy()
        tiny_column[:, 2] = 1e-6
        with self.assertRaisesRegex(ValueError, "zero column"):
            build_matrix_image(
                tiny_column, self.profile, source_domain="raw", source_tag="rounded-col"
            )

    def test_tail_is_explicit_zero_and_uninitialized_or_corrupt_tail_rejected(self):
        image = build_matrix_image(
            self.physical, self.profile, source_domain="raw", source_tag="tail"
        )
        layout = MatrixLayout(image.rows, image.columns)
        # 3 outputs leave one padded output in the final group; every tail cell
        # is explicit zero in the resident representation.
        self.assertTrue(all(value == 0 for value in image.forward_banks[3]))
        valid = [list(bank) for bank in image.forward_banks]
        bank, address = layout.address(0, 0)
        valid[bank][address] = None
        with self.assertRaisesRegex(ValueError, "uninitialized"):
            unpack_orientation(valid, layout, image.coefficient_format)
        # MatrixLayout.address intentionally rejects padded output.  Bank 3
        # has no valid output for this 3x5 shape and is entirely tail.
        valid = [list(bank_values) for bank_values in image.forward_banks]
        valid[3][0] = 1
        with self.assertRaisesRegex(ValueError, "tail"):
            unpack_orientation(valid, layout, image.coefficient_format)

    def test_export_import_manifest_and_corruption_checks(self):
        image = build_matrix_image(
            self.physical, self.profile, source_domain="raw", source_tag="export"
        )
        with tempfile.TemporaryDirectory() as temp:
            destination = Path(temp)
            manifest = image.write_bank_images(destination)
            loaded = read_matrix_image(destination, self.profile)
            self.assertEqual(loaded.raw_matrix, image.raw_matrix)
            self.assertEqual(manifest["resident_payload_bytes"], 2 * 3 * 5)
            self.assertEqual(manifest["resident_orientations"]["A"]["bank_depth"], 5)
            # One-character corruption remains a valid signed word but fails
            # against the canonical integer matrix hash.
            bank_path = destination / "A_bank00.hex"
            lines = bank_path.read_text(encoding="ascii").splitlines()
            lines[0] = signed_hex(1, self.profile.coefficient)
            bank_path.write_text("\n".join(lines) + "\n", encoding="ascii")
            with self.assertRaisesRegex(ValueError, "hash"):
                read_matrix_image(destination, self.profile)


if __name__ == "__main__":
    unittest.main()
