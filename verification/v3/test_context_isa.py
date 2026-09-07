from __future__ import annotations

import unittest

from compiler.v3 import context_isa as isa


class ContextIsaTests(unittest.TestCase):
    def test_tile_context_round_trip(self) -> None:
        context = isa.TileContext(
            operation=isa.TileOperation.SATURATING_ADD,
            source_a=isa.OperandSource.LOCAL_RF,
            source_b=isa.OperandSource.EXTERNAL,
            rf_read_a=7,
            rf_write_address=3,
            rf_write_enable=1,
            route_east_select=isa.RouteSource.PE_RESULT,
        )
        self.assertEqual(isa.unpack_tile(isa.pack_tile(context)), context)

    def test_one_array_control_word_drives_both_clusters(self) -> None:
        context = isa.ArrayControlContext(
            next_pc=12,
            next_pc_mode=isa.NextPcMode.COUNTED_LOOP,
            loop_limit_select=isa.LoopLimitSource.MEASUREMENT_COUNT,
            cluster_enable_mask=0b11,
        )
        self.assertEqual(
            isa.unpack_array_control(isa.pack_array_control(context)), context
        )

    def test_array_control_rejects_empty_cluster_mask(self) -> None:
        with self.assertRaises(ValueError):
            isa.pack_array_control(isa.ArrayControlContext(cluster_enable_mask=0))

    def test_guaranteed_commit_cross_word_contract(self) -> None:
        control = isa.ArrayControlContext(guaranteed_commit=1)
        isa.validate_context_bundle(control, isa.StreamContext(), isa.ResourceContext())
        with self.assertRaises(ValueError):
            isa.validate_context_bundle(
                control,
                isa.StreamContext(vector_read_a_enable=1),
                isa.ResourceContext(),
            )
        with self.assertRaises(ValueError):
            isa.validate_context_bundle(
                control,
                isa.StreamContext(),
                isa.ResourceContext(wait_for_ready=1),
            )
        with self.assertRaises(ValueError):
            isa.validate_context_bundle(
                isa.ArrayControlContext(
                    guaranteed_commit=1,
                    next_pc_mode=isa.NextPcMode.WAIT_EVENT,
                ),
                isa.StreamContext(),
                isa.ResourceContext(),
            )

    def test_phase_instruction_round_trip(self) -> None:
        instruction = isa.PhaseInstruction(
            operation=isa.PhaseOperation.LAUNCH_ARRAY,
            array_entry_pc=3,
            condition_select=isa.PhaseCondition.ARRAY_ROUTINE_DONE,
            condition_invert=1,
            target_pc=8,
            event_id=2,
            terminal_code=4,
            safe_abort_point=1,
            trace_emit=1,
        )
        self.assertEqual(isa.unpack_phase(isa.pack_phase(instruction)), instruction)

    def test_stream_context_can_consume_memory_and_phi_together(self) -> None:
        context = isa.StreamContext(
            vector_read_a_enable=1,
            vector_configuration_a=5,
            external_a_select=isa.ExternalStreamSource.VECTOR_A,
            phi_command=isa.PhiStreamCommand.CONSUME,
            advance_vector_streams=1,
            stall_on_input=1,
        )
        self.assertEqual(isa.unpack_stream(isa.pack_stream(context)), context)

    def test_field_width_is_enforced(self) -> None:
        with self.assertRaises(ValueError):
            isa.pack_tile(isa.TileContext(rf_read_a=8))
        with self.assertRaises(ValueError):
            isa.pack_phase(isa.PhaseInstruction(array_entry_pc=256))
        with self.assertRaises(ValueError):
            isa.pack_phase(isa.PhaseInstruction(reserved=1))

    def test_revision_rejects_undefined_enum_encoding(self) -> None:
        with self.assertRaises(ValueError):
            isa.pack_tile(isa.TileContext(operation=63))
        with self.assertRaises(ValueError):
            isa.unpack_phase(0x0f)
        self.assertEqual(
            isa.unpack_tile(isa.pack_tile(isa.TileContext(
                operation=isa.TileOperation.PHI_ACCUMULATE))).operation,
            isa.TileOperation.PHI_ACCUMULATE)
        with self.assertRaises(ValueError):
            isa.pack_tile(isa.TileContext(operation=16))

    def test_every_word_layout_covers_its_exact_width(self) -> None:
        for layout, width in (
            (isa.TILE_FIELDS, isa.TILE_CONTEXT_WIDTH),
            (isa.ARRAY_CONTROL_FIELDS, isa.ARRAY_CONTROL_CONTEXT_WIDTH),
            (isa.STREAM_FIELDS, isa.STREAM_CONTEXT_WIDTH),
            (isa.PHASE_FIELDS, isa.PHASE_INSTRUCTION_WIDTH),
            (isa.RESOURCE_FIELDS, isa.RESOURCE_CONTEXT_WIDTH),
            (isa.MEMORY_CONFIGURATION_FIELDS, isa.MEMORY_CONFIGURATION_WIDTH),
        ):
            occupied = 0
            for field in layout.values():
                self.assertEqual(occupied & field.mask, 0)
                occupied |= field.mask
            self.assertEqual(occupied, (1 << width) - 1)

    def test_resource_context_round_trip(self) -> None:
        context = isa.ResourceContext(
            operation=isa.ResourceOperation.TOPK_PUSH,
            input_select=isa.ResourceInput.EAST_EDGE,
            output_select=isa.ResourceOutput.TOPK_STATE,
            configuration_id=17,
            count_select=isa.ResourceCountSource.IMMEDIATE,
            lane_mask=0x0f,
            stream_boundary=isa.StreamBoundary.FIRST,
            clear_before=1,
            wait_for_ready=1,
            event_id=3,
        )
        self.assertEqual(isa.unpack_resource(isa.pack_resource(context)), context)

    def test_shared_vector_arithmetic_is_a_scheduled_resource(self) -> None:
        for operation in (
            isa.ResourceOperation.SHARED_VECTOR_DOT,
            isa.ResourceOperation.SHARED_VECTOR_NORM_SQ,
            isa.ResourceOperation.SHARED_VECTOR_SCALE,
            isa.ResourceOperation.SHARED_VECTOR_AXPY,
            isa.ResourceOperation.SHARED_VECTOR_COPY,
            isa.ResourceOperation.REFINEMENT_CHECK,
        ):
            context = isa.ResourceContext(
                operation=operation,
                input_select=isa.ResourceInput.MEMORY_STREAM,
                output_select=isa.ResourceOutput.MEMORY_STREAM,
                count_select=isa.ResourceCountSource.ACTIVE_WORK_COUNT,
                lane_mask=0xf,
                wait_for_ready=1,
                wait_for_result=1,
            )
            self.assertEqual(isa.unpack_resource(isa.pack_resource(context)), context)

    def test_reserved_scalar_encodings_remain_decodable(self) -> None:
        for operation in (isa.ResourceOperation.SCALAR_RECIPROCAL,
                          isa.ResourceOperation.SCALAR_SQRT):
            context = isa.ResourceContext(operation=operation)
            self.assertEqual(isa.unpack_resource(isa.pack_resource(context)), context)

    def test_memory_configuration_round_trip(self) -> None:
        configuration = isa.MemoryConfiguration(
            base_word_address=0x120,
            element_count=1024,
            element_stride_words=1,
            bank_base=0,
            bank_count_log2=3,
            bank_mode=isa.BankMode.CYCLIC,
            element_format=isa.ElementFormat.DATA18,
            packing_mode=isa.PackingMode.FOUR,
            read_enable=1,
            write_enable=1,
            atomic_commit=1,
            memory_space=isa.MemorySpace.VECTOR_SCRATCHPAD,
        )
        self.assertEqual(
            isa.unpack_memory_configuration(isa.pack_memory_configuration(configuration)),
            configuration,
        )

    def test_word_width_and_configuration_reserved_bits_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            isa.unpack_resource(1 << isa.RESOURCE_CONTEXT_WIDTH)
        with self.assertRaises(ValueError):
            isa.unpack_memory_configuration(1 << 63)
        with self.assertRaises(ValueError):
            isa.unpack_memory_configuration(7 << 49)


if __name__ == "__main__":
    unittest.main()
