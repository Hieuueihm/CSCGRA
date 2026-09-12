"""Integer control256 decoder and loader/store/sequencer cycle oracle."""

import json
from pathlib import Path

from compiler.v4.context_image import CONTROL_KINDS, CONTROL_FIELDS, REVISION, unpack_control, ImageValidationError

ROOT = Path(__file__).resolve().parents[2]
ABI = json.loads((ROOT / "config/v4_control_exec.json").read_text())
FAULT = ABI["faults"]

def decode(raw, rev=REVISION):
    fields = {}
    offset = 0
    for name, width in CONTROL_FIELDS:
        fields[name] = raw >> offset & ((1 << width)-1)
        offset += width
    if rev != REVISION:
        return fields, FAULT["REV"]
    try:
        unpack_control(raw.to_bytes(32, "little"))
    except (ImageValidationError, StopIteration, OverflowError):
        return fields, FAULT["WORD"]
    code = fields["kind"]
    permitted = {"kind", "reserved"}
    permitted |= {1: {"count", "loop_target"}, 2: {"loop_target"}, 3: {"branch_target", "predicate"},
                  4: {"predicate"}, 5: {"address_mode", "immediate_address", "stride"}}.get(code, set())
    if any(value and name not in permitted for name, value in fields.items()) or (code == 5 and not fields["address_mode"]):
        return fields, FAULT["EXEC"]
    return fields, 0

def predicate(code, values):
    if code in (0, 7):
        return code == 0
    return bool(values >> (code-1 if code <= 3 else code-4) & 1) != (code > 3)

