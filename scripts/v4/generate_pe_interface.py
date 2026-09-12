"""Generate the decoded PE primitive ABI; do not alter the context image ISA."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from compiler.v4.context_image import ROUTES


def render() -> str:
    abi = json.loads((ROOT / "config/v4_pe_interface.json").read_text(encoding="utf-8"))
    tags = json.loads((ROOT / "config/v4_phi_interface.json").read_text(encoding="utf-8"))
    design = json.loads((ROOT / "config/v4_design.json").read_text(encoding="utf-8"))
    if (abi["state_width"], abi["coeff_width"], abi["split_bits"], abi["acc_width"]) != (27, 18, 17, 64):
        raise ValueError("review the split multiplier and local ABI before changing widths")
    if not (0 < abi["state_frac"] < abi["state_width"] and 0 < abi["coeff_frac"] < abi["coeff_width"]):
        raise ValueError("this primitive contract requires positive fractional shifts with signed headroom")
    if (design["array"]["rows"], design["array"]["columns"], design["array"]["clusters"]) != (4, 4, 2):
        raise ValueError("router contract requires two independent 4x4 arrays")
    values = {"S_W": abi["state_width"], "S_F": abi["state_frac"],
              "C_W": abi["coeff_width"], "C_F": abi["coeff_frac"],
              "ACC_W": abi["acc_width"], "SPLIT": abi["split_bits"],
              "OP_W": abi["opcode_width"], "FAULT_W": abi["fault_width"],
              "JOB_W": tags["job_tag_bits"], "TAG_W": tags["op_tag_bits"],
              "FMT_W": tags["format_tag_bits"], "ROUTE_W": 3,
              "ROWS": design["array"]["rows"], "COLS": design["array"]["columns"],
              "TILES": design["array"]["full_processing_elements"]}
    for prefix, table in (("OP", abi["ops"]), ("FAULT", abi["faults"]),
                          ("ROUTE", ROUTES), ("ROUTE_FAULT", abi["route_faults"])):
        values.update({prefix + "_" + name: number for name, number in table.items()})
    lines = ["`ifndef CSR_PE_INTERFACE_VH", "`define CSR_PE_INTERFACE_VH"]
    lines.extend(f"`define CSR_PE_{name} {value}" for name, value in values.items())
    return "\n".join([*lines, "`endif", ""])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "rtl/v4/include/pe_interface.vh"
    expected = render()
    if args.check:
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            raise SystemExit("pe_interface.vh is missing/stale; regenerate before testing")
        print("PE interface definitions match local contracts")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8")
        print(path)


if __name__ == "__main__":
    main()
