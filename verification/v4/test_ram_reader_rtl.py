"""Real B/vector RAM composition with independent coordinate assertions."""

import json
import unittest

from models.v4.memory_exec import ROOT, SW, CW, VectorModel, BModel, packed
from models.v4.operand_read import ReaderModel
from verification.v4.test_feeder_rtl import Replay
from verification.v4.test_operand_reader_rtl import request

RUNS = []
IO = json.loads((ROOT / "verification/v4/memory/ram_reader_io.json").read_text())

class RamModel:
    def __init__(self):
        self.reader, self.matrix, self.vector = ReaderModel(), BModel(), VectorModel()
        self.ios = {prefix: json.loads((ROOT / f"verification/v4/memory/{kind}_io.json").read_text())
                    for prefix, kind in (("b", "b"), ("v", "vector"))}

    def wire(self, pins):
        stores = {}
        for prefix, io in self.ios.items():
            stores[prefix] = {name: pins.get(prefix+"_"+name, 0) for name in io["inputs"]}
            stores[prefix].update(rst=pins["rst"], cancel=pins["cancel"])
        outputs = {"b": self.matrix.outputs(stores["b"]), "v": self.vector.outputs(stores["v"])}
        reader = json.loads((ROOT / "verification/v4/memory/reader_io.json").read_text())
        feed = {name: pins.get(name, 0) for name in reader["inputs"]}
        for prefix, source in (("b", "mat"), ("v", "vec")):
            feed[source+"_ready"] = (outputs[prefix]["rd_ready"] & 1) * pins[source+"_req_en"]
            feed[source+"_rsp_valid"] = (outputs[prefix]["rsp_valid"] & 1) * pins[source+"_rsp_en"]
            for name in ("data", "mask", "generation", "job", "tag", "fmt", "fault"):
                width = reader["inputs"][source+"_rsp_"+name]
                feed[source+"_rsp_"+name] = outputs[prefix]["rsp_"+name] & ((1 << width)-1)
        result = self.reader.outputs(feed)
        for prefix, source in (("b", "mat"), ("v", "vec")):
            target = stores[prefix]
            target["rd_valid"] = result[source+"_valid"] * pins[source+"_req_en"]
            target["rsp_ready"] = result[source+"_rsp_ready"] * pins[source+"_rsp_en"]
            for name in ("mask", "addr", "generation"):
                target["rd_"+name] = result[source+"_"+name]
            for name in ("job", "tag", "fmt"):
                target["rd_"+name] = result["mem_"+name]
            target["rd_key" if prefix == "b" else "rd_plane"] = result["mat_key" if prefix == "b" else "vec_plane"]
        return feed, stores, outputs, result

    def outputs(self, pins):
        _, _, outputs, result = self.wire(pins)
        for prefix in outputs:
            result.update({prefix+"_"+name: value for name, value in outputs[prefix].items() if prefix+"_"+name in IO["outputs"]})
        return result

    def tick(self, pins):
        feed, stores, _, _ = self.wire(pins)
        self.reader.tick(feed)
        self.matrix.tick(stores["b"])
        self.vector.tick(stores["v"])

class RamReplay(Replay):
    runs, io, top, bench = RUNS, IO, "tb_ram_reader", "verification/v4/memory/tb_ram_reader.sv"

    def __init__(self):
        self.model, self.rows, self.expected = RamModel(), [], []
        self.zero = dict.fromkeys(IO["inputs"], 0)
        self.send(rst=1)

    def send(self, **pins):
        self.step(dict(self.zero, **pins))

    def load(self, rows, cols):
        self.send(b_begin_valid=1, b_begin_rows=rows, b_begin_cols=cols, b_begin_key=91,
                  b_begin_generation=1, b_begin_job=7, b_begin_fmt=3,
                  v_begin_valid=1, v_begin_plane=0, v_begin_length=4096,
                  v_begin_generation=2, v_begin_job=7, v_begin_fmt=3)
        for block in range(128):
            self.send(v_fill_valid=1, v_fill_block=block, v_fill_mask=(1 << 32)-1,
                      v_fill_data=packed([10000-3*index for index in range(block*32, block*32+32)], SW), v_fill_last=int(block == 127))
        for col in range(cols):
            for block in range((rows+31)//32):
                values = [row*101-col*53 for row in range(block*32, min(rows, block*32+32))]
                self.send(b_fill_valid=1, b_fill_slot=col, b_fill_block=block,
                          b_fill_mask=(1 << len(values))-1, b_fill_data=packed(values, CW),
                          b_fill_last=int(col == cols-1 and (block+1)*32 >= rows))

    def transact(self, req):
        self.send(**req, req_valid=1)
        for cycle in range(100):
            pins = dict(self.zero, **req, mat_req_en=int(cycle%3 == 0), vec_req_en=int(cycle%2 == 0),
                        mat_rsp_en=int(cycle%5 == 0), vec_rsp_en=int(cycle%7 == 0))
            result = self.model.outputs(pins)
            if result["rsp_valid"]:
                for _ in range(4):
                    self.step(dict(pins, req_valid=1, req_out=2047, req_tag=65535))
                self.step(dict(pins, rsp_ready=1))
                return result
            self.step(pins)
        raise AssertionError("RAM reader timeout")

class RamReaderRtlTests(unittest.TestCase):
    def test_real_ram_both_directions_tail_and_backpressure(self):
        replay = RamReplay()
        for rows, cols in ((1, 1), (33, 35), (128, 96)):
            replay.load(rows, cols)
            for mode in (2, 3):
                for trans in (0, 1):
                    outputs, reductions = (cols, rows) if trans else (rows, cols)
                    stride = 8 if mode == 3 else 32
                    for out in (0, ((outputs-1)//stride)*stride):
                        for red in (0, ((reductions-1)//32)*32 if mode == 3 else reductions-1):
                            for step in range(8 if mode == 3 else 1):
                                req = request(mode, trans, rows, cols, out, red, step, base=7)
                                result = replay.transact(req)
                                matrix, vector, mask = [0]*32, [0]*32, 0
                                for tile in range(32):
                                    output = out+(tile//4 if mode == 3 else tile)
                                    reduction = red+(8*(tile%4)+step if mode == 3 else 0)
                                    if output < outputs and reduction < reductions:
                                        row, col = (reduction, output) if trans else (output, reduction)
                                        matrix[tile] = row*101-col*53
                                        vector[tile] = 10000-3*(7+reduction)
                                        mask |= 1 << tile
                                self.assertEqual((result["rsp_fault"], result["rsp_mask"], result["rsp_mat"], result["rsp_vec"]),
                                                 (0, mask, packed(matrix, SW), packed(vector, SW)))
            for change in ({"req_key": 92}, {"req_vec_generation": 3}):
                req = request(2, 0, rows, cols)
                req.update(change)
                self.assertNotEqual(replay.transact(req)["rsp_fault"], 0)
            for reset in ("cancel", "rst"):
                replay.send(**request(2, 0, rows, cols), req_valid=1)
                replay.send(mat_req_en=1, vec_req_en=1)
                replay.send(**{reset: 1})
                self.assertNotEqual(replay.transact(request(2, 0, rows, cols))["rsp_fault"], 0)
                replay.load(rows, cols)
        replay.run(self)
