"""Generate the V4 resident-memory geometry and local protocol faults."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def render():
    abi = json.loads((ROOT / "config/v4_memory_exec.json").read_text())
    design = json.loads((ROOT / "config/v4_design.json").read_text())
    limits = design["limits"]
    memory = next(value for value in design.values() if isinstance(value, dict) and "vector_planes" in value)
    if (memory["vector_planes"], memory["vector_banks_per_plane"], memory["vector_elements_per_plane"]) != (3, 32, 4096):
        raise ValueError("review resident vector contract before geometry changes")
    values = dict(PLANES=3, BANKS=32, V_DEPTH=128, V_AW=7, V_LEN=4096,
                  B_ROWS=limits["m"], B_COLS=limits["working_support"],
                  B_DEPTH=limits["m"]*((limits["working_support"]+31)//32), B_AW=9)
    values.update({"FAULT_"+name: value for name, value in abi["faults"].items()})
    return "\n".join(["`ifndef CSR_MEMORY_DEFS_VH", "`define CSR_MEMORY_DEFS_VH",
                        '`include "pe_interface.vh"',
                        *[f"`define CSR_MEM_{name} {value}" for name, value in values.items()], "`endif", ""])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "rtl/v4/include/memory_defs.vh"
    expected = render()
    if args.check:
        if not path.exists() or path.read_text() != expected:
            raise SystemExit("memory_defs.vh is missing/stale")
    else:
        path.write_text(expected)

if __name__ == "__main__":
    main()
