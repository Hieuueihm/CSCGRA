#!/usr/bin/env python3
"""Generate deterministic bit-exact vectors for the M6 homogeneous PE."""
from __future__ import annotations

from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.v3.context_isa import TileOperation
from compiler.v3.architecture_scaling import LOCAL_ACC_W
from models.v3.hardware import Arithmetic, Events, NumericProfile

OUTPUT = ROOT / "verification" / "v3" / "m6" / "generated" / "m6_golden.vh"


def bits(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def pack(values: list[int], width: int) -> int:
    packed = 0
    for index, value in enumerate(values):
        packed |= bits(value, width) << (index * width)
    return packed


def main() -> None:
    arithmetic = Arithmetic(NumericProfile(), Events())
    data_min = -(1 << 26)
    data_max = (1 << 26) - 1
    acc_max = (1 << (LOCAL_ACC_W - 1)) - 1
    cases = [
        ("NOP", 0, 0, 5, 1, 1, 0),
        ("PASS", -7, 0, 0, 1, 1, 0),
        ("ADD", data_max, 1, 0, 1, 1, 0),
        ("SUB", data_min, 1, 0, 1, 1, 0),
        ("ABS", data_min, 0, 0, 1, 1, 0),
        ("MIN", -3, 2, 0, 1, 1, 0),
        ("MAX", -3, 2, 0, 1, 1, 0),
        ("COMPARE_EQ", 9, 9, 0, 1, 1, 0),
        ("COMPARE_LT", -1, 2, 0, 1, 1, 0),
        ("COMPARE_LE", 3, 2, 0, 1, 1, 0),
        ("SELECT", 11, 22, 0, 1, 1, 0),
        ("SELECT", 11, 22, 0, 0, 1, 0),
        ("SHIFT", 3, 2, 0, 1, 1, 0),
        ("SHIFT", data_max, 1, 0, 1, 1, 0),
        ("SHIFT", -32, -2, 0, 1, 1, 0),
        ("BIT_AND", 0x15555, 0x0F0F0, 0, 1, 1, 0),
        ("BIT_OR", 0x15555, 0x0F0F0, 0, 1, 1, 0),
        ("BIT_XOR", 0x15555, 0x0F0F0, 0, 1, 1, 0),
        ("PHI_ACCUMULATE", 100, 0, 200, 1, 0, 0),
        ("PHI_ACCUMULATE", 100, 0, 200, 1, 1, 0),
        ("PHI_ACCUMULATE", 100, 0, 200, 1, 1, 1),
        ("PHI_ACCUMULATE", data_min, 0, 0, 1, 1, 1),
        ("PHI_ACCUMULATE", 1, 0, acc_max, 1, 1, 0),
        ("ACCUMULATOR_READ", 0, 0, 1 << 30, 1, 1, 0),
        ("SATURATING_ADD", 100, 200, 0, 1, 1, 0),
        ("SATURATING_ADD", acc_max, 1, 0, 1, 1, 0),
        ("SATURATING_SUB", 20, 30, 0, 1, 1, 0),
        ("SATURATING_SUB", -(1 << (LOCAL_ACC_W - 1)), 1, 0, 1, 1, 0),
        ("PHI_SIGN_SCALE", 123, 0, 0, 1, 0, 0),
        ("PHI_SIGN_SCALE", 123, 0, 0, 1, 1, 0),
        ("PHI_SIGN_SCALE", 123, 0, 0, 1, 1, 1),
        ("PHI_SIGN_SCALE", data_min, 0, 0, 1, 1, 1),
        ("ACCUMULATOR_CLEAR", 0, 0, 999, 1, 1, 0),
    ]
    rng = random.Random(0xC6A048)
    acc_min = -(1 << (LOCAL_ACC_W - 1))
    for _ in range(64):
        cases.append(("SATURATING_ADD",
                      rng.randint(acc_min, acc_max),
                      rng.randint(acc_min, acc_max), 0, 1, 1, 0))
        cases.append(("SATURATING_SUB",
                      rng.randint(acc_min, acc_max),
                      rng.randint(acc_min, acc_max), 0, 1, 1, 0))
        cases.append(("PHI_ACCUMULATE",
                      rng.randint(data_min, data_max), 0,
                      rng.randint(acc_min, acc_max), 1,
                      rng.randint(0, 1), rng.randint(0, 1)))

    operations: list[int] = []
    operand_a: list[int] = []
    operand_b: list[int] = []
    accumulators: list[int] = []
    predicates: list[int] = []
    nonzero: list[int] = []
    signs: list[int] = []
    results: list[int] = []
    accumulator_next: list[int] = []
    accumulator_write: list[int] = []
    comparisons: list[int] = []
    saturated: list[int] = []
    for name, a, b, acc, pred, nz, sign in cases:
        result = arithmetic.pe_execute(
            name, a, b, acc, selected_predicate=bool(pred),
            phi_nonzero=bool(nz), phi_sign=bool(sign))
        operations.append(int(TileOperation[name]))
        operand_a.append(a)
        operand_b.append(b)
        accumulators.append(acc)
        predicates.append(pred)
        nonzero.append(nz)
        signs.append(sign)
        results.append(result[0])
        accumulator_next.append(result[1])
        accumulator_write.append(int(result[2]))
        comparisons.append(int(result[3]))
        saturated.append(int(result[4]))

    count = len(cases)
    lines = [
        "`ifndef M6_GOLDEN_VH",
        "`define M6_GOLDEN_VH",
        "// Generated from models/v3/hardware.py. Do not edit.",
        f"`define M6_CASE_COUNT {count}",
        f"`define M6_CASE_OPERATIONS {count*5}'h{pack(operations, 5):x}",
        f"`define M6_CASE_OPERAND_A {count*LOCAL_ACC_W}'h{pack(operand_a, LOCAL_ACC_W):x}",
        f"`define M6_CASE_OPERAND_B {count*LOCAL_ACC_W}'h{pack(operand_b, LOCAL_ACC_W):x}",
        f"`define M6_CASE_ACCUMULATOR {count*LOCAL_ACC_W}'h{pack(accumulators, LOCAL_ACC_W):x}",
        f"`define M6_CASE_PREDICATE {count}'h{pack(predicates, 1):x}",
        f"`define M6_CASE_PHI_NONZERO {count}'h{pack(nonzero, 1):x}",
        f"`define M6_CASE_PHI_SIGN {count}'h{pack(signs, 1):x}",
        f"`define M6_CASE_RESULT {count*27}'h{pack(results, 27):x}",
        f"`define M6_CASE_ACCUMULATOR_NEXT {count*LOCAL_ACC_W}'h{pack(accumulator_next, LOCAL_ACC_W):x}",
        f"`define M6_CASE_ACCUMULATOR_WRITE {count}'h{pack(accumulator_write, 1):x}",
        f"`define M6_CASE_COMPARISON {count}'h{pack(comparisons, 1):x}",
        f"`define M6_CASE_SATURATED {count}'h{pack(saturated, 1):x}",
        "`endif",
        "",
    ]
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"generated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
