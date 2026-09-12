"""Functional and structural checks for the predicted v4 GEMV mapping."""
from dataclasses import replace
import json
import random
import unittest

from compiler.v4.mapping import Architecture, MatrixLayout, compile_gemv, predicted_cycles, replay


class MappingTests(unittest.TestCase):
    def test_integer_replay_matches_independent_matvec_with_tails(self):
        rng = random.Random(41817)
        for rows in (1, 3, 4, 7, 8, 9, 16, 17):
            for columns in (1, 2, 3, 4, 5, 7, 8, 9, 16, 31):
                matrix = [[rng.randrange(-31, 32) for _ in range(columns)] for _ in range(rows)]
                for transpose in (False, True):
                    for reduction_lanes in (None, 1, 4):
                        with self.subTest(rows=rows, columns=columns, transpose=transpose, R=reduction_lanes):
                            schedule = compile_gemv(rows, columns, transpose=transpose,
                                                    reduction_lanes=reduction_lanes)
                            vector = [rng.randrange(-17, 18) for _ in range(schedule.layout.reduction_count)]
                            expected = ([sum(matrix[r][c] * vector[r] for r in range(rows))
                                         for c in range(columns)] if transpose else
                                        [sum(matrix[r][c] * vector[c] for c in range(columns))
                                         for r in range(rows)])
                            self.assertEqual(replay(schedule, matrix, vector), expected)

    def test_layout_is_bijective_and_dispatch_conflict_free(self):
        for transpose in (False, True):
            layout = MatrixLayout(17, 35, transpose)
            addresses = set()
            for output in range(layout.output_count):
                for reduction in range(layout.reduction_count):
                    address = layout.address(output, reduction)
                    self.assertNotIn(address, addresses)
                    addresses.add(address)
            self.assertEqual(len(addresses), 17 * 35)
            for reduction_lanes in (1, 4):
                schedule = compile_gemv(17, 35, transpose=transpose, reduction_lanes=reduction_lanes)
                for cycle in schedule.cycles:
                    banks = [request.bank for request in cycle.bank_reads]
                    self.assertEqual(len(banks), len(set(banks)))

    def test_forward_and_transpose_layouts_are_not_claimed_interchangeable(self):
        forward, transpose = MatrixLayout(17, 35), MatrixLayout(17, 35, True)
        # Same physical A[5][9], different operator coordinates and banks.
        self.assertNotEqual(forward.address(5, 9), transpose.address(9, 5))

    def test_metrics_use_complete_compute_cycles_and_only_real_macs(self):
        schedule = compile_gemv(128, 1024, reduction_lanes=4)
        metrics = schedule.metrics
        self.assertEqual(metrics["predicted_compute_cycles"], 16 * (256 + 7))
        self.assertEqual(metrics["useful_mac_count"], 128 * 1024)
        self.assertEqual(metrics["peak_macs_per_cycle"], 32)
        self.assertEqual(metrics["registered_link_transfers"], 128 * 4)
        self.assertEqual(metrics["scheduled_reduction_adds"], 128 * 3)
        self.assertAlmostEqual(metrics["mac_slot_utilization"], 256 / 263)
        self.assertIsNone(metrics["rtl_measured_cycles"])
        self.assertIn("host/DMA", metrics["costs_excluded"])
        self.assertEqual(json.loads(json.dumps(schedule.to_dict()))["metrics"], metrics)

    def test_all_32_pes_do_real_mac_work(self):
        for rows, reduction_lanes in ((8, 4), (32, 1)):
            schedule = compile_gemv(rows, 8, reduction_lanes=reduction_lanes)
            active = [event.pe for event in schedule.cycles[1].pe_events]
            self.assertEqual(active, list(range(32)))
            self.assertTrue(all(schedule.architecture.adjacent(route.source_pe, route.destination_pe)
                                for cycle in schedule.cycles for route in cycle.routes))

    def test_invalid_architecture_shapes_and_input_types(self):
        for args in ((0, 8), (8, 0), (-1, 8), (2.5, 8), (True, 8)):
            with self.subTest(args=args), self.assertRaises(ValueError):
                compile_gemv(*args)
        with self.assertRaises(ValueError):
            Architecture(clusters=1)
        with self.assertRaises(ValueError):
            Architecture(link_latency=2)
        with self.assertRaises(ValueError):
            Architecture(inter_array_neighbor_links=True)
        with self.assertRaises(ValueError):
            compile_gemv(2, 3, transpose=1)
        with self.assertRaises(ValueError):
            compile_gemv(2, 3, reduction_lanes=2)
        with self.assertRaises(ValueError):
            compile_gemv(2, 3, reduction_lanes=1.0)
        schedule = compile_gemv(2, 3)
        for matrix, vector in (([[1, 2, 3]], [1, 2, 3]),
                               ([[1, 2, 3], [1, 2]], [1, 2, 3]),
                               ([[1, 2, 3], [1, 2, 3]], [1, 2]),
                               ([[1.0, 2, 3], [1, 2, 3]], [1, 2, 3]),
                               ([[1, 2, 3], [1, 2, 3]], [True, 2, 3])):
            with self.subTest(matrix=matrix, vector=vector), self.assertRaises(ValueError):
                replay(schedule, matrix, vector)

    def test_off_mesh_and_row_wrap_edges_rejected(self):
        arch = Architecture()
        self.assertFalse(arch.adjacent(12, 16))  # MVP has no inter-array mesh connector.
        self.assertFalse(arch.adjacent(15, 19))
        self.assertFalse(arch.adjacent(3, 4))
        schedule = compile_gemv(8, 8, reduction_lanes=4)
        cycle_index = next(i for i, cycle in enumerate(schedule.cycles) if cycle.routes)
        cycle = schedule.cycles[cycle_index]
        for destination in (3, 4, 7):
            route = replace(cycle.routes[0], destination_pe=destination)
            cycles = list(schedule.cycles)
            cycles[cycle_index] = replace(cycle, routes=(route,) + cycle.routes[1:])
            with self.subTest(destination=destination), self.assertRaisesRegex(ValueError, "one-hop"):
                replay(replace(schedule, cycles=tuple(cycles)), [[1] * 8 for _ in range(8)], [1] * 8)
        route = replace(cycle.routes[0], source_pe=12, destination_pe=16)
        cycles = list(schedule.cycles)
        cycles[cycle_index] = replace(cycle, routes=(route,) + cycle.routes[1:])
        with self.assertRaisesRegex(ValueError, "one-hop"):
            replay(replace(schedule, cycles=tuple(cycles)), [[1] * 8 for _ in range(8)], [1] * 8)

    def test_route_values_replayed_and_bad_value_rejected(self):
        schedule = compile_gemv(1, 4, reduction_lanes=4)
        matrix, vector = [[2, 3, 5, 7]], [11, 13, 17, 19]
        self.assertEqual(replay(schedule, matrix, vector), [279])
        index = next(i for i, cycle in enumerate(schedule.cycles) if cycle.phase == "cross_route_2")
        cycles = list(schedule.cycles)
        route = replace(cycles[index].routes[0], value_id="not_a_live_register")
        cycles[index] = replace(cycles[index], routes=(route,))
        with self.assertRaisesRegex(ValueError, "not uniquely available"):
            replay(replace(schedule, cycles=tuple(cycles)), matrix, vector)

    def test_same_cycle_multihop_cannot_read_new_link(self):
        schedule = compile_gemv(1, 4, reduction_lanes=4)
        first = next(i for i, cycle in enumerate(schedule.cycles) if cycle.phase == "cross_route_1")
        cycles = list(schedule.cycles)
        cycles[first] = replace(cycles[first], routes=cycles[first].routes + cycles[first + 1].routes)
        cycles[first + 1] = replace(cycles[first + 1], routes=())
        with self.assertRaisesRegex(ValueError, "not uniquely available"):
            replay(replace(schedule, cycles=tuple(cycles)), [[1, 2, 3, 4]], [1] * 4)

    def test_link_capacity_and_bank_address_contract(self):
        schedule = compile_gemv(1, 4, reduction_lanes=4)
        cycles = list(schedule.cycles)
        route_cycle = next(i for i, cycle in enumerate(cycles) if cycle.routes)
        cycles[route_cycle] = replace(cycles[route_cycle], routes=cycles[route_cycle].routes * 2)
        with self.assertRaisesRegex(ValueError, "capacity"):
            replay(replace(schedule, cycles=tuple(cycles)), [[1] * 4], [1] * 4)
        cycles = list(schedule.cycles)
        event = replace(cycles[1].pe_events[0], matrix_address=1)
        cycles[1] = replace(cycles[1], pe_events=(event,) + cycles[1].pe_events[1:])
        with self.assertRaisesRegex(ValueError, "bank/address/PE"):
            replay(replace(schedule, cycles=tuple(cycles)), [[1] * 4], [1] * 4)

    def test_accumulator_and_routed_partial_precision(self):
        schedule = compile_gemv(1, 4, architecture=Architecture(accumulator_bits=8), reduction_lanes=4)
        with self.assertRaisesRegex(ValueError, "overflow"):
            replay(schedule, [[100, 100, 100, 100]], [1] * 4)
        self.assertEqual(replay(schedule, [[100] * 4], [1] * 4, check_accumulator_range=False), [400])
        self.assertEqual(replay(schedule, [[-128, 0, 0, 0]], [1] * 4), [-128])

    def test_missing_store_and_duplicate_pe_rejected(self):
        schedule = compile_gemv(1, 4, reduction_lanes=4)
        with self.assertRaisesRegex(ValueError, "store every"):
            replay(replace(schedule, cycles=schedule.cycles[:-1]), [[1] * 4], [1] * 4)
        cycles = list(schedule.cycles)
        cycles[1] = replace(cycles[1], pe_events=cycles[1].pe_events * 2)
        with self.assertRaisesRegex(ValueError, "one PE slot"):
            replay(replace(schedule, cycles=tuple(cycles)), [[1] * 4], [1] * 4)

    def test_support_aware_choice_uses_complete_schedule_cost(self):
        forward = compile_gemv(128, 8)
        transpose = compile_gemv(128, 8, transpose=True)
        self.assertEqual((forward.reduction_lanes, len(forward.cycles)), (1, 40))
        self.assertEqual((transpose.reduction_lanes, len(transpose.cycles)), (4, 39))
        self.assertEqual(predicted_cycles(128, 8, 4), 144)
        self.assertEqual(predicted_cycles(8, 128, 1), 130)
        self.assertEqual(forward.metrics["matrix_storage_words_padded"], 128 * 8)
        self.assertEqual(transpose.metrics["matrix_storage_words_padded"], 32 * 128)
        self.assertEqual(compile_gemv(128, 8, reduction_lanes=4).layout, forward.layout)

    def test_bank_steering_needs_only_documented_group_permutations(self):
        layout = MatrixLayout(128, 35)
        for k in range(35):
            for pe in range(32):
                # R1: four groups of eight banks rotate by k modulo four.
                expected = pe % 8 + 8 * ((pe // 8 + k) % 4)
                self.assertEqual(layout.address(pe, k)[0], expected)
        for base in range(0, 128, 8):
            for col in range(4):
                for row in range(8):
                    # R4: fixed transpose plus rotation by output tile group.
                    expected = row + 8 * ((base // 8 + col) % 4)
                    self.assertEqual(layout.address(base + row, col)[0], expected)

    def test_synchronous_bank_response_cannot_be_used_same_cycle(self):
        schedule = compile_gemv(1, 4, reduction_lanes=4)
        cycles = list(schedule.cycles)
        cycles[1] = replace(cycles[1], bank_reads=cycles[0].bank_reads)
        cycles[0] = replace(cycles[0], bank_reads=())
        with self.assertRaisesRegex(ValueError, "earlier cycle"):
            replay(replace(schedule, cycles=tuple(cycles)), [[1] * 4], [1] * 4)


if __name__ == "__main__":
    unittest.main()
