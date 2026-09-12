"""Two-array integer/cycle replay, compiler-packed words and global rollback."""

import json
import random
import unittest

from compiler.v4.context_image import TileInstruction, pack_tile, REVISION
from models.v4.fabric_exec import FabricModel, pack
from models.v4.feeder_exec import ROOT
from models.v4.pe_exec import SW, AW, SMASK
from models.v4.fixed import Arithmetic
from models.v4.lfsr_operator import indexed_sign
from verification.v4.test_feeder_rtl import Replay, bundle

IO = json.loads((ROOT / "verification/v4/dataflow/fabric_io.json").read_text())
RUNS = []

def word(op="NOP", src="NONE", other="NONE", **fields):
    return int.from_bytes(pack_tile(TileInstruction(op, src, other, **fields)), "little")

def request(words=None, **fields):
    pins = dict(bundle(2, 0, 32, 32), req_words=pack(words or [0]*32, 64), req_rev=REVISION,
                req_alu_mode=0, req_operands=1, req_enable=(1 << 32)-1, link_ready=(1 << 128)-1)
    pins.update(fields)
    return pins

class FabricReplay(Replay):
    io = IO
    runs = RUNS
    top = "tb_cgra_fabric"
    bench = "verification/v4/dataflow/tb_cgra_fabric.sv"

    def __init__(self):
        self.model = FabricModel()
        self.rows, self.expected = [], []
        self.step(request(rst=1))

    def send(self, words=None, stalls=2, seed=0, **fields):
        pins = request(words, **fields)
        self.step(dict(pins, req_valid=1))
        rng = random.Random(seed)
        for cycle in range(100):
            if self.model.outputs(pins)["rsp_valid"]:
                break
            self.step(dict(pins, req_valid=0, link_ready=rng.getrandbits(128) if cycle < 15 else (1 << 128)-1))
        else:
            raise AssertionError("array did not complete")
        result = self.model.outputs(pins)
        for index in range(stalls):
            self.step(dict(pins, req_valid=1, req_words=0, req_job=65535-index, req_dense=index,
                           link_ready=0, rsp_ready=0))
        self.step(dict(pins, req_valid=1, rsp_ready=1))
        self.step(dict(pins, req_valid=0))
        return result

