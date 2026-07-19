#!/usr/bin/env python3
"""Evaluate a fixed-point Newton-Raphson reciprocal on RTL divider samples."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SAMPLE_RE = re.compile(
    r"DIV_SAMPLE\s+kind=(?P<kind>\w+)\s+num=(?P<num>-?\d+)\s+den=(?P<den>-?\d+)"
)
FRAC = 62
ONE = 1 << FRAC


def round_shift_positive(value: int, shift: int) -> int:
    if shift <= 0:
        return value << -shift
    return (value + (1 << (shift - 1))) >> shift


def exact_signed_divide(num: int, den: int) -> int:
    """Match the RTL: absolute restoring divide, nearest/ties-up, then sign."""
    if den == 0:
        return 0
    negative = (num < 0) ^ (den < 0)
    anum, aden = abs(num), abs(den)
    quotient, remainder = divmod(anum, aden)
    if remainder * 2 >= aden:
        quotient += 1
    return -quotient if negative else quotient


def nr_signed_divide(num: int, den: int, iterations: int) -> int:
    """Q2.62 reciprocal with a linear seed and rounded NR products."""
    if den == 0:
        return 0
    negative = (num < 0) ^ (den < 0)
    anum, aden = abs(num), abs(den)
    exponent = aden.bit_length() - 1
    if exponent <= FRAC:
        normalized = aden << (FRAC - exponent)  # [1, 2) in Q2.62
    else:
        normalized = round_shift_positive(aden, exponent - FRAC)

    # For d in [1,2), x0 = 24/17 - (8/17)d approximates 1/d.
    seed_numerator = 24 * ONE - 8 * normalized
    reciprocal = (seed_numerator + 8) // 17
    for _ in range(iterations):
        d_times_x = round_shift_positive(normalized * reciprocal, FRAC)
        correction = 2 * ONE - d_times_x
        reciprocal = round_shift_positive(reciprocal * correction, FRAC)

    quotient_abs = round_shift_positive(
        anum * reciprocal, FRAC + exponent
    )
    return -quotient_abs if negative else quotient_abs


def load_samples(paths: list[Path]) -> list[tuple[str, int, int]]:
    samples: list[tuple[str, int, int]] = []
    for path in paths:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = SAMPLE_RE.search(line)
            if match:
                samples.append(
                    (
                        match.group("kind"),
                        int(match.group("num")),
                        int(match.group("den")),
                    )
                )
    return samples


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument(
        "--wide-mul-cycles",
        type=int,
        default=6,
        help="Measured controller cycles per shared four-row 64x64 multiply",
    )
    args = parser.parse_args()
    samples = load_samples(args.logs)
    if not samples:
        raise SystemExit("no DIV_SAMPLE records found")

    print(f"samples={len(samples)} unique={len(set(samples))}")
    for kind in sorted({sample[0] for sample in samples}):
        print(f"kind={kind} samples={sum(sample[0] == kind for sample in samples)}")
    kinds = sorted({sample[0] for sample in samples})
    for iterations in range(7):
        mismatch = 0
        max_abs_error = 0
        mismatch_by_kind = {kind: 0 for kind in kinds}
        for kind, num, den in samples:
            expected = exact_signed_divide(num, den)
            actual = nr_signed_divide(num, den, iterations)
            error = actual - expected
            mismatch += error != 0
            if error != 0:
                mismatch_by_kind[kind] += 1
            max_abs_error = max(max_abs_error, abs(error))
        multiplies = 2 * iterations + 1
        shared_cycles = multiplies * args.wide_mul_cycles
        print(
            f"iterations={iterations} multiplies={multiplies} "
            f"shared_mul_cycles>={shared_cycles} mismatches={mismatch} "
            f"max_abs_lsb_error={max_abs_error} "
            + " ".join(
                f"{kind.lower()}_mismatches={mismatch_by_kind[kind]}"
                for kind in kinds
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