class ControlModel:
    def __init__(self):
        self.loading = False
        self.image_ready = False
        self.generation = self.load_fault = self.next_pc = self.next_bank = 0
        self.memory = {}
        self.pending = False
        self.mem = dict(words=0, control=0, pc=0, generation=0, fault=0)
        self.state = "idle"
        self.pc = self.retired = self.done_fault = self.job = self.tag = self.fmt = 0
        self.run_generation = self.limit = self.words = self.control = self.next = 0
        self.stack = []
        self.push = self.end = self.halt = False

    def outputs(self, pins):
        active = not (pins["rst"] or pins["cancel"])
        idle = self.state == "idle"
        begin_ready = active and idle and not self.loading
        start_ready = active and idle and not pins["begin_valid"] and not self.loading
        start_take = pins["start_valid"] and start_ready
        invalid = not active or (pins["begin_valid"] and begin_ready)
        dec, _ = decode(self.control)
        badtag = (pins["exec_rsp_job"], pins["exec_rsp_tag"], pins["exec_rsp_fmt"]) != (self.job, self.tag, self.fmt)
        result = dict(begin_ready=int(begin_ready), wr_ready=int(active and idle and self.loading),
                      image_ready=int(self.image_ready), loading=int(self.loading), load_fault=self.load_fault,
                      start_ready=int(start_ready), addr_valid=int(active and self.state == "address"),
                      addr_mode=dec["address_mode"], addr_value=dec["immediate_address"], addr_stride=dec["stride"],
                      addr_rsp_ready=int(active and self.state == "addr_wait"), exec_valid=int(active and self.state == "issue"),
                      exec_words=self.words, exec_job=self.job, exec_tag=self.tag, exec_fmt=self.fmt, exec_last=int(self.halt),
                      exec_cancel=int(not active or start_take or (self.state == "done" and self.done_fault != 0)),
                      exec_rsp_ready=int(active and self.state == "retire" and not badtag and not pins["exec_rsp_fault"]),
                      done_valid=int(active and self.state == "done"), done_fault=self.done_fault, pc=self.pc, retired=self.retired,
                      state_depth=len(self.stack), state_remaining=sum(item[1] << (16*index) for index, item in enumerate(self.stack)),
                      state_fetch_valid=int(active and self.state == "fetch"),
                      state_mem_valid=int(not invalid and self.pending))
        return result

    def flow(self, pins):
        dec, fault = decode(self.control)
        kind = dec["kind"]
        successor, push = self.pc+1, False
        flow_fault = fault
        if kind == CONTROL_KINDS["HALT"]:
            successor = self.pc
            if self.stack:
                flow_fault = FAULT["LOOP"]
        if kind == CONTROL_KINDS["BRANCH"]:
            if self.stack:
                flow_fault = FAULT["LOOP"]
            if predicate(dec["predicate"], pins["predicates"]):
                successor = dec["branch_target"]
        if kind == CONTROL_KINDS["LOOP_BEGIN"]:
            if dec["loop_target"] != self.pc+1:
                flow_fault = FAULT["LOOP"]
            push = not self.stack or self.stack[-1][0] != self.pc
            if push and len(self.stack) == ABI["loop_depth"]:
                flow_fault = FAULT["LOOP"]
        if kind == CONTROL_KINDS["LOOP_END"]:
            if not self.stack or self.stack[-1][0] != dec["loop_target"]:
                flow_fault = FAULT["LOOP"]
            elif self.stack[-1][1] > 1:
                successor = dec["loop_target"]
        if successor > 255:
            flow_fault = FAULT["PC"]
        if self.retired >= self.limit:
            flow_fault = FAULT["EXEC"]
        if self.retired and not self.tag:
            flow_fault = FAULT["TAG"]
        return dec, fault or flow_fault, successor & 255, push

    def tick(self, pins):
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__()
            return
        old_image, old_generation = self.image_ready, self.generation
        old_mem, old_pending = self.mem.copy(), self.pending
        begin_take = pins["begin_valid"] and before["begin_ready"]
        write_take = pins["wr_valid"] and before["wr_ready"]
        last = self.next_pc == 255 and self.next_bank == 32
        write_good = (pins["wr_pc"], pins["wr_bank"], bool(pins["wr_last"])) == (self.next_pc, self.next_bank, last) and (pins["wr_bank"] == 32 or pins["wr_data"] >> 64 == 0)
        if begin_take:
            self.image_ready = False
            self.generation = pins["begin_generation"]
            self.next_pc = self.next_bank = 0
            self.loading = (pins["begin_rev"], pins["begin_depth"], pins["begin_verified"]) == (REVISION, 256, 1)
            self.load_fault = 0 if self.loading else FAULT["HEADER"]
        if write_take:
            if not write_good:
                self.loading = False
                self.load_fault = FAULT["STREAM"]
            else:
                self.memory[(pins["wr_pc"], pins["wr_bank"])] = pins["wr_data"]
                if last:
                    self.loading, self.image_ready = False, True
                elif self.next_bank == 32:
                    self.next_bank = 0
                    self.next_pc += 1
                else:
                    self.next_bank += 1
        if begin_take:
            self.pending = False
            self.mem = dict(words=0, control=0, pc=0, generation=0, fault=0)
        elif self.state == "fetch" and not old_pending:
            good = old_image and old_generation == self.run_generation
            self.pending = True
            self.mem = dict(words=sum(self.memory.get((self.pc, bank), 0) << (64*bank) for bank in range(32)) if good else 0,
                            control=self.memory.get((self.pc, 32), 0) if good else 0, pc=self.pc,
                            generation=self.run_generation, fault=0 if good else FAULT["FETCH"])
        elif self.state == "read" and old_pending:
            self.pending = False
        if self.state == "idle":
            if pins["start_valid"] and before["start_ready"]:
                self.pc, self.limit = pins["start_pc"], pins["start_limit"]
                self.run_generation, self.job, self.fmt = old_generation, pins["start_job"], pins["start_fmt"]
                self.tag = self.retired = 0
                self.stack = []
                self.done_fault = 0 if old_image and self.limit else FAULT["HEADER"]
                self.state = "fetch" if not self.done_fault else "done"
        elif self.state == "fetch":
            if not old_pending:
                self.state = "read"
        elif self.state == "read":
            if old_pending:
                if old_mem["fault"] or (old_mem["pc"], old_mem["generation"]) != (self.pc, self.run_generation):
                    self.done_fault, self.state = FAULT["FETCH"], "done"
                else:
                    self.words, self.control, self.state = old_mem["words"], old_mem["control"], "check"
        elif self.state == "check":
            dec, fault, successor, push = self.flow(pins)
            if fault:
                self.done_fault, self.state = fault, "done"
            else:
                self.next, self.push = successor, push
                self.end, self.halt = dec["kind"] == 2, dec["kind"] == 6
                self.state = {4: "wait_pred", 5: "address"}.get(dec["kind"], "issue")
        elif self.state == "wait_pred":
            if predicate(decode(self.control)[0]["predicate"], pins["predicates"]):
                self.state = "issue"
        elif self.state == "address":
            if pins["addr_ready"]:
                self.state = "addr_wait"
        elif self.state == "addr_wait":
            if pins["addr_rsp_valid"]:
                bad = (pins["addr_rsp_job"], pins["addr_rsp_tag"]) != (self.job, self.tag)
                if bad or pins["addr_rsp_fault"]:
                    self.done_fault, self.state = FAULT["TAG"] if bad else FAULT["BACKEND"], "done"
                else:
                    self.state = "issue"
        elif self.state == "issue":
            if pins["exec_ready"]:
                self.state = "retire"
        elif self.state == "retire":
            if pins["exec_rsp_valid"]:
                bad = (pins["exec_rsp_job"], pins["exec_rsp_tag"], pins["exec_rsp_fmt"]) != (self.job, self.tag, self.fmt)
                if bad or pins["exec_rsp_fault"]:
                    self.done_fault, self.state = FAULT["TAG"] if bad else FAULT["BACKEND"], "done"
                else:
                    self.retired += 1
                    self.tag = (self.tag+1) & 65535
                    if self.push:
                        self.stack.append([self.pc, decode(self.control)[0]["count"]])
                    if self.end:
                        if self.stack[-1][1] > 1:
                            self.stack[-1][1] -= 1
                        else:
                            self.stack.pop()
                    self.pc, self.state = self.next, "done" if self.halt else "fetch"
        elif self.state == "done" and pins["done_ready"]:
            self.state = "idle"
