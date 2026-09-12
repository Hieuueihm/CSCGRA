"""Real decoded pe_tile RTL against transactional V4 integer/RF/predicate state."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import tempfile
import unittest

from compiler.v4.context_image import OPERANDS
from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources
from models.v4.pe_exec import ROOT, OPS, SMASK, AMASK, SW, CF, SF, edges
from models.v4.tile_exec import ABI, FAULTS, PSEL, TileModel
from scripts.v4.generate_tile_interface import render

IO = json.loads((ROOT / "verification/v4/pe/tile_io.json").read_text(encoding="utf-8"))
RUNS: list[dict] = []
COMMANDS: list[dict] = []
COMPILE_LOGS: list[str] = []


class Scenario:
    def __init__(self, seed: int, tile: int = 5):
        self.tile = tile
        self.rng = random.Random(seed)
        self.model = TileModel(tile)
        self.pins = dict.fromkeys(IO["inputs"], 0)
        self.rows, self.expected = [], []
        self.step(rst=1)
        self.step(rst=0)

    def step(self, **changes: int) -> None:
        self.pins.update(changes)
        packed = 0
        for name, width in IO["inputs"].items():
            if not 0 <= self.pins[name] < 1 << width:
                raise ValueError(f"bad {name}: {self.pins[name]}")
            packed = (packed << width) | self.pins[name]
        self.rows.append(packed)
        self.expected.append(self.model.outputs(self.pins) if len(self.rows) > 1 else {})
        self.model.tick(self.pins)
        self.expected.append(self.model.outputs(self.pins))

    def request(self, op: str | int = "MOV", **fields: int) -> dict[str, int]:
        req = {"req_valid": 1, "req_op": OPS[op] if isinstance(op, str) else op,
               "req_mode": 0, "req_a_kind": 0, "req_b_kind": 0, "req_a_idx": 0, "req_b_idx": 0,
               "req_imm": 0, "req_mat": 0, "req_vec": 0, "req_links": 0,
               "req_mat_valid": 1, "req_vec_valid": 1, "req_link_valid": 15,
               "req_wide": 0, "req_wide_valid": 1, "req_guard": 0, "req_sel": 0,
               "req_rf_we": 0, "req_dst": 0, "req_pred_we": 0, "req_pred_dst": 0,
               "req_pred_src": 0, "req_lane": 1, "rsp_ready": 0,
               "req_job": self.rng.getrandbits(16), "req_tag": self.rng.getrandbits(16),
               "req_fmt": self.rng.getrandbits(8), "req_last": self.rng.getrandbits(1)}
        req.update({"req_" + key: value for key, value in fields.items()})
        return req

    def send(self, op: str | int = "MOV", stalls: int = 2, **fields: int) -> dict:
        if not self.model.outputs(self.pins)["req_ready"]:
            raise AssertionError("test overwrote pending tile request")
        self.step(**self.request(op, **fields))
        wait = 0
        while not self.model.outputs(self.pins)["rsp_valid"]:
            self.step(req_valid=1, req_imm=self.rng.getrandbits(16), req_vec=self.rng.getrandbits(SW),
                      req_mat=self.rng.getrandbits(SW), req_guard=7, req_sel=7, req_op=31)
            wait += 1
            if wait > 1:
                raise AssertionError("tile inserted an undeclared latency")
        response = self.model.outputs(self.pins).copy()
        for _ in range(stalls):
            self.step(req_valid=1, req_dst=self.rng.randrange(8), req_pred_dst=self.rng.randrange(4),
                      req_pred_src=self.rng.randrange(8), req_rf_we=1, req_pred_we=1,
                      req_wide=self.rng.getrandbits(64), req_tag=self.rng.getrandbits(16))
        self.step(req_valid=0, rsp_ready=1)
        return response

    def load(self, slot: int, value: int) -> None:
        self.send(a_kind=OPERANDS["VECTOR"], vec=value & SMASK, rf_we=1, dst=slot)


class TileRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if (ROOT / "rtl/v4/include/tile_interface.vh").read_text(encoding="utf-8") != render():
            raise RuntimeError("stale decoded tile definitions")
        cls.keep = os.environ.get("V4_PE_KEEP") == "1"
        (ROOT / "work").mkdir(exist_ok=True)
        cls.tmp = None if cls.keep else tempfile.TemporaryDirectory(prefix="v4_tile_", dir=ROOT / "work")
        cls.work = Path(tempfile.mkdtemp(prefix="v4_tile_", dir=ROOT / "work") if cls.keep else cls.tmp.name)
        cls.executables = {}

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.keep:
            print(f"Retained tile vectors/traces: {cls.work}")
        else:
            cls.tmp.cleanup()

    def replay(self, scenario: Scenario) -> None:
        tile = scenario.tile
        if tile not in self.executables:
            exe = self.work / f"tile_{tile}.xsim.json"
            result = compile_rtl(exe, "tb_pe_tile", filelist_sources(ROOT)+[ROOT/"verification/v4/pe/tb_pe_tile.sv"],
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
            fields = line.split()
            self.assertEqual([int(fields[0]), int(fields[1])], [index // 2, index % 2])
            actual = dict(zip(IO["outputs"], fields[2:]))
            for signal, value in expected.items():
                self.assertNotRegex(actual[signal], "[xz]", f"unknown {signal} cycle {index // 2}")
                self.assertEqual(int(actual[signal], 16), value,
                                 f"{name} cycle={index // 2} phase={index % 2} {signal}")
                checks += 1
        RUNS.append({"test": name, "tile": tile, "cycles": len(scenario.rows), "checks": checks,
                     "status": "PASS", "vectors_sha256": hashlib.sha256(payload.encode("ascii")).hexdigest(),
                     "trace_sha256": hashlib.sha256(trace.read_bytes()).hexdigest()})

    def test_rf8_sources_read_after_write_and_uninitialized(self) -> None:
        scenario = Scenario(23)
        for slot in range(8):
            response = scenario.send(a_kind=OPERANDS["RF"], a_idx=slot, rf_we=1, dst=slot)
            self.assertEqual(response["rsp_fault"], FAULTS["UNINIT"])
        for slot in range(8):
            scenario.load(slot, (slot-4)*7001)
        for slot in range(8):
            response = scenario.send("ADD", a_kind=OPERANDS["RF"], a_idx=slot,
                                     b_kind=OPERANDS["IMMEDIATE"], imm=1, rf_we=1, dst=slot, stalls=4)
            self.assertEqual(response["rsp_data"], ((slot-4)*7001+1) & SMASK)
        for value in (0, 1, 0x7FFF, 0x8000, 0xFFFF):
            scenario.send(a_kind=OPERANDS["IMMEDIATE"], imm=value, rf_we=1, dst=0)
        for kind in ("NONE", "MATRIX", "VECTOR"):
            scenario.send(a_kind=OPERANDS[kind], mat=SMASK, vec=1 << (SW-1), rf_we=1, dst=3)
        for kind in range(8, 16):
            self.assertEqual(scenario.send(a_kind=kind)["rsp_fault"], FAULTS["SOURCE"])
        for kind, field in (("MATRIX", "mat_valid"), ("VECTOR", "vec_valid")):
            self.assertEqual(scenario.send(a_kind=OPERANDS[kind], **{field: 0})["rsp_fault"], FAULTS["SOURCE"])
        self.replay(scenario)

    def test_predicate_compare_boolean_guard_and_select(self) -> None:
        scenario = Scenario(47)
        for pred in range(3):
            for source in range(7):
                scenario.send("CMP_S", a_kind=OPERANDS["VECTOR"], vec=SMASK,
                              b_kind=OPERANDS["IMMEDIATE"], imm=1,
                              pred_we=1, pred_dst=pred, pred_src=source, rf_we=1, dst=pred)
                for guard in range(8):
                    scenario.send(a_kind=OPERANDS["IMMEDIATE"], imm=123, guard=guard,
                                  rf_we=1, dst=7, pred_we=1, pred_dst=(pred+1)%3, pred_src=PSEL["DATA"])
                for select in range(8):
                    scenario.send("SELECT", a_kind=OPERANDS["IMMEDIATE"], imm=12,
                                  b_kind=OPERANDS["VECTOR"], vec=99, sel=select, rf_we=1, dst=6)
        for pred in range(3):
            scenario.send("XOR", a_kind=OPERANDS["PREDICATE"], a_idx=pred,
                          b_kind=OPERANDS["IMMEDIATE"], imm=1, pred_we=1, pred_dst=pred, pred_src=0)
        for op in ("AND", "OR", "CMP_U", "CMP_S"):
            scenario.send(op, a_kind=OPERANDS["PREDICATE"], a_idx=0,
                          b_kind=OPERANDS["PREDICATE"], b_idx=1, pred_we=1, pred_dst=2, pred_src=0)
        self.replay(scenario)

    def test_fault_priority_unused_operands_masks_and_atomicity(self) -> None:
        scenario = Scenario(101)
        scenario.send("ACC_ADD", wide=12345)
        for fields, code in ((dict(pred_we=1, pred_dst=3, a_kind=15), FAULTS["PRED"]),
                             (dict(pred_we=1, pred_src=7), FAULTS["PRED"]),
                             (dict(a_kind=OPERANDS["PREDICATE"], a_idx=3), FAULTS["PRED"]),
                             (dict(a_kind=OPERANDS["RF"], a_idx=1), FAULTS["UNINIT"]),
                             (dict(a_kind=OPERANDS["LINK"], a_idx=4), FAULTS["LINK"])):
            response = scenario.send(rf_we=1, dst=5, **fields)
            self.assertEqual(response["rsp_fault"], code)
            self.assertEqual(scenario.model.valid, 0)
        for op in ("HOLD", "ACC_CLEAR", "ACC_READ"):
            self.assertEqual(scenario.send(op, a_kind=15, b_kind=15)["rsp_fault"], 0)
        self.assertEqual(scenario.send(a_kind=OPERANDS["NONE"], b_kind=15)["rsp_fault"], 0)
        self.assertEqual(scenario.send("SELECT", a_kind=0, b_kind=15, sel=0)["rsp_fault"], FAULTS["SOURCE"])
        self.assertEqual(scenario.send("ACC_ADD", wide_valid=0)["rsp_fault"], FAULTS["SOURCE"])
        for opcode in range(32):
            for lane, guard in ((0, 0), (1, 7)):
                response = scenario.send(opcode, a_kind=15, b_kind=15, lane=lane, guard=guard,
                                         pred_we=1, pred_dst=3, pred_src=7, rf_we=1, dst=0)
                self.assertEqual(response["rsp_fault"], 0)
        scenario.load(0, 13)
        scenario.send("ACC_CLEAR", mode=0)
        scenario.send("MAC", a_kind=OPERANDS["RF"], a_idx=0, b_kind=OPERANDS["MATRIX"],
                      mat=100, mode=0, rf_we=1, dst=4, pred_we=1, pred_dst=2, pred_src=PSEL["ONE"], stalls=7)
        self.assertEqual(scenario.model.alu.acc, 1300)
        self.assertEqual(scenario.model.rf[4], 0)
        self.assertEqual(scenario.model.preds & 4, 4)
        self.replay(scenario)

    def test_acc_operand_rounding_mac_overflow_and_rollback(self) -> None:
        scenario = Scenario(211)
        for mode, shift in ((0, CF), (1, SF)):
            scenario.send("ACC_CLEAR", mode=mode)
            for value in (1 << (shift-1), -(1 << (shift-1)), (1 << 63)-1, -(1 << 63)):
                scenario.send("ACC_CLEAR", mode=mode)
                scenario.send("ACC_ADD", mode=mode, wide=value & AMASK)
                result = scenario.send(a_kind=OPERANDS["ACC"], rf_we=1, dst=1)
                if abs(value) < 1 << shift:
                    self.assertEqual(result["rsp_data"], 1 if value > 0 else SMASK)
                else:
                    self.assertEqual(result["rsp_fault"], FAULTS["ACC_RANGE"])
            scenario.send("ACC_CLEAR", mode=mode)
            scenario.send("ACC_ADD", wide=(1 << 63)-1, mode=mode)
            result = scenario.send("MAC", a_kind=OPERANDS["IMMEDIATE"], b_kind=OPERANDS["IMMEDIATE"],
                                   imm=1, mode=mode, rf_we=1, dst=2, pred_we=1, pred_dst=0, pred_src=PSEL["ONE"])
            self.assertEqual(result["rsp_fault"], 2)
            self.assertEqual(scenario.model.alu.acc, (1 << 63)-1)
            self.assertFalse(scenario.model.valid & (1 << 2))
            self.assertEqual(scenario.model.preds, 0)
        self.replay(scenario)

    def test_links_all_tile_positions_and_bad_selectors(self) -> None:
        for tile in range(32):
            scenario = Scenario(307+tile, tile)
            for idx in range(8):
                response = scenario.send(a_kind=OPERANDS["LINK"], a_idx=idx,
                                         links=sum((direction+1) << (direction*SW) for direction in range(4)), rf_we=1, dst=0)
                self.assertEqual(response["rsp_fault"], 0 if idx < 4 and edges(tile) & (1 << idx) else FAULTS["LINK"])
            for idx in range(4):
                scenario.send("ADD", a_kind=OPERANDS["IMMEDIATE"], imm=1,
                              b_kind=OPERANDS["LINK"], b_idx=idx, links=SMASK, link_valid=0)
            self.replay(scenario)

    def test_random_decoded_programs_and_read_after_write(self) -> None:
        scenario = Scenario(509)
        for slot in range(8):
            scenario.load(slot, scenario.rng.getrandbits(SW))
        for _ in range(1300):
            opcode = scenario.rng.randrange(32)
            scenario.send(opcode, mode=scenario.rng.randrange(2), a_kind=scenario.rng.randrange(16),
                          b_kind=scenario.rng.randrange(16), a_idx=scenario.rng.randrange(8), b_idx=scenario.rng.randrange(8),
                          imm=scenario.rng.getrandbits(16), mat=scenario.rng.getrandbits(SW), vec=scenario.rng.getrandbits(SW),
                          links=scenario.rng.getrandbits(4*SW), mat_valid=scenario.rng.randrange(2),
                          vec_valid=scenario.rng.randrange(2), link_valid=scenario.rng.randrange(16),
                          wide=scenario.rng.getrandbits(64), wide_valid=scenario.rng.randrange(2),
                          rf_we=scenario.rng.randrange(2), dst=scenario.rng.randrange(8), pred_we=scenario.rng.randrange(2),
                          pred_dst=scenario.rng.randrange(4), pred_src=scenario.rng.randrange(8),
                          guard=scenario.rng.randrange(8), sel=scenario.rng.randrange(8),
                          lane=scenario.rng.randrange(2), stalls=scenario.rng.randrange(4))
        scenario.send("ACC_CLEAR", mode=1)
        for _ in range(300):
            scenario.send("MAC", mode=1, a_kind=OPERANDS["VECTOR"], vec=scenario.rng.getrandbits(SW),
                          b_kind=OPERANDS["RF"], b_idx=scenario.rng.randrange(8), stalls=3)
        self.replay(scenario)

    def test_reset_cancel_snapshot_and_pending_combined_commit(self) -> None:
        scenario = Scenario(601)
        for control in ("rst", "cancel"):
            for stage in ("low", "response"):
                scenario.load(0, 123)
                scenario.send("ACC_CLEAR", mode=1)
                scenario.step(**scenario.request("MAC", mode=1, a_kind=OPERANDS["RF"], a_idx=0,
                                                  b_kind=OPERANDS["IMMEDIATE"], imm=321,
                                                  rf_we=1, dst=7, pred_we=1, pred_dst=1, pred_src=PSEL["ONE"]))
                if stage == "response":
                    scenario.step(req_valid=0, req_imm=0, req_guard=7)
                    scenario.step()
                scenario.step(**{control: 1}, req_valid=1, rsp_ready=1)
                scenario.step(**{control: 0}, req_valid=0, rsp_ready=0)
                self.assertEqual(scenario.model.valid, 0)
                self.assertEqual(scenario.model.preds, 0)
                self.assertEqual(scenario.model.alu.acc, 0)
                scenario.send(a_kind=OPERANDS["RF"], a_idx=7)
        self.replay(scenario)


if __name__ == "__main__":
    unittest.main()
