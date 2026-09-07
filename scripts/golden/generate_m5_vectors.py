#!/usr/bin/env python3
"""Generate deterministic SystemVerilog vectors for the M5 arithmetic leaves."""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models.v3.hardware import Arithmetic, Events, NumericProfile

OUTPUT = ROOT / "verification" / "v3" / "m5" / "generated" / "m5_golden.vh"


def bits(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def pack(values: list[int], width: int) -> int:
    result = 0
    for lane, value in enumerate(values):
        result |= bits(value, width) << (lane * width)
    return result


def solver_div(num: int, den: int, arithmetic: Arithmetic) -> tuple[int, int, int]:
    if den == 0:
        return 0, 1, 0
    raw = arithmetic.round_div(abs(num) << arithmetic.p.solver_f, abs(den))
    if (num < 0) ^ (den < 0):
        raw = -raw
    before = arithmetic.events.solver_saturation
    result = arithmetic.solver(raw)
    return result, 0, int(arithmetic.events.solver_saturation != before)


def main() -> None:
    arithmetic = Arithmetic(NumericProfile(), Events())
    div_cases = [
        (3, 2),
        (-3, 2),
        (1, 3),
        ((1 << 61) - 1, 1),
        (-(1 << 61), 1),
        (7, 0),
    ]

    vector_a = [
        0, 1, -1, 1 << 18, -(1 << 18), 1 << 19, -(1 << 19),
        3 << 18, -(3 << 18), 12345, -23456, (1 << 26) - 1,
        -(1 << 26), (1 << 25), -(1 << 25), 777777,
    ]
    vector_b = [
        1 << 19, -(1 << 19), 3 << 18, -(3 << 18), 1, -1, 123,
        -456, 789, -1011, 1 << 18, (1 << 26) - 1,
        -(1 << 26), 1 << 20, -(1 << 20), -333333,
    ]
    scalar = 3 << 17  # 0.75 in S27F19.
    scale = []
    scale_sat = 0
    for lane, value in enumerate(vector_a):
        before = arithmetic.events.solver_saturation
        scale.append(arithmetic.solver_mul(value, scalar))
        if arithmetic.events.solver_saturation != before:
            scale_sat |= 1 << lane
    axpy = []
    axpy_sat = 0
    for lane, (a, b) in enumerate(zip(vector_a, vector_b)):
        before = arithmetic.events.solver_saturation
        axpy.append(arithmetic.solver(a + arithmetic.solver_mul(b, scalar)))
        if arithmetic.events.solver_saturation != before:
            axpy_sat |= 1 << lane
    dot = sum(a * b for a, b in zip(vector_a, vector_b))
    norm = sum(a * a for a in vector_a)
    dot_over_norm, _, dot_over_norm_sat = solver_div(dot, norm, arithmetic)
    norm_over_dot, _, norm_over_dot_sat = solver_div(norm, dot, arithmetic)

    lines = [
        "`ifndef M5_GOLDEN_VH",
        "`define M5_GOLDEN_VH",
        "// Generated from models/v3/hardware.py. Do not edit.",
        f"`define M5_VECTOR_A 432'h{pack(vector_a, 27):0108x}",
        f"`define M5_VECTOR_B 432'h{pack(vector_b, 27):0108x}",
        f"`define M5_VECTOR_SCALE 432'h{pack(scale, 27):0108x}",
        f"`define M5_VECTOR_AXPY 432'h{pack(axpy, 27):0108x}",
        f"`define M5_VECTOR_SCALE_SAT 16'h{scale_sat:04x}",
        f"`define M5_VECTOR_AXPY_SAT 16'h{axpy_sat:04x}",
        f"`define M5_VECTOR_SCALAR 27'h{bits(scalar, 27):07x}",
        f"`define M5_VECTOR_DOT 62'h{bits(dot, 62):016x}",
        f"`define M5_VECTOR_NORM 62'h{bits(norm, 62):016x}",
        f"`define M5_DOT_OVER_NORM 27'h{bits(dot_over_norm, 27):07x}",
        f"`define M5_DOT_OVER_NORM_SAT 1'b{dot_over_norm_sat}",
        f"`define M5_NORM_OVER_DOT 27'h{bits(norm_over_dot, 27):07x}",
        f"`define M5_NORM_OVER_DOT_SAT 1'b{norm_over_dot_sat}",
        "`define M5_DIV_CASE_COUNT 6",
    ]
    for index, (num, den) in enumerate(div_cases):
        result, div_zero, saturated = solver_div(num, den, arithmetic)
        lines.extend([
            f"`define M5_DIV_NUM_{index} 62'h{bits(num, 62):016x}",
            f"`define M5_DIV_DEN_{index} 62'h{bits(den, 62):016x}",
            f"`define M5_DIV_RESULT_{index} 27'h{bits(result, 27):07x}",
            f"`define M5_DIV_ZERO_{index} 1'b{div_zero}",
            f"`define M5_DIV_SAT_{index} 1'b{saturated}",
        ])
    lines.extend(["`endif", ""])
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
