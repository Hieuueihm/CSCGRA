"""Integer coordinate and cycle oracle for aligned operand bundles."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ABI = json.loads((ROOT / "config/v4_feeder_interface.json").read_text())
PE = json.loads((ROOT / "config/v4_pe_interface.json").read_text())
LIMITS = json.loads((ROOT / "config/v4_design.json").read_text())["limits"]
SW, CW = PE["state_width"], PE["coeff_width"]
FAULT = ABI["faults"]

def signed(value: int, width: int) -> int:
    return (value & ((1 << (width - 1)) - 1)) - (value & (1 << (width - 1)))

def evaluate(pins: dict) -> dict:
    mode = pins["req_mode"]
    dense, rfour = mode >= 2, mode in (1, 3)
    trans = bool(pins["req_trans"]) if dense else rfour
    rows, cols = pins["req_rows"], pins["req_cols"]
    out, red, step = (pins["req_" + name] for name in ("out", "red", "step"))
    outputs, reductions = (cols, rows) if trans else (rows, cols)
    scale = signed(pins["req_scale"], CW)
    fault = FAULT["NONE"]
    max_cols = LIMITS["working_support"] if dense else LIMITS["n"]
    if not (1 <= rows <= LIMITS["m"] and 1 <= cols <= max_cols):
        fault = FAULT["SHAPE"]
    elif (out >= outputs or red >= reductions or out % (8 if rfour else 32)
          or (rfour and red % 32) or (not rfour and step)
          or (not dense and bool(pins["req_trans"]) != rfour)):
        fault = FAULT["INDEX"]
    elif not dense and scale <= 0:
        fault = FAULT["SCALE"]
    result = {"rsp_" + name: pins["req_" + name] for name in ("job", "tag", "fmt", "last")}
    result.update(rsp_mat=0, rsp_vec=0, rsp_mask=0, rsp_fault=fault)
    missing = bool(pins["req_src_fault"])
    for output_lane in range(8 if rfour else 32):
        for reduction_lane in range(4 if rfour else 1):
            tile = output_lane * (4 if rfour else 1) + reduction_lane
            output = out + output_lane
            reduction = red + (8 * reduction_lane + step if rfour else 0)
            if output >= outputs or reduction >= reductions:
                continue
            row, col = (reduction, output) if trans else (output, reduction)
            if dense:
                bank = (row + col) % 32
                coeff = signed(pins["req_dense"] >> (CW * bank), CW)
                present = pins["req_dense_valid"] >> bank & 1
            else:
                bank, bit = col % 8, row % 32
                coeff = scale if pins["req_signs"] >> (32 * bank + bit) & 1 else -scale
                present = (pins["req_sign_valid"] >> bank & 1) and (pins["req_masks"] >> (32 * bank + bit) & 1)
            missing |= not present or not (pins["req_vec_valid"] >> reduction_lane & 1)
            vector = pins["req_vec"] >> (SW * reduction_lane) & ((1 << SW) - 1)
            result["rsp_mat"] |= (coeff & ((1 << SW) - 1)) << (SW * tile)
            result["rsp_vec"] |= vector << (SW * tile)
            result["rsp_mask"] |= 1 << tile
    if not fault and missing:
        result["rsp_fault"] = FAULT["SOURCE"]
    if result["rsp_fault"]:
        result.update(rsp_mat=0, rsp_vec=0, rsp_mask=0)
    return result

class FeederModel:
    def __init__(self):
        self.pending = False
        self.payload = dict.fromkeys(("rsp_mat", "rsp_vec", "rsp_mask", "rsp_fault", "rsp_job",
                                      "rsp_tag", "rsp_fmt", "rsp_last"), 0)

    def outputs(self, pins: dict) -> dict:
        active = not (pins["rst"] or pins["cancel"])
        return dict(self.payload, req_ready=int(active and not self.pending), rsp_valid=int(active and self.pending))

    def tick(self, pins: dict) -> None:
        if pins["rst"] or pins["cancel"]:
            self.__init__()
        elif self.pending:
            if pins["rsp_ready"]:
                self.pending = False
        elif pins["req_valid"]:
            self.payload = evaluate(pins)
            self.pending = True
