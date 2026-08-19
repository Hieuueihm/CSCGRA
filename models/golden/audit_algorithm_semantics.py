"""Compare the RTL-compatible K-sweep reference with canonical algorithms.

This is intentionally an audit tool. It does not rewrite any golden file and
it does not declare a mismatch to be an RTL failure: fixed-point arithmetic,
capacity limits, and a different step-size policy can all be deliberate
hardware variants.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reference"))
from canonical import run_all
import generate_k_sweep_golden as hw


Q = 16


def active_cases() -> list[tuple[int, int, int]]:
    return list(hw.CASES)


def load_y() -> tuple[int, int, list[int]]:
    text = hw.IMMUTABLE.read_text(errors="ignore")
    y_map = hw.parse_hex_func(text, "gold_y")
    seed = hw.parse_int_func(text, "gold_case_seed").get(0, 17)
    scale_q = hw.parse_hex_func(text, "gold_case_scale").get(0, 0x4000)
    y = [hw.s24(y_map.get(idx, 0)) for idx in range(64)]
    return seed, scale_q, y


def support_of(x: list[float], eps: float = 1.0e-12) -> set[int]:
    return {idx for idx, value in enumerate(x) if abs(value) > eps}


def q_to_float(values: list[int]) -> list[float]:
    return [hw.s24(value) / float(1 << Q) for value in values]


def matrix_to_float(phi: list[list[int]]) -> list[list[float]]:
    return [[value / float(1 << Q) for value in row] for row in phi]


def row(case_idx: int, name: str, hw_x: list[int], canonical_x: list[float]) -> str:
    fixed = support_of(q_to_float(hw_x))
    reference = support_of(canonical_x)
    union = fixed | reference
    overlap = fixed & reference
    jaccard = len(overlap) / len(union) if union else 1.0
    return f"| {case_idx} | {name} | {len(fixed)} | {len(reference)} | {len(overlap)} | {jaccard:.4f} |"


def audit() -> str:
    seed, scale_q, y64 = load_y()
    lines = [
        "# Canonical versus RTL-compatible golden audit",
        "",
        f"Inputs: seed={seed}, phi_scale_q=0x{scale_q:06X}, Q={Q}, GP/LS variants explicit.",
        "",
        "This report compares final nonzero support only; it does not rewrite the active golden.",
        "",
        "| case | algorithm | RTL nnz | canonical nnz | overlap | Jaccard |",
        "|---:|---|---:|---:|---:|---:|",
    ]
    for case_idx, (m_size, n_size, k_size) in enumerate(active_cases()):
        phi_q = hw.make_phi(m_size, n_size, seed, scale_q)
        y_q = y64[:m_size]
        phi = matrix_to_float(phi_q)
        y = q_to_float(y_q)
        canonical = run_all(phi, y, k_size, iht_step=1.0 / (1 << hw.MU_SHIFT))
        for alg_idx, name in enumerate(hw.TB_ALG_NAMES):
            fixed_x = hw.run_reference_alg(alg_idx, phi_q, y_q, n_size, k_size, scale_q)
            lines.append(row(case_idx, name, fixed_x, canonical[name].x))
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="optional Markdown output path")
    args = parser.parse_args()
    report = audit()
    if args.output:
        output = args.output if args.output.is_absolute() else hw.ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(report, newline="\n")
        print(output)
    else:
        print(report, end="")


if __name__ == "__main__":
    main()
