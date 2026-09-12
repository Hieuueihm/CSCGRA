"""Bit/cycle replay of PE primitives using permanent SystemVerilog benches."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources
from models.v4.pe_exec import ABI, AMASK, AW, CF, FAULTS, OPS, ROOT, SF, SMASK, SW
from models.v4.pe_exec import AluModel, RouterModel, edges, evaluate
from scripts.v4.generate_pe_interface import render

IO = json.loads((ROOT / "verification/v4/pe/io.json").read_text(encoding="utf-8"))
RUNS: list[dict] = []
COMMANDS: list[dict] = []
COMPILE_LOGS: list[str] = []


class Scenario:
    def __init__(self, kind: str, seed: int, tile: int = 0):
        self.kind = kind
        self.tile = tile
        self.rng = random.Random(seed)
        self.model = AluModel() if kind == "alu" else RouterModel(tile)
        self.pins = dict.fromkeys(IO[kind]["inputs"], 0)
        self.pins.update(req_lane=1, req_exec=1)
        self.rows: list[int] = []
        self.expected: list[dict] = []
        self.step(rst=1)
        self.step(rst=0)

    def step(self, **changes: int) -> None:
        self.pins.update(changes)
        packed = 0
        for name, width in IO[self.kind]["inputs"].items():
            value = self.pins[name]
            if not 0 <= value < (1 << width):
                raise ValueError(f"{name} does not fit {width} bits: {value}")
            packed = (packed << width) | value
        self.rows.append(packed)
        self.expected.append(self.model.outputs(self.pins) if len(self.rows) > 1 else {})
        self.model.tick(self.pins)
        self.expected.append(self.model.outputs(self.pins))

    def meta(self) -> dict[str, int]:
        return {"req_job": self.rng.getrandbits(16), "req_tag": self.rng.getrandbits(16),
                "req_fmt": self.rng.getrandbits(8), "req_last": self.rng.getrandbits(1)}

    def alu(self, op: str | int, arg_a: int = 0, arg_b: int = 0, acc: int = 0,
            mode: int = 0, lane: int = 1, execute: int = 1, sel: int = 0, stalls: int = 0) -> dict:
        if not self.model.outputs(self.pins)["req_ready"]:
            raise AssertionError("test tried to overwrite an outstanding request")
        self.step(req_valid=1, req_op=OPS[op] if isinstance(op, str) else op,
                  req_a=arg_a & SMASK, req_b=arg_b & SMASK, req_acc=acc & AMASK,
                  req_mode=mode, req_lane=lane, req_exec=execute, req_sel=sel,
                  rsp_ready=0, **self.meta())
        request = self.pins.copy()
        latency = 1
        while self.model.response is None:
            self.step(req_valid=0, req_a=self.rng.getrandbits(SW), req_b=self.rng.getrandbits(SW),
                      req_op=31, req_mode=1-mode, **self.meta())
            latency += 1
            if latency > 2:
                raise AssertionError("arithmetic response missed schedule")
        expected_latency = evaluate(request, self.model.acc, self.model.mode)[2]
        if latency != expected_latency:
            raise AssertionError("arithmetic latency differs from machine contract")
        response = self.model.response.copy()
        for _ in range(stalls):
            self.step(req_valid=1, req_a=self.rng.getrandbits(SW), req_b=self.rng.getrandbits(SW),
                      req_acc=self.rng.getrandbits(AW), **self.meta())
        self.step(req_valid=0, rsp_ready=1)
        return response

    def route(self, selectors: list[int], sources: int = 7, lane: int = 1, execute: int = 1,
              stalls: bool = True) -> dict:
        if not self.model.outputs(self.pins)["req_ready"]:
            raise AssertionError("test tried to overwrite an outstanding route")
        self.step(req_valid=1, req_routes=sum(sel << (direction*3) for direction, sel in enumerate(selectors)),
                  req_src=sources, req_val=self.rng.getrandbits(AW), req_acc=self.rng.getrandbits(AW),
                  req_res=self.rng.getrandbits(AW), req_lane=lane, req_exec=execute,
                  out_ready=0, rsp_ready=0, **self.meta())
        delivered = 0
        initial = self.model.pending
        cycles = 0
        while self.model.pending:
            ready = self.rng.randrange(16) if stalls and cycles < 20 else 15
            accepted = self.model.pending & ready
            if accepted & delivered:
                raise AssertionError("duplicate modeled link delivery")
            delivered |= accepted
            self.step(req_valid=1, out_ready=ready, req_val=self.rng.getrandbits(AW),
                      req_acc=self.rng.getrandbits(AW), req_res=self.rng.getrandbits(AW),
                      req_routes=self.rng.getrandbits(12), req_src=0, **self.meta())
            cycles += 1
        if delivered != initial:
            raise AssertionError("incomplete modeled route")
        response = self.model.response.copy()
        for _ in range(3 if stalls else 0):
            self.step(req_valid=1, out_ready=15, **self.meta())
        self.step(req_valid=0, rsp_ready=1)
        return response


class PeRtlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if (ROOT / "rtl/v4/include/pe_interface.vh").read_text(encoding="utf-8") != render():
            raise RuntimeError("stale PE generated definitions")
        (ROOT / "work").mkdir(exist_ok=True)
        cls.keep = os.environ.get("V4_PE_KEEP") == "1"
        cls.tmp = None if cls.keep else tempfile.TemporaryDirectory(prefix="v4_pe_", dir=ROOT / "work")
        cls.work = Path(tempfile.mkdtemp(prefix="v4_pe_", dir=ROOT / "work") if cls.keep else cls.tmp.name)
        cls.executables = {}

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.keep:
            print(f"Retained PE RTL vectors/traces: {cls.work}")
        else:
            cls.tmp.cleanup()

    def replay(self, scenario: Scenario) -> None:
        kind = scenario.kind
        key = kind, scenario.tile
        if key not in self.executables:
            top = "tb_pe_alu" if kind == "alu" else "tb_mesh_router"
            exe = self.work / f"{top}_{scenario.tile}.xsim.json"
            result = compile_rtl(exe, top, filelist_sources(ROOT)+[ROOT/f"verification/v4/pe/{top}.sv"],
                                 root=ROOT, parameters={"TILE_ID": scenario.tile} if kind == "router" else None)
            COMMANDS.extend(result.commands)
            COMPILE_LOGS.append(result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.executables[key] = exe
        name = f"{self._testMethodName}_{scenario.tile}"
        vector = self.work / (name + ".hex")
        trace = self.work / (name + ".trace")
        payload = "".join(f"{row:x}\n" for row in scenario.rows)
        vector.write_text(payload, encoding="ascii")
        result = run_rtl(self.executables[key], ["+src="+vector.as_posix(), "+dst="+trace.as_posix()], root=ROOT)
        COMMANDS.extend(result.commands)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS cycles={len(scenario.rows)}", result.stdout)
        lines = trace.read_text(encoding="ascii").splitlines()
        self.assertEqual(len(lines), len(scenario.expected))
        checks = 0
        for index, (line, expected) in enumerate(zip(lines, scenario.expected)):
            tokens = line.split()
            self.assertEqual([int(tokens[0]), int(tokens[1])], [index // 2, index % 2])
            actual = dict(zip(IO[kind]["outputs"], tokens[2:]))
            for signal, value in expected.items():
                self.assertNotRegex(actual[signal], "[xz]", f"unknown {signal} at edge {index // 2}")
                self.assertEqual(int(actual[signal], 16), value,
                                 f"{name} cycle={index // 2} phase={index % 2} {signal}")
                checks += 1
        RUNS.append({"test": name, "kind": kind, "tile": scenario.tile, "cycles": len(scenario.rows),
                     "checks": checks, "status": "PASS",
                     "vectors_sha256": hashlib.sha256(payload.encode("ascii")).hexdigest(),
                     "trace_sha256": hashlib.sha256(trace.read_bytes()).hexdigest()})

    def test_alu_scalar_edges_predicates_and_random(self) -> None:
        scenario = Scenario("alu", 23)
        bounds = (-(1 << (SW-1)), -(1 << (SW-1))+1, -1, 0, 1, (1 << (SW-1))-1)
        for op in ("HOLD", "MOV", "ADD", "SUB", "ABS", "CMP_S", "CMP_U", "SELECT", "AND", "OR", "XOR", "NOT"):
            for arg_a in bounds:
                for arg_b in bounds:
                    scenario.alu(op, arg_a, arg_b, sel=scenario.rng.randrange(2), stalls=scenario.rng.randrange(4))
        for _ in range(700):
            op = scenario.rng.choice(("ADD", "SUB", "ABS", "CMP_S", "CMP_U", "SELECT", "AND", "OR", "XOR", "NOT"))
            scenario.alu(op, scenario.rng.getrandbits(SW), scenario.rng.getrandbits(SW),
                         sel=scenario.rng.randrange(2), stalls=scenario.rng.randrange(4))
        self.replay(scenario)

    def test_alu_multiply_split_rounding_and_coeff_faults(self) -> None:
        scenario = Scenario("alu", 47)
        for mode, shift, width in ((0, CF, 18), (1, SF, SW)):
            bounds_a = (-(1 << 26), -(1 << 26)+1, -1, 0, 1, (1 << 26)-1)
            bounds_b = (-(1 << (width-1)), -131073, -131072, -1, 0, 1, 131071, 131072, (1 << (width-1))-1)
            for arg_a in bounds_a:
                for arg_b in bounds_b:
                    scenario.alu("MUL", arg_a, arg_b, mode=mode, stalls=2)
            for sign in (-1, 1):
                for offset in (-1, 0, 1):
                    response = scenario.alu("MUL", sign * ((1 << (shift-1)) + offset), 1, mode=mode, stalls=3)
                    self.assertEqual(response["rsp_data"], (sign if offset >= 0 else 0) & SMASK)
            for _ in range(650):
                scenario.alu("MUL", scenario.rng.getrandbits(SW),
                             scenario.rng.randrange(-(1 << (width-1)), 1 << (width-1)),
                             mode=mode, stalls=scenario.rng.randrange(3))
        self.replay(scenario)

    def test_alu_acc_prefix_overflow_mode_and_retirement(self) -> None:
        scenario = Scenario("alu", 101)
        maximum = (1 << 63) - 1
        for mode in (0, 1):
            scenario.alu("ACC_CLEAR", mode=mode, stalls=4)
            for _ in range(300):
                scenario.alu("MAC", scenario.rng.randrange(-100000, 100001),
                             scenario.rng.randrange(-100000, 100001), mode=mode, stalls=2)
            scenario.alu("ACC_READ", mode=mode, stalls=3)
            for edge, increment in ((maximum, 1), (-(1 << 63), -1)):
                scenario.alu("ACC_CLEAR", mode=mode)
                scenario.alu("ACC_ADD", acc=edge, mode=mode, stalls=4)
                result = scenario.alu("MAC", increment, 1, mode=mode, stalls=5)
                self.assertEqual(result["rsp_fault"], FAULTS["ACC"])
                self.assertEqual(scenario.model.acc, edge)
                result = scenario.alu("ACC_ADD", acc=increment, mode=mode)
                self.assertEqual(result["rsp_fault"], FAULTS["ACC"])
                self.assertEqual(scenario.model.acc, edge)
                scenario.alu("ACC_ADD", acc=-increment, mode=mode)
                scenario.alu("ACC_READ", mode=mode)
            for op in ("MAC", "ACC_ADD", "ACC_READ"):
                result = scenario.alu(op, 1, 1, mode=1-mode, stalls=2)
                self.assertEqual(result["rsp_fault"], FAULTS["MODE"])
            scenario.alu("ACC_CLEAR", mode=mode)
            scenario.alu("ACC_ADD", acc=-(1 << (CF if mode == 0 else SF)-1), mode=mode)
            result = scenario.alu("ACC_READ", mode=mode)
            self.assertEqual(result["rsp_data"], SMASK)
        self.replay(scenario)

    def test_alu_masked_faults_and_unknown_ops(self) -> None:
        scenario = Scenario("alu", 211)
        for opcode in range(17, 32):
            result = scenario.alu(opcode, stalls=2)
            self.assertEqual(result["rsp_fault"], FAULTS["OP"])
        scenario.alu("ACC_ADD", acc=917)
        for lane, execute in ((0, 1), (1, 0), (0, 0)):
            for opcode in range(32):
                result = scenario.alu(opcode, -(1 << 26), (1 << 26)-1, acc=AMASK,
                                      mode=1, lane=lane, execute=execute, stalls=2)
                self.assertEqual(result["rsp_fault"], 0)
                self.assertEqual(scenario.model.acc, 917)
        self.replay(scenario)

    def test_alu_reset_cancel_split_and_unretired_commit(self) -> None:
        scenario = Scenario("alu", 307)
        for control in ("rst", "cancel"):
            for mode, op, stage in ((0, "ACC_ADD", "response"), (1, "MAC", "low"),
                                     (1, "MAC", "response"), (1, "MUL", "low"),
                                     (0, "ACC_CLEAR", "response")):
                scenario.alu("ACC_CLEAR", mode=mode)
                scenario.alu("ACC_ADD", acc=123456, mode=mode)
                scenario.step(req_valid=1, req_op=OPS[op], req_a=123, req_b=SMASK,
                              req_acc=99, req_mode=mode, req_lane=1, req_exec=1, rsp_ready=0)
                if stage == "response":
                    while scenario.model.response is None:
                        scenario.step(req_valid=0)
                    scenario.step(req_valid=0)
                    scenario.step()
                scenario.step(**{control: 1}, rsp_ready=1, req_valid=1)
                scenario.step(**{control: 0}, req_valid=0, rsp_ready=0)
                result = scenario.alu("ACC_READ", mode=0)
                self.assertEqual(result["rsp_acc"], 0)
                self.assertEqual(result["rsp_data"], 0)
        self.replay(scenario)

    def test_router_all_tiles_edges_sources_and_independent_stalls(self) -> None:
        for tile in range(32):
            scenario = Scenario("router", 401+tile, tile)
            for direction in range(4):
                for selector in range(1, 8):
                    routes = [0]*4
                    routes[direction] = selector
                    scenario.route(routes)
            legal = edges(tile)
            routes = [1 + direction % 3 if legal & (1 << direction) else 0 for direction in range(4)]
            scenario.route(routes, stalls=False)
            for src in range(8):
                scenario.route(routes, sources=src)
            for _ in range(40):
                routes = [scenario.rng.randrange(4) if legal & (1 << direction) else 0 for direction in range(4)]
                scenario.route(routes)
            scenario.route([0]*4)
            scenario.route([7]*4, sources=0, lane=0)
            scenario.route([7]*4, sources=0, execute=0)
            self.replay(scenario)

    def test_router_cancel_partial_delivery_and_completion_stall(self) -> None:
        scenario = Scenario("router", 509, 5)
        for control in ("rst", "cancel"):
            for phase in ("before_link", "partial", "complete"):
                scenario.step(req_valid=1, req_routes=1 | (2 << 3) | (3 << 6) | (1 << 9),
                              req_val=SMASK, req_acc=1 << 63, req_res=AMASK, req_src=7,
                              req_lane=1, req_exec=1, out_ready=0, rsp_ready=0, **scenario.meta())
                if phase != "before_link":
                    scenario.step(req_valid=0, out_ready=1 if phase == "partial" else 15)
                    scenario.step(out_ready=0)
                scenario.step(**{control: 1}, out_ready=15, rsp_ready=1)
                scenario.step(**{control: 0}, req_valid=0, out_ready=0, rsp_ready=0)
                scenario.route([1, 2, 3, 1])
        self.replay(scenario)


if __name__ == "__main__":
    unittest.main()
