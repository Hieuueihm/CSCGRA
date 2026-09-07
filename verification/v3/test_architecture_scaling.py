from __future__ import annotations
import unittest
from compiler.v3 import architecture_scaling as scaling

class ArchitectureScalingTests(unittest.TestCase):
    def test_active_build_is_k32_only(self) -> None:
        payload = scaling.payload()
        self.assertEqual(payload["active_build"], "K32 only")
        self.assertEqual(len(payload["profiles"]), 1)
        self.assertEqual(payload["profiles"][0]["profile"]["sparsity"], 32)

    def test_homogeneous_pe_and_shared_vector_resource(self) -> None:
        architecture = scaling.payload()["architecture"]
        self.assertEqual(architecture["pe_count"], 32)
        self.assertEqual(architecture["pe_isa"], "homogeneous_no_general_multiply")
        self.assertNotIn("multiply_capable_pe_count", architecture)
        self.assertEqual(architecture["shared_vector_arithmetic_lanes"], 16)
        self.assertEqual(architecture["shared_vector_multiply_ii"], 2)
        self.assertEqual(architecture["shared_vector_results_per_cycle"], 8)

    def test_k32_capacity_is_2k_and_3k(self) -> None:
        value = scaling.estimate(scaling.BASELINE)
        self.assertEqual((value.candidate_depth, value.work_depth), (64, 96))
        self.assertEqual(value.topk_physical_depth, 64)
        self.assertEqual((value.phi_stored_bits, value.phi_storage_bram36,
                          value.phi_storage_uram), (0, 0, 0))

    def test_scratch_contract_omits_dense_n_vectors(self) -> None:
        value = scaling.estimate(scaling.BASELINE)
        expected = (3 * scaling.BASELINE.measurement_count * scaling.DATA_W
                    + (scaling.BASELINE.measurement_count + 3 * value.work_depth)
                    * scaling.SOLVER_W)
        self.assertEqual(value.vector_and_refinement_scratch_bits, expected)
        self.assertLess(value.vector_and_refinement_scratch_bits,
                        scaling.BASELINE.signal_length * scaling.SOLVER_W)

    def test_k64_is_not_silently_allocated(self) -> None:
        with self.assertRaises(ValueError):
            scaling.estimate(scaling.ScalingProfile("future", 1024, 256, 64))

if __name__ == "__main__":
    unittest.main()
