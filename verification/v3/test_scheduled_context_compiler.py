from __future__ import annotations

import copy
from dataclasses import replace
import json
from pathlib import Path
import unittest

from compiler.v3 import architecture_configuration as architecture
from compiler.v3 import context_isa as isa
from compiler.v3 import modulo_mapping_graph as mmg
from compiler.v3 import reconstruction_graphs as graphs
from compiler.v3 import scheduled_context_compiler as compiler


class ScheduledContextCompilerTests(unittest.TestCase):
    def test_d22_closure_value_types_are_mapped_but_not_active(self) -> None:
        self.assertEqual(
            (compiler.CLOSURE_VALUE_TYPES["D22F18"].width,
             compiler.CLOSURE_VALUE_TYPES["S31F23"].width,
             compiler.CLOSURE_VALUE_TYPES["A70F46"].width,
             compiler.CLOSURE_VALUE_TYPES["A70F46"].fraction,
             compiler.CLOSURE_VALUE_TYPES["TOPK_RECORD41"].width),
            (22, 31, 70, 46, 41),
        )
        self.assertEqual(compiler.VALUE_TYPES["D18F14"].width, 18)

    ROOT = Path(__file__).resolve().parents[2]

    @classmethod
    def setUpClass(cls) -> None:
        cls.configuration = architecture.load()
        _, cls.ddgs = graphs.validate_all()
        cls.payload = compiler.payload()

    def test_every_routine_edge_has_one_explicit_type(self) -> None:
        self.assertEqual(set(self.payload["typed_ssa"]), set(self.ddgs))
        for name, ddg in self.ddgs.items():
            ssa = self.payload["typed_ssa"][name]
            typed_values = {(value["producer"], value["base_name"])
                            for value in ssa["values"]}
            expected = {(edge.source, edge.value) for edge in ddg.dependencies}
            self.assertEqual(typed_values, expected)
            for value in ssa["values"]:
                self.assertGreater(value["type"]["width"], 0)
                self.assertLessEqual(value["type"]["fraction"], value["type"]["width"])

    def test_local_rf_allocation_is_explicit_and_fits_8x27(self) -> None:
        for name in mmg.MODULO_KERNELS:
            allocation = self.payload["local_rf_allocations"][name]
            self.assertLessEqual(allocation["peak_registers"], 8)
            self.assertEqual(allocation["peak_registers"], 0)
            self.assertEqual(allocation["allocations"], [])

    def test_memory_plan_matches_matrix_free_workspace(self) -> None:
        memory = self.payload["memory_allocation"]
        self.assertEqual(memory["allocated_words_per_bank"], 238)
        names = {item["name"] for item in memory["objects"]}
        self.assertEqual(names, {
            "measurement_y", "residual_current", "residual_proposed",
            "solver_d", "solver_x", "solver_g", "solver_p", "solver_r",
            "iht_x_dense", "iht_gradient_dense", "iht_tentative_dense",
        })
        self.assertIn("proxy[N]", memory["forbidden_objects"])
        self.assertNotIn("proxy", names)
        ranges = sorted((item["base_word_address_per_bank"],
                         item["base_word_address_per_bank"] + item["words_per_bank"])
                        for item in memory["objects"])
        self.assertTrue(all(left[1] <= right[0]
                            for left, right in zip(ranges, ranges[1:])))
        ids = {item["name"]: item["id"] for item in memory["configurations"]}
        self.assertLess(ids["measurement_y"], 16)
        self.assertTrue(16 <= ids["solver_x"] < 32)
        self.assertTrue(40 <= ids["phi_dense"] < 48)
        self.assertEqual(ids["phi_dense_no_capture"], 44)
        configurations = {item["name"]: isa.unpack_memory_configuration(
            item["word"]) for item in memory["configurations"]}
        for source in ("solver_d", "solver_r"):
            even = configurations[f"{source}_even_stripes"]
            odd = configurations[f"{source}_odd_stripes"]
            self.assertEqual(even.element_stride_words, 2)
            self.assertEqual(odd.element_stride_words, 2)
            self.assertEqual(odd.base_word_address,
                             even.base_word_address + 1)

    def test_iht_dense_correlation_disables_candidate_capture(self) -> None:
        segment = next(item for item in self.payload["resident_segments"]
                       if item["kernel"] == "iht_dense_correlation")
        prologue = segment["contexts"][0]
        stream = isa.unpack_stream(prologue["stream_word"])
        self.assertEqual(prologue["region"], "prologue")
        self.assertEqual(stream.phi_command, 1)
        self.assertEqual(stream.phi_configuration_id, 44)

    def test_emitted_contexts_round_trip_and_cover_mappings(self) -> None:
        self.assertEqual(self.payload["array_context_count"], 255)
        self.assertEqual(self.payload["blocked_kernels"], [])
        self.assertEqual([kernel["kernel"] for kernel in self.payload["kernels"]],
                         list(mmg.MODULO_KERNELS))
        mappings = mmg.payload()["kernels"]
        expected_entry = 0
        for kernel in self.payload["kernels"]:
            self.assertEqual(kernel["entry_pc"], expected_entry)
            expected_entry += kernel["context_count"]
            emitted = {name for context in kernel["contexts"]
                       for name in context["semantic_operations"]}
            self.assertEqual(emitted,
                             set(mappings[kernel["kernel"]]["mapping"]["placements"]))
            self.assertEqual(kernel["contexts"][0]["region"], "prologue")
            self.assertEqual(kernel["contexts"][-1]["region"], "epilogue")
            for context in kernel["contexts"]:
                for word in context["tile_words"]:
                    isa.unpack_tile(word)
                control = isa.unpack_array_control(context["array_control_word"])
                stream = isa.unpack_stream(context["stream_word"])
                resource = isa.unpack_resource(context["resource_word"])
                isa.validate_context_bundle(control, stream, resource)
                accesses = int(stream.vector_read_a_enable)
                accesses += int(stream.vector_read_b_enable)
                accesses += int(stream.vector_write_enable)
                self.assertLessEqual(accesses, 2)
            if kernel["kernel"] == "phi_support_transpose":
                reduction = next(
                    context for context in kernel["contexts"]
                    if "reduce" in context["semantic_operations"])
                resource = isa.unpack_resource(reduction["resource_word"])
                self.assertNotEqual(resource.configuration_id, 0)
                self.assertEqual(resource.output_select,
                                 isa.ResourceOutput.MEMORY_STREAM)

    def test_restricted_refinement_is_resident_phase_orchestrated(self) -> None:
        segments = self.payload["resident_segments"]
        self.assertEqual(
            [(item["kernel"], item["entry_pc"], item["context_count"])
             for item in segments],
            [("restricted_refinement_transpose", 40, 12),
             ("restricted_refinement_initialize", 52, 16),
             ("restricted_refinement_pre_transpose", 68, 9),
             ("restricted_refinement_certificate", 77, 3),
             ("restricted_refinement_continuation", 80, 6),
             ("restricted_refinement_restart_residual", 86, 3),
             ("restricted_refinement_restart_direction", 89, 8),
             ("omp_support_append_commit", 97, 5),
             ("iht_dense_correlation", 102, 13),
             ("vector_axpy", 115, 4),
             ("topk_stream", 119, 5),
             ("iht_support_replace", 124, 10),
             ("iht_dense_rebuild", 134, 4),
             ("iht_support_pack", 138, 4),
             ("htp_support_coefficient_scatter", 142, 4),
             ("htp_dense_scatter", 146, 4),
             ("cosamp_union_3k", 150, 5),
             ("cosamp_coefficient_topk", 155, 5),
             ("cosamp_prune_support", 160, 10),
             ("sp_union_2k", 170, 5),
             ("sp_prune_support", 175, 10),
             ("sp_proposal_coefficient_scatter", 185, 4),
             ("sp_accept", 189, 3),
             ("sp_rollback", 192, 3),
             ("gp_top1_stream", 195, 5),
             ("gp_line_search", 200, 15),
             ("gp_update", 215, 4),
             ("gomp_top2_stream", 219, 5),
             ("gomp_support_union", 224, 8),
             ("gp_support_policy", 232, 5),
             ("gp_direction_pack", 237, 4),
             ("mp_direction_pack", 241, 4),
             ("residual_measure", 245, 9),
             ("htp_fresh_refinement_marker", 254, 1)])
        ids = {item["name"]: item["id"]
               for item in self.payload["memory_allocation"]["configurations"]}
        initialize = segments[1]
        initial_issue = next(item for item in initialize["contexts"]
                             if item["region"] == "initial_direction_issue")
        initial_wait = next(item for item in initialize["contexts"]
                            if item["region"] == "initial_direction_wait")
        gamma_issue = next(item for item in initialize["contexts"]
                           if item["region"] == "gamma_reference_first_issue")
        initial_resource = isa.unpack_resource(initial_issue["resource_word"])
        initial_stream = isa.unpack_stream(initial_wait["stream_word"])
        gamma_stream = isa.unpack_stream(gamma_issue["stream_word"])
        self.assertEqual(initial_resource.operation,
                         isa.ResourceOperation.SHARED_VECTOR_COPY)
        self.assertEqual(initial_resource.configuration_id, 3)
        self.assertEqual(initial_stream.vector_configuration_write,
                         ids["solver_p"])
        self.assertEqual(gamma_stream.vector_configuration_a, ids["solver_p"])
        for segment in segments:
            resources = [isa.unpack_resource(item["resource_word"])
                         for item in segment["contexts"]]
            for index, context in enumerate(segment["contexts"]):
                control = isa.unpack_array_control(context["array_control_word"])
                stream = isa.unpack_stream(context["stream_word"])
                resource = resources[index]
                self.assertFalse(resource.wait_for_ready and resource.wait_for_result)
                self.assertEqual(control.routine_done,
                                 int(index == len(resources) - 1))
                if index == len(resources) - 1 and \
                        segment["kernel"] != "htp_fresh_refinement_marker":
                    self.assertEqual(control.next_pc_mode,
                                     isa.NextPcMode.RETURN_TO_PHASE)
                if resource.wait_for_ready and resource.operation in {
                        isa.ResourceOperation.SHARED_VECTOR_DOT,
                        isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                        isa.ResourceOperation.SHARED_VECTOR_AXPY}:
                    self.assertTrue(stream.vector_read_a_enable)
                if resource.wait_for_result and resource.operation == \
                        isa.ResourceOperation.SHARED_VECTOR_AXPY:
                    self.assertTrue(stream.vector_write_enable)
            limits = {isa.unpack_array_control(item["array_control_word"])
                      .loop_limit_select for item in segment["contexts"]}
            if segment["kernel"].startswith("restricted_refinement_") and \
                    segment["kernel"] not in {
                        "restricted_refinement_transpose",
                        "restricted_refinement_certificate"}:
                self.assertTrue(limits & {
                    isa.LoopLimitSource.MEASUREMENT_STRIPES_16,
                    isa.LoopLimitSource.ACTIVE_WORK_STRIPES_16})
        scatter = {item["kernel"]: item for item in segments}
        for name in ("restricted_refinement_pre_transpose",
                     "restricted_refinement_certificate"):
            resources = [isa.unpack_resource(item["resource_word"])
                         for item in scatter[name]["contexts"]]
            self.assertNotIn(isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
                             {resource.operation for resource in resources})
        ids = {item["name"]: item["id"]
               for item in self.payload["memory_allocation"]["configurations"]}
        coefficient_issue = isa.unpack_resource(
            scatter["htp_support_coefficient_scatter"]["contexts"][1]
            ["resource_word"])
        coefficient_wait = isa.unpack_array_control(
            scatter["htp_support_coefficient_scatter"]["contexts"][2]
            ["array_control_word"])
        self.assertEqual(coefficient_issue.operation,
                         isa.ResourceOperation.SUPPORT_SCATTER)
        self.assertEqual(coefficient_issue.input_select,
                         isa.ResourceInput.MEMORY_STREAM)
        self.assertEqual(coefficient_wait.loop_limit_select,
                         isa.LoopLimitSource.RUN_PARAMETER_1)
        dense_issue = isa.unpack_resource(
            scatter["htp_dense_scatter"]["contexts"][1]["resource_word"])
        self.assertEqual(dense_issue.operation,
                         isa.ResourceOperation.SHARED_VECTOR_COPY)
        self.assertEqual(dense_issue.configuration_id, 2)
        sp_union_prepare = isa.unpack_resource(
            scatter["sp_union_2k"]["contexts"][2]["resource_word"])
        self.assertEqual(sp_union_prepare.operation,
                         isa.ResourceOperation.SUPPORT_COMMIT)
        self.assertEqual(sp_union_prepare.configuration_id, 1)
        sp_prune_resources = [isa.unpack_resource(item["resource_word"])
                              for item in scatter["sp_prune_support"]["contexts"]]
        self.assertEqual(sp_prune_resources[0].configuration_id, 3)
        self.assertEqual(sp_prune_resources[4].configuration_id, 3)
        self.assertEqual(sp_prune_resources[7].configuration_id, 3)
        sp_scatter = isa.unpack_resource(
            scatter["sp_proposal_coefficient_scatter"]["contexts"][1]
            ["resource_word"])
        self.assertEqual(sp_scatter.operation,
                         isa.ResourceOperation.SUPPORT_SCATTER)
        self.assertEqual(sp_scatter.configuration_id, 1)
        sp_accept = isa.unpack_resource(
            scatter["sp_accept"]["contexts"][0]["resource_word"])
        sp_rollback = isa.unpack_resource(
            scatter["sp_rollback"]["contexts"][0]["resource_word"])
        self.assertEqual(sp_accept.operation,
                         isa.ResourceOperation.SUPPORT_COMMIT)
        self.assertEqual(sp_accept.configuration_id, 0)
        self.assertEqual(sp_rollback.operation,
                         isa.ResourceOperation.SUPPORT_ROLLBACK)
        gp_push_context = next(
            item for item in scatter["gp_top1_stream"]["contexts"]
            if item["region"] == "push_issue")
        gp_push = isa.unpack_resource(gp_push_context["resource_word"])
        self.assertEqual(gp_push.configuration_id, 2)
        gp_append = isa.unpack_resource(
            scatter["gp_support_policy"]["contexts"][0]["resource_word"])
        self.assertEqual(gp_append.input_select,
                         isa.ResourceInput.SUPPORT_STREAM)
        gp_pack = isa.unpack_resource(
            scatter["gp_direction_pack"]["contexts"][1]["resource_word"])
        self.assertEqual(gp_pack.configuration_id, 3)
        gp_numerator = scatter["gp_line_search"]["contexts"][1]
        gp_numerator_stream = isa.unpack_stream(gp_numerator["stream_word"])
        gp_numerator_resource = isa.unpack_resource(gp_numerator["resource_word"])
        self.assertEqual(gp_numerator_resource.operation,
                         isa.ResourceOperation.SHARED_VECTOR_NORM_SQ)
        self.assertEqual(gp_numerator_resource.count_select,
                         isa.ResourceCountSource.ACTIVE_WORK_COUNT)
        self.assertEqual(gp_numerator_stream.vector_configuration_a,
                         ids["solver_p"])
        routine = self.payload["hierarchical_routines"][0]
        self.assertEqual(routine["routine"], "restricted_refinement_iteration")
        self.assertEqual(routine["execution_model"],
                         "phase_orchestrated_segments")
        self.assertFalse(routine["solver_pc"])
        self.assertTrue(routine["hardware_execution_ready"])
        self.assertEqual(routine["execution_blockers"], [])

    def test_correlation_streams_candidates_without_full_proxy_store(self) -> None:
        correlation = self.ddgs["correlation"]
        operations = {item.name: item.operation for item in correlation.operations}
        self.assertEqual(operations["collect"], "TOPK_PUSH")
        self.assertNotIn("STORE_VECTOR", operations.values())
        normalized = next(edge for edge in correlation.dependencies
                          if edge.target == "collect")
        self.assertEqual(normalized.route, "normalized_result")
        mapped = mmg.map_kernel(correlation, self.configuration)["mapping"]
        self.assertNotEqual(mapped["placements"]["reduce"]["modulo_slot"],
                            mapped["placements"]["collect"]["modulo_slot"])

    def test_phi_normalizer_is_an_explicit_fixed_route_resource(self) -> None:
        resources = architecture.physical_resource_map(self.configuration)
        normalizer = resources["phi_operator_normalizer"]
        self.assertEqual(normalizer["kind"], "fixed_route_pipeline")
        self.assertEqual(normalizer["operations"], ["PHI_NORMALIZE"])
        timing = architecture.operation_timing(self.configuration)["PHI_NORMALIZE"]
        self.assertEqual((timing["latency"], timing["initiation_interval"]), (4, 1))
        links = {item["id"] for item in architecture.mrrg_payload(self.configuration)["links"]}
        self.assertIn("reduction_pipeline_0_to_phi_operator_normalizer_0", links)
        self.assertIn("phi_operator_normalizer_0_to_selection_unit_0", links)

    def test_correlation_uses_nested_transaction_contract(self) -> None:
        kernel = self.payload["kernels"][0]
        self.assertEqual(kernel["kernel"], "correlation")
        self.assertEqual(kernel["body_ii"], 1)
        contract = kernel["operator_contract"]
        self.assertEqual(contract["inner_limit_formula"], "ceil(M/32)")
        self.assertEqual(contract["inner_loop_counter"], 0)
        self.assertEqual(contract["outer_loop_counter"], 1)
        self.assertTrue(contract["reduction_emit"])
        self.assertTrue(contract["normalizer_required"])
        self.assertEqual(contract["candidate_index_source"],
                         "registered_phi_column")
        by_region = {context["region"]: context
                     for context in kernel["contexts"]}
        body_control = isa.unpack_array_control(
            by_region["row_block_body"]["array_control_word"])
        body_stream = isa.unpack_stream(
            by_region["row_block_body"]["stream_word"])
        restart = isa.unpack_resource(
            by_region["column_setup"]["resource_word"])
        reduction_issue = isa.unpack_resource(
            by_region["prime_reduction_issue"]["resource_word"])
        middle_reduce = isa.unpack_resource(
            by_region["middle_reduction_issue"]["resource_word"])
        push_issue = isa.unpack_resource(
            by_region["middle_topk_push_issue"]["resource_word"])
        push_wait = isa.unpack_resource(
            by_region["middle_topk_push_wait"]["resource_word"])
        drain_push = isa.unpack_resource(
            by_region["drain_topk_push_issue"]["resource_word"])
        commit_issue = isa.unpack_resource(
            by_region["topk_commit_issue"]["resource_word"])
        commit_wait = isa.unpack_resource(
            by_region["topk_commit_wait"]["resource_word"])
        self.assertEqual(contract["column_pipeline"], "prime_middle_drain")
        self.assertFalse(contract["reduction_response_wait"])
        self.assertEqual(body_control.loop_counter_select, 0)
        self.assertEqual(body_control.loop_limit_select,
                         isa.LoopLimitSource.RUN_PARAMETER_0)
        self.assertEqual(body_stream.phi_command,
                         isa.PhiStreamCommand.CONSUME)
        self.assertEqual((restart.operation, restart.stream_boundary,
                          restart.configuration_id),
                         (isa.ResourceOperation.NOP,
                          isa.StreamBoundary.FIRST, 1))
        self.assertEqual(reduction_issue.commit_after, 1)
        self.assertEqual(reduction_issue.output_select,
                         isa.ResourceOutput.TOPK_STATE)
        self.assertEqual(reduction_issue.wait_for_result, 0)
        self.assertEqual(middle_reduce.wait_for_result, 0)
        self.assertEqual(push_issue.wait_for_ready, 1)
        self.assertEqual(push_wait.wait_for_result, 1)
        self.assertEqual(drain_push.wait_for_ready, 1)
        self.assertEqual(commit_issue.wait_for_ready, 1)
        self.assertEqual(commit_wait.wait_for_result, 1)

    def test_nested_operator_templates_are_canonical(self) -> None:
        expected = {
            "residual_update": (["prologue", "row_block_setup", "support_body",
                "subtract", "writeback", "epilogue"],
                "RUN_PARAMETER_1", "RUN_PARAMETER_0"),
            "phi_support_forward": (["prologue", "row_block_setup", "support_body",
                "accumulator_read", "writeback_low", "writeback", "epilogue"],
                "RUN_PARAMETER_1", "RUN_PARAMETER_0"),
            "phi_support_transpose": (["prologue", "support_setup", "row_block_body",
                "prime_reduction_issue", "prime_reduction_wait",
                "single_item_drain_jump", "middle_support_setup",
                "middle_row_block_body", "middle_reduction_issue",
                "middle_reduction_wait_writeback", "drain_writeback", "epilogue"],
                "RUN_PARAMETER_0", "RUN_PARAMETER_1"),
        }
        kernels = {item["kernel"]: item for item in self.payload["kernels"]}
        for name, (regions, inner_limit, outer_limit) in expected.items():
            kernel = kernels[name]
            self.assertEqual([item["region"] for item in kernel["contexts"]], regions)
            contract = kernel["operator_contract"]
            self.assertEqual((contract["inner_loop_counter"], contract["inner_limit"]),
                             (0, inner_limit))
            self.assertEqual((contract["outer_loop_counter"], contract["outer_limit"]),
                             (1, outer_limit))
            self.assertEqual(contract["vector_restart_mask"],
                             3 if name == "phi_support_transpose" else 1)
            self.assertEqual(contract["reduction_response_wait"],
                             name == "phi_support_transpose")
            self.assertTrue(contract["writeback_after_response"])
            self.assertTrue(contract["schedule_shape_valid"])
            self.assertTrue(contract["hardware_execution_ready"])
            self.assertEqual(contract["execution_blockers"], [])
            by_region = {item["region"]: item for item in kernel["contexts"]}
            body_region = ("row_block_body" if name == "phi_support_transpose"
                           else "support_body")
            body_operation = isa.unpack_tile(
                by_region[body_region]["tile_words"][0]).operation
            self.assertEqual(
                body_operation,
                isa.TileOperation.PHI_DATA_ACCUMULATE
                if name == "residual_update"
                else isa.TileOperation.PHI_ACCUMULATE)
            epilogue = isa.unpack_stream(by_region["epilogue"]["stream_word"])
            if name == "phi_support_transpose":
                body = isa.unpack_stream(by_region[body_region]["stream_word"])
                self.assertEqual(body.vector_read_a_enable, 1)
                self.assertEqual(body.vector_read_b_enable, 1)
                issue = isa.unpack_resource(
                    by_region["prime_reduction_issue"]["resource_word"])
                wait = isa.unpack_resource(
                    by_region["prime_reduction_wait"]["resource_word"])
                middle = by_region["middle_reduction_wait_writeback"]
                middle_control = isa.unpack_array_control(
                    middle["array_control_word"])
                middle_stream = isa.unpack_stream(middle["stream_word"])
                middle_resource = isa.unpack_resource(middle["resource_word"])
                self.assertEqual(issue.commit_after, 1)
                self.assertEqual(wait.wait_for_result, 1)
                self.assertEqual(middle_control.loop_counter_select, 1)
                self.assertEqual(middle_control.loop_counter_increment, 1)
                self.assertEqual(middle_resource.wait_for_result, 1)
                self.assertEqual(middle_stream.vector_write_enable, 1)
                self.assertEqual(contract["transpose_pipeline_shape"],
                                 "prime_middle_drain")
            else:
                writeback = isa.unpack_array_control(
                    by_region["writeback"]["array_control_word"])
                self.assertEqual(writeback.loop_counter_select, 1)
                self.assertEqual(writeback.loop_counter_increment, 1)
            self.assertEqual(epilogue.phi_command, isa.PhiStreamCommand.STOP)

    def test_plane_images_have_exact_physical_widths(self) -> None:
        files = compiler.mem_files(self.payload)
        for plane in range(9):
            lines = files[f"array_plane_{plane}.mem"].splitlines()
            self.assertEqual(len(lines), self.payload["array_context_count"])
            self.assertTrue(all(len(line) == 18 for line in lines))
        resource_lines = files["array_plane_9.mem"].splitlines()
        self.assertTrue(all(len(line) == 9 for line in resource_lines))
        self.assertEqual(len(files["memory_configurations.mem"].splitlines()), 64)

    def test_gomp_top2_uses_context_literal_without_algorithm_decode(self) -> None:
        segments = {item["kernel"]: item
                    for item in self.payload["resident_segments"]}
        top2 = segments["gomp_top2_stream"]
        push = next(item for item in top2["contexts"]
                    if item["region"] == "push_issue")
        resource = isa.unpack_resource(push["resource_word"])
        self.assertEqual(resource.operation, isa.ResourceOperation.TOPK_PUSH)
        self.assertEqual(resource.input_select,
                         isa.ResourceInput.MEMORY_STREAM)
        self.assertEqual(resource.configuration_id, 0x20 | 2)
        self.assertEqual(top2["operator_contract"]["retained_count"], 2)
        self.assertTrue(top2["operator_contract"][
            "active_support_gradient_capture"])
        self.assertFalse(top2["operator_contract"][
            "hardware_algorithm_decode"])
        for kernel_name in ("topk_stream", "gp_top1_stream",
                            "gomp_top2_stream"):
            segment = segments[kernel_name]
            self.assertNotIn("restart",
                             [item["region"] for item in segment["contexts"]])
            push_issue = next(item for item in segment["contexts"]
                              if item["region"] == "push_issue")
            push_wait = next(item for item in segment["contexts"]
                             if item["region"] == "push_wait")
            issue_control = isa.unpack_array_control(
                push_issue["array_control_word"])
            self.assertEqual(issue_control.next_pc,
                             push_issue["pc"])
            issue_resource = isa.unpack_resource(push_issue["resource_word"])
            wait_resource = isa.unpack_resource(push_wait["resource_word"])
            self.assertEqual(issue_resource.event_id, 9)
            self.assertEqual(wait_resource.event_id, 9)

    def test_mp_direction_pack_is_context_owned_one_hot(self) -> None:
        segments = {item["kernel"]: item
                    for item in self.payload["resident_segments"]}
        pack = segments["mp_direction_pack"]
        issue = next(item for item in pack["contexts"]
                     if item["region"] == "issue")
        resource = isa.unpack_resource(issue["resource_word"])
        self.assertEqual(resource.operation,
                         isa.ResourceOperation.SHARED_VECTOR_COPY)
        self.assertEqual(resource.input_select, isa.ResourceInput.SUPPORT_STREAM)
        self.assertEqual(resource.configuration_id, 4)
        self.assertEqual(pack["operator_contract"]["selection"],
                         "top1_atom_one_hot_over_active_support")
        self.assertFalse(pack["operator_contract"][
            "hardware_algorithm_decode"])

    def test_missing_type_and_stale_hash_are_hard_errors(self) -> None:
        saved = compiler.EDGE_TYPES["correlation"].pop("residual")
        try:
            with self.assertRaises(ValueError):
                compiler.typed_ssa(self.ddgs["correlation"])
        finally:
            compiler.EDGE_TYPES["correlation"]["residual"] = saved
        generated = copy.deepcopy(self.payload)
        generated["architecture_hash"] = "0" * 64
        with self.assertRaises(ValueError):
            compiler.validate_compiled(generated, self.configuration)

    def test_reserved_scalar_operation_cannot_be_emitted(self) -> None:
        for operation in (isa.ResourceOperation.SCALAR_RECIPROCAL,
                          isa.ResourceOperation.SCALAR_SQRT):
            generated = copy.deepcopy(self.payload)
            generated["kernels"][0]["contexts"][0]["resource_word"] = (
                isa.pack_resource(isa.ResourceContext(operation=operation)))
            with self.assertRaisesRegex(ValueError, "unavailable resource operation"):
                compiler.validate_compiled(generated, self.configuration)

    def test_rf_width_overflow_is_rejected(self) -> None:
        source = self.ddgs["correlation"]
        edges = tuple(
            graphs.DependencyEdge(edge.source, edge.target, edge.value,
                                  edge.iteration_distance,
                                  "same_tile_bundle" if edge.value == "lane_partial"
                                  else edge.route)
            for edge in source.dependencies)
        invalid = graphs.ArrayRoutineDDG(
            source.name, source.loop_axis, source.partition_mode,
            source.operations, edges, source.mapping_domain)
        ssa = compiler.typed_ssa(invalid)
        mapping = mmg.map_kernel(
            self.ddgs["correlation"], self.configuration)["mapping"]
        with self.assertRaises(ValueError):
            compiler.allocate_local_rf(
                invalid, mapping, ssa)

    def test_bank_overlap_and_three_access_context_are_rejected(self) -> None:
        overlap = copy.deepcopy(self.payload)
        objects = overlap["memory_allocation"]["objects"]
        objects[1]["base_word_address_per_bank"] = objects[0]["base_word_address_per_bank"]
        with self.assertRaises(ValueError):
            compiler.validate_compiled(overlap, self.configuration)

        over_port = copy.deepcopy(self.payload)
        body = next(context for context in over_port["kernels"][0]["contexts"]
                    if context["region"] in {"body", "row_block_body"})
        body["stream_word"] = isa.pack_stream(isa.StreamContext(
            vector_read_a_enable=1, vector_read_b_enable=1,
            vector_write_enable=1, vector_configuration_a=1,
            vector_configuration_b=2, vector_configuration_write=16,
            advance_vector_streams=1,
        ))
        with self.assertRaises(ValueError):
            compiler.validate_compiled(over_port, self.configuration)

    def test_phi_only_tile_capability_violations_are_rejected(self) -> None:
        for mutation, message in (
                ({"operation": isa.TileOperation.ADD}, "operation ADD"),
                ({"rf_write_enable": 1}, "RF write"),
                ({"route_east_select": isa.RouteSource.PE_RESULT}, "routing")):
            generated = copy.deepcopy(self.payload)
            context = generated["kernels"][0]["contexts"][0]
            tile = isa.unpack_tile(context["tile_words"][4])
            context["tile_words"][4] = isa.pack_tile(replace(tile, **mutation))
            with self.assertRaisesRegex(ValueError, message):
                compiler.validate_compiled(generated, self.configuration)

    def test_generated_context_collateral_matches_live_compiler(self) -> None:
        path = self.ROOT / "reports" / "v3" / "scheduled_context_library.json"
        generated = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(generated, self.payload)


if __name__ == "__main__":
    unittest.main()
