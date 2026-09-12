"""Integer execution/retirement oracle for the local PE arithmetic/router ABI."""

from __future__ import annotations

import json
from pathlib import Path

from compiler.v4.context_image import ROUTES
from models.v4.fixed import Arithmetic, Format, Profile

ROOT = Path(__file__).resolve().parents[2]
ABI = json.loads((ROOT / "config/v4_pe_interface.json").read_text(encoding="utf-8"))
OPS, FAULTS, ROUTE_FAULTS = ABI["ops"], ABI["faults"], ABI["route_faults"]
SW, CW, AW = ABI["state_width"], ABI["coeff_width"], ABI["acc_width"]
SF, CF = ABI["state_frac"], ABI["coeff_frac"]
SMASK, AMASK = (1 << SW) - 1, (1 << AW) - 1
S_FMT = Format(SW, SF)
PROFILE = Profile(Format(18, 14), Format(CW, CF), S_FMT, AW)
META = ("job", "tag", "fmt", "last", "lane")


def signed(raw: int, width: int) -> int:
    return raw - (1 << width) if raw & (1 << (width - 1)) else raw


def evaluate(req: dict[str, int], acc: int, mode: int) -> tuple[dict[str, int], bool, int]:
    arithmetic = Arithmetic(PROFILE)
    op = req["req_op"]
    enabled = req["req_lane"] and req["req_exec"]
    result = {"rsp_" + field: req["req_" + field] for field in META}
    result.update(rsp_exec=int(enabled), rsp_data=0, rsp_acc=acc & AMASK, rsp_cmp=0, rsp_fault=0)
    write = False
    latency = 1
    if not enabled:
        return result, write, latency
    arg_a, arg_b = signed(req["req_a"], SW), signed(req["req_b"], SW)
    is_mul = op in (OPS["MUL"], OPS["MAC"])
    if op not in OPS.values():
        result["rsp_fault"] = FAULTS["OP"]
    elif op in (OPS["MAC"], OPS["ACC_ADD"], OPS["ACC_READ"]) and req["req_mode"] != mode:
        result["rsp_fault"] = FAULTS["MODE"]
    elif is_mul and not req["req_mode"] and not -(1 << (CW-1)) <= arg_b < (1 << (CW-1)):
        result["rsp_fault"] = FAULTS["COEFF"]
    if result["rsp_fault"]:
        return result, write, latency
    if is_mul and req["req_mode"]:
        latency = ABI["schedule"]["alu_ss_multiply_latency"]
    data = 0
    candidate = acc
    shift = SF if req["req_mode"] else CF
    if op == OPS["MOV"]:
        data = arg_a
    elif op == OPS["ADD"]:
        data = int(arithmetic.add(arg_a, arg_b, S_FMT))
    elif op == OPS["SUB"]:
        data = int(arithmetic.sub(arg_a, arg_b, S_FMT))
    elif op == OPS["ABS"]:
        data = abs(arg_a)
    elif op in (OPS["CMP_S"], OPS["CMP_U"]):
        left, right = (arg_a, arg_b) if op == OPS["CMP_S"] else (req["req_a"], req["req_b"])
        data = int(left < right)
        result["rsp_cmp"] = int(left < right) | (int(left == right) << 1) | (int(left > right) << 2)
    elif op == OPS["SELECT"]:
        data = arg_a if req["req_sel"] else arg_b
    elif op == OPS["AND"]:
        data = arg_a & arg_b
    elif op == OPS["OR"]:
        data = arg_a | arg_b
    elif op == OPS["XOR"]:
        data = arg_a ^ arg_b
    elif op == OPS["NOT"]:
        data = ~arg_a
    elif op == OPS["MUL"]:
        data = int(arithmetic.clip(Arithmetic.round_shift(arg_a * arg_b, shift), S_FMT))
    elif op == OPS["MAC"]:
        candidate = acc + arg_a * arg_b
        write = True
    elif op == OPS["ACC_CLEAR"]:
        candidate, write = 0, True
    elif op == OPS["ACC_ADD"]:
        candidate, write = acc + signed(req["req_acc"], AW), True
    elif op == OPS["ACC_READ"]:
        data = int(arithmetic.clip(Arithmetic.round_shift(acc, shift), S_FMT))
    if write:
        minimum, maximum = -(1 << (AW-1)), (1 << (AW-1)) - 1
        if not minimum <= candidate <= maximum:
            result["rsp_fault"] = FAULTS["ACC"]
            candidate = max(minimum, min(maximum, candidate))
    if arithmetic.events["saturation"]:
        result["rsp_fault"] = FAULTS["SAT"]
    result.update(rsp_data=data & SMASK, rsp_acc=candidate & AMASK)
    return result, write, latency


