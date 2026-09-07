from __future__ import annotations

import unittest

from scripts.numeric import v3_p15_arithmetic_contract_audit as audit


class P15ArithmeticContractTests(unittest.TestCase):
    def test_candidate_widths_headroom_and_latency(self) -> None:
        result = audit.build_audit()
        candidate = result["contracts"]["quality_d22"]
        self.assertEqual(candidate["multiply"]["full_product_width"], 62)
        self.assertTrue(candidate["multiply"]["directed_and_random_check"]["exact"])
        self.assertEqual(candidate["global_dot_norm"]["internal_width"], 72)
        self.assertEqual(candidate["global_dot_norm"]["architectural_result_width"], 70)
        self.assertFalse(candidate["global_dot_norm"]["encoded_extreme_fits_result"])
        self.assertEqual(candidate["local_phi_accumulator"]["forward_terms"], 1024)
        self.assertGreaterEqual(
            candidate["local_phi_accumulator"]["forward_margin_bits"], 6)
        self.assertGreaterEqual(
            candidate["local_phi_accumulator"]["transpose_margin_bits"], 9)
        self.assertEqual(candidate["divide"]["work_width"], 101)
        self.assertEqual(candidate["divide"]["derived_latency"], 17)
        self.assertEqual(candidate["certificate"]["energy_scale_shift"], 0)
        self.assertTrue(all(result["gates"].values()))

    def test_production_contract_remains_active(self) -> None:
        result = audit.build_audit()
        production = result["contracts"]["production"]
        self.assertEqual(result["active_profile"], "production")
        self.assertEqual(production["identity"]["solver_width"], 27)
        self.assertEqual(production["divide"]["authority_latency"], 15)
        self.assertEqual(production["multiply"]["full_product_width"], 54)


if __name__ == "__main__":
    unittest.main()
