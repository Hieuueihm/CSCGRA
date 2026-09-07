#!/usr/bin/env python3
"""Generate deterministic SystemVerilog vectors for the M7 Phi path."""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3 import phi_generator

OUTPUT = ROOT / "verification" / "v3" / "m7" / "generated" / "m7_golden.vh"


def bits(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def main() -> None:
    phi_cases = (
        (0x0000000000000000, 0, 0, 128, 0x10),
        (0x0123456789ABCDEF, 3, 0, 70, 0x21),
        (0xDEADBEEF12345678, 17, 1, 128, 0x32),
        (0xCAFEBABE0BADF00D, 1023, 0, 33, 0x43),
        (0x0000000000000001, 11, 1, 96, 0x54),
        (0xFFFFFFFFFFFFFFFF, 511, 0, 64, 0x65),
    )
    normalizer_cases = (
        (1 << 19, 1 << 17, -3, 0, 0x11),
        (3, 1 << 17, -1, 1, 0x22),
        (-3, 1 << 17, -1, 0, 0x33),
        (1234567, 185364, -4, 1, 0x44),
        (-7654321, 185364, -4, 0, 0x55),
        (1 << 40, 1 << 17, 0, 1, 0x66),
        (-(1 << 40), 1 << 17, 0, 0, 0x77),
        (1, 1 << 17, -16, 1, 0x88),
    )

    lines = [
        "`ifndef M7_GOLDEN_VH",
        "`define M7_GOLDEN_VH",
        "// Generated from models/v3/phi_generator.py. Do not edit.",
        f"`define M7_PHI_CASE_COUNT {len(phi_cases)}",
    ]
    for index, (seed, column, row_pair, measurement_count, tag) in enumerate(phi_cases):
        word0 = phi_generator.phi_sign_word(seed, column, 2 * row_pair)
        word1 = phi_generator.phi_sign_word(seed, column, 2 * row_pair + 1)
        row_base0 = 64 * row_pair
        valid0 = max(0, min(32, measurement_count - row_base0))
        valid1 = max(0, min(32, measurement_count - row_base0 - 32))
        mask0 = (1 << valid0) - 1 if valid0 else 0
        mask1 = (1 << valid1) - 1 if valid1 else 0
        lines.extend((
            f"`define M7_PHI_SEED_{index} 64'h{seed:016x}",
            f"`define M7_PHI_COLUMN_{index} 10'h{column:03x}",
            f"`define M7_PHI_ROW_PAIR_{index} 3'h{row_pair:x}",
            f"`define M7_PHI_MEASUREMENT_{index} 9'h{measurement_count:03x}",
            f"`define M7_PHI_TAG_{index} 8'h{tag:02x}",
            f"`define M7_PHI_WORD0_{index} 32'h{word0:08x}",
            f"`define M7_PHI_WORD1_{index} 32'h{word1:08x}",
            f"`define M7_PHI_MASK0_{index} 32'h{mask0:08x}",
            f"`define M7_PHI_MASK1_{index} 32'h{mask1:08x}",
        ))

    lines.append(f"`define M7_NORMALIZER_CASE_COUNT {len(normalizer_cases)}")
    for index, (value, mantissa, exponent, placement, tag) in enumerate(normalizer_cases):
        result, saturated = phi_generator.runtime_scale_s27(
            value, mantissa, exponent
        )
        lines.extend((
            f"`define M7_NORMALIZER_INPUT_{index} 62'h{bits(value, 62):016x}",
            f"`define M7_NORMALIZER_MANTISSA_{index} 18'h{mantissa:05x}",
            f"`define M7_NORMALIZER_EXPONENT_{index} 5'h{bits(exponent, 5):02x}",
            f"`define M7_NORMALIZER_PLACEMENT_{index} 1'b{placement}",
            f"`define M7_NORMALIZER_TAG_{index} 8'h{tag:02x}",
            f"`define M7_NORMALIZER_RESULT_{index} 27'h{bits(result, 27):07x}",
            f"`define M7_NORMALIZER_SATURATED_{index} 1'b{int(saturated)}",
        ))
    lines.extend(("`endif", ""))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
