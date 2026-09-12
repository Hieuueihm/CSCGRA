"""Replay real feeder RTL against integer coordinates before/after every edge."""

import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import tempfile
import unittest

from scripts.v4.xsim import compile_rtl, run_rtl, filelist_sources
from models.v4.feeder_exec import ROOT, SW, CW, FeederModel, evaluate
from models.v4.phi_stream import sign_word
from models.v4.lfsr_operator import indexed_sign
from scripts.v4.generate_feeder_interface import render

IO = json.loads((ROOT / "verification/v4/dataflow/io.json").read_text())
RUNS = []

def pack(values, width):
    return sum((value & ((1 << width) - 1)) << (index * width) for index, value in enumerate(values))

def bundle(mode=0, trans=0, rows=65, cols=57, out=0, red=0, step=0):
    pins = dict.fromkeys(IO["inputs"], 0)
    pins.update(req_mode=mode, req_trans=trans, req_rows=rows, req_cols=cols,
                req_out=out, req_red=red, req_step=step, req_scale=32768,
                req_vec=pack([12345, -23456, (1 << 26)-1, -(1 << 26)], SW), req_vec_valid=15,
                req_sign_valid=255, req_dense_valid=(1 << 32)-1)
    transpose = bool(trans) if mode >= 2 else mode == 1
    rfour = mode in (1, 3)
    signs, masks, coeffs = [0]*8, [0]*8, [0]*32
    addresses = {}
    for tile in range(32):
        output = out + (tile // 4 if rfour else tile)
        reduction = red + (8*(tile % 4)+step if rfour else 0)
        row, col = (reduction, output) if transpose else (output, reduction)
        if row >= rows or col >= cols:
            continue
        if mode < 2:
            signs[col % 8] = sign_word(0x12345678, rows, col, row // 32)
            masks[col % 8] = (1 << min(32, rows - row // 32 * 32))-1
        else:
            bank = (row + col) % 32
            address = row * ((cols + 31)//32) + col//32
            if bank in addresses and addresses[bank] != address:
                raise AssertionError("dense schedule has a bank conflict")
            addresses[bank] = address
            coeffs[bank] = ((row * 7919 + col * 104729) % (1 << CW)) - (1 << (CW-1))
    pins.update(req_signs=pack(signs, 32), req_masks=pack(masks, 32), req_dense=pack(coeffs, CW))
    return pins

class Replay:
    io = IO
    runs = RUNS
    top = "tb_operand_feeder"
    bench = "verification/v4/dataflow/tb_operand_feeder.sv"
    def __init__(self):
        self.model = FeederModel()
        self.rows, self.expected = [], []
        self.step(dict(bundle(), rst=1))

    def step(self, pins):
        packed = 0
        for name, width in self.io["inputs"].items():
            if not 0 <= pins[name] < 1 << width:
                raise AssertionError((name, pins[name], width))
            packed = packed << width | pins[name]
        self.rows.append(packed)
        self.expected.append(self.model.outputs(pins) if len(self.rows) > 1 else {})
        self.model.tick(pins)
        self.expected.append(self.model.outputs(pins))

    def transaction(self, pins, stalls=2):
        self.step(dict(pins, req_valid=1, rsp_ready=0))
        for index in range(stalls):
            self.step(dict(pins, req_valid=1, req_scale=index, req_signs=index,
                           req_vec=index, req_job=65535-index, rsp_ready=0))
        self.step(dict(pins, req_valid=1, rsp_ready=1))
        self.step(dict(pins, req_valid=0, rsp_ready=0))

    def run(self, test):
        work = ROOT / "work"
        work.mkdir(exist_ok=True)
        path = Path(tempfile.mkdtemp(prefix="v4_feeder_", dir=work))
        try:
            vectors, trace, image = path / "vectors.hex", path / "trace.txt", path / "sim.xsim.json"
            vectors.write_text("".join(f"{row:x}\n" for row in self.rows))
            logs = []
            compiled = compile_rtl(image, self.top, filelist_sources(ROOT)+[ROOT/self.bench], root=ROOT)
            logs.extend(compiled.commands)
            test.assertEqual(compiled.returncode, 0, compiled.stdout+compiled.stderr)
            simulation = run_rtl(image, ["+src="+vectors.as_posix(), "+dst="+trace.as_posix()], root=ROOT)
            logs.extend(simulation.commands)
            test.assertEqual(simulation.returncode, 0, simulation.stdout+simulation.stderr)
            test.assertIn("PASS cycles=", simulation.stdout)
            lines = trace.read_text().splitlines()
            test.assertEqual(len(lines), len(self.expected))
            comparisons = 0
            for index, (line, expected) in enumerate(zip(lines, self.expected)):
                values = line.split()
                test.assertEqual((int(values[0]), int(values[1])), (index//2, index%2))
                test.assertEqual(len(values), len(self.io["outputs"])+2)
                for name, actual in zip(self.io["outputs"], values[2:]):
                    if name in expected:
                        test.assertEqual(int(actual, 16), expected[name], f"cycle/edge {index//2}/{index%2} {name}")
                        comparisons += 1
            self.runs.append(dict(cycles=len(self.rows), comparisons=comparisons, commands=logs,
                             vector_sha256=hashlib.sha256(vectors.read_bytes()).hexdigest(),
                             trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest()))
        finally:
            if os.environ.get("V4_PE_KEEP") != "1":
                shutil.rmtree(path)

class FeederRtlTests(unittest.TestCase):
    def test_definitions(self):
        self.assertEqual((ROOT / "rtl/v4/include/feeder_interface.vh").read_text(), render())

    def test_coordinate_schedules(self):
        replay = Replay()
        for mode, trans in ((0, 0), (1, 1), (2, 0), (2, 1), (3, 0), (3, 1)):
            for rows, cols in ((1, 1), (7, 9), (31, 33), (32, 32), (33, 31), (65, 57), (128, 96)):
                outputs, reductions = (cols, rows) if trans else (rows, cols)
                rfour = mode in (1, 3)
                for out in range(0, outputs, 8 if rfour else 32):
                    for red in range(0, reductions, 32 if rfour else 1):
                        for step in range(8 if rfour else 1):
                            pins = bundle(mode, trans, rows, cols, out, red, step)
                            result = evaluate(pins)
                            self.assertEqual(result["rsp_fault"], 0)
                            for tile in range(32):
                                output = out + (tile//4 if rfour else tile)
                                reduction = red + (8*(tile%4)+step if rfour else 0)
                                row, col = (reduction, output) if trans else (output, reduction)
                                valid = row < rows and col < cols
                                self.assertEqual(result["rsp_mask"] >> tile & 1, int(valid))
                                if valid:
                                    coeff = (indexed_sign(0x12345678, rows, row, col)*32768 if mode < 2 else
                                             ((row * 7919 + col * 104729) % (1 << CW)) - (1 << (CW-1)))
                                    self.assertEqual(result["rsp_mat"] >> (tile*SW) & ((1 << SW)-1), coeff & ((1 << SW)-1))
                            pins.update(req_job=123, req_tag=(red+out)&65535, req_fmt=99, req_last=int(red+32 >= reductions))
                            replay.transaction(pins, stalls=0)
        replay.run(self)

    def test_maximum_phi_and_dense_extremes(self):
        replay = Replay()
        for mode, trans, out, red, step in ((0, 0, 96, 1023, 0), (1, 1, 1016, 96, 7)):
            pins = bundle(mode, trans, 128, 1024, out, red, step)
            self.assertEqual(evaluate(pins)["rsp_mask"], (1 << 32)-1)
            replay.transaction(pins, stalls=5)
        pins = bundle(2, 0, 32, 1)
        pins["req_dense"] = pack([-(1 << (CW-1)), (1 << (CW-1))-1]*16, CW)
        response = evaluate(pins)
        self.assertEqual(response["rsp_mat"] & ((1 << SW)-1), (-(1 << (CW-1))) & ((1 << SW)-1))
        self.assertEqual(response["rsp_mat"] >> SW & ((1 << SW)-1), (1 << (CW-1))-1)
        replay.transaction(pins)
        replay.run(self)

    def test_stall_reset_cancel_faults(self):
        replay = Replay()
        rng = random.Random(9401)
        for index in range(400):
            mode = index % 4
            pins = bundle(mode, mode % 2)
            pins.update(req_job=rng.getrandbits(16), req_tag=rng.getrandbits(16),
                        req_fmt=rng.getrandbits(8), req_last=index % 2)
            mutation = index % 13
            edits = ({"req_rows": 0}, {"req_cols": 2047}, {"req_out": 1}, {"req_red": 2047},
                     {"req_scale": 0}, {"req_scale": 1 << (CW-1)}, {"req_src_fault": 1},
                     {"req_vec_valid": 0}, {"req_sign_valid": 0, "req_dense_valid": 0},
                     {"req_masks": 0}, {"req_scale": (1 << (CW-1))-1}, {}, {})
            pins.update(edits[mutation])
            replay.transaction(pins, rng.randrange(5))
            replay.step(dict(pins, req_valid=1))
            replay.step(dict(pins, req_valid=1, **({"rst": 1} if index % 2 else {"cancel": 1})))
            replay.transaction(bundle(), stalls=1)
        replay.run(self)

    def test_masked_sources_and_fault_priority(self):
        replay = Replay()
        pins = bundle(1, 1, 1, 1)
        pins.update(req_sign_valid=1, req_vec_valid=1)
        self.assertEqual(evaluate(pins)["rsp_mask"], 1)
        replay.transaction(pins)
        pins.update(req_step=7, req_sign_valid=0, req_vec_valid=0)
        self.assertEqual(evaluate(pins)["rsp_fault"], 0)
        self.assertEqual(evaluate(pins)["rsp_mask"], 0)
        replay.transaction(pins)
        for edits, expected in (({"req_rows": 0, "req_out": 1, "req_scale": 0, "req_src_fault": 1}, 1),
                                ({"req_out": 1, "req_scale": 0, "req_src_fault": 1}, 2),
                                ({"req_scale": 0, "req_src_fault": 1}, 3), ({"req_src_fault": 1}, 4)):
            request = dict(bundle(), **edits)
            self.assertEqual(evaluate(request)["rsp_fault"], expected)
            replay.transaction(request)
        replay.run(self)
