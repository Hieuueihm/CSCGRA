from __future__ import annotations

import copy
import unittest

from compiler.v3 import context_isa as isa
from compiler.v3 import m11_program_images


class M11ProgramImageTests(unittest.TestCase):
    @staticmethod
    def _without_residual_measure(launches: list[int], ranges: dict) -> list[int]:
        measure_pc = ranges["residual_measure"]["entry_pc"]
        return [entry_pc for entry_pc in launches if entry_pc != measure_pc]

    @staticmethod
    def _with_residual_measure(entries: list[int], ranges: dict) -> list[int]:
        result = []
        residual_pc = ranges["residual_update"]["entry_pc"]
        measure_pc = ranges["residual_measure"]["entry_pc"]
        for entry_pc in entries:
            result.append(entry_pc)
            if entry_pc == residual_pc:
                result.append(measure_pc)
        return result

    @classmethod
    def setUpClass(cls) -> None:
        cls.library = m11_program_images.payload()
        cls.programs = {item["program_id"]: item
                        for item in cls.library["programs"]}
        cls.program = cls.programs[0]
        cls.cosamp = cls.programs[1]
        cls.iht = cls.programs[2]
        cls.htp = cls.programs[3]
        cls.sp = cls.programs[4]
        cls.gp = cls.programs[5]
        cls.gomp = cls.programs[6]
        cls.mp = cls.programs[7]

    def test_program_abi_is_software_owned(self) -> None:
        self.assertEqual(self.library["program_abi"], {
            "0": "omp", "1": "cosamp", "2": "iht", "3": "htp",
            "4": "sp", "5": "gp", "6": "gomp", "7": "mp",
            "15": "m3_control_test",
        })
        self.assertEqual(
            self.library["implemented_program_ids"],
            [0, 1, 2, 3, 4, 5, 6, 7])
        self.assertFalse(self.program["hardware_algorithm_decode"])
        self.assertTrue(self.program["software_defined_context"])
        self.assertEqual(self.program["scalar_preloads"], [])
        self.assertEqual(
            self.library["scalar_preload_contract"]["ownership"],
            "software_program_image")
        self.assertFalse(
            self.library["scalar_preload_contract"]["hardware_algorithm_decode"])

    def test_iht_phase_sequence_crc_and_scalar_preload(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.iht["phase_instructions"]]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        ranges = self.iht["array_context_ranges"]
        self.assertEqual(self._without_residual_measure(launches, ranges),
                         [ranges[name]["entry_pc"] for name in (
            "iht_dense_rebuild",
            "iht_dense_correlation", "vector_axpy", "topk_stream",
            "iht_support_replace", "iht_dense_rebuild", "iht_support_pack",
            "residual_update")])
        self.assertEqual(self.iht["scalar_preloads"], [{
            "address": 0,
            "value_s27f19_raw": m11_program_images.IHT_DEFAULT_STEP_SIZE_S27F19_RAW,
            "semantic": "iht_step_size",
        }])
        self.assertEqual(len(instructions), 25)
        self.assertNotEqual(self.iht["phase_crc32"], 0)
        memories = m11_program_images.mem_files()
        self.assertEqual(
            len(memories["program_02_phase.mem"].splitlines()), 25)

    def test_cosamp_phase_sequence_prunes_without_second_ls(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.cosamp["phase_instructions"]]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        ranges = self.cosamp["array_context_ranges"]
        names = (
            "correlation", "cosamp_union_3k", "iht_support_pack",
            "restricted_refinement_initialize", "phi_support_forward",
            "restricted_refinement_pre_transpose",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_continuation", "cosamp_coefficient_topk",
            "cosamp_prune_support", "iht_support_pack",
            "htp_dense_scatter", "residual_update",
            "residual_update", "restricted_refinement_restart_residual",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_restart_direction")
        self.assertEqual(self._without_residual_measure(launches, ranges),
                         [ranges[name]["entry_pc"] for name in names])
        prune_position = launches.index(ranges["cosamp_prune_support"]["entry_pc"])
        self.assertNotIn(ranges["restricted_refinement_initialize"]["entry_pc"],
                         launches[prune_position + 1:])
        self.assertEqual(self.cosamp["scalar_preloads"], [])
        self.assertEqual(len(instructions), 57)
        self.assertNotEqual(self.cosamp["phase_crc32"], 0)
        self.assertEqual(len(m11_program_images.mem_files()
                             ["program_01_phase.mem"].splitlines()), 57)

    def test_htp_phase_sequence_crc_and_scalar_preload(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.htp["phase_instructions"]]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        ranges = self.htp["array_context_ranges"]
        self.assertEqual(self._without_residual_measure(launches, ranges),
                         [ranges[name]["entry_pc"] for name in (
            "iht_dense_rebuild",
            "iht_dense_correlation", "vector_axpy", "topk_stream",
            "iht_support_replace", "htp_fresh_refinement_marker",
            "iht_support_pack",
            "restricted_refinement_restart_residual",
            "restricted_refinement_transpose",
            "restricted_refinement_restart_direction",
            "phi_support_forward",
            "restricted_refinement_pre_transpose",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_continuation",
            "htp_support_coefficient_scatter", "htp_dense_scatter",
            "residual_update",
            "residual_update", "restricted_refinement_restart_residual",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_restart_direction")])
        self.assertEqual(self.htp["scalar_preloads"], [{
            "address": 0,
            "value_s27f19_raw": m11_program_images.HTP_DEFAULT_STEP_SIZE_S27F19_RAW,
            "semantic": "htp_step_size",
        }])
        self.assertEqual(len(instructions), 65)
        self.assertNotEqual(self.htp["phase_crc32"], 0)
        self.assertEqual(len(m11_program_images.mem_files()
                             ["program_03_phase.mem"].splitlines()), 65)

    def test_sp_phase_accepts_then_rolls_back_non_decrease(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.sp["phase_instructions"]]
        ranges = self.sp["array_context_ranges"]
        launches = []
        certificate_count = 0
        residual_count = 0
        pc = 0
        for _ in range(500):
            instruction = instructions[pc]
            if instruction.operation == isa.PhaseOperation.LAUNCH_ARRAY:
                launches.append(instruction.array_entry_pc)
                if instruction.array_entry_pc == \
                        ranges["restricted_refinement_certificate"]["entry_pc"]:
                    certificate_count += 1
                if instruction.array_entry_pc == \
                        ranges["residual_update"]["entry_pc"]:
                    residual_count += 1
                pc += 1
            elif instruction.operation == isa.PhaseOperation.WAIT_CONDITION:
                pc += 1
            elif instruction.operation == isa.PhaseOperation.BRANCH:
                take = instruction.condition_select == isa.PhaseCondition.ALWAYS
                if instruction.condition_select == isa.PhaseCondition.SOLVER_FAULT:
                    take = False
                elif instruction.condition_select == \
                        isa.PhaseCondition.SOLVER_CONVERGED:
                    take = certificate_count % 2 == 0
                elif instruction.condition_select == \
                        isa.PhaseCondition.RESIDUAL_DECREASED:
                    take = residual_count == 3
                elif instruction.condition_select in {
                        isa.PhaseCondition.RESIDUAL_LIMIT,
                        isa.PhaseCondition.ITERATION_LIMIT,
                        isa.PhaseCondition.SUPPORT_STABLE,
                        isa.PhaseCondition.SOLVER_RECOMPUTE_REQUIRED,
                        isa.PhaseCondition.SOLVER_REPLACEMENT_REQUIRED}:
                    take = False
                pc = instruction.target_pc if take else pc + 1
            elif instruction.operation == isa.PhaseOperation.COMPLETE:
                self.assertEqual(instruction.terminal_code, 4)
                break
            else:
                self.fail(f"unexpected SP phase operation {instruction.operation}")
        else:
            self.fail("SP phase trace did not terminate")
        self.assertEqual(launches.count(ranges["sp_union_2k"]["entry_pc"]), 2)
        self.assertEqual(launches.count(ranges["sp_prune_support"]["entry_pc"]), 2)
        self.assertEqual(launches.count(
            ranges["sp_proposal_coefficient_scatter"]["entry_pc"]), 4)
        self.assertEqual(launches.count(ranges["sp_accept"]["entry_pc"]), 1)
        self.assertEqual(launches.count(ranges["sp_rollback"]["entry_pc"]), 1)
        self.assertEqual(residual_count, 6)
        self.assertEqual(len(instructions), 163)
        self.assertEqual(len(m11_program_images.mem_files()
                             ["program_04_phase.mem"].splitlines()), 163)

    def test_gp_phase_reselection_keeps_support_stable_nonterminal(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.gp["phase_instructions"]]
        ranges = self.gp["array_context_ranges"]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        self.assertEqual(self._without_residual_measure(launches, ranges),
                         [ranges[name]["entry_pc"] for name in (
            "iht_dense_correlation", "gp_top1_stream", "gp_support_policy",
            "iht_support_pack",
            "gp_direction_pack", "phi_support_forward", "gp_line_search",
            "gp_update", "htp_support_coefficient_scatter",
            "htp_dense_scatter", "residual_update")])
        branch_conditions = [item.condition_select for item in instructions
                             if item.operation == isa.PhaseOperation.BRANCH]
        self.assertNotIn(isa.PhaseCondition.SUPPORT_STABLE, branch_conditions)
        self.assertEqual(len(instructions), 29)
        self.assertNotEqual(self.gp["phase_crc32"], 0)
        self.assertEqual(len(m11_program_images.mem_files()
                             ["program_05_phase.mem"].splitlines()), 29)

    def test_gomp_phase_uses_context_owned_top2_group(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.gomp["phase_instructions"]]
        ranges = self.gomp["array_context_ranges"]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        self.assertEqual(self._without_residual_measure(launches, ranges),
                         [ranges[name]["entry_pc"] for name in (
            "iht_dense_correlation", "gomp_top2_stream",
            "gomp_support_union", "iht_support_pack",
            "restricted_refinement_initialize", "phi_support_forward",
            "restricted_refinement_pre_transpose",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_continuation",
            "htp_support_coefficient_scatter", "htp_dense_scatter",
            "residual_update",
            "residual_update", "restricted_refinement_restart_residual",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_restart_direction")])
        self.assertEqual(self.gomp["selection_k"], 2)
        self.assertEqual(len(instructions), 55)
        self.assertNotEqual(self.gomp["phase_crc32"], 0)
        self.assertEqual(len(m11_program_images.mem_files()
                             ["program_06_phase.mem"].splitlines()), 55)

    def test_mp_phase_is_rank_one_without_restricted_ls(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.mp["phase_instructions"]]
        ranges = self.mp["array_context_ranges"]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        self.assertEqual(self._without_residual_measure(launches, ranges),
                         [ranges[name]["entry_pc"] for name in (
            "iht_dense_correlation", "gp_top1_stream", "gp_support_policy",
            "iht_support_pack", "mp_direction_pack", "phi_support_forward",
            "gp_line_search", "gp_update",
            "htp_support_coefficient_scatter", "htp_dense_scatter",
            "residual_update")])
        self.assertFalse(any("restricted_refinement" in name
                             for name in ranges))
        branch_conditions = [item.condition_select for item in instructions
                             if item.operation == isa.PhaseOperation.BRANCH]
        self.assertNotIn(isa.PhaseCondition.SUPPORT_STABLE, branch_conditions)
        self.assertEqual(self.mp["selection_k"], 1)
        self.assertEqual(len(instructions), 29)
        self.assertEqual(len(m11_program_images.mem_files()
                             ["program_07_phase.mem"].splitlines()), 29)

    def test_readiness_is_generated_from_current_context_library(self) -> None:
        readiness = m11_program_images.readiness_payload(self.library)
        self.assertEqual(readiness["context_revision"], isa.CONTEXT_FORMAT_REVISION)
        self.assertEqual(readiness["array_context_count"],
                         self.iht["array_context_count"])
        self.assertEqual(
            readiness["implemented_program_ids"],
            [0, 1, 2, 3, 4, 5, 6, 7])
        programs = {item["program_id"]: item for item in readiness["programs"]}
        self.assertEqual(programs[1]["status"], "READY")
        self.assertTrue(programs[1]["phase_image_packaged"])
        self.assertEqual(programs[1]["phase_crc32"], self.cosamp["phase_crc32"])
        self.assertEqual(programs[1]["blockers"], [])
        self.assertIn("reports/v3/M11_COSAMP_STATUS.md",
                      programs[1]["qualification_evidence"])
        self.assertEqual(programs[2]["status"], "READY")
        self.assertTrue(programs[2]["phase_image_packaged"])
        self.assertEqual(programs[2]["phase_crc32"], self.iht["phase_crc32"])
        self.assertIn("reports/v3/m8_vivado/summary.txt",
                      programs[2]["qualification_evidence"])
        topk = next(item for item in programs[2]["phases"]
                    if item["phase"] == "TOP_K")
        self.assertEqual(topk["lowering"]["targets"], [
            "topk_stream", "iht_support_replace", "iht_dense_rebuild",
            "iht_support_pack"])
        self.assertTrue(topk["hardware_callable"])
        self.assertEqual(programs[3]["status"], "READY")
        self.assertTrue(programs[3]["phase_image_packaged"])
        self.assertEqual(programs[3]["phase_crc32"], self.htp["phase_crc32"])
        self.assertEqual(programs[3]["blockers"], [])
        self.assertIn("reports/v3/m8_vivado/summary.txt",
                      programs[3]["qualification_evidence"])
        self.assertEqual(programs[4]["status"], "READY")
        self.assertTrue(programs[4]["phase_image_packaged"])
        self.assertEqual(programs[4]["phase_crc32"], self.sp["phase_crc32"])
        self.assertEqual(programs[4]["blockers"], [])
        self.assertEqual(programs[5]["status"], "READY")
        self.assertTrue(programs[5]["phase_image_packaged"])
        self.assertEqual(programs[5]["phase_crc32"], self.gp["phase_crc32"])
        self.assertEqual(programs[5]["blockers"], [])
        self.assertIn("reports/v3/M11_GP_STATUS.md",
                      programs[5]["qualification_evidence"])
        self.assertEqual(programs[6]["status"], "READY")
        self.assertTrue(programs[6]["phase_image_packaged"])
        self.assertEqual(programs[6]["phase_crc32"], self.gomp["phase_crc32"])
        self.assertEqual(programs[6]["blockers"], [])
        self.assertIn("reports/v3/M11_GOMP_STATUS.md",
                      programs[6]["qualification_evidence"])
        self.assertEqual(programs[6]["phases"][1]["lowering"], {
            "kind": "resident_segment", "target": "gomp_top2_stream"})
        self.assertEqual(programs[7]["status"], "READY")
        self.assertTrue(programs[7]["phase_image_packaged"])
        self.assertEqual(programs[7]["phase_crc32"], self.mp["phase_crc32"])
        self.assertEqual(programs[7]["blockers"], [])
        self.assertIn("reports/v3/M11_MP_STATUS.md",
                      programs[7]["qualification_evidence"])
        self.assertEqual(programs[7]["phases"][1]["lowering"], {
            "kind": "resident_segment", "target": "gp_top1_stream"})
    def test_omp_phase_sequence_and_crc(self) -> None:
        words = [item["word"] for item in self.program["phase_instructions"]]
        instructions = [isa.unpack_phase(word) for word in words]
        launches = [item.array_entry_pc for item in instructions
                    if item.operation == isa.PhaseOperation.LAUNCH_ARRAY]
        ranges = self.program["array_context_ranges"]
        self.assertEqual(launches[:3], [
            ranges["correlation"]["entry_pc"],
            ranges["omp_support_append_commit"]["entry_pc"],
            ranges["restricted_refinement_initialize"]["entry_pc"],
        ])
        self.assertEqual(len(words), 47)
        self.assertEqual(self.program["selection_k"], 1)
        self.assertNotEqual(self.program["phase_crc32"], 0)
        self.assertEqual(len(m11_program_images.mem_files()["program_00_phase.mem"].splitlines()), 47)

    def test_stale_context_library_is_rejected(self) -> None:
        from compiler.v3 import scheduled_context_compiler
        compiled = scheduled_context_compiler.payload()
        compiled["architecture_hash"] = "stale"
        with self.assertRaises(ValueError):
            m11_program_images.omp_program(compiled)
        with self.assertRaises(ValueError):
            m11_program_images.iht_program(compiled)
        with self.assertRaises(ValueError):
            m11_program_images.htp_program(compiled)
        with self.assertRaises(ValueError):
            m11_program_images.sp_program(compiled)

    def test_corrupt_phase_crc_is_rejected(self) -> None:
        corrupt = copy.deepcopy(self.program)
        corrupt["phase_instructions"][0]["word"] ^= 1 << 3
        with self.assertRaisesRegex(ValueError, "CRC mismatch"):
            m11_program_images.validate_program(corrupt)

    def test_scalar_preload_contract_is_fail_closed(self) -> None:
        invalid_address = copy.deepcopy(self.program)
        invalid_address["scalar_preloads"] = [
            {"address": 2, "value_s27f19_raw": 1}]
        with self.assertRaisesRegex(ValueError, "address"):
            m11_program_images.validate_program(invalid_address)
        invalid_value = copy.deepcopy(self.program)
        invalid_value["scalar_preloads"] = [
            {"address": 0, "value_s27f19_raw": 1 << 26}]
        with self.assertRaisesRegex(ValueError, "S27F19"):
            m11_program_images.validate_program(invalid_value)
        with self.assertRaisesRegex(ValueError, "nonzero"):
            m11_program_images.iht_program(step_size_s27f19_raw=0)
        with self.assertRaisesRegex(ValueError, "nonzero"):
            m11_program_images.htp_program(step_size_s27f19_raw=0)

    def test_omp_phase_trace_reaches_residual_completion(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.program["phase_instructions"]]
        pc = 0
        launches = []
        for _ in range(80):
            instruction = instructions[pc]
            if instruction.operation == isa.PhaseOperation.LAUNCH_ARRAY:
                launches.append(instruction.array_entry_pc)
                pc += 1
            elif instruction.operation == isa.PhaseOperation.WAIT_CONDITION:
                pc += 1
            elif instruction.operation == isa.PhaseOperation.BRANCH:
                condition = {
                    isa.PhaseCondition.ALWAYS: True,
                    isa.PhaseCondition.SOLVER_FAULT: False,
                    isa.PhaseCondition.SOLVER_CONVERGED: True,
                    isa.PhaseCondition.RESIDUAL_LIMIT: True,
                    isa.PhaseCondition.ITERATION_LIMIT: False,
                    isa.PhaseCondition.SUPPORT_STABLE: False,
                    isa.PhaseCondition.SOLVER_RECOMPUTE_REQUIRED: False,
                    isa.PhaseCondition.SOLVER_REPLACEMENT_REQUIRED: False,
                }[instruction.condition_select]
                pc = instruction.target_pc if condition else pc + 1
            elif instruction.operation == isa.PhaseOperation.COMPLETE:
                self.assertEqual(instruction.terminal_code, 1)
                break
            else:
                self.fail(f"unexpected phase operation {instruction.operation}")
        else:
            self.fail("OMP phase trace did not terminate")
        ranges = self.program["array_context_ranges"]
        self.assertEqual(launches, self._with_residual_measure([
            ranges["correlation"]["entry_pc"],
            ranges["omp_support_append_commit"]["entry_pc"],
            ranges["restricted_refinement_initialize"]["entry_pc"],
            ranges["phi_support_forward"]["entry_pc"],
            ranges["restricted_refinement_pre_transpose"]["entry_pc"],
            ranges["restricted_refinement_transpose"]["entry_pc"],
            ranges["restricted_refinement_certificate"]["entry_pc"],
            ranges["htp_support_coefficient_scatter"]["entry_pc"],
            ranges["residual_update"]["entry_pc"],
        ], ranges))

    def test_iht_phase_trace_loops_then_reaches_each_stop(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.iht["phase_instructions"]]
        ranges = self.iht["array_context_ranges"]
        prefix = [ranges["iht_dense_rebuild"]["entry_pc"]]
        expected_launches = [
            ranges[name]["entry_pc"]
            for name in ("iht_dense_correlation", "vector_axpy", "topk_stream",
                         "iht_support_replace", "iht_dense_rebuild",
                         "iht_support_pack", "residual_update")]

        def trace(stop_condition: isa.PhaseCondition,
                  continue_iterations: int) -> tuple[list[int], int]:
            pc = 0
            launches = []
            completed_iterations = 0
            for _ in range(160):
                instruction = instructions[pc]
                if instruction.operation == isa.PhaseOperation.LAUNCH_ARRAY:
                    launches.append(instruction.array_entry_pc)
                    pc += 1
                elif instruction.operation == isa.PhaseOperation.WAIT_CONDITION:
                    pc += 1
                elif instruction.operation == isa.PhaseOperation.BRANCH:
                    take = instruction.condition_select == isa.PhaseCondition.ALWAYS
                    if instruction.condition_select == stop_condition:
                        take = completed_iterations >= continue_iterations
                    if (instruction.condition_select == isa.PhaseCondition.ALWAYS
                            and take):
                        completed_iterations += 1
                    pc = instruction.target_pc if take else pc + 1
                elif instruction.operation == isa.PhaseOperation.COMPLETE:
                    return launches, instruction.terminal_code
                else:
                    self.fail(f"unexpected phase operation {instruction.operation}")
            self.fail("IHT phase trace did not terminate")

        for condition, terminal_code in (
                (isa.PhaseCondition.RESIDUAL_LIMIT, 1),
                (isa.PhaseCondition.ITERATION_LIMIT, 2)):
            with self.subTest(condition=condition):
                launches, observed_code = trace(condition, 1)
                self.assertEqual(observed_code, terminal_code)
                self.assertEqual(
                    launches,
                    prefix + self._with_residual_measure(expected_launches, ranges) * 2)

    def test_htp_phase_trace_refines_then_rebuilds_dense_state(self) -> None:
        instructions = [isa.unpack_phase(item["word"])
                        for item in self.htp["phase_instructions"]]
        ranges = self.htp["array_context_ranges"]
        prefix = [ranges["iht_dense_rebuild"]["entry_pc"]]
        expected_launches = [ranges[name]["entry_pc"] for name in (
            "iht_dense_correlation", "vector_axpy", "topk_stream",
            "iht_support_replace", "htp_fresh_refinement_marker",
            "iht_support_pack",
            "restricted_refinement_restart_residual",
            "restricted_refinement_transpose",
            "restricted_refinement_restart_direction",
            "phi_support_forward",
            "restricted_refinement_pre_transpose",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "restricted_refinement_continuation", "phi_support_forward",
            "restricted_refinement_pre_transpose",
            "restricted_refinement_transpose",
            "restricted_refinement_certificate",
            "htp_support_coefficient_scatter", "htp_dense_scatter",
            "residual_update")]
        pc = 0
        launches = []
        certificate_count = 0
        outer_count = 0
        for _ in range(240):
            instruction = instructions[pc]
            if instruction.operation == isa.PhaseOperation.LAUNCH_ARRAY:
                launches.append(instruction.array_entry_pc)
                if instruction.array_entry_pc == \
                        ranges["restricted_refinement_certificate"]["entry_pc"]:
                    certificate_count += 1
                pc += 1
            elif instruction.operation == isa.PhaseOperation.WAIT_CONDITION:
                pc += 1
            elif instruction.operation == isa.PhaseOperation.BRANCH:
                take = instruction.condition_select == isa.PhaseCondition.ALWAYS
                if instruction.condition_select == isa.PhaseCondition.SOLVER_FAULT:
                    take = False
                elif instruction.condition_select in {
                        isa.PhaseCondition.SOLVER_RECOMPUTE_REQUIRED,
                        isa.PhaseCondition.SOLVER_REPLACEMENT_REQUIRED}:
                    take = False
                elif instruction.condition_select == \
                        isa.PhaseCondition.SOLVER_CONVERGED:
                    take = certificate_count % 2 == 0
                elif instruction.condition_select == \
                        isa.PhaseCondition.ITERATION_LIMIT:
                    take = outer_count == 1
                elif instruction.condition_select in {
                        isa.PhaseCondition.RESIDUAL_LIMIT,
                        isa.PhaseCondition.SUPPORT_STABLE}:
                    take = False
                if instruction.condition_select == isa.PhaseCondition.ALWAYS and \
                        instruction.target_pc == 2:
                    outer_count += 1
                pc = instruction.target_pc if take else pc + 1
            elif instruction.operation == isa.PhaseOperation.COMPLETE:
                self.assertEqual(instruction.terminal_code, 2)
                break
            else:
                self.fail(f"unexpected HTP phase operation {instruction.operation}")
        else:
            self.fail("HTP phase trace did not terminate")
        self.assertEqual(
            launches,
            prefix + self._with_residual_measure(expected_launches, ranges) * 2)


if __name__ == "__main__":
    unittest.main()
