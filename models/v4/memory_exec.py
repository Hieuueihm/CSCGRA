"""Coordinate-based integer models for resident vector and diagonal B memories."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAULT = json.loads((ROOT / "config/v4_memory_exec.json").read_text())["faults"]
SW, CW = 27, 18

def field(raw, index, width):
    return raw >> (index*width) & ((1 << width)-1)

def packed(values, width):
    return sum((value & ((1 << width)-1)) << (index*width) for index, value in enumerate(values))

class VectorModel:
    def __init__(self):
        self.memory = [{}, {}, {}]
        self.desc = [None]*3
        self.valid = 0
        self.loading = False
        self.plane = self.block = self.fault = 0
        self.pending = [False]*2
        self.payload = [dict(data=0, mask=0, generation=0, job=0, tag=0, fmt=0, fault=0) for _ in range(2)]

    def outputs(self, pins):
        active = not (pins["rst"] or pins["cancel"])
        result = dict(begin_ready=int(active and not self.loading and not any(self.pending)),
                      fill_ready=int(active and self.loading), loading=int(self.loading), plane_valid=self.valid, load_fault=self.fault,
                      rd_ready=packed([active and not pins["begin_valid"] and not value for value in self.pending], 1),
                      rsp_valid=packed([active and value for value in self.pending], 1))
        for name, width in (("data", 32*SW), ("mask", 32), ("generation", 32), ("job", 16), ("tag", 16), ("fmt", 8), ("fault", 4)):
            result["rsp_"+name] = packed([payload[name] for payload in self.payload], width)
        return result

    def tick(self, pins):
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__()
            return
        for port in range(2):
            if before["rsp_valid"] >> port & pins["rsp_ready"] >> port & 1:
                self.pending[port] = False
            if before["rd_ready"] >> port & pins["rd_valid"] >> port & 1:
                plane = field(pins["rd_plane"], port, 2)
                payload = {name: field(pins["rd_"+name], port, width) for name, width in (("generation", 32), ("job", 16), ("tag", 16), ("fmt", 8))}
                mask = field(pins["rd_mask"], port, 32)
                fault, data = 0, [0]*32
                if plane > 2:
                    fault = FAULT["PLANE"]
                elif not self.valid >> plane & 1 or (payload["generation"], payload["job"], payload["fmt"]) != self.desc[plane][1:]:
                    fault = FAULT["KEY"]
                else:
                    for bank in range(32):
                        idx = field(pins["rd_addr"], port*32+bank, 7)*32+bank
                        if mask >> bank & 1:
                            if idx >= self.desc[plane][0]:
                                fault = FAULT["RANGE"]
                            else:
                                data[bank] = self.memory[plane][idx]
                payload.update(data=packed(data, SW) if not fault else 0, mask=mask if not fault else 0, fault=fault)
                self.payload[port] = payload
                self.pending[port] = True
        if pins["begin_valid"] and before["begin_ready"]:
            plane, length = pins["begin_plane"], pins["begin_length"]
            self.fault = 0
            if plane > 2:
                self.fault = FAULT["PLANE"]
            else:
                self.valid &= ~(1 << plane)
                if not 1 <= length <= 4096:
                    self.fault = FAULT["SHAPE"]
                else:
                    self.loading, self.plane, self.block = True, plane, 0
                    self.desc[plane] = (length, pins["begin_generation"], pins["begin_job"], pins["begin_fmt"])
        if pins["fill_valid"] and before["fill_ready"]:
            length = self.desc[self.plane][0]
            count = min(32, length-32*self.block)
            mask = (1 << count)-1
            last = 32*(self.block+1) >= length
            if (pins["fill_block"], pins["fill_mask"], bool(pins["fill_last"])) != (self.block, mask, last) or pins["fill_data"] >> (count*SW):
                self.loading, self.fault = False, FAULT["STREAM"]
            else:
                for lane in range(count):
                    self.memory[self.plane][self.block*32+lane] = field(pins["fill_data"], lane, SW)
                if last:
                    self.loading = False
                    self.valid |= 1 << self.plane
                else:
                    self.block += 1

class BModel:
    def __init__(self):
        self.memory = {}
        self.rows = self.cols = self.slot = self.block = self.fault = 0
        self.key = self.generation = self.job = self.fmt = 0
        self.loading = self.valid = self.pending = False
        self.payload = dict(data=0, mask=0, generation=0, job=0, tag=0, fmt=0, fault=0)

    def outputs(self, pins):
        active = not (pins["rst"] or pins["cancel"])
        result = {"rsp_"+name: value for name, value in self.payload.items()}
        result.update(begin_ready=int(active and not self.loading and not self.pending), fill_ready=int(active and self.loading),
                      loading=int(self.loading), cache_valid=int(self.valid), load_fault=self.fault,
                      rd_ready=int(active and not self.loading and not self.pending and not pins["begin_valid"]), rsp_valid=int(active and self.pending))
        return result

    def tick(self, pins):
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__()
            return
        if before["rsp_valid"] and pins["rsp_ready"]:
            self.pending = False
        if pins["rd_valid"] and before["rd_ready"]:
            payload = {name: pins["rd_"+name] for name in ("generation", "job", "tag", "fmt")}
            fault, data = 0, [0]*32
            if not self.valid or (pins["rd_key"], pins["rd_generation"], pins["rd_job"], pins["rd_fmt"]) != (self.key, self.generation, self.job, self.fmt):
                fault = FAULT["KEY"]
            else:
                groups = (self.cols+31)//32
                for bank in range(32):
                    if pins["rd_mask"] >> bank & 1:
                        address = field(pins["rd_addr"], bank, 9)
                        row, group = divmod(address, groups)
                        col = group*32 + (bank-row)%32
                        if row >= self.rows or col >= self.cols or address >= 384:
                            fault = FAULT["RANGE"]
                        else:
                            data[bank] = self.memory[row, col]
            payload.update(data=packed(data, CW) if not fault else 0, mask=pins["rd_mask"] if not fault else 0, fault=fault)
            self.payload, self.pending = payload, True
        if pins["begin_valid"] and before["begin_ready"]:
            self.valid = False
            self.fault = self.slot = self.block = 0
            if not 1 <= pins["begin_rows"] <= 128 or not 1 <= pins["begin_cols"] <= 96:
                self.fault = FAULT["SHAPE"]
            else:
                self.loading = True
                self.rows, self.cols = pins["begin_rows"], pins["begin_cols"]
                self.key, self.generation, self.job, self.fmt = (pins["begin_"+name] for name in ("key", "generation", "job", "fmt"))
        if pins["fill_valid"] and before["fill_ready"]:
            count = min(32, self.rows-self.block*32)
            block_last = (self.block+1)*32 >= self.rows
            last = block_last and self.slot+1 == self.cols
            if (pins["fill_slot"], pins["fill_block"], pins["fill_mask"], bool(pins["fill_last"])) != (self.slot, self.block, (1 << count)-1, last) or pins["fill_data"] >> (count*CW):
                self.loading, self.fault = False, FAULT["STREAM"]
            else:
                for lane in range(count):
                    self.memory[self.block*32+lane, self.slot] = field(pins["fill_data"], lane, CW)
                if last:
                    self.loading, self.valid = False, True
                elif block_last:
                    self.block = 0
                    self.slot += 1
                else:
                    self.block += 1
