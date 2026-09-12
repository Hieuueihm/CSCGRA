"""Actual image-load and control256 cycle replay with permanent SV benches."""

import hashlib
import json
from pathlib import Path
import random
import tempfile
import unittest

from compiler.v4.context_image import ControlInstruction, TileInstruction, pack_context, pack_control, pack_tile, write_image, load_image, REVISION
from models.v4.control_exec import ControlModel, ROOT, FAULT, decode
from models.v4.control_fabric import ControlFabricModel
from models.v4.control_primitives import DecodeModel, StoreModel
from scripts.v4.generate_control_defs import render
from scripts.v4.export_control_stream import export_stream
from verification.v4.test_feeder_rtl import Replay

IO = json.loads((ROOT / "verification/v4/control/io.json").read_text())
RUNS, IMAGES = [], []
FABRIC_RUNS = []
PRIMITIVE_RUNS = []

def defaults(**changes):
    pins = dict.fromkeys(IO["inputs"], 0)
    pins.update(begin_rev=REVISION, begin_depth=256, begin_verified=1, begin_generation=123,
                start_limit=1000, start_job=7, start_fmt=3, exec_rsp_job=7, exec_rsp_fmt=3,
                addr_rsp_job=7)
    pins.update(changes)
    return pins

def image(controls, rows=None):
    if rows is None:
        rows = [[TileInstruction("MOV", "IMMEDIATE", immediate=pc, rf_write=1)]*32 for pc in range(len(controls))]
    return pack_context(rows, controls)

class ControlReplay(Replay):
    io = IO
    runs = RUNS
    top = "tb_context_engine"
    bench = "verification/v4/control/tb_context_engine.sv"

    def __init__(self):
        self.model = ControlModel()
        self.rows, self.expected, self.issues = [], [], []
        self.step(defaults(rst=1))

    def load(self, program, seed=1):
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp) / "image", Path(tmp) / "stream"
            manifest = write_image(program, source)
            header = export_stream(source, target, generation=123)
            records = (target / "loader.txt").read_text().splitlines()
            IMAGES.append(dict(files=manifest["files"], header=header,
                               scope="RTL loads all256 rows after compiler hash/structure verification"))
        self.step(defaults(begin_valid=1, start_valid=1))
        rng = random.Random(seed)
        for record in records:
            pc, bank, value, last = (int(field, 16) for field in record.split())
            if rng.randrange(100) == 0:
                self.step(defaults(wr_valid=0, wr_data=rng.getrandbits(256), start_valid=1))
            self.step(defaults(wr_valid=1, wr_pc=pc, wr_bank=bank, wr_data=value, wr_last=last))
        if not self.model.image_ready:
            raise AssertionError("loader did not publish complete image")

    def run_program(self, start=0, limit=1000, seed=1, bad_tag=False, backend_fault=False, addr_fault=False, addr_bad_tag=False, pred_bits=0):
        self.step(defaults(start_valid=1, start_pc=start, start_limit=limit))
        rng = random.Random(seed)
        pending = None
        address = None
        issued = []
        wait_cycles = 0
        for cycle in range(20000):
            pins = defaults(exec_ready=int(rng.randrange(3) != 0), addr_ready=int(rng.randrange(3) != 0), predicates=pred_bits)
            if self.model.state == "wait_pred":
                wait_cycles += 1
                pins["predicates"] = 7 if wait_cycles > 4 else 0
            if pending:
                if pending[0]:
                    pending[0] -= 1
                else:
                    pins.update(exec_rsp_valid=1, exec_rsp_tag=pending[1]+int(bad_tag), exec_rsp_fault=int(backend_fault))
            if address:
                if address[0]:
                    address[0] -= 1
                else:
                    pins.update(addr_rsp_valid=1, addr_rsp_tag=address[1]+int(addr_bad_tag), addr_rsp_fault=int(addr_fault))
            before = self.model.outputs(pins)
            if before["done_valid"]:
                result = (before["done_fault"], before["retired"])
                for _ in range(3):
                    self.step(defaults(start_valid=1, begin_valid=1))
                self.step(defaults(done_ready=1))
                self.issues.extend(issued)
                return result, issued
            if before["exec_valid"] and pins["exec_ready"]:
                pending = [rng.randrange(4), before["exec_tag"]]
                issued.append((before["pc"], before["exec_tag"], before["exec_words"]))
            elif before["exec_rsp_ready"] and pins["exec_rsp_valid"]:
                pending = None
            if before["addr_valid"] and pins["addr_ready"]:
                address = [rng.randrange(4), before["exec_tag"]]
            elif before["addr_rsp_ready"] and pins["addr_rsp_valid"]:
                address = None
            self.step(pins)
        raise AssertionError("bounded program failed to complete")

