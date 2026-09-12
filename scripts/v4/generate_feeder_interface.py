"""Generate the aligned V4 operand feeder contract definitions."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def render() -> str:
    abi = json.loads((ROOT / "config/v4_feeder_interface.json").read_text())
    limits = json.loads((ROOT / "config/v4_design.json").read_text())["limits"]
    values = {"MAX_ROWS": limits["m"], "MAX_COLS": limits["n"], "MAX_SUPPORT": limits["working_support"]}
    for prefix, table in (("MODE", abi["modes"]), ("FAULT", abi["faults"])):
        values.update({prefix + "_" + name: value for name, value in table.items()})
    return "\n".join(["`ifndef CSR_FEEDER_INTERFACE_VH", "`define CSR_FEEDER_INTERFACE_VH",
                        *[f"`define CSR_FEED_{name} {value}" for name, value in values.items()], "`endif", ""])

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "rtl/v4/include/feeder_interface.vh"
    text = render()
    if args.check:
        if not path.exists() or path.read_text() != text:
            raise SystemExit("feeder_interface.vh is missing/stale")
    else:
        path.write_text(text)

if __name__ == "__main__":
    main()
