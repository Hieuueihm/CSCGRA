"""Verification for the standalone one-copy matrix GEMV prototype."""
from __future__ import annotations

import unittest

from compiler.v4.single_matrix import (
    BANK_COUNT,
    NO_RTL_NO_PIPELINE_PROOF,
    SingleMatrixLayout,
    build_study_report,
    compile_single_matrix,
    direct_gemv,
    replay_gemv,
)
from compiler.v4.mapping import compile_gemv as reference_compile_gemv


class SingleMatrixLayoutTests(unittest.TestCase):
    def test_inverse_is_bijective_including_zero_tail_slots(self):
        for rows, columns in ((1, 1), (3, 33), (17, 65), (128, 1024)):
            layout = SingleMatrixLayout(rows, columns)
            self.assertTrue(layout.verify_inverse_bijection())
            self.assertEqual(layout.padded_columns % BANK_COUNT, 0)
            self.assertEqual(layout.padded_words, BANK_COUNT * layout.bank_depth)

    def test_pack_is_one_exact_copy_and_zero_pads(self):
        matrix = [[0, -2, 7], [11, 0, 4]]
        layout = SingleMatrixLayout(2, 3)
        banks = layout.pack(matrix)
        self.assertEqual(layout.unpack(banks), tuple(tuple(row) for row in matrix))
        self.assertEqual(layout.copy_count, 1)
        for bank in range(BANK_COUNT):
            for address, value in enumerate(banks[bank]):
                row, column = layout.inverse(bank, address)
                if column >= layout.columns:
                    self.assertEqual(value, 0)


class SingleMatrixReplayTests(unittest.TestCase):
    def test_both_orientations_and_reduction_modes_match_direct_integer_oracle(self):
        for rows, columns in ((1, 1), (3, 5), (7, 33), (17, 65), (35, 19)):
            matrix = [[(5 * row - 3 * column + row * column) % 11 - 5
                       for column in range(columns)] for row in range(rows)]
            for transpose in (False, True):
                vector = [2 * i - 3 for i in range(rows if transpose else columns)]
                expected = direct_gemv(matrix, vector, transpose=transpose)
                for lanes in (1, 4):
                    schedule = compile_single_matrix(rows, columns, transpose=transpose,
                                                      reduction_lanes=lanes)
                    self.assertEqual(replay_gemv(schedule, matrix, vector), expected)
                    metrics = schedule.metrics()
                    self.assertEqual(metrics["bank_read_conflict_count"], 0)
                    self.assertTrue(metrics["all_recorded_bank_addresses_concrete"])
                    self.assertLessEqual(metrics["max_active_reads_per_issue"], 32)
                    self.assertLessEqual(metrics["vector_unique_words_per_issue_max"], lanes)

    def test_r4_uses_eight_u_issues_and_explicit_masks_for_small_k(self):
        schedule = compile_single_matrix(9, 3, reduction_lanes=4)
        issues = schedule.requests()
        self.assertEqual(len(issues), 2 * 1 * 8)
        self.assertTrue(any(issue.active_read_count == 0 for issue in issues))
        self.assertTrue(all(len(issue.reads) == 32 for issue in issues))
        self.assertTrue(all(all(isinstance(read.bank, int) and isinstance(read.address, int)
                                 for read in issue.reads) for issue in issues))

    def test_r4_checks_lane_prefix_before_final_sum(self):
        # Lane 0 reaches 200 at its second prefix, while the final dot product
        # is zero.  A final-only check would incorrectly accept this case.
        matrix = [[0] * 32]
        matrix[0][0] = 100
        matrix[0][1] = 100
        matrix[0][8] = -100
        matrix[0][9] = -100
        vector = [1] * 32
        schedule = compile_single_matrix(1, 32, reduction_lanes=4, accumulator_bits=8)
        with self.assertRaisesRegex(ValueError, "lane 0 prefix"):
            replay_gemv(schedule, matrix, vector)
        self.assertEqual(replay_gemv(schedule, matrix, vector,
                                     check_accumulator_range=False), [0])

    def test_tampered_packed_bank_image_is_rejected(self):
        matrix = [[1, -2, 3, 4, 5]]
        vector = [1, 1, 1, 1, 1]
        schedule = compile_single_matrix(1, 5, reduction_lanes=1)
        packed = [list(bank) for bank in schedule.layout.pack(matrix)]
        bank, address = schedule.layout.logical_address(0, 0)
        packed[bank][address] += 1
        with self.assertRaisesRegex(ValueError, "packed bank image"):
            replay_gemv(schedule, matrix, vector, packed_banks=packed)

    def test_tampered_padded_tail_is_rejected(self):
        matrix = [[1, 2, 3]]
        layout = SingleMatrixLayout(1, 3)
        packed = [list(bank) for bank in layout.pack(matrix)]
        tail_bank, tail_address = next(
            (bank, address)
            for bank in range(BANK_COUNT)
            for address in range(layout.bank_depth)
            if layout.inverse(bank, address)[1] >= layout.columns)
        packed[tail_bank][tail_address] = 1
        with self.assertRaisesRegex(ValueError, "padded bank tail"):
            layout.unpack(packed)

    def test_r4_payload_reference_counts_match_existing_mapping(self):
        # The existing two-orientation layout issues four reductions per MAC
        # phase; the one-copy candidate issues eight u payloads per 32-word
        # block. They perform the same useful MAC count with different issue
        # counts.
        for rows, columns, expected_reference, expected_candidate in (
                (128, 8, 32, 128), (3, 5, 2, 8)):
            reference = reference_compile_gemv(rows, columns, reduction_lanes=4)
            reference_payload = sum(cycle.phase == "mac" for cycle in reference.cycles)
            candidate = compile_single_matrix(rows, columns, reduction_lanes=4)
            self.assertEqual(reference_payload, expected_reference)
            self.assertEqual(candidate.metrics()["payload_issues"], expected_candidate)
            self.assertEqual(reference.metrics["useful_mac_count"], candidate.metrics()["useful_macs"])

    def test_integer_and_shape_validation_rejects_bool_and_bad_dimensions(self):
        with self.assertRaises(ValueError):
            compile_single_matrix(True, 4)
        with self.assertRaises(ValueError):
            compile_single_matrix(4, 4, reduction_lanes=2)
        with self.assertRaises(ValueError):
            SingleMatrixLayout(2, 2).pack([[1, 0], [0, True]])
        with self.assertRaises(ValueError):
            direct_gemv([[1, 2]], [False, 1])


class SingleMatrixReportTests(unittest.TestCase):
    def test_main_report_records_one_copy_and_explicit_limitations(self):
        report = build_study_report(128, 1024)
        self.assertEqual(report["claim_status"], NO_RTL_NO_PIPELINE_PROOF)
        self.assertEqual(report["candidate"]["copies"], 1)
        self.assertEqual(report["candidate"]["padded_storage_KiB_at_C18"], 288)
        self.assertEqual(report["candidate"]["bram36_at_C18"], 64)
        self.assertEqual(report["two_orientation_reference"]["dual_bram36_at_C18"], 128)
        self.assertEqual(report["two_orientation_reference"]["dual_storage_KiB_at_C18"], 576)
        self.assertIn("R4", report["orientations"]["forward"])
        self.assertEqual(set(report["restricted_M128_supports"]), {"M128S8", "M128S32", "M128S96"})

    def test_bram_estimate_scales_with_bank_depth(self):
        report = build_study_report(2, 3)
        self.assertEqual(report["candidate"]["bram36_at_C18"], 32)


if __name__ == "__main__":
    unittest.main()