class FabricRtlTests(unittest.TestCase):
    def test_phi_forward_and_transpose_program_driven_frames(self):
        replay = FabricReplay()
        clear = word("CLEAR", acc_write=1, format="FIXED")
        mac = word("MAC", "MATRIX", "VECTOR", acc_write=1, format="FIXED")
        rows, cols = 33, 9
        vector = [12000 - 991*col for col in range(cols)]
        for out in (0, 32):
            replay.send([clear]*32, req_operands=0)
            for col in range(cols):
                pins = bundle(0, 0, rows, cols, out, col)
                pins["req_vec"] = vector[col] & SMASK
                replay.send([mac]*32, **{name: value for name, value in pins.items() if name not in ("rst", "cancel", "req_valid", "rsp_ready")})
            result = replay.send([word("STORE", "ACC", format="FIXED")]*32, req_operands=0,
                                 req_enable=(1 << min(32, rows-out))-1)
            self.assertEqual(result["rsp_fault"], 0)
            for tile in range(min(32, rows-out)):
                total = sum(indexed_sign(0x12345678, rows, out+tile, col)*32768*vector[col] for col in range(cols))
                self.assertEqual(result["rsp_data"] >> (tile*SW) & SMASK, int(Arithmetic.round_shift(total, 16)) & SMASK)
        residual = [12000 - 331*row for row in range(rows)]
        for out in (0, 8):
            enable = (1 << (4*min(8, cols-out)))-1
            replay.send([clear]*32, req_operands=0)
            for red in (0, 32):
                for step in range(8):
                    pins = bundle(1, 1, rows, cols, out, red, step)
                    pins["req_vec"] = pack([residual[red+8*lane+step] if red+8*lane+step < rows else 0 for lane in range(4)], SW)
                    replay.send([mac]*32, **{name: value for name, value in pins.items() if name not in ("rst", "cancel", "req_valid", "rsp_ready")})
            phases = [
                [word("ROUTE", "ACC", routeW="ACC") if tile%4 in (1, 3) else 0 for tile in range(32)],
                [word("ADD", "ACC", "LINK", srcB_reg=1, acc_write=1, format="FIXED") if tile%4 in (0, 2) else 0 for tile in range(32)],
                [word("ROUTE", "ACC", routeW="ACC") if tile%4 == 2 else 0 for tile in range(32)],
                [word("ROUTE", "LINK", srcA_reg=1, routeW="VALUE") if tile%4 == 1 else 0 for tile in range(32)],
                [word("ADD", "ACC", "LINK", srcB_reg=1, acc_write=1, format="FIXED") if tile%4 == 0 else 0 for tile in range(32)]]
            for phase, words in enumerate(phases):
                self.assertEqual(replay.send(words, req_operands=0, req_enable=enable, seed=phase)["rsp_fault"], 0)
            result = replay.send([word("STORE", "ACC", format="FIXED") if tile%4 == 0 else 0 for tile in range(32)],
                                 req_operands=0, req_enable=enable)
            for output in range(min(8, cols-out)):
                total = sum(indexed_sign(0x12345678, rows, row, out+output)*32768*residual[row] for row in range(rows))
                self.assertEqual(result["rsp_data"] >> (output*4*SW) & SMASK, int(Arithmetic.round_shift(total, 16)) & SMASK)
        replay.run(self)

    def test_vertical_routes_tags_predicates_and_wide_scalar_fault(self):
        replay = FabricReplay()
        for route, src_side, enabled in (("routeN", 2, lambda tile: tile%16 >= 4), ("routeS", 0, lambda tile: tile%16 < 12)):
            words = [word("MOV", "IMMEDIATE", immediate=tile+1, **{route: "RESULT"}) if enabled(tile) else 0 for tile in range(32)]
            replay.send(words, req_operands=0, seed=7)
            readers = [word("MOV", "LINK", srcA_reg=src_side, rf_write=1) if (tile%16 < 12 if src_side == 2 else tile%16 >= 4) else 0 for tile in range(32)]
            self.assertEqual(replay.send(readers, req_operands=0)["rsp_fault"], 0)
            self.assertEqual(replay.send(readers, req_operands=0, req_job=1)["rsp_fault"], 1)
            self.assertEqual(replay.send(readers, req_operands=0, req_fmt=1)["rsp_fault"], 1)
        words = [word("CMP", "IMMEDIATE", "NONE", immediate=65535, format="SIGNED")]*32
        words[31] = 63
        replay.send(words, req_operands=0)
        self.assertEqual([tile.preds for tile in replay.model.tiles], [0]*32)
        replay.send([word("MAC", "MATRIX", "VECTOR", acc_write=1, format="FIXED")]*32)
        replay.send([word("ROUTE", "ACC", routeW="ACC") if tile%4 else 0 for tile in range(32)], req_operands=0)
        self.assertEqual(replay.send([word("MOV", "LINK", srcA_reg=1) if tile%4 < 3 else 0 for tile in range(32)], req_operands=0)["rsp_fault"], 1)
        self.assertEqual(replay.send([word("MOV", "MATRIX")]*32, req_operands=0)["rsp_fault"], 1)
        replay.run(self)

    def test_r4_wide_reduction_and_alu_route(self):
        replay = FabricReplay()
        clear = word("CLEAR", acc_write=1, format="FIXED")
        replay.send([clear]*32)
        replay.send([word("MAC", "MATRIX", "VECTOR", acc_write=1, format="FIXED")]*32)
        before = [tile.alu.acc for tile in replay.model.tiles]
        words = [word("ROUTE", "ACC", routeW="ACC") if tile%4 in (1, 3) else 0 for tile in range(32)]
        replay.send(words, seed=1)
        words = [word("ADD", "ACC", "LINK", srcB_reg=1, acc_write=1, format="FIXED") if tile%4 in (0, 2) else 0 for tile in range(32)]
        replay.send(words)
        replay.send([word("ROUTE", "ACC", routeW="ACC") if tile%4 == 2 else 0 for tile in range(32)], seed=2)
        replay.send([word("ROUTE", "LINK", srcA_reg=1, routeW="VALUE") if tile%4 == 1 else 0 for tile in range(32)], seed=3)
        replay.send([word("ADD", "ACC", "LINK", srcB_reg=1, acc_write=1, format="FIXED") if tile%4 == 0 else 0 for tile in range(32)])
        for tile in range(0, 32, 4):
            self.assertEqual(replay.model.tiles[tile].alu.acc, sum(before[tile:tile+4]))
        words = [word("MOV", "IMMEDIATE", immediate=77, rf_write=1, routeE="RESULT") if tile%4 < 3 else 0 for tile in range(32)]
        replay.send(words, seed=4)
        result = replay.send([word("MOV", "LINK", srcA_reg=3, rf_write=1, dst_reg=1) if tile%4 else 0 for tile in range(32)])
        self.assertEqual(result["rsp_fault"], 0)
        for tile in range(32):
            if tile%4:
                self.assertEqual(replay.model.tiles[tile].rf[1], 77)
        replay.run(self)

    def test_cross_array_fault_atomicity_tail_and_cancel(self):
        replay = FabricReplay()
        init = [word("MOV", "IMMEDIATE", immediate=19, rf_write=1)]*32
        replay.send(init)
        change = [word("MOV", "IMMEDIATE", immediate=88, rf_write=1)]*32
        for bad in (63, word("MOV", "RF", srcA_reg=7, rf_write=1), word("ROUTE", "NONE", routeW="VALUE")):
            words = change.copy()
            words[31] = bad
            result = replay.send(words)
            self.assertEqual(result["rsp_fault"], 1)
            self.assertEqual([tile.rf[0] for tile in replay.model.tiles], [19]*32)
        words = change.copy()
        words[15] = word("ROUTE", "ACC", routeE="ACC")
        self.assertEqual(replay.send(words)["rsp_fault"], 1)
        words[15] = 0
        words[16] = word("ROUTE", "ACC", routeW="ACC")
        self.assertEqual(replay.send(words)["rsp_fault"], 1)
        tail = replay.send(init, req_rows=1)
        self.assertEqual(tail["rsp_exec"], 1)
        words = init.copy()
        words[31] = 63
        self.assertEqual(replay.send(words, req_rows=1)["rsp_fault"], 1)
        for reset in ("rst", "cancel"):
            pins = request([word("ROUTE", "ACC", routeE="ACC") if tile%4 < 3 else 0 for tile in range(32)], req_valid=1)
            replay.step(pins)
            for _ in range(5):
                replay.step(dict(pins, req_valid=0, link_ready=0x22222222))
            replay.step(dict(pins, **{reset: 1}, rsp_ready=1))
            replay.send(init)
        replay.run(self)

    def test_global_failure_preserves_links_acc_and_halt_events(self):
        replay = FabricReplay()
        routes = [word("MOV", "IMMEDIATE", immediate=77, routeE="RESULT") if tile%4 < 3 else 0 for tile in range(32)]
        replay.send(routes, req_operands=0)
        changed = [word("MOV", "IMMEDIATE", immediate=88, routeE="RESULT") if tile%4 < 3 else 0 for tile in range(32)]
        changed[31] = 63
        self.assertEqual(replay.send(changed, req_operands=0)["rsp_fault"], 1)
        read = [word("MOV", "LINK", srcA_reg=3, rf_write=1) if tile%4 else 0 for tile in range(32)]
        replay.send(read, req_operands=0)
        self.assertEqual([replay.model.tiles[tile].rf[0] for tile in range(32) if tile%4], [77]*24)
        mac = [word("MAC", "MATRIX", "VECTOR", acc_write=1, format="FIXED")]*32
        replay.send(mac)
        before = [tile.alu.acc for tile in replay.model.tiles]
        mac[31] = 63
        self.assertEqual(replay.send(mac)["rsp_fault"], 1)
        self.assertEqual([tile.alu.acc for tile in replay.model.tiles], before)
        halt = replay.send([word("HALT")]*32, req_operands=0, stalls=7)
        self.assertEqual(halt["rsp_halt"], (1 << 32)-1)
        failed = [word("HALT")]*32
        failed[31] = 63
        self.assertEqual(replay.send(failed, req_operands=0)["rsp_halt"], 0)
        replay.run(self)

    def test_random_scalar_programs_modes_and_feeder_fault(self):
        replay = FabricReplay()
        rng = random.Random(9402)
        for iteration in range(80):
            words = [word("MOV", "IMMEDIATE", immediate=rng.randrange(65536), rf_write=1,
                          dst_reg=iteration%8, predicate=0 if iteration%3 else 7) for _ in range(32)]
            replay.send(words, seed=iteration, stalls=iteration%4)
        replay.send([word("CLEAR", acc_write=1, format="FIXED")]*32, req_alu_mode=1)
        result = replay.send([word("MUL", "VECTOR", "VECTOR", format="FIXED", rf_write=1)]*32, req_alu_mode=1)
        self.assertEqual(result["rsp_fault"], 0)
        self.assertEqual(replay.send(req_src_fault=1)["rsp_feed_fault"], 4)
        self.assertEqual(replay.send(req_rows=0)["rsp_feed_fault"], 1)
        self.assertEqual(replay.send(req_rev=0)["rsp_fault"], 1)
        replay.run(self)
