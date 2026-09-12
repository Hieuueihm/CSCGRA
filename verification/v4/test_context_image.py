"""Checks for the bounded v4 context image candidate (ISA revision 1)."""
from pathlib import Path
import tempfile
import unittest

from compiler.v4.context_image import (
    DEPTH, PE_SLOTS, ContextImage, ControlInstruction, ImageValidationError,
    TileInstruction, build_gemv_template, load_image, pack_context, pack_control,
    pack_tile, unpack_control, unpack_tile, write_image,
)


class ContextImageTests(unittest.TestCase):
    def test_all_32_tile_slots_are_distinct_and_round_trip(self):
        slots = [TileInstruction("MOV", "RF", "IMMEDIATE", srcA_reg=pe % 8,
                                 dst_reg=pe % 8, rf_write=1, immediate=pe)
                 for pe in range(PE_SLOTS)]
        payloads = [pack_tile(tile) for tile in slots]
        self.assertEqual(len(set(payloads)), PE_SLOTS)
        self.assertEqual([unpack_tile(payload) for payload in payloads], slots)

    def test_control_round_trip_and_exact_width(self):
        control = ControlInstruction("LOOP_BEGIN", repeat=2, count=1024,
                                     loop_target=7, address_mode="MATRIX",
                                     immediate_address=4096, stride=1)
        payload = pack_control(control)
        self.assertEqual(len(payload), 32)
        self.assertEqual(unpack_control(payload), control)

    def test_depth_is_bounded_and_images_have_32_slots(self):
        with self.assertRaisesRegex(ImageValidationError, "exceeds 256"):
            pack_context([[TileInstruction() for _ in range(PE_SLOTS)] for _ in range(DEPTH + 1)])
        image = pack_context([[TileInstruction() for _ in range(PE_SLOTS)]], [ControlInstruction()])
        self.assertEqual((len(image.tiles), len(image.tiles[0]), len(image.controls)),
                         (DEPTH, PE_SLOTS, DEPTH))
        self.assertEqual(image.payload_bytes, 73728)

    def test_invalid_reserved_fields_and_route_edges_rejected(self):
        with self.assertRaisesRegex(ImageValidationError, "reserved"):
            pack_tile(TileInstruction(reserved=1))
        with self.assertRaisesRegex(ImageValidationError, "unknown"):
            pack_tile(TileInstruction(opcode="NOT_AN_OPCODE"))
        # The ALU and registered-router sideband are independent and may issue
        # together in one tile word.
        pack_tile(TileInstruction("MAC", "ACC", "VECTOR", acc_write=1, routeW="VALUE"))
        with self.assertRaisesRegex(ImageValidationError, "selector"):
            image = pack_context([[TileInstruction("MOV", "LINK", dst_reg=1,
                                                    srcA_reg=4) for _ in range(PE_SLOTS)]],
                                 [ControlInstruction()])
        rows = [[TileInstruction() for _ in range(PE_SLOTS)] for _ in range(1)]
        rows[0][0] = TileInstruction("ROUTE", "ACC", routeN="ACC")
        with self.assertRaisesRegex(ImageValidationError, "north cluster"):
            pack_context(rows, [ControlInstruction()])
        rows = [[TileInstruction() for _ in range(PE_SLOTS)]]
        rows[0][1] = TileInstruction("MOV", "LINK", dst_reg=1, srcA_reg=0)
        with self.assertRaisesRegex(ImageValidationError, "LINK read"):
            pack_context(rows, [ControlInstruction()])

    def test_hash_manifest_detects_corruption(self):
        image = build_gemv_template(1)
        with tempfile.TemporaryDirectory() as temp:
            write_image(image, temp)
            tile = Path(temp) / "tile_00.hex"
            content = tile.read_text(encoding="ascii")
            tile.write_text(("0" if content[0] != "0" else "1") + content[1:], encoding="ascii")
            with self.assertRaisesRegex(ImageValidationError, "hash mismatch"):
                load_image(temp)

    def test_gemv_templates_are_bounded_but_execution_is_unproven(self):
        for lanes in (1, 4):
            image = build_gemv_template(lanes, output_count=128, reduction_count=1024)
            self.assertEqual(len(image.tiles), DEPTH)
            self.assertEqual(image.metadata["execution_status"], "NOT_EXECUTED")
            self.assertEqual(image.metadata["equivalence"], "NOT_PROVEN")
            self.assertGreater(image.metadata["reduction_count"], 256)
            expected_inner = (1024 + lanes - 1) // lanes
            self.assertEqual(image.controls[1].count, expected_inner)
            self.assertEqual(image.metadata["inner_loop_count"], expected_inner)
            self.assertIn("clear", image.metadata["phases"])
            self.assertIn("mac", image.metadata["phases"])
            self.assertIn("store", image.metadata["phases"])
            if lanes == 4:
                self.assertIn("cross_route_2", image.metadata["phases"])
                self.assertTrue(any(tile.opcode == "ROUTE" for tile in image.tiles[5]))
            else:
                self.assertTrue(any(tile.opcode == "READ" for tile in image.tiles[2]))

    def test_r4_nondivisible_reduction_tail_is_explicitly_unresolved(self):
        image = build_gemv_template(4, output_count=9, reduction_count=6)
        self.assertEqual(image.controls[1].count, 2)  # ceil(6 / 4)
        self.assertEqual(image.controls[2].stride, 4)
        self.assertEqual(image.metadata["tail_semantics"],
                         "UNRESOLVED_FEEDER_PREDICATE_FOR_FINAL_PARTIAL_BLOCK")


if __name__ == "__main__":
    unittest.main()
