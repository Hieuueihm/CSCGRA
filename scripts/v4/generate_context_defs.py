"""Generate packed tile decoder constants from the unchanged V4 compiler ABI."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from compiler.v4.context_image import FORMATS, OPCODES, OPERANDS, REVISION, ROUTES, TILE_FIELDS


def render() -> str:
    abi = json.loads((ROOT / "config/v4_context_exec.json").read_text(encoding="utf-8"))
    if REVISION != abi["packed_isa_revision"] or sum(width for _, width in TILE_FIELDS) != 64:
        raise ValueError("review execution contract before changing packed ISA")
    values = {"REVISION": REVISION, "WORD_W": 64}
    offset = 0
    for name, width in TILE_FIELDS:
        values[name.upper() + "_LSB"] = offset
        values[name.upper() + "_W"] = width
        offset += width
    for prefix, table in (("OP", OPCODES), ("SRC", OPERANDS), ("FMT", FORMATS), ("ROUTE", ROUTES), ("FAULT", abi["faults"])):
        values.update({prefix + "_" + name: number for name, number in table.items()})
    lines = ["`ifndef CSR_CONTEXT_DEFS_VH", "`define CSR_CONTEXT_DEFS_VH", '`include "tile_interface.vh"']
    lines.extend(f"`define CSR_CTX_{name} {value}" for name, value in values.items())
    return "\n".join([*lines, "`endif", ""])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "rtl/v4/include/context_defs.vh"
    content = render()
    if args.check:
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            raise SystemExit("context_defs.vh is missing/stale")
        print("Packed context definitions match V4 compiler ABI")
    else:
        path.parent.mkdir(exist_ok=True, parents=True)
        path.write_text(content, encoding="utf-8")
        print(path)


if __name__ == "__main__":
    main()