class ControlRtlTests(unittest.TestCase):
    def test_generated_defs_and_control_decoding(self):
        self.assertEqual((ROOT / "rtl/v4/include/control_defs.vh").read_text(), render())
        self.assertEqual(decode(15)[1], FAULT["WORD"])
        self.assertEqual(decode(0, 0)[1], FAULT["REV"])

    def test_nested_loops_branch_wait_address_and_reload(self):
        replay = ControlReplay()
        controls = [ControlInstruction("LOOP_BEGIN", count=2, loop_target=1),
                    ControlInstruction("LOOP_BEGIN", count=3, loop_target=2),
                    ControlInstruction(), ControlInstruction("LOOP_END", loop_target=1),
                    ControlInstruction("LOOP_END", loop_target=0),
                    ControlInstruction("WAIT", predicate=1),
                    ControlInstruction("ADDRESS", address_mode="VECTOR", immediate_address=123, stride=65532),
                    ControlInstruction("BRANCH", branch_target=9), ControlInstruction(), ControlInstruction("HALT")]
        replay.load(image(controls))
        result, issued = replay.run_program()
        sequence = [0, 1, 2, 3, 1, 2, 3, 1, 2, 3, 4]*2 + [5, 6, 7, 9]
        self.assertEqual(result, (0, len(sequence)))
        self.assertEqual([item[0] for item in issued], sequence)
        self.assertEqual([item[1] for item in issued], list(range(len(sequence))))
        replay.load(image([ControlInstruction("HALT")]), seed=2)
        self.assertEqual(replay.run_program(seed=2)[0], (0, 1))
        replay.run(self)

class ControlFabricReplay(ControlReplay):
    io = json.loads((ROOT / "verification/v4/control/fabric_io.json").read_text())
    runs = FABRIC_RUNS
    top = "tb_context_fabric"
    bench = "verification/v4/control/tb_context_fabric.sv"

    def __init__(self):
        self.model = ControlFabricModel()
        self.rows, self.expected, self.issues = [], [], []
        self.step(defaults(rst=1))

    def step(self, pins):
        supplied = dict(issue_allow=1, response_allow=1, backend_mask=(1 << 32)-1, link_ready=(1 << 128)-1)
        supplied.update(pins)
        super().step({name: supplied[name] for name in self.io["inputs"]})

    def run_program(self, seed=1, mask=(1 << 32)-1):
        self.step(defaults(start_valid=1))
        rng = random.Random(seed)
        sequence = []
        for cycle in range(5000):
            pins = defaults()
            pins.update(issue_allow=int(rng.randrange(3) != 0), response_allow=int(rng.randrange(3) != 0),
                        backend_mask=mask, link_ready=rng.getrandbits(128), predicates=int(cycle > 50))
            before = self.model.outputs(pins)
            control_pins, _, _, _ = self.model.wires(pins)
            if before["exec_valid"] and control_pins["exec_ready"]:
                sequence.append(before["pc"])
            if before["done_valid"]:
                for _ in range(3):
                    self.step(pins)
                result = (before["done_fault"], before["retired"])
                self.step(dict(pins, done_ready=1))
                return result, sequence
            self.step(pins)
        raise AssertionError("image/fabric program did not finish")

