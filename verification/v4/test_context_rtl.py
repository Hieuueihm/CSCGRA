"""Packed compiler words through real decoder/tile RTL with architectural replay."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import tempfile
import unittest

from compiler.v4.context_image import TileInstruction, TILE_FIELDS
from compiler.v4.context_image import build_gemv_template, load_image, pack_context, pack_tile, write_image
from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources
from models.v4.context_exec import ContextModel, FIELDS, FAULTS
from models.v4.fixed import Arithmetic
from models.v4.pe_exec import ROOT, SMASK, SW, CF, edges
from scripts.v4.generate_context_defs import render

IO = json.loads((ROOT / "verification/v4/pe/context_io.json").read_text(encoding="utf-8"))
RUNS: list[dict] = []
COMMANDS: list[dict] = []
COMPILE_LOGS: list[str] = []
IMAGES: list[dict] = []


def word(tile: TileInstruction) -> int:
    return int.from_bytes(pack_tile(tile), "little")


def replace(raw: int, field: str, value: int) -> int:
    offset, width = FIELDS[field]
    return (raw & ~(((1 << width)-1) << offset)) | (value << offset)


class Scenario:
    def __init__(self, seed: int, tile: int = 5):
        self.tile = tile
        self.rng = random.Random(seed)
        self.model = ContextModel(tile)
        self.pins = dict.fromkeys(IO["inputs"], 0)
        self.rows, self.expected = [], []
        self.step(rst=1)
        self.step(rst=0)

    def step(self, **changes: int) -> None:
        self.pins.update(changes)
        packed = 0
        for name, width in IO["inputs"].items():
            if not 0 <= self.pins[name] < (1 << width):
                raise ValueError(f"{name} out of range")
            packed = (packed << width) | self.pins[name]
        self.rows.append(packed)
        self.expected.append(self.model.outputs(self.pins) if len(self.rows) > 1 else {})
        self.model.tick(self.pins)
        self.expected.append(self.model.outputs(self.pins))

    def request(self, raw: int, **inputs: int) -> dict:
        pins = dict(req_valid=1, req_word=raw, req_rev=1, req_mode=0, req_mat=0, req_vec=0,
                    req_links=0, req_wlinks=0, req_mat_valid=1, req_vec_valid=1, req_link_valid=15,
                    req_lane=1, req_job=self.rng.getrandbits(16), req_tag=self.rng.getrandbits(16),
                    req_fmt=self.rng.getrandbits(8), req_last=self.rng.randrange(2), rsp_ready=0)
        pins.update({"req_"+name: value for name, value in inputs.items()})
        return pins

    def send(self, tile: TileInstruction | int, stalls: int = 2, **inputs: int) -> dict:
        raw = word(tile) if isinstance(tile, TileInstruction) else tile
        if not self.model.outputs(self.pins)["req_ready"]:
            raise AssertionError("request overwrites pending context")
        self.step(**self.request(raw, **inputs))
        latency = 1
        while not self.model.outputs(self.pins)["rsp_valid"]:
            self.step(req_valid=1, req_word=self.rng.getrandbits(64), req_mode=1-self.pins["req_mode"],
                      req_mat=self.rng.getrandbits(SW), req_vec=self.rng.getrandbits(SW))
            latency += 1
            if latency > 2:
                raise AssertionError("decoder added undeclared pipeline latency")
        response = self.model.outputs(self.pins).copy()
        for _ in range(stalls):
            self.step(req_valid=1, req_word=self.rng.getrandbits(64), req_rev=self.rng.randrange(256),
                      req_tag=self.rng.getrandbits(16), req_wlinks=self.rng.getrandbits(256), req_lane=self.rng.randrange(2))
        self.step(req_valid=0, rsp_ready=1)
        return response


class ContextRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if (ROOT / "rtl/v4/include/context_defs.vh").read_text(encoding="utf-8") != render():
            raise RuntimeError("stale compiler-derived decoder definitions")
        cls.keep = os.environ.get("V4_PE_KEEP") == "1"
        (ROOT / "work").mkdir(exist_ok=True)
        cls.tmp = None if cls.keep else tempfile.TemporaryDirectory(prefix="v4_context_", dir=ROOT / "work")
        cls.work = Path(tempfile.mkdtemp(prefix="v4_context_", dir=ROOT / "work") if cls.keep else cls.tmp.name)
        cls.executables = {}

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.keep:
            print(f"Retained context images/vectors/traces: {cls.work}")
        else:
            cls.tmp.cleanup()

    def replay(self, scenario: Scenario) -> None:
        tile = scenario.tile
        if tile not in self.executables:
            exe = self.work / f"context_{tile}.xsim.json"
            result = compile_rtl(exe, "tb_pe_context", filelist_sources(ROOT)+[ROOT/"verification/v4/pe/tb_pe_context.sv"],
                                 root=ROOT, parameters={"TILE_ID": tile})
            COMMANDS.extend(result.commands)
            COMPILE_LOGS.append(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.executables[tile] = exe
        name = f"{self._testMethodName}_{tile}"
        vector, trace = self.work / (name + ".hex"), self.work / (name + ".trace")
        payload = "".join(f"{row:x}\n" for row in scenario.rows)
        vector.write_text(payload, encoding="ascii")
        result = run_rtl(self.executables[tile], ["+src="+vector.as_posix(), "+dst="+trace.as_posix()], root=ROOT)
        COMMANDS.extend(result.commands)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS cycles={len(scenario.rows)}", result.stdout)
        lines = trace.read_text(encoding="ascii").splitlines()
        self.assertEqual(len(lines), len(scenario.expected))
        checks = 0
        for index, (line, expected) in enumerate(zip(lines, scenario.expected)):
            parts = line.split()
            self.assertEqual([int(parts[0]), int(parts[1])], [index // 2, index % 2])
            actual = dict(zip(IO["outputs"], parts[2:]))
            for signal, value in expected.items():
                self.assertNotRegex(actual[signal], "[xz]", f"unknown {signal} at {index // 2}")
                self.assertEqual(int(actual[signal], 16), value,
                                 f"{name} cycle={index // 2} phase={index % 2} {signal}")
                checks += 1
        RUNS.append(dict(test=name, tile=tile, cycles=len(scenario.rows), checks=checks, status="PASS",
                         vectors_sha256=hashlib.sha256(payload.encode("ascii")).hexdigest(),
                         trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))

    def test_compiler_image_byte_order_and_scalar_dot_program(self) -> None:
        coeffs, values = [32768, -65536, 98304], [2000000, -700000, 450000]
        program = [TileInstruction("CLEAR", acc_write=1, format="FIXED")]
        for _ in coeffs:
            program += [TileInstruction("READ", "MATRIX", dst_reg=1, rf_write=1, format="ADDRESS"),
                        TileInstruction("MAC", "RF", "VECTOR", srcA_reg=1, acc_write=1, format="FIXED")]
        program += [TileInstruction("STORE", "ACC", format="FIXED"), TileInstruction("HALT")]
        image = pack_context([[tile]*32 for tile in program], metadata={"test_only": "straight_line_scalar_dot_not_GEMV_control"})
        directory = self.work / "scalar_image"
        manifest = write_image(image, directory)
        loaded = load_image(directory)
        self.assertEqual(loaded.tile_payload(5), image.tile_payload(5))
        IMAGES.append(dict(name="scalar_dot", files=manifest["files"], execution_scope="straight_line_one_tile_external_operands"))
        lines = (directory / "tile_05.hex").read_text().splitlines()
        scenario = Scenario(23)
        stored = None
        for index, line in enumerate(lines):
            raw = int.from_bytes(bytes.fromhex(line), "little")
            self.assertEqual(raw, int.from_bytes(loaded.tile_payload(5)[index*8:(index+1)*8], "little"))
            args = {}
            if 1 <= index <= 6:
                term = (index-1)//2
                args = dict(mat=coeffs[term] & SMASK, vec=values[term] & SMASK)
            result = scenario.send(raw, stalls=3, **args)
            self.assertEqual(result["rsp_fault"], 0)
            if index == 7:
                self.assertEqual(result["rsp_store"], 1)
                stored = result["rsp_data"]
            if index == 8:
                self.assertEqual(result["rsp_halt"], 1)
        self.assertEqual(stored, int(Arithmetic.round_shift(sum(coef*value for coef,value in zip(coeffs,values)), CF)) & SMASK)
        self.assertNotEqual(int(lines[1], 16), word(program[1]))
        self.replay(scenario)

    def test_execution_formats_flags_compare_select_and_mode(self) -> None:
        scenario = Scenario(47)
        for mode in (0, 1):
            scenario.send(TileInstruction("CLEAR", acc_write=1, format="FIXED"), mode=mode)
            for code in ("ADD", "SUB", "MUL", "MAC", "READ", "MOV", "STORE", "CMP", "SELECT"):
                for fmt in ("NONE", "SIGNED", "UNSIGNED", "FIXED", "ADDRESS"):
                    for acc_write in (0, 1):
                        for pred in range(8):
                            tile = TileInstruction(code, "IMMEDIATE", "VECTOR", dst_reg=3, rf_write=1,
                                                   acc_write=acc_write, predicate=pred, format=fmt, immediate=17)
                            scenario.send(tile, mode=mode, vec=123, stalls=1)
        scenario.send(TileInstruction("CMP", "IMMEDIATE", "VECTOR", predicate=0, format="SIGNED", immediate=0xFFFF), vec=1)
        self.assertEqual(scenario.model.tile.preds & 1, 1)
        result = scenario.send(TileInstruction("SELECT", "IMMEDIATE", "VECTOR", predicate=1, immediate=19), vec=72)
        self.assertEqual(result["rsp_data"], 19)
        self.replay(scenario)

    def test_malformed_fields_revision_tail_and_rollback(self) -> None:
        scenario = Scenario(101)
        scenario.send(TileInstruction("MOV", "IMMEDIATE", dst_reg=0, rf_write=1, immediate=19))
        baseline = scenario.model.tile.rf.copy()
        base = word(TileInstruction("MOV", "IMMEDIATE", immediate=13, rf_write=1))
        for field, width in TILE_FIELDS:
            for value in range(1 << width) if width <= 6 else (0, 1, (1 << width)-1):
                raw = replace(base, field, value)
                scenario.send(raw, lane=0, stalls=1)
                self.assertEqual(scenario.model.tile.rf, baseline)
        for revision in (0, 2, 255):
            result = scenario.send(base, rev=revision)
            self.assertEqual(result["rsp_fault"], FAULTS["REV"])
        for _ in range(350):
            scenario.send(scenario.rng.getrandbits(64), lane=scenario.rng.randrange(2), stalls=1)
        for bit in range(59,64):
            result = scenario.send(base | (1 << bit), lane=0)
            self.assertEqual(result["rsp_fault"], FAULTS["WORD"])
        for code in range(13,64):
            self.assertEqual(scenario.send(replace(base,"opcode",code))["rsp_fault"], FAULTS["WORD"])
        self.replay(scenario)

    def test_all_tile_edges_routes_reject_before_any_state_change(self) -> None:
        route_fields = ("routeN", "routeE", "routeS", "routeW")
        for tile_id in range(32):
            scenario = Scenario(211+tile_id,tile_id)
            for direction in range(4):
                for selector in ("VALUE","ACC","RESULT"):
                    raw = word(TileInstruction("MOV", "IMMEDIATE", rf_write=1, immediate=7,
                                               **{route_fields[direction]: selector}))
                    result = scenario.send(raw)
                    self.assertEqual(result["rsp_fault"], FAULTS["EXEC"] if edges(tile_id)&(1<<direction) else FAULTS["EDGE"])
                    self.assertEqual(scenario.model.tile.valid,0)
                result = scenario.send(TileInstruction("MOV", "LINK", srcA_reg=direction), links=1, link_valid=15)
                self.assertEqual(result["rsp_fault"],0 if edges(tile_id)&(1<<direction) else FAULTS["EDGE"])
            self.replay(scenario)

    def test_wide_link_add_and_template_word_decode(self) -> None:
        scenario = Scenario(307,5)
        scenario.send(TileInstruction("CLEAR", acc_write=1,format="FIXED"))
        wide = (1 << 45) + 123
        tile = TileInstruction("ADD","ACC","LINK",srcB_reg=1,acc_write=1,format="FIXED")
        scenario.send(tile,wlinks=wide << 64,links=0,link_valid=2)
        self.assertEqual(scenario.model.tile.alu.acc,wide)
        self.assertEqual(scenario.send(tile,link_valid=0)["rsp_fault"],6)
        for lanes in (1,4):
            image = build_gemv_template(lanes,output_count=37,reduction_count=33)
            directory = self.work / f"template_r{lanes}"
            manifest = write_image(image,directory)
            self.assertEqual(manifest["execution_status"],"NOT_EXECUTED")
            self.assertEqual(manifest["execution_proof"],"NOT_PROVEN")
            IMAGES.append(dict(name=f"template_r{lanes}",files=manifest["files"],execution_scope="word_decode_only_no_control_flow"))
            loaded = load_image(directory)
            for tile_id in range(32):
                template_scenario = Scenario(401+tile_id,tile_id)
                payloads = (directory / f"tile_{tile_id:02d}.hex").read_text().splitlines()
                for index,line in enumerate(payloads[:16]):
                    self.assertEqual(bytes.fromhex(line),loaded.tile_payload(tile_id)[index*8:(index+1)*8])
                    template_scenario.send(int.from_bytes(bytes.fromhex(line),"little"),mat=0,vec=0,stalls=0)
                self.replay(template_scenario)
        self.replay(scenario)

    def test_reset_cancel_two_cycle_store_halt_and_fault_pending(self) -> None:
        scenario = Scenario(509)
        for control in ("rst","cancel"):
            for code,stage in (("MAC","low"),("MAC","response"),("STORE","response"),("HALT","response"),("BAD","response")):
                scenario.send(TileInstruction("MOV","IMMEDIATE",rf_write=1,immediate=1))
                scenario.send(TileInstruction("CLEAR",acc_write=1,format="FIXED"),mode=1)
                tile = {"MAC": TileInstruction("MAC","IMMEDIATE","VECTOR",acc_write=1,rf_write=1,format="FIXED",immediate=7),
                        "STORE": TileInstruction("STORE","RF"),"HALT":TileInstruction("HALT"),"BAD":1<<63}[code]
                raw = tile if isinstance(tile,int) else word(tile)
                scenario.step(**scenario.request(raw,mode=1,vec=123))
                if stage == "response":
                    scenario.step(req_valid=0)
                    scenario.step()
                scenario.step(**{control:1},req_valid=1,rsp_ready=1)
                scenario.step(**{control:0},req_valid=0,rsp_ready=0)
                self.assertEqual(scenario.model.tile.valid,0)
                self.assertEqual(scenario.model.tile.alu.acc,0)
                result = scenario.send(TileInstruction("STORE","RF"))
                self.assertEqual(result["rsp_fault"],7)
                self.assertEqual(result["rsp_store"],0)
        self.replay(scenario)


if __name__ == "__main__":
    unittest.main()
