"""Integer transaction and cycle oracle for the local Phi RTL contract."""

from __future__ import annotations

from functools import lru_cache
import json
from pathlib import Path

from models.v4.lfsr_operator import indexed_sign

ROOT = Path(__file__).resolve().parents[2]
ABI = json.loads((ROOT / "config/v4_phi_interface.json").read_text(encoding="utf-8"))
LIMITS = json.loads((ROOT / "config/v4_design.json").read_text(encoding="utf-8"))["limits"]
WORD = ABI["word_bits"]
BANKS = ABI["banks"]
DEPTH = ((LIMITS["n"] + BANKS - 1) // BANKS) * ((LIMITS["m"] + WORD - 1) // WORD)
ADDR_W = (DEPTH - 1).bit_length()
FAULT = ABI["fault_codes"]
TAGS = ("job_tag", "op_tag", "format_tag", "generation")


def valid_shape(rows: int, cols: int) -> bool:
    return 1 <= rows <= LIMITS["m"] and 1 <= cols <= LIMITS["n"]


def lane_mask(rows: int, block: int) -> int:
    return (1 << min(WORD, rows - block * WORD)) - 1


@lru_cache(maxsize=65536)
def sign_word(seed: int, rows: int, col: int, block: int) -> int:
    return sum(
        (indexed_sign(seed, rows, row, col) > 0) << lane
        for lane, row in enumerate(range(block * WORD, min(rows, (block + 1) * WORD)))
    )


class PhiCycleModel:
    def __init__(self) -> None:
        self.gen: dict = {"busy": 0, "done": 0, "fault": 0, "pos": 0}
        self.cache: dict = {"filling": 0, "valid": 0, "published": 0, "fault": 0, "rsp": None}
        self.ram: dict[tuple[int, int], int] = {}

    def outputs(self, pins: dict[str, int]) -> dict[str, int]:
        gen = self.gen
        cache = self.cache
        gen_active = not (pins["rst"] or pins["g_cancel"])
        cache_active = not (pins["rst"] or pins["c_invalidate"])
        result = {
            "g_start_ready": int(gen_active and not gen["busy"]),
            "g_busy": gen["busy"], "g_done": gen["done"], "g_fault_code": gen["fault"],
            "g_out_valid": int(gen_active and gen["busy"]),
            "c_begin_ready": int(cache_active and not cache["filling"] and cache["rsp"] is None),
            "c_filling": cache["filling"], "c_fill_ready": int(cache_active and cache["filling"]),
            "c_cache_valid": cache["valid"], "c_published": cache["published"],
            "c_fault_code": cache["fault"], "c_rsp_valid": int(cache_active and cache["rsp"] is not None),
            "c_rd_ready": int(cache_active and cache["valid"] and not cache["filling"]
                              and (cache["rsp"] is None or pins["c_rsp_ready"]) and not pins["c_begin_valid"]),
        }
        if gen["busy"]:
            col, block = divmod(gen["pos"], gen["blocks"])
            result.update({
                "g_out_signs": sign_word(gen["seed"], gen["rows"], col, block),
                "g_out_mask": lane_mask(gen["rows"], block),
                "g_out_column": col, "g_out_row_block": block,
                "g_out_last": int(gen["pos"] == gen["cols"] * gen["blocks"] - 1),
            })
            result.update({"g_out_" + tag: gen[tag] for tag in TAGS})
        if cache["valid"]:
            result["c_cache_key"] = cache["key"]
            result["c_cache_generation"] = cache["generation"]
        if cache["rsp"] is not None:
            result.update({"c_rsp_" + name: value for name, value in cache["rsp"].items()})
        return result

    def tick(self, pins: dict[str, int]) -> None:
        before = self.outputs(pins)
        effective = pins.copy()
        if pins["link"]:
            effective["g_out_ready"] = before["c_fill_ready"] and pins["link_gate"]
            effective["c_fill_valid"] = before["g_out_valid"] and pins["link_gate"]
            for field in ("signs", "mask", "column", "row_block", *TAGS, "last"):
                effective["c_fill_" + field] = before.get("g_out_" + field, 0)
        self._tick_gen(effective, before)
        self._tick_cache(effective, before)

    def _tick_gen(self, pins: dict[str, int], before: dict[str, int]) -> None:
        gen = self.gen
        if pins["rst"] or pins["g_cancel"]:
            self.gen = {"busy": 0, "done": 0, "fault": 0, "pos": 0}
            return
        gen["done"] = 0
        if pins["g_start_valid"] and before["g_start_ready"]:
            rows, cols = pins["g_start_rows"], pins["g_start_columns"]
            valid = (valid_shape(rows, cols) and pins["g_start_family"] == ABI["family"]
                     and pins["g_start_revision"] == ABI["generator_revision"])
            gen["fault"] = FAULT["NONE"] if valid else FAULT["DESCRIPTOR"]
            if valid:
                gen.update(busy=1, rows=rows, cols=cols, blocks=(rows + WORD - 1) // WORD,
                           seed=pins["g_start_seed"], pos=0)
                gen.update({tag: pins["g_start_" + tag] for tag in TAGS})
        elif before["g_out_valid"] and pins["g_out_ready"]:
            if before["g_out_last"]:
                gen.update(busy=0, done=1)
            else:
                gen["pos"] += 1

    def _tick_cache(self, pins: dict[str, int], before: dict[str, int]) -> None:
        cache = self.cache
        if pins["rst"] or pins["c_invalidate"]:
            self.cache = {"filling": 0, "valid": 0, "published": 0, "fault": 0, "rsp": None}
            return
        cache["published"] = 0
        if cache["rsp"] is not None and pins["c_rsp_ready"]:
            cache["rsp"] = None
        if pins["c_begin_valid"] and before["c_begin_ready"]:
            rows, cols = pins["c_begin_rows"], pins["c_begin_columns"]
            cache["valid"] = 0
            cache["fault"] = FAULT["NONE"] if valid_shape(rows, cols) else FAULT["DESCRIPTOR"]
            if valid_shape(rows, cols):
                cache.update(filling=1, rows=rows, cols=cols, blocks=(rows + WORD - 1) // WORD,
                             pos=0, key=pins["c_begin_key"])
                cache.update({tag: pins["c_begin_" + tag] for tag in TAGS})
        elif pins["c_fill_valid"] and before["c_fill_ready"]:
            col, block = divmod(cache["pos"], cache["blocks"])
            mask = lane_mask(cache["rows"], block)
            last = cache["pos"] == cache["cols"] * cache["blocks"] - 1
            expected = {"column": col, "row_block": block, "mask": mask, "last": int(last)}
            expected.update({tag: cache[tag] for tag in TAGS})
            valid = (all(pins["c_fill_" + field] == value for field, value in expected.items())
                     and pins["c_fill_signs"] & ~mask == 0)
            if not valid:
                cache.update(fault=FAULT["FILL"], filling=0, valid=0)
            else:
                self.ram[col % BANKS, (col // BANKS) * cache["blocks"] + block] = pins["c_fill_signs"]
                if last:
                    cache.update(filling=0, valid=1, published=1)
                else:
                    cache["pos"] += 1
        elif pins["c_rd_valid"] and before["c_rd_ready"]:
            mask = pins["c_rd_bank_mask"]
            valid = mask != 0 and pins["c_rd_generation"] == cache["generation"]
            signs, masks = 0, 0
            for bank in range(BANKS):
                if mask & (1 << bank):
                    addr = (pins["c_rd_addresses"] >> (bank * ADDR_W)) & (DEPTH - 1)
                    group, block = divmod(addr, cache["blocks"])
                    if group * BANKS + bank >= cache["cols"]:
                        valid = False
                    else:
                        signs |= self.ram[bank, addr] << (bank * WORD)
                        masks |= lane_mask(cache["rows"], block) << (bank * WORD)
            cache["rsp"] = {
                "signs": signs if valid else 0, "masks": masks if valid else 0,
                "bank_mask": mask, "generation": pins["c_rd_generation"],
                "tag": pins["c_rd_tag"], "fault": FAULT["NONE"] if valid else FAULT["READ"],
            }
            if not valid:
                cache["fault"] = FAULT["READ"]