class ControlFabricRtlTests(unittest.TestCase):
    def test_full_image_nested_execution_on_real_arrays(self):
        replay = ControlFabricReplay()
        nop = [TileInstruction()]*32
        rows = [[TileInstruction("MOV", "IMMEDIATE", immediate=0, rf_write=1)]*32,
                nop, [TileInstruction("ADD", "RF", "IMMEDIATE", immediate=2, rf_write=1, format="SIGNED")]*32,
                nop,
                [TileInstruction("MOV", "RF", routeW="RESULT") if tile%4 in (1, 3) else TileInstruction() for tile in range(32)],
                [TileInstruction("MOV", "LINK", srcA_reg=1, dst_reg=1, rf_write=1) if tile%4 in (0, 2) else TileInstruction() for tile in range(32)],
                [TileInstruction("STORE", "RF")]*32, nop, nop]
        controls = [ControlInstruction(), ControlInstruction("LOOP_BEGIN", count=3, loop_target=2),
                    ControlInstruction(), ControlInstruction("LOOP_END", loop_target=1),
                    ControlInstruction(), ControlInstruction(), ControlInstruction("WAIT", predicate=1),
                    ControlInstruction("BRANCH", branch_target=8), ControlInstruction("HALT")]
        replay.load(image(controls, rows))
        result, sequence = replay.run_program()
        self.assertEqual(sequence, [0]+[1, 2, 3]*3+[4, 5, 6, 7, 8])
        self.assertEqual(result, (0, len(sequence)))
        self.assertEqual([tile.rf[0] for tile in replay.model.fabric.tiles], [6]*32)
        self.assertEqual([replay.model.fabric.tiles[tile].rf[1] for tile in range(32) if tile%4 in (0, 2)], [6]*16)
        result, _ = replay.run_program(mask=65535)
        self.assertEqual(result[0], 0)
        self.assertEqual([tile.rf[0] for tile in replay.model.fabric.tiles], [6]*16+[0]*16)
        replay.run(self)

    def test_real_array_failure_cancels_without_accepting_response(self):
        replay = ControlFabricReplay()
        rows = [[TileInstruction("MOV", "IMMEDIATE", immediate=12, rf_write=1)]*32,
                [TileInstruction("MOV", "RF", srcA_reg=7)]*32]
        replay.load(image([ControlInstruction(), ControlInstruction("HALT")], rows))
        result, sequence = replay.run_program()
        self.assertEqual(result, (FAULT["BACKEND"], 1))
        self.assertEqual(sequence, [0, 1])
        self.assertEqual([tile.valid for tile in replay.model.fabric.tiles], [0]*32)
        replay.run(self)

class ControlFaultRtlTests(unittest.TestCase):
    def test_stack_limits_branch_predicates_and_never_wait(self):
        replay = ControlReplay()
        controls = [ControlInstruction("LOOP_BEGIN", count=1, loop_target=pc+1) for pc in range(5)]
        controls += [ControlInstruction("HALT")]
        controls += [ControlInstruction("LOOP_BEGIN", count=65535, loop_target=7),
                     ControlInstruction("BRANCH", branch_target=8), ControlInstruction("HALT"),
                     ControlInstruction("WAIT", predicate=7)]
        for code in range(8):
            pc = len(controls)
            controls += [ControlInstruction("BRANCH", predicate=code, branch_target=pc+2), ControlInstruction(), ControlInstruction("HALT")]
        replay.load(image(controls))
        self.assertEqual(replay.run_program()[0], (FAULT["LOOP"], 4))
        self.assertEqual(replay.run_program(start=6)[0], (FAULT["LOOP"], 1))
        for code in range(8):
            for bits in (0, 1, 2, 4, 7):
                result, issued = replay.run_program(start=10+code*3, pred_bits=bits)
                taken = (code == 0 or (1 <= code <= 3 and bool(bits >> (code-1) & 1)) or
                         (4 <= code <= 6 and not bool(bits >> (code-4) & 1)))
                self.assertEqual(result, (0, 2 if taken else 3))
                self.assertEqual(len(issued), result[1])
        replay.step(defaults(start_valid=1, start_pc=9))
        for _ in range(20):
            replay.step(defaults(predicates=7))
        self.assertEqual(replay.model.state, "wait_pred")
        replay.step(defaults(cancel=1))
        self.assertFalse(replay.model.image_ready)
        replay.run(self)

    def test_loader_faults_and_incomplete_image(self):
        replay = ControlReplay()
        for change in ({"begin_rev": 0}, {"begin_depth": 255}, {"begin_verified": 0}):
            replay.step(defaults(begin_valid=1, **change))
            self.assertEqual(replay.model.load_fault, FAULT["HEADER"])
            replay.step(defaults(wr_valid=1))
            replay.step(defaults(start_valid=1))
            replay.step(defaults(done_ready=1))
        for change in ({"wr_bank": 1}, {"wr_pc": 1}, {"wr_last": 1}, {"wr_data": 1 << 65}):
            replay.step(defaults(begin_valid=1))
            replay.step(defaults(wr_valid=1, **change))
            self.assertEqual(replay.model.load_fault, FAULT["STREAM"])
        replay.step(defaults(begin_valid=1))
        replay.step(defaults(wr_valid=1))
        replay.step(defaults(wr_valid=1))
        self.assertEqual(replay.model.load_fault, FAULT["STREAM"])
        replay.step(defaults(begin_valid=1))
        replay.step(defaults(wr_valid=1))
        replay.step(defaults(cancel=1))
        self.assertFalse(replay.model.image_ready)
        replay.step(defaults(start_valid=1))
        self.assertEqual(replay.model.done_fault, FAULT["HEADER"])
        replay.run(self)