class AluModel:
    def __init__(self) -> None:
        self.acc, self.mode = 0, 0
        self.response: dict[str, int] | None = None
        self.delayed: tuple | None = None
        self.write = False
        self.next_mode = 0

    def outputs(self, pins: dict[str, int]) -> dict[str, int]:
        active = not (pins["rst"] or pins["cancel"])
        values = {"req_ready": int(active and self.response is None and self.delayed is None),
                  "rsp_valid": int(active and self.response is not None),
                  "state_acc": self.acc & AMASK, "state_mode": self.mode}
        if self.response is not None:
            values.update(self.response)
        return values

    def tick(self, pins: dict[str, int]) -> None:
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__()
        elif self.response is not None:
            if pins["rsp_ready"]:
                if self.write and not self.response["rsp_fault"]:
                    self.acc = signed(self.response["rsp_acc"], AW)
                    self.mode = self.next_mode
                self.response = None
        elif self.delayed is not None:
            self.response, self.write, self.next_mode = self.delayed
            self.delayed = None
        elif pins["req_valid"] and before["req_ready"]:
            response, write, latency = evaluate(pins, self.acc, self.mode)
            if latency == 2:
                self.delayed = response, write, pins["req_mode"]
            else:
                self.response, self.write, self.next_mode = response, write, pins["req_mode"]


def edges(tile: int) -> int:
    row, col = divmod(tile % 16, 4)
    return int(row > 0) | (int(col < 3) << 1) | (int(row < 3) << 2) | (int(col > 0) << 3)


class RouterModel:
    def __init__(self, tile: int) -> None:
        self.tile = tile
        self.pending = 0
        self.response: dict[str, int] | None = None
        self.data = 0
        self.selectors = 0

    def outputs(self, pins: dict[str, int]) -> dict[str, int]:
        active = not (pins["rst"] or pins["cancel"])
        values = {"req_ready": int(active and self.response is None),
                  "out_valid": self.pending if active else 0,
                  "rsp_valid": int(active and self.response is not None and not self.pending)}
        if self.response is not None:
            values.update(self.response)
            values.update(out_data=self.data, out_sel=self.selectors)
            values.update({"out_" + field: self.response["rsp_" + field] for field in ("job", "tag", "fmt", "last")})
        return values

    def tick(self, pins: dict[str, int]) -> None:
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__(self.tile)
            return
        if self.response is not None:
            if self.pending:
                self.pending &= ~pins["out_ready"]
            elif pins["rsp_ready"]:
                self.response = None
            return
        if not (pins["req_valid"] and before["req_ready"]):
            return
        enabled = pins["req_lane"] and pins["req_exec"]
        response = {"rsp_" + field: pins["req_" + field] for field in META}
        response.update(rsp_exec=int(enabled), rsp_fault=0)
        selectors = [(pins["req_routes"] >> (direction * 3)) & 7 for direction in range(4)]
        selected = sum(1 << direction for direction, sel in enumerate(selectors) if sel)
        self.data, self.selectors, self.pending = 0, 0, 0
        if enabled:
            if any(sel not in ROUTES.values() for sel in selectors):
                response["rsp_fault"] = ROUTE_FAULTS["SEL"]
            elif selected & ~edges(self.tile):
                response["rsp_fault"] = ROUTE_FAULTS["EDGE"]
            elif any(sel and not (pins["req_src"] & (1 << (sel - 1))) for sel in selectors):
                response["rsp_fault"] = ROUTE_FAULTS["SRC"]
            else:
                self.pending = selected
                sources = (0, pins["req_val"], pins["req_acc"], pins["req_res"])
                self.data = sum(sources[sel] << (direction * AW) for direction, sel in enumerate(selectors))
                self.selectors = pins["req_routes"]
        self.response = response
