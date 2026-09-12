"""Generate sign-only RTL definitions from the selected V4 contracts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def render() -> str:
    design = json.loads((ROOT / "config/v4_design.json").read_text(encoding="utf-8"))
    interface = json.loads((ROOT / "config/v4_phi_interface.json").read_text(encoding="utf-8"))
    limits = design["limits"]
    generator = design["architecture_decision"]["generator_selection"]
    if (interface["word_bits"], interface["banks"], limits["m"], limits["n"]) != (32, 8, 128, 1024):
        raise ValueError("changing capacity requires reviewing the local wire ABI")
    if generator["selected_family"] != "LFSR32_Galois_rightshift_v2":
        raise ValueError("this RTL implements only the selected LFSR32 family")
    word_bits = interface["word_bits"]
    banks = interface["banks"]
    blocks = (limits["m"] + word_bits - 1) // word_bits
    depth = ((limits["n"] + banks - 1) // banks) * blocks
    values = {
        "MAX_ROWS": limits["m"], "MAX_COLUMNS": limits["n"],
        "WORD_BITS": interface["word_bits"], "BANKS": interface["banks"],
        "BANK_DEPTH": depth, "ROWS_W": limits["m"].bit_length(),
        "COLUMNS_W": limits["n"].bit_length(),
        "COLUMN_W": (limits["n"] - 1).bit_length(),
        "ROW_BLOCK_W": max(1, (blocks - 1).bit_length()), "ADDR_W": (depth - 1).bit_length(),
        "FAMILY": interface["family"], "REVISION": interface["generator_revision"],
    }
    for name in ("job_tag", "op_tag", "format_tag", "generation", "key", "read_tag", "fault"):
        values[name.upper() + "_W"] = interface[name + "_bits"]
    values.update({"FAULT_" + name: value for name, value in interface["fault_codes"].items()})
    lines = ["`ifndef CSR_PHI_INTERFACE_VH", "`define CSR_PHI_INTERFACE_VH"]
    lines.extend(f"`define CSR_PHI_{name} {value}" for name, value in values.items())
    lines.extend([
        f"`define CSR_PHI_TAPS 32'h{generator['taps_hex'][2:]}",
        f"`define CSR_PHI_DEFAULT_SEED 32'h{generator['zero_seed_substitution_hex'][2:]}",
        "`endif", "",
    ])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = ROOT / "rtl/v4/include/phi_interface.vh"
    content = render()
    if args.check:
        if not output.exists() or output.read_text(encoding="utf-8") != content:
            raise SystemExit("phi_interface.vh is missing or stale; run generate_phi_interface.py")
        print("Phi interface definitions match selected contracts")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(content, encoding="utf-8")
        print(output)


if __name__ == "__main__":
    main()
