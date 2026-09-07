from __future__ import annotations
from dataclasses import replace
import unittest
from compiler.v3 import run_configuration as rc

class RunConfigurationTests(unittest.TestCase):
    @staticmethod
    def configuration() -> rc.RunConfiguration:
        return rc.RunConfiguration(
            result_mode=rc.ResultMode.BOTH,
            matrix_kind=rc.MatrixKind.DENSE_RADEMACHER,
            measurement_count=128, signal_length=1024, sparsity=32,
            outer_iteration_limit=32, refinement_iteration_limit=64,
            normal_residual_shift=14,
            refinement_profile=rc.RefinementProfile.STRICT_PAPER,
            residual_threshold_acc62=1 << 20, phi_seed=0x123456789abcdef0,
            measurement_address=0x1000, dense_result_address=0x2000,
            sparse_result_address=0x3000, user_tag=0xfeedbeef,
            phi_scale_mantissa_uq17=1 << 17, phi_scale_exponent=-3,
            phi_column_weight=128, require_unit_norm=0)

    def test_revision6_round_trip_and_profile_bits(self) -> None:
        value = self.configuration()
        words = rc.pack(value)
        self.assertEqual(len(words), 16)
        self.assertEqual((words[2] >> 30) & 3, rc.RefinementProfile.STRICT_PAPER)
        self.assertEqual((words[2] >> 29) & 1, rc.TerminationMode.NORMAL)
        self.assertEqual(rc.unpack(words), value)

    def test_force_termination_mode_round_trip(self) -> None:
        value = replace(
            self.configuration(),
            termination_mode=rc.TerminationMode.FORCE_OUTER_ITERATIONS)
        words = rc.pack(value)
        self.assertEqual((words[2] >> 29) & 1,
                         rc.TerminationMode.FORCE_OUTER_ITERATIONS)
        self.assertEqual(rc.unpack(words), value)

    def test_all_legal_profiles_round_trip(self) -> None:
        for profile in rc.RefinementProfile:
            value = replace(self.configuration(), refinement_profile=profile)
            self.assertEqual(rc.unpack(rc.pack(value)), value)

    def test_reserved_and_invalid_profile_rejected(self) -> None:
        words = list(rc.pack(self.configuration()))
        words[1] |= 1 << 31
        with self.assertRaises(ValueError): rc.unpack(words)
        with self.assertRaises(ValueError):
            rc.pack(replace(self.configuration(), refinement_profile=3))

    def test_k64_cannot_enter_active_build(self) -> None:
        with self.assertRaises(ValueError):
            rc.pack(replace(self.configuration(), sparsity=64,
                            measurement_count=128, phi_column_weight=128))

    def test_context_selector_bits_are_reserved(self) -> None:
        words = list(rc.pack(self.configuration()))
        words[0] |= 0xf << 24
        with self.assertRaisesRegex(ValueError, "reserved bits"):
            rc.unpack(words)

    def test_word3_remains_reserved(self) -> None:
        words = list(rc.pack(self.configuration()))
        words[3] = 1
        with self.assertRaisesRegex(ValueError, "reserved bits"):
            rc.unpack(words)

    def test_unimplemented_matrix_mode_and_false_unit_norm_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "matrix kind.*unavailable"):
            rc.pack(replace(
                self.configuration(),
                matrix_kind=rc.MatrixKind.FIXED_COLUMN_WEIGHT_EXPERIMENTAL,
                phi_column_weight=32))
        with self.assertRaisesRegex(ValueError, "unit norm"):
            rc.pack(replace(self.configuration(), require_unit_norm=1))
        unit = replace(
            self.configuration(), require_unit_norm=1,
            phi_scale_mantissa_uq17=185364, phi_scale_exponent=-4)
        self.assertEqual(rc.unpack(rc.pack(unit)), unit)

    def test_non_positive_data_normalizer_shift_is_rejected(self) -> None:
        legal = replace(self.configuration(), phi_scale_exponent=11)
        self.assertEqual(rc.unpack(rc.pack(legal)), legal)
        with self.assertRaisesRegex(ValueError, "normalizer shift non-positive"):
            rc.pack(replace(self.configuration(), phi_scale_exponent=12))

if __name__ == "__main__":
    unittest.main()
