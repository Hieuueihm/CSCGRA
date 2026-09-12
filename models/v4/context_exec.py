"""Packed scalar tile execution oracle using the V4 compiler's unpack/validation."""

from __future__ import annotations

import json

from compiler.v4.context_image import ImageValidationError, OPERANDS, REVISION, ROUTES, TILE_FIELDS, unpack_tile
from models.v4.pe_exec import ROOT, OPS, AW, AMASK, edges
from models.v4.tile_exec import TileModel, PSEL

ABI = json.loads((ROOT / "config/v4_context_exec.json").read_text(encoding="utf-8"))
FAULTS = ABI["faults"]
FIELDS = {}
offset = 0
for name, width in TILE_FIELDS:
    FIELDS[name] = offset, width
    offset += width


def decode(word: int, revision: int, mode: int, tile_id: int, routing: bool = False) -> tuple[dict, int]:
    if revision != REVISION:
        return {}, FAULTS["REV"]
    try:
        tile = unpack_tile(word.to_bytes(8, "little"))
    except (ImageValidationError, StopIteration, OverflowError):
        return {}, FAULTS["WORD"]
    available = edges(tile_id)
    for kind, direction in ((tile.srcA_kind, tile.srcA_reg), (tile.srcB_kind, tile.srcB_reg)):
        if kind == "LINK" and not available & (1 << direction):
            return {}, FAULTS["EDGE"]
    routes = (tile.routeN, tile.routeE, tile.routeS, tile.routeW)
    if any(sel != "NONE" and not available & (1 << direction) for direction, sel in enumerate(routes)):
        return {}, FAULTS["EDGE"]
    if (not routing and any(sel != "NONE" for sel in routes)) or (tile.opcode != "ROUTE" and "VALUE" in routes):
        return {}, FAULTS["EXEC"]
    result = dict(op=OPS["HOLD"], a_kind=OPERANDS[tile.srcA_kind], b_kind=OPERANDS[tile.srcB_kind],
                  a_idx=tile.srcA_reg, b_idx=tile.srcB_reg, imm=tile.immediate,
                  guard=tile.predicate, sel=0, rf_we=tile.rf_write, dst=tile.dst_reg,
                  pred_we=0, pred_dst=0, pred_src=0, wide=0, wide_idx=tile.srcB_reg,
                  store=int(tile.opcode == "STORE"), halt=int(tile.opcode == "HALT"))
    fault = False
    code = tile.opcode
    if code == "NOP":
        result.update(guard=0, rf_we=0)
    elif code == "CLEAR":
        result["op"] = OPS["ACC_CLEAR"]
        fault = not tile.acc_write or tile.rf_write or tile.format not in ("FIXED", "NONE")
    elif code in ("READ", "MOV", "STORE"):
        result["op"] = OPS["MOV"]
        fault = bool(tile.acc_write)
    elif code in ("MAC", "MUL"):
        result["op"] = OPS[code]
        fault = tile.format != "FIXED" or tile.acc_write != int(code == "MAC")
        if not mode:
            result.update(a_kind=OPERANDS[tile.srcB_kind], b_kind=OPERANDS[tile.srcA_kind],
                          a_idx=tile.srcB_reg, b_idx=tile.srcA_reg)
    elif code in ("ADD", "SUB"):
        result["op"] = OPS[code]
        fault = tile.format not in ("SIGNED", "FIXED")
        if tile.acc_write:
            if (code, tile.srcA_kind, tile.srcB_kind, tile.format) == ("ADD", "ACC", "LINK", "FIXED"):
                result.update(op=OPS["ACC_ADD"], wide=1, a_kind=0, b_kind=0)
            else:
                fault = True
    elif code == "CMP":
        fault = bool(tile.acc_write) or tile.predicate > 2 or tile.format == "NONE"
        result.update(op=OPS["CMP_U"] if tile.format in ("UNSIGNED", "ADDRESS") else OPS["CMP_S"],
                      guard=0, pred_we=1, pred_dst=tile.predicate, pred_src=PSEL["LT"])
    elif code == "SELECT":
        result.update(op=OPS["SELECT"], guard=0, sel=tile.predicate)
        fault = bool(tile.acc_write)
    elif code == "ROUTE":
        fault = not routing or bool(tile.rf_write or tile.acc_write)
    elif code == "HALT":
        result.update(guard=0, rf_we=0)
        fault = bool(word >> 6)
    else:
        fault = True
    return (result, FAULTS["EXEC"]) if fault else (result, 0)


class ContextModel:
    def __init__(self, tile: int = 5):
        self.tile = TileModel(tile)
        self.saved: dict | None = None

    def outputs(self, pins: dict[str, int]) -> dict[str, int]:
        result = self.tile.outputs(pins)
        _, fault = decode(pins["req_word"], pins["req_rev"], pins["req_mode"], self.tile.tile)
        result["state_decode_fault"] = fault
        result["state_routes"] = (pins["req_word"] >> FIELDS["routeN"][0]) & 4095
        if self.tile.alu.response is not None and self.saved is not None:
            if self.saved["fault"]:
                result.update(rsp_fault=self.saved["fault"], rsp_lane=self.saved["lane"], rsp_exec=0)
            result["rsp_store"] = int(self.saved["store"] and result["rsp_exec"] and not result["rsp_fault"])
            result["rsp_halt"] = int(self.saved["halt"] and result["rsp_exec"] and not result["rsp_fault"])
        return result

    def tick(self, pins: dict[str, int]) -> None:
        before = self.outputs(pins)
        if pins["rst"] or pins["cancel"]:
            self.__init__(self.tile.tile)
            return
        decoded, fault = decode(pins["req_word"], pins["req_rev"], pins["req_mode"], self.tile.tile)
        if fault:
            decoded = dict(op=OPS["HOLD"], a_kind=0, b_kind=0, a_idx=0, b_idx=0,
                           imm=0, guard=0, sel=0, rf_we=0, dst=0, pred_we=0, pred_dst=0,
                           pred_src=0, wide=0, wide_idx=0, store=0, halt=0)
        req = pins.copy()
        req.update({"req_" + name: value for name, value in decoded.items() if name not in ("wide", "wide_idx", "store", "halt")})
        req["req_lane"] = pins["req_lane"] if not fault else 0
        req["req_wide"] = ((pins["req_wlinks"] >> (decoded["wide_idx"] * AW)) & AMASK) if decoded["wide"] else 0
        req["req_wide_valid"] = int(bool(decoded["wide"] and pins["req_link_valid"] & (1 << decoded["wide_idx"])))
        if pins["req_valid"] and before["req_ready"]:
            self.saved = dict(fault=fault, lane=pins["req_lane"], store=decoded["store"], halt=decoded["halt"])
        self.tile.tick(req)
