"""Resident RAM and operand read-path RTL cycle replay."""

import json
import random
import unittest

from models.v4.memory_exec import ROOT, SW, CW, FAULT, VectorModel, BModel, packed, field
from scripts.v4.generate_memory_defs import render
from verification.v4.test_feeder_rtl import Replay

RUNS = []

class MemoryReplay(Replay):
    runs = RUNS

    def __init__(self, kind):
        self.io = json.loads((ROOT / f"verification/v4/memory/{kind}_io.json").read_text())
        self.top = "tb_vector_store" if kind == "vector" else "tb_support_matrix_cache"
        self.bench = f"verification/v4/memory/{self.top}.sv"
        self.model = VectorModel() if kind == "vector" else BModel()
        self.rows, self.expected = [], []
        self.pins = dict.fromkeys(self.io["inputs"], 0)
        self.step(dict(self.pins, rst=1))

    def send(self, **fields):
        self.step(dict(self.pins, **fields))

    def vector(self, plane, values, generation=1):
        self.send(begin_valid=1, begin_plane=plane, begin_length=len(values), begin_generation=generation, begin_job=7, begin_fmt=3)
        for block in range((len(values)+31)//32):
            chunk = values[block*32:(block+1)*32]
            self.send(fill_valid=1, fill_block=block, fill_mask=(1 << len(chunk))-1, fill_data=packed(chunk, SW), fill_last=int((block+1)*32 >= len(values)))

    def matrix(self, matrix, generation=1):
        rows, cols = len(matrix), len(matrix[0])
        self.send(begin_valid=1, begin_rows=rows, begin_cols=cols, begin_key=91, begin_generation=generation, begin_job=7, begin_fmt=3)
        for col in range(cols):
            for block in range((rows+31)//32):
                values = [matrix[row][col] for row in range(block*32, min(rows, (block+1)*32))]
                self.send(fill_valid=1, fill_slot=col, fill_block=block, fill_mask=(1 << len(values))-1,
                          fill_data=packed(values, CW), fill_last=int(col == cols-1 and (block+1)*32 >= rows))

class MemoryRtlTests(unittest.TestCase):
    def test_generated_geometry(self):
        self.assertEqual((ROOT / "rtl/v4/include/memory_defs.vh").read_text(), render())

    def test_three_planes_two_ports_tail_and_concurrent_destination(self):
        replay = MemoryReplay("vector")
        rng = random.Random(9421)
        values = [[rng.randrange(-(1 << 26), 1 << 26) for _ in range(length)] for length in (4096, 65, 33)]
        for plane in range(3):
            replay.vector(plane, values[plane])
        for port_planes in ((0, 1), (1, 0), (0, 0), (1, 2), (2, 2)):
            for block in (0, 1, 2, 127):
                req = dict(rd_valid=3, rd_plane=packed(port_planes, 2), rd_mask=(1 << 64)-1,
                           rd_addr=packed([block]*64, 7), rd_generation=packed([1, 1], 32),
                           rd_job=packed([7, 7], 16), rd_tag=packed([block, 100+block], 16), rd_fmt=packed([3, 3], 8))
                replay.send(**req)
                for _ in range(4):
                    replay.send(**dict(req, rd_addr=rng.getrandbits(448)))
                replay.send(rsp_ready=1)
                replay.send(rsp_ready=2)
        replay.send(begin_valid=1, begin_plane=2, begin_length=33, begin_generation=2, begin_job=7, begin_fmt=3)
        for block in (0, 1):
            count = 32 if block == 0 else 1
            replay.send(fill_valid=1, fill_block=block, fill_mask=(1 << count)-1, fill_data=packed([55]*count, SW), fill_last=block,
                        rd_valid=3, rd_plane=packed([0, 1], 2), rd_mask=packed([1, 1], 32), rd_addr=0,
                        rd_generation=packed([1, 1], 32), rd_job=packed([7, 7], 16), rd_fmt=packed([3, 3], 8), rsp_ready=3)
        replay.send(rsp_ready=3)
        for plane, gen, job, fmt in ((3, 1, 7, 3), (0, 2, 7, 3), (0, 1, 8, 3), (0, 1, 7, 4)):
            replay.send(rd_valid=1, rd_plane=plane, rd_mask=1, rd_generation=gen, rd_job=job, rd_fmt=fmt)
            self.assertNotEqual(replay.model.payload[0]["fault"], 0)
            replay.send(rsp_ready=1)
        replay.run(self)

    def test_vector_replacement_identity_and_begin_under_stall(self):
        replay = MemoryReplay("vector")
        replay.vector(0, [11]*33)
        read = dict(rd_valid=1, rd_plane=0, rd_mask=1, rd_generation=1, rd_job=7, rd_fmt=3)
        begin = dict(begin_valid=1, begin_plane=0, begin_length=33, begin_generation=2, begin_job=7, begin_fmt=3)
        replay.send(**read)
        for _ in range(3):
            replay.send(**begin)
            self.assertEqual(replay.model.valid, 1)
            self.assertFalse(replay.model.loading)
        replay.send(**begin, rsp_ready=1)
        self.assertFalse(replay.model.loading)
        replay.send(**begin)
        replay.send(**read, fill_valid=1, fill_block=0, fill_mask=(1 << 32)-1, fill_data=packed([22]*32, SW))
        self.assertEqual(replay.model.payload[0]["fault"], FAULT["KEY"])
        replay.send(fill_valid=1, fill_block=1, fill_mask=1, fill_data=22, fill_last=1, rsp_ready=1)
        replay.send(**read)
        self.assertEqual(replay.model.payload[0]["fault"], FAULT["KEY"])
        replay.send(rsp_ready=1)
        replay.send(**dict(read, rd_generation=2))
        self.assertEqual((replay.model.payload[0]["fault"], replay.model.payload[0]["data"]), (0, 22))
        replay.run(self)

    def test_B_diagonal_single_copy_all_coordinates(self):
        replay = MemoryReplay("b")
        rng = random.Random(9422)
        for rows, cols in ((1, 1), (33, 35), (128, 96)):
            matrix = [[rng.randrange(-(1 << 17), 1 << 17) for _ in range(cols)] for _ in range(rows)]
            replay.matrix(matrix)
            groups = (cols+31)//32
            for row in range(rows):
                for group in range(groups):
                    addresses, mask = [0]*32, 0
                    for col in range(group*32, min(cols, (group+1)*32)):
                        bank = (row+col)%32
                        addresses[bank] = row*groups+group
                        mask |= 1 << bank
                    replay.send(rd_valid=1, rd_mask=mask, rd_addr=packed(addresses, 9), rd_key=91, rd_generation=1, rd_job=7, rd_fmt=3, rd_tag=row)
                    self.assertEqual(replay.model.payload["fault"], 0)
                    for col in range(group*32, min(cols, (group+1)*32)):
                        self.assertEqual(field(replay.model.payload["data"], (row+col)%32, CW), matrix[row][col] & ((1 << CW)-1))
                    replay.send(rd_valid=1, rd_mask=0, rd_addr=rng.getrandbits(288))
                    replay.send(rsp_ready=1)
            for fields in ({"rd_key": 92}, {"rd_generation": 2}, {"rd_job": 8}, {"rd_fmt": 4}, {"rd_addr": packed([511]*32, 9)}):
                request = dict(rd_valid=1, rd_mask=1, rd_addr=0, rd_key=91, rd_generation=1, rd_job=7, rd_fmt=3)
                request.update(fields)
                replay.send(**request)
                self.assertNotEqual(replay.model.payload["fault"], 0)
                replay.send(rsp_ready=1)
        replay.run(self)

    def test_incomplete_load_fault_reset_cancel_and_publication(self):
        for kind in ("vector", "b"):
            replay = MemoryReplay(kind)
            if kind == "vector":
                begin = dict(begin_valid=1, begin_plane=0, begin_length=33, begin_generation=1, begin_job=7, begin_fmt=3)
                fill = dict(fill_valid=1, fill_block=0, fill_mask=(1 << 32)-1, fill_data=0, fill_last=0)
                invalid_shape = dict(begin, begin_length=0)
            else:
                begin = dict(begin_valid=1, begin_rows=33, begin_cols=1, begin_key=91, begin_generation=1, begin_job=7, begin_fmt=3)
                fill = dict(fill_valid=1, fill_slot=0, fill_block=0, fill_mask=(1 << 32)-1, fill_data=0, fill_last=0)
                invalid_shape = dict(begin, begin_rows=0)
            replay.send(**invalid_shape)
            self.assertEqual(replay.model.fault, FAULT["SHAPE"])
            for change in ({"fill_mask": 0}, {"fill_block": 1}, {"fill_last": 1}):
                replay.send(**begin)
                replay.send(**dict(fill, **change))
                self.assertEqual(replay.model.fault, FAULT["STREAM"])
            replay.send(**begin)
            replay.send(**fill)
            replay.send(**fill)
            self.assertEqual(replay.model.fault, FAULT["STREAM"])
            replay.send(**begin)
            replay.send(**fill)
            replay.send(**dict(fill, fill_block=1, fill_mask=1, fill_last=1, fill_data=1 << (SW if kind == "vector" else CW)))
            self.assertEqual(replay.model.fault, FAULT["STREAM"])
            for reset in ("rst", "cancel"):
                replay.send(**begin)
                replay.send(**fill)
                replay.send(**{reset: 1})
                replay.send(rd_valid=1)
                replay.send(rsp_ready=1)
            replay.run(self)
