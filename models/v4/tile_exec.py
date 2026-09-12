"""Transactional RF/predicate tile oracle built on the V4 integer arithmetic model."""

from __future__ import annotations

import json

from compiler.v4.context_image import OPERANDS
from models.v4.fixed import Arithmetic
from models.v4.pe_exec import ROOT, OPS, SW, SF, CF, AMASK, SMASK, AluModel, edges, signed

ABI = json.loads((ROOT / "config/v4_tile_interface.json").read_text(encoding="utf-8"))
FAULTS, PSEL = ABI["faults"], ABI["pred_sources"]
UNARY = {OPS[name] for name in ("MOV", "ABS", "NOT")}
BINARY = {OPS[name] for name in ("ADD", "SUB", "CMP_S", "CMP_U", "SELECT", "AND", "OR", "XOR", "MUL", "MAC")}


def guard(code: int, predicates: int) -> int:
    if code == 0:
        return 1
    if code == 7:
        return 0
    if code <= 3:
        return (predicates >> (code - 1)) & 1
    return 1 ^ ((predicates >> (code - 4)) & 1)


class TileModel:
    def __init__(self, tile: int = 0):
        self.tile = tile
        self.rf = [0] * ABI["rf_words"]
        self.valid = 0
        self.preds = 0
        self.alu = AluModel()
        self.saved: dict | None = None

    def operand(self, pins: dict[str, int], side: str) -> tuple[int, int]:
        kind, idx = pins[f"req_{side}_kind"], pins[f"req_{side}_idx"]
        if kind == OPERANDS["NONE"]:
            return 0, 0
        if kind == OPERANDS["RF"]:
            return (self.rf[idx], 0) if self.valid & (1 << idx) else (0, FAULTS["UNINIT"])
        if kind == OPERANDS["ACC"]:
            raw = int(Arithmetic.round_shift(self.alu.acc, SF if self.alu.mode else CF))
            return (raw & SMASK, 0) if -(1 << (SW-1)) <= raw < (1 << (SW-1)) else (0, FAULTS["ACC_RANGE"])
        if kind == OPERANDS["IMMEDIATE"]:
            return signed(pins["req_imm"], ABI["immediate_bits"]) & SMASK, 0
        if kind in (OPERANDS["MATRIX"], OPERANDS["VECTOR"]):
            name = "mat" if kind == OPERANDS["MATRIX"] else "vec"
            return (pins[f"req_{name}"], 0) if pins[f"req_{name}_valid"] else (0, FAULTS["SOURCE"])
        if kind == OPERANDS["LINK"]:
            if idx > 3 or not (edges(self.tile) & pins["req_link_valid"] & (1 << idx)):
                return 0, FAULTS["LINK"]
            return (pins["req_links"] >> (idx * SW)) & SMASK, 0
        if kind == OPERANDS["PREDICATE"]:
            return ((self.preds >> idx) & 1, 0) if idx < 3 else (0, FAULTS["PRED"])
        return 0, FAULTS["SOURCE"]

    def decode(self, pins: dict[str, int]) -> tuple[dict[str, int], int, int]:
        enabled = pins["req_lane"] and guard(pins["req_guard"], self.preds)
        op = pins["req_op"]
        fault, arg_a, arg_b = 0, 0, 0
        if enabled:
            if pins["req_pred_we"] and (pins["req_pred_dst"] >= 3 or pins["req_pred_src"] not in PSEL.values()):
                fault = FAULTS["PRED"]
            if not fault and op in UNARY | BINARY:
                arg_a, fault = self.operand(pins, "a")
            if not fault and op in BINARY:
                arg_b, fault = self.operand(pins, "b")
            if not fault and op == OPS["ACC_ADD"] and not pins["req_wide_valid"]:
                fault = FAULTS["SOURCE"]
        req = pins.copy()
        req.update(req_a=arg_a, req_b=arg_b, req_acc=pins["req_wide"],
                   req_sel=guard(pins["req_sel"], self.preds), req_exec=int(enabled and not fault))
        return req, fault, int(enabled)

    def outputs(self, pins: dict[str, int]) -> dict[str, int]:
        result = self.alu.outputs(pins)
        result.update(state_rf=sum(raw << (slot * SW) for slot, raw in enumerate(self.rf)),
                      state_valid=self.valid, state_preds=self.preds)
        if self.alu.response is not None and self.saved is not None and self.saved["fault"]:
            result.update(rsp_fault=self.saved["fault"], rsp_exec=self.saved["enabled"])
        return result

    def tick(self, pins: dict[str, int]) -> None:
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__(self.tile)
            return
        if before["rsp_valid"] and pins["rsp_ready"]:
            saved = self.saved
            if not before["rsp_fault"] and before["rsp_exec"]:
                if saved["rf_we"]:
                    self.rf[saved["dst"]] = before["rsp_data"]
                    self.valid |= 1 << saved["dst"]
                if saved["pred_we"]:
                    options = (before["rsp_data"] & 1, before["rsp_cmp"] & 1,
                               (before["rsp_cmp"] >> 1) & 1, (before["rsp_cmp"] >> 2) & 1,
                               1 ^ (before["rsp_data"] & 1), 0, 1)
                    mask = 1 << saved["pred_dst"]
                    self.preds = (self.preds & ~mask) | (options[saved["pred_src"]] << saved["pred_dst"])
        req, fault, enabled = self.decode(pins)
        if before["req_ready"] and pins["req_valid"]:
            self.saved = {name: pins["req_" + name] for name in ("rf_we", "dst", "pred_we", "pred_dst", "pred_src")}
            self.saved.update(fault=fault, enabled=enabled)
        self.alu.tick(req)
