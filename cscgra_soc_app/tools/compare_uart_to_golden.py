#!/usr/bin/env python3
"""Compare CSCGRA SoC UART x-vector dumps against the golden model.

Build the bare-metal app with CGRA_DUMP_FULL_X=1 so it prints lines like:

    X_DUMP OMP alg_idx=0 idx=38 value=0xfee6ea

Then run this script on the captured UART log.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ALG_ALIASES = {
    "OMP": 0,
    "OMP_DIRECTPHI": 0,
    "GOMP": 1,
    "COSAMP": 2,
    "SP": 3,
    "IHT": 4,
    "HTP": 5,
    "GP": 6,
    "MP": 7,
}

X_DUMP_RE = re.compile(
    r"\bX_DUMP\s+(?P<name>\S+)\s+alg_idx=(?P<alg_idx>\d+)\s+"
    r"idx=(?P<idx>\d+)\s+value=0x(?P<value>[0-9a-fA-F]+)"
)


def signed24(value: int) -> int:
    value &= 0x00FFFFFF
    if value & 0x00800000:
        value |= ~0x00FFFFFF
    return value


def absdiff24(lhs: int, rhs: int) -> int:
    return abs(signed24(lhs) - signed24(rhs))


def parse_localparam(text: str, name: str, default: int) -> int:
    match = re.search(rf"localparam\s+integer\s+{re.escape(name)}\s*=\s*(\d+)\s*;", text)
    return int(match.group(1)) if match else default


def load_golden_x(path: Path) -> tuple[dict[tuple[int, int], int], int, int]:
    text = path.read_text(encoding="utf-8", errors="ignore")
    max_n = parse_localparam(text, "GOLD_MAX_N", 256)
    max_iters = parse_localparam(text, "GOLD_MAX_ITERS", 16)
    final_iter = max_iters - 1

    mem_values: dict[int, int] = {}
    for match in re.finditer(r"gold_iter_x_hat_mem\[(\d+)\]\s*=\s*24'h([0-9a-fA-F]+)\s*;", text):
        mem_values[int(match.group(1))] = int(match.group(2), 16)

    if not mem_values:
        raise ValueError(f"No gold_iter_x_hat_mem entries found in {path}")

    golden: dict[tuple[int, int], int] = {}
    for alg_idx in range(8):
        base = ((alg_idx * max_iters) + final_iter) * max_n
        for idx in range(max_n):
            golden[(alg_idx, idx)] = mem_values.get(base + idx, 0) & 0x00FFFFFF
    return golden, max_n, final_iter


def parse_uart_log(path: Path) -> dict[str, dict[int, int]]:
    dumps: dict[str, dict[int, int]] = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        match = X_DUMP_RE.search(line)
        if not match:
            continue
        name = match.group("name")
        alg_idx_from_name = ALG_ALIASES.get(name.upper())
        alg_idx_from_log = int(match.group("alg_idx"))
        if alg_idx_from_name is not None and alg_idx_from_name != alg_idx_from_log:
            raise ValueError(
                f"Algorithm {name} reports alg_idx={alg_idx_from_log}, "
                f"expected {alg_idx_from_name}"
            )
        idx = int(match.group("idx"))
        value = int(match.group("value"), 16) & 0x00FFFFFF
        dumps.setdefault(name, {})[idx] = value
    return dumps


def compare_one(
    name: str,
    values: dict[int, int],
    golden: dict[tuple[int, int], int],
    max_n: int,
    tol: int,
    max_show: int,
) -> bool:
    alg_idx = ALG_ALIASES.get(name.upper())
    if alg_idx is None:
        print(f"FAIL {name}: unknown algorithm name")
        return False

    missing = [idx for idx in range(max_n) if idx not in values]
    mismatches: list[tuple[int, int, int, int]] = []
    for idx in range(max_n):
        if idx not in values:
            continue
        got = values[idx]
        exp = golden[(alg_idx, idx)]
        diff = absdiff24(got, exp)
        if diff > tol:
            mismatches.append((idx, got, exp, diff))

    if missing or mismatches:
        print(
            f"FAIL {name}: dumped={len(values)}/{max_n} "
            f"missing={len(missing)} mismatches={len(mismatches)} tol={tol}"
        )
        for idx in missing[:max_show]:
            print(f"  MISSING idx={idx}")
        for idx, got, exp, diff in mismatches[:max_show]:
            print(f"  MISMATCH idx={idx} got=0x{got:06x} exp=0x{exp:06x} diff={diff}")
        return False

    print(f"PASS {name}: {max_n}/{max_n} entries match tol={tol}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", required=True, type=Path, help="Captured UART log")
    parser.add_argument(
        "--golden",
        type=Path,
        default=Path(r"D:\vivado_pj\golden_model\golden_cases_array.vh"),
        help="Path to golden_cases_array.vh",
    )
    parser.add_argument("--tol", type=int, default=512, help="Signed 24-bit tolerance")
    parser.add_argument("--max-show", type=int, default=16, help="Maximum details per failure")
    args = parser.parse_args()

    golden, max_n, final_iter = load_golden_x(args.golden)
    dumps = parse_uart_log(args.log)
    if not dumps:
        print("FAIL: no X_DUMP lines found in UART log")
        print("Build the app with CGRA_DUMP_FULL_X=1 and capture the UART output.")
        return 2

    print(f"Golden: {args.golden} final_iter={final_iter} N={max_n}")
    ok = True
    for name in sorted(dumps.keys(), key=lambda n: (ALG_ALIASES.get(n.upper(), 99), n)):
        ok = compare_one(name, dumps[name], golden, max_n, args.tol, args.max_show) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