class PrimitiveReplay(Replay):
    runs = PRIMITIVE_RUNS

    def __init__(self, kind):
        self.io = json.loads((ROOT / f"verification/v4/control/{kind}_io.json").read_text())
        self.top = "tb_control_decode" if kind == "decode" else "tb_context_store"
        self.bench = f"verification/v4/control/{self.top}.sv"
        self.model = DecodeModel() if kind == "decode" else StoreModel()
        self.rows, self.expected = [], []

class ControlPrimitiveRtlTests(unittest.TestCase):
    def test_all_control_fields_and_fault_priority(self):
        from compiler.v4.context_image import CONTROL_FIELDS
        replay = PrimitiveReplay("decode")
        rng = random.Random(9411)
        for word in (0, 1 << 255, 15, int.from_bytes(pack_control(ControlInstruction("HALT")), "little")):
            for rev in (0, 1, 255):
                replay.step(dict(word=word, rev=rev))
        offset = 0
        for name, width in CONTROL_FIELDS:
            for value in (1, (1 << width)-1):
                replay.step(dict(word=value << offset, rev=1))
            offset += width
        for _ in range(500):
            replay.step(dict(word=rng.getrandbits(126), rev=1))
        replay.run(self)

    def test_context_store_stalls_generation_reset_and_last_address(self):
        replay = PrimitiveReplay("store")
        pins = dict.fromkeys(replay.io["inputs"], 0)
        replay.step(dict(pins, rst=1))
        rng = random.Random(9412)
        for pc in (0, 1, 255):
            for bank in range(33):
                replay.step(dict(pins, wr_en=1, wr_pc=pc, wr_bank=bank, wr_data=rng.getrandbits(256)))
        for pc in (255, 0, 1):
            request = dict(pins, image_ready=1, generation=9, rd_generation=9, rd_valid=1, rd_pc=pc)
            replay.step(request)
            for _ in range(8):
                replay.step(dict(request, rd_pc=rng.randrange(256), generation=8))
            replay.step(dict(request, rsp_ready=1))
            replay.step(dict(pins, rd_valid=1, rd_pc=pc))
            replay.step(dict(pins, rsp_ready=1))
            replay.step(dict(request, rd_generation=8))
            replay.step(dict(pins, rsp_ready=1))
            replay.step(request)
            replay.step(dict(pins, invalidate=1))
            replay.step(request)
            replay.step(dict(pins, cancel=1))
            replay.step(request)
            replay.step(dict(pins, rst=1))
        replay.run(self)

    def test_export_rejects_corrupt_manifest_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp) / "image", Path(tmp) / "stream"
            write_image(image([ControlInstruction("HALT")]), source)
            path = source / "tile_00.hex"
            path.write_text("1" + path.read_text()[1:])
            with self.assertRaises(ValueError):
                export_stream(source, target)
            self.assertFalse((target / "loader_header.json").exists())

    def test_execution_faults_budget_and_reset(self):
        replay = ControlReplay()
        controls = [ControlInstruction("LOOP_END"), ControlInstruction("LOOP_BEGIN", count=2, loop_target=0),
                    ControlInstruction("NOP", repeat=1), ControlInstruction("WAIT", predicate=1),
                    ControlInstruction("ADDRESS", address_mode="MATRIX", immediate_address=5), ControlInstruction("HALT")]
        replay.load(image(controls))
        for start, code in ((0, "LOOP"), (1, "LOOP"), (2, "EXEC")):
            self.assertEqual(replay.run_program(start=start)[0], (FAULT[code], 0))
        self.assertEqual(replay.run_program(start=5, bad_tag=True)[0], (FAULT["TAG"], 0))
        self.assertEqual(replay.run_program(start=5, backend_fault=True)[0], (FAULT["BACKEND"], 0))
        self.assertEqual(replay.run_program(start=4, addr_fault=True)[0], (FAULT["BACKEND"], 0))
        self.assertEqual(replay.run_program(start=4, addr_bad_tag=True)[0], (FAULT["TAG"], 0))
        self.assertEqual(replay.run_program(start=4, limit=1)[0], (FAULT["EXEC"], 1))
        self.assertEqual(replay.run_program(start=255)[0], (FAULT["PC"], 0))
        replay.step(defaults(start_valid=1, start_pc=3))
        for _ in range(10):
            replay.step(defaults())
        self.assertEqual(replay.model.state, "wait_pred")
        replay.step(defaults(rst=1))
        self.assertEqual(replay.model.state, "idle")
        replay.run(self)
