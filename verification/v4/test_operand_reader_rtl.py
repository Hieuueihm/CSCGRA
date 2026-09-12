"""Address-plan and tagged split-response reader replay, including reordered sources."""

import json
import random
import unittest

from models.v4.memory_exec import ROOT, SW, CW, FAULT, packed, field
from models.v4.operand_read import PlanModel, ReaderModel, plan
from models.v4.phi_stream import sign_word
from verification.v4.test_feeder_rtl import Replay

RUNS = []

class ReaderReplay(Replay):
    runs = RUNS

    def __init__(self, kind="reader"):
        self.io = json.loads((ROOT / f"verification/v4/memory/{kind}_io.json").read_text())
        self.top = "tb_operand_reader" if kind == "reader" else "tb_operand_plan"
        self.bench = f"verification/v4/memory/{self.top}.sv"
        self.model = ReaderModel() if kind == "reader" else PlanModel()
        self.rows, self.expected = [], []
        self.zero = dict.fromkeys(self.io["inputs"], 0)
        self.step(dict(self.zero, **({"rst": 1} if kind == "reader" else {})))

    def send(self, request, seed=1, bad=None):
        pins = dict(self.zero, **request, req_valid=1)
        self.step(pins)
        rng = random.Random(seed)
        jobs = {}
        for cycle in range(50):
            pins = dict(self.zero, **request)
            pins.update(mat_ready=int(cycle%3 == 0), vec_ready=int(cycle%2 == 0))
            before = self.model.outputs(pins)
            if before["rsp_valid"]:
                result = before.copy()
                for _ in range(3):
                    self.step(dict(pins, req_valid=1, req_out=2047, req_job=65535, mat_rsp_data=rng.getrandbits(576), vec_rsp_data=rng.getrandbits(864)))
                self.step(dict(pins, rsp_ready=1))
                return result
            for name in ("mat", "vec"):
                if name in jobs:
                    jobs[name][0] -= 1
                    if jobs[name][0] <= 0:
                        pins.update(jobs[name][1])
                        if before[name+"_rsp_ready"]:
                            jobs.pop(name)
                if before[name+"_valid"] and pins[name+"_ready"]:
                    response = {name+"_rsp_"+meta: before["mem_"+meta] for meta in ("job", "tag", "fmt")}
                    response.update({name+"_rsp_valid": 1, name+"_rsp_mask": before[name+"_mask"], name+"_rsp_generation": before[name+"_generation"]})
                    if name == "vec":
                        data = [0]*32
                        for bank in range(32):
                            if before["vec_mask"] >> bank & 1:
                                index = field(before["vec_addr"], bank, 7)*32+bank
                                data[bank] = 10000-index*3
                        response["vec_rsp_data"] = packed(data, SW)
                    elif before["mat_dense"]:
                        response["mat_rsp_data"] = packed([bank*1000-17000 for bank in range(32)], CW)
                    else:
                        signs, masks = [0]*8, [0]*8
                        for bank in range(8):
                            if before["mat_mask"] >> bank & 1:
                                address = field(before["mat_addr"], bank, 9)
                                group, block = divmod(address, (request["req_rows"]+31)//32)
                                col = group*8+bank
                                signs[bank] = sign_word(123, request["req_rows"], col, block)
                                masks[bank] = (1 << min(32, request["req_rows"]-block*32))-1
                        response.update(mat_rsp_data=packed(signs, 32), mat_rsp_masks=packed(masks, 32))
                    if bad and bad[0] == name:
                        response[name+"_rsp_"+bad[1]] = bad[2]
                    jobs[name] = [rng.randrange(1, 6), response]
            self.step(pins)
        raise AssertionError("reader did not complete")

def request(mode=0, trans=0, rows=33, cols=35, out=0, red=0, step=0, base=0):
    return dict(req_mode=mode, req_trans=trans, req_rows=rows, req_cols=cols, req_out=out, req_red=red, req_step=step,
                req_vec_base=base, req_vec_plane=0, req_scale=32768, req_key=91,
                req_mat_generation=1, req_vec_generation=2, req_job=7, req_tag=55, req_fmt=3, req_last=0)

class OperandReadRtlTests(unittest.TestCase):
    def test_plan_all_directions_banks_and_shape_extremes(self):
        replay = ReaderReplay("plan")
        for mode, trans in ((0, 0), (1, 1), (2, 0), (2, 1), (3, 0), (3, 1)):
            for rows, cols in ((1, 1), (33, 35), (128, 96), (128, 1024)):
                outputs, reductions = (cols, rows) if trans else (rows, cols)
                for out in (0, ((outputs-1)//(8 if mode%2 else 32))*(8 if mode%2 else 32)):
                    for red in (0, ((reductions-1)//32)*32 if mode%2 else reductions-1):
                        for step in range(8 if mode%2 else 1):
                            for base in (0, 7, 4095):
                                replay.step(dict(mode=mode, trans=trans, rows=rows, cols=cols, out_idx=out, red_idx=red, step=step, vec_base=base))
        for row in (0, 129):
            replay.step(dict(mode=0, trans=0, rows=row, cols=1024, out_idx=0, red_idx=0, step=0, vec_base=0))
        replay.run(self)

    def test_source_reordering_stalls_tail_and_metadata_faults(self):
        replay = ReaderReplay()
        for mode, trans in ((0, 0), (1, 1), (2, 0), (2, 1), (3, 0), (3, 1)):
            for base in (0, 7):
                result = replay.send(request(mode, trans, base=base), seed=mode+base)
                self.assertEqual(result["rsp_fault"], 0)
        result = replay.send(request(1, 1, rows=1, cols=1, step=7))
        self.assertEqual((result["rsp_fault"], result["rsp_mask"]), (0, 0))
        for source in ("mat", "vec"):
            for field_name, value, expected in (("tag", 54, "TAG"), ("job", 8, "TAG"), ("fmt", 4, "TAG"),
                                                ("generation", 33, "TAG"), ("fault", 1, "SOURCE"), ("mask", 0, "SOURCE")):
                result = replay.send(request(3, 1), bad=(source, field_name, value))
                self.assertEqual(result["rsp_fault"], FAULT[expected])
                self.assertEqual(result["rsp_mask"], 0)
        for edits in ({"req_rows": 0}, {"req_out": 1}, {"req_vec_base": 4095}, {"req_vec_plane": 3}, {"req_scale": 0}):
            req = request(1, 1)
            req.update(edits)
            self.assertNotEqual(replay.send(req)["rsp_fault"], 0)
        replay.run(self)

    def test_reset_cancel_after_partial_join(self):
        replay = ReaderReplay()
        for reset in ("rst", "cancel"):
            req = request()
            replay.step(dict(replay.zero, **req, req_valid=1))
            replay.step(dict(replay.zero, **req, mat_ready=1, vec_ready=0))
            replay.step(dict(replay.zero, **req, mat_rsp_valid=1, mat_rsp_mask=1, mat_rsp_generation=1, mat_rsp_job=7, mat_rsp_tag=55, mat_rsp_fmt=3))
            replay.step(dict(replay.zero, **req, **{reset: 1}, vec_rsp_valid=1))
            self.assertEqual(replay.send(req)["rsp_fault"], 0)
        replay.run(self)
