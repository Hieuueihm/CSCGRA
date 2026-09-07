from __future__ import annotations

import unittest

from compiler.v3 import reconstruction_graphs as graphs


class ReconstructionGraphContractTests(unittest.TestCase):
    def test_all_paper_algorithms_have_valid_cfg(self) -> None:
        cfgs, _ = graphs.validate_all()
        self.assertEqual(set(cfgs), set(graphs.PAPER_DOI))

    def test_sp_and_cosamp_keep_full_work_support_before_prune(self) -> None:
        cfgs, _ = graphs.validate_all()
        cosamp = [node.name for node in cfgs["CoSaMP"].nodes]
        sp = [node.name for node in cfgs["SP"].nodes]
        self.assertLess(cosamp.index("LS_3K"), cosamp.index("PRUNE_K"))
        self.assertLess(sp.index("LS_2K"), sp.index("PRUNE_K"))
        self.assertLess(sp.index("PRUNE_K"), sp.index("LS_K"))

    def test_recurrence_edges_are_explicit(self) -> None:
        _, ddgs = graphs.validate_all()
        recurrent = {
            name for name, ddg in ddgs.items()
            if any(edge.iteration_distance > 0 for edge in ddg.dependencies)
        }
        self.assertTrue({"correlation", "dot_norm", "phi_support_transpose", "topk_stream"} <= recurrent)

    def test_dual_cluster_architecture_is_encoded(self) -> None:
        architecture = graphs.payload()["architecture"]
        self.assertEqual(architecture["cluster_count"], 2)
        self.assertEqual((architecture["rows_per_cluster"], architecture["columns_per_cluster"]), (4, 4))
        self.assertEqual(
            architecture["cluster_execution"], "shared_synchronous_context"
        )
        self.assertEqual(architecture["context_format"]["cycle_width"], 684)
        self.assertEqual(architecture["context_format"]["phase_width"], 36)
        self.assertEqual(architecture["context_format"]["revision"], 9)
        self.assertEqual(architecture["context_format"]["physical_ramb36"], 10)
        self.assertEqual(architecture["intercluster_pe_links"], 8)
        self.assertEqual(
            architecture["intercluster_routing"],
            "bidirectional_registered_column_connector")

    def test_auxiliary_resources_are_explicit_mrrg_resources(self) -> None:
        architecture = graphs.payload()["architecture"]
        resources = {item["id"]: item
                     for item in architecture["physical_resources"]}
        self.assertEqual(resources["paired_context_tile"]["count"], 16)
        self.assertEqual(resources["shared_vector_arithmetic_unit"]["count"], 1)
        self.assertEqual(resources["paired_context_tile"]["context_coupling"],
                         "same_word_for_corresponding_tiles")
        self.assertEqual(architecture["context_format"]["resource_width"], 36)
        self.assertIn("support_union", graphs.build_array_routine_ddgs())
        self.assertIn("restricted_refinement", graphs.build_array_routine_ddgs())

    def test_reserved_scalar_operations_cannot_enter_a_ddg(self) -> None:
        with self.assertRaises(ValueError):
            graphs._op("illegal_reciprocal", "SCALAR_RECIPROCAL",
                       "scalar_function_unit")
        with self.assertRaises(ValueError):
            graphs._op("illegal_sqrt", "SCALAR_SQRT", "scalar_function_unit")

    def test_six_paper_macroblocks_and_restricted_refinement(self) -> None:
        payload = graphs.payload()
        self.assertEqual(len(payload["architecture"]["macroblocks"]), 6)
        routines = {node["routine"] for cfg in payload["phase_cfgs"].values()
                    for node in cfg["nodes"]}
        self.assertIn("restricted_refinement", routines)
        self.assertNotIn("matrix_free_pcg", routines)

    def test_phase_nodes_use_one_synchronous_array_stream(self) -> None:
        cfgs, _ = graphs.validate_all()
        usage = {node.array_usage for cfg in cfgs.values() for node in cfg.nodes}
        self.assertEqual(usage, {"tiles_and_resources", "resources_only"})

    def test_generated_phi_uses_no_matrix_banks(self) -> None:
        architecture = graphs.payload()["architecture"]
        memory = architecture["memory"]
        self.assertEqual(memory["vector_banks"], 8)
        self.assertEqual(memory["phi_banks"], 0)
        self.assertEqual(memory["bank_word_width"], 72)
        resources = {item["id"]: item
                     for item in architecture["physical_resources"]}
        generator = resources["phi_generator"]
        self.assertEqual(generator["count"], 1)
        self.assertEqual(generator["operations"], ["PHI_SIGN_WORD"])

    def test_all_paper_routines_have_explicit_lowering(self) -> None:
        cfgs, ddgs = graphs.validate_all()
        referenced = {node.routine for cfg in cfgs.values() for node in cfg.nodes}
        self.assertEqual(referenced, set(graphs.ROUTINE_LOWERING))
        self.assertEqual(
            {name for name, ddg in ddgs.items()
             if ddg.mapping_domain == "modulo_array"},
            {"correlation", "residual_update", "phi_support_forward",
             "phi_support_transpose"})

    def test_ddg_timing_comes_from_architecture_authority(self) -> None:
        _, ddgs = graphs.validate_all()
        refinement = {node.name: node
                      for node in ddgs["restricted_refinement"].operations}
        self.assertEqual(refinement["alpha"].latency, 15)
        self.assertEqual(refinement["delta"].latency, 6)
        self.assertEqual(refinement["update_x"].latency, 4)
        self.assertEqual(refinement["check"].latency, 1)


if __name__ == "__main__":
    unittest.main()
