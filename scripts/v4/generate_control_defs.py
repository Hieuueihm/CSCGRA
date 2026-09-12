"""Generate control256 execution definitions from the V4 compiler candidate."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from compiler.v4.context_image import CONTROL_FIELDS, CONTROL_KINDS, ADDRESS_MODES, REVISION, DEPTH, PE_SLOTS

def render() -> str:
    abi = json.loads((ROOT / "config/v4_control_exec.json").read_text())
    if sum(width for _, width in CONTROL_FIELDS) != 256 or (DEPTH, PE_SLOTS) != (256, 32):
        raise ValueError("review control execution before changing context geometry")
    values = dict(REV=REVISION, DEPTH=DEPTH, TILES=PE_SLOTS, LOOP_DEPTH=abi["loop_depth"])
    offset = 0
    for name, width in CONTROL_FIELDS:
        values[name.upper()+"_LSB"] = offset
        values[name.upper()+"_W"] = width
        offset += width
    for prefix, table in (("KIND", CONTROL_KINDS), ("ADDR", ADDRESS_MODES), ("FAULT", abi["faults"])):
        values.update({prefix+"_"+name: value for name, value in table.items()})
    return "\n".join(["`ifndef CSR_CONTROL_DEFS_VH", "`define CSR_CONTROL_DEFS_VH",
                        *[f"`define CSR_CTL_{name} {value}" for name, value in values.items()], "`endif", ""])

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "rtl/v4/include/control_defs.vh"
    expected = render()
    if args.check:
        if not path.exists() or path.read_text() != expected:
            raise SystemExit("control_defs.vh is missing/stale")
    else:
        path.write_text(expected)

if __name__ == "__main__":
    main()
