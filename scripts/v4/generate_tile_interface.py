"""Generate the decoded tile interface without changing the V4 context packer."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from compiler.v4.context_image import OPERANDS


def render() -> str:
    abi = json.loads((ROOT / "config/v4_tile_interface.json").read_text(encoding="utf-8"))
    design = json.loads((ROOT / "config/v4_design.json").read_text(encoding="utf-8"))
    if abi["rf_words"] != design["array"]["local_registers_per_pe"] or abi["rf_words"] != 8:
        raise ValueError("decoded tile v1 requires RF8")
    if abi["predicate_bits"] != 3 or abi["predicate_bits"] < design["array"]["selection_predicate_bits_per_pe_min"]:
        raise ValueError("review predicate encoding before changing bank size")
    values = {"RF_WORDS": abi["rf_words"], "PRED_BITS": abi["predicate_bits"],
              "SRC_W": abi["source_bits"], "REG_W": abi["reg_bits"], "GUARD_W": abi["guard_bits"],
              "PDST_W": abi["pred_dst_bits"], "IMM_W": abi["immediate_bits"]}
    for prefix, table in (("SRC", OPERANDS), ("GUARD", abi["guards"]),
                          ("PSEL", abi["pred_sources"]), ("FAULT", abi["faults"])):
        values.update({prefix + "_" + name: value for name, value in table.items()})
    lines = ["`ifndef CSR_TILE_INTERFACE_VH", "`define CSR_TILE_INTERFACE_VH", '`include "pe_interface.vh"']
    lines.extend(f"`define CSR_TILE_{name} {value}" for name, value in values.items())
    return "\n".join([*lines, "`endif", ""])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "rtl/v4/include/tile_interface.vh"
    content = render()
    if args.check:
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            raise SystemExit("tile_interface.vh is missing or stale")
        print("Decoded tile interface matches V4 contracts")
    else:
        path.parent.mkdir(exist_ok=True, parents=True)
        path.write_text(content, encoding="utf-8")
        print(path)


if __name__ == "__main__":
    main()
