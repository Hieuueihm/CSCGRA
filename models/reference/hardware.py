"""Hardware Python reference derived from the canonical algorithms.

This is the second and only hardware reference source beside
``reference/canonical.py``. It models the implementation choices that are
part of the RTL contract (Q16 normal equations, diagonal regularisation, LDLT
factorisation, reciprocal-D scaling and signed-24-bit coefficient
quantisation). It never imports RTL or a RTL-generated golden.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
from typing import Sequence

Q = 16
DATA_W = 24
DATA_MASK = (1 << DATA_W) - 1
MIN_S24 = -(1 << (DATA_W - 1))
MAX_S24 = (1 << (DATA_W - 1)) - 1
MAX_SUPPORT = 16
TAPS = 0x80200003
DEFAULT_SEED = 0xDEADBEEF
ROOT = Path(__file__).resolve().parents[2]
IMMUTABLE_INPUT = ROOT / "models" / "golden" / "golden_cases.vh"
DEFAULT_GOLDEN = ROOT / "verification" / "v2" / "run1" / "k_sweep_golden_hardware.vh"
DEFAULT_C_GOLDEN = ROOT / "sw" / "v2" / "src" / "cscgra_k_sweep_golden.h"
CASES = [
    (64, 256, 16),
    (64, 256, 8),
    (64, 256, 4),
    (32, 128, 8),
    (32, 128, 4),
    (32, 128, 2),
    (16, 64, 4),
    (16, 64, 2),
]
ALGORITHM_NAMES = ["OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"]


def s24(value: int) -> int:
    value &= DATA_MASK
    return value - (1 << DATA_W) if value & (1 << (DATA_W - 1)) else value


def sat_s24(value: int) -> int:
    return max(MIN_S24, min(MAX_S24, int(value)))


def _galois_step(state: int) -> int:
    shifted = (state >> 1) & 0x7FFFFFFF
    return (shifted ^ TAPS) & 0xFFFFFFFF if state & 1 else shifted


def _lfsr_advance(state: int, steps: int) -> int:
    for _ in range(steps):
        state = _galois_step(state)
    return state


def make_phi(m_size: int, n_size: int, seed: int, scale_q: int) -> list[list[int]]:
    seed = seed or DEFAULT_SEED
    phi: list[list[int]] = []
    for row_idx in range(m_size):
        row_state = _lfsr_advance(seed, row_idx * n_size)
        row = []
        for col_idx in range(n_size):
            state = _lfsr_advance(row_state, col_idx + 1)
            row.append(scale_q if state & 1 else -scale_q)
        phi.append(row)
    return phi


def _div_round(num: int, den: int) -> int:
    """Signed round-to-nearest divider, matching the RTL restoring divider."""

    if den == 0:
        return 0
    quotient, remainder = divmod(abs(num), abs(den))
    if (remainder << 1) >= abs(den):
        quotient += 1
    return -quotient if (num < 0) ^ (den < 0) else quotient


def _corr(phi: list[list[int]], residual: Sequence[int]) -> list[int]:
    return [
        sat_s24(sum(phi[row][col] * s24(residual[row]) for row in range(len(phi))) >> Q)
        for col in range(len(phi[0]))
    ]


def _matvec(phi: list[list[int]], vector: Sequence[int]) -> list[int]:
    return [sat_s24(sum(phi[row][col] * s24(vector[col]) for col in range(len(vector))) >> Q) for row in range(len(phi))]


def _residual(phi: list[list[int]], y: Sequence[int], x: Sequence[int]) -> list[int]:
    fitted = _matvec(phi, x)
    return [sat_s24(s24(y[row]) - fitted[row]) for row in range(len(phi))]


def _argmax_abs(values: Sequence[int], excluded: set[int]) -> int:
    return min((idx for idx in range(len(values)) if idx not in excluded), key=lambda idx: (-abs(s24(values[idx])), idx))


def _top(values: Sequence[int], count: int, excluded: set[int] | None = None) -> list[int]:
    excluded = excluded or set()
    ranked = [idx for idx in range(len(values)) if idx not in excluded]
    ranked.sort(key=lambda idx: (-abs(s24(values[idx])), idx))
    return ranked[:max(0, count)]


def _threshold(values: Sequence[int], count: int) -> list[int]:
    # The post-update x top-K path used by HTP preserves rank order (magnitude,
    # then index), and that order becomes the LDLT row/column order. It must
    # not be sorted because finite-precision LDLT is order-sensitive.
    return _top(values, count)


def _threshold_refine_support(values: Sequence[int], count: int) -> list[int]:
    """Model the sorted candidate path used after CoSaMP/SP REFINE."""

    return sorted(_top(values, count))


def _support_fingerprint(support: Sequence[int]) -> int:
    """Return the commutative 32-bit reject fingerprint used by factor-check."""

    value = (0x6D2B79F5 ^ len(support)) & 0xFFFFFFFF
    for index in support:
        word = index & 0xFFFFFFFF
        value ^= word ^ ((word << 10) & 0xFFFFFFFF) ^ ((word << 20) & 0xFFFFFFFF) ^ 0x9E3779B9
        value &= 0xFFFFFFFF
    return value


@dataclass
class HardwareTrace:
    x: list[int]
    residual: list[int]
    support: list[int]
    history: list[tuple[list[int], list[int], list[int]]]


def _ldlt_solve(phi: list[list[int]], y: Sequence[int], support: Sequence[int]) -> tuple[list[int], list[int]]:
    """Solve one support set with the controller's fixed LDLT schedule.

    Gram, RHS and D are stored as raw Q32 sums. The RTL adds one Q32 LSB to
    every diagonal, stores L and reciprocal-D in Q16, and truncates each
    multiply-accumulate at the corresponding registered boundary.
    """

    ordered = list(dict.fromkeys(support))[:MAX_SUPPORT]
    n_size = len(phi[0])
    if not ordered:
        return [0] * n_size, [s24(value) for value in y]
    k_size = len(ordered)
    gram = [[
        sum(phi[row][ordered[i]] * phi[row][ordered[j]] for row in range(len(phi)))
        for j in range(k_size)
    ] for i in range(k_size)]
    rhs = [sum(phi[row][ordered[i]] * s24(y[row]) for row in range(len(phi))) for i in range(k_size)]
    for i in range(k_size):
        gram[i][i] += 1

    l = [[0] * k_size for _ in range(k_size)]
    inv_d = [0] * k_size  # Q16 reciprocal, from ge_div_num=2**48 / D(Q32)
    d = [0] * k_size
    for i in range(k_size):
        for j in range(i):
            # The RTL wide multiplier keeps the Q32 product of L*L and then
            # multiplies by D before one registered >>>32 reduction.  Doing
            # two early Q16 truncations here changes the factor materially.
            acc = sum((l[i][p] * l[j][p] * d[p]) >> 32 for p in range(j))
            num = gram[i][j] - acc
            l[i][j] = (num * inv_d[j]) >> 32
        acc_diag = sum((l[i][p] * l[i][p] * d[p]) >> 32 for p in range(i))
        d[i] = gram[i][i] - acc_diag
        inv_d[i] = _div_round(1 << 48, d[i] if d[i] else 1)
        l[i][i] = 1 << Q

    # Forward solve L(Q16) z(Q32) = rhs(Q32).
    z = [0] * k_size
    for i in range(k_size):
        z[i] = rhs[i] - sum((l[i][j] * z[j]) >> Q for j in range(i))
    # z is Q32 and inv(D) is Q16; >>>32 leaves a Q16 diagonal result.
    w = [(z[i] * inv_d[i]) >> 32 for i in range(k_size)]

    # Back solve L^T x = w, preserving controller's truncation points.
    coeff = [0] * k_size
    for i in range(k_size - 1, -1, -1):
        value = w[i] - sum((l[j][i] * coeff[j]) >> Q for j in range(i + 1, k_size))
        coeff[i] = sat_s24(value)
    x = [0] * n_size
    for idx, value in zip(ordered, coeff):
        x[idx] = value
    return x, _residual(phi, y, x)


@dataclass
class _LdltService:
    """Stateful model of the RTL factor cache and set-based reuse policy."""

    phi: list[list[int]]
    y: Sequence[int]
    factor_order: list[int]
    factor_fingerprint: int | None

    @classmethod
    def create(cls, phi: list[list[int]], y: Sequence[int]) -> "_LdltService":
        return cls(phi, y, [], None)

    def solve(self, support: Sequence[int]) -> tuple[list[int], list[int]]:
        request = list(dict.fromkeys(support))[:MAX_SUPPORT]
        cached = self.factor_order
        request_fingerprint = _support_fingerprint(request)
        scanned = bool(cached) and len(request) >= len(cached)
        exact = (
            scanned
            and len(request) == len(cached)
            and set(request) == set(cached)
            and request_fingerprint == self.factor_fingerprint
        )
        prefix = scanned and len(request) > len(cached) and set(cached).issubset(request)
        if exact:
            # FACTOR_REUSE_EXACT is set-based. The controller restores the
            # cached order when both its set scan and reject fingerprint hit.
            order = list(cached)
        elif prefix:
            # Prefix extension retains the old triangle and appends newly
            # observed entries in request order.
            cached_set = set(cached)
            order = list(cached) + [index for index in request if index not in cached_set]
        else:
            order = request
        result = _ldlt_solve(self.phi, self.y, order)
        if not exact:
            self.factor_order = order
            # When factor-check is bypassed (no cache or a smaller request),
            # RTL reaches DONE without scanning support tokens and caches only
            # the initialized fingerprint. A scanned miss/prefix caches the
            # complete request fingerprint.
            self.factor_fingerprint = (
                request_fingerprint if scanned else (0x6D2B79F5 ^ len(request)) & 0xFFFFFFFF
            )
        return result


def _omp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    ls = _LdltService.create(phi, y)
    for _ in range(k):
        support.append(_argmax_abs(_corr(phi, residual), set(support)))
        x, residual = ls.solve(support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def cosamp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0])
    residual = [s24(value) for value in y]
    support: list[int] = []
    history: list[tuple[list[int], list[int], list[int]]] = []
    ls = _LdltService.create(phi, y)
    for _ in range(k):
        candidates = _top(_corr(phi, residual), 2 * k)
        merged = sorted(set(support).union(candidates))[:MAX_SUPPORT]
        temp_x, _ = ls.solve(merged)
        support = _threshold_refine_support(temp_x, k)
        x, residual = ls.solve(support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _htp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    ls = _LdltService.create(phi, y)
    for _ in range(k):
        corr = _corr(phi, residual)
        z = [sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]
        support = _threshold(z, k)
        x, residual = ls.solve(support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _sp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    ls = _LdltService.create(phi, y)
    for _ in range(k):
        candidates = _top(_corr(phi, residual), k)
        merged = sorted(set(support).union(candidates))[:MAX_SUPPORT]
        temp_x, _ = ls.solve(merged)
        support = _threshold_refine_support(temp_x, k)
        x, residual = ls.solve(support)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _gomp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    ls = _LdltService.create(phi, y)
    iteration = 0
    while len(support) < k:
        count = min(2, k - len(support))
        support.extend(_top(_corr(phi, residual), count, set(support)))
        x, residual = ls.solve(support)
        history.append((list(support), list(x), list(residual)))
        iteration += 1
    return HardwareTrace(x, residual, support, history)


def _gradient_update(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    """Hardware gradient path: Q16 correlation followed by ``>>>3`` update."""

    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    for _ in range(k):
        corr = _corr(phi, residual)
        x = [sat_s24(x[i] + (corr[i] >> 3)) for i in range(len(x))]
        support = _threshold(x, k)
        keep = set(support)
        x = [x[i] if i in keep else 0 for i in range(len(x))]
        residual = _residual(phi, y, x)
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def _mp(phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    x = [0] * len(phi[0]); residual = [s24(value) for value in y]
    support: list[int] = []; history: list[tuple[list[int], list[int], list[int]]] = []
    norm = sum(phi[row][0] * phi[row][0] for row in range(len(phi))) >> Q
    for _ in range(k):
        corr = _corr(phi, residual)
        idx = _argmax_abs(corr, set())
        alpha = _div_round(corr[idx] << Q, norm or 1)
        x[idx] = sat_s24(x[idx] + alpha)
        if idx not in support:
            support.append(idx)
        # OP_MP_UPDATE consumes the residual bank at 0x080 and subtracts only
        # the newly selected rank-1 contribution. Recomputing y-Phi*x would
        # move the fixed-point truncation boundary and diverges at larger K.
        residual = [
            sat_s24(residual[row] - ((phi[row][idx] * alpha) >> Q))
            for row in range(len(phi))
        ]
        history.append((list(support), list(x), list(residual)))
    return HardwareTrace(x, residual, support, history)


def run(algorithm: str, phi: list[list[int]], y: Sequence[int], k: int) -> HardwareTrace:
    # LS-based algorithms use the same hardware contract: Q16 normal
    # equations, +1 diagonal regularisation, LDLT, Q32 reciprocal-D and
    # signed-24 coefficient writes.  Non-LS paths retain their fixed-point
    # algorithmic update, since they do not traverse the LS service.
    runners = {
        "OMP": _omp,
        "CoSaMP": cosamp,
        "HTP": _htp,
        "SP": _sp,
        "gOMP": _gomp,
        "GOMP": _gomp,
    }
    if algorithm in runners:
        return runners[algorithm](phi, y, k)
    if algorithm in {"IHT", "GP"}:
        return _gradient_update(phi, y, k)
    if algorithm == "MP":
        return _mp(phi, y, k)
    raise ValueError(f"unsupported hardware algorithm: {algorithm}")


def _parse_hex_function(text: str, name: str) -> dict[int, int]:
    match = re.search(rf"function\s+\[[^\]]+\]\s+{name};(?P<body>.*?)endfunction", text, re.S)
    if not match:
        raise ValueError(f"missing input function {name}")
    return {
        int(index): int(value, 16)
        for index, value in re.findall(
            rf"\b(\d+)\s*:\s*{name}\s*=\s*\d+'h([0-9a-fA-F]+)\s*;",
            match.group("body"),
        )
    }


def _parse_int_function(text: str, name: str) -> dict[int, int]:
    match = re.search(rf"function\s+integer\s+{name};(?P<body>.*?)endfunction", text, re.S)
    if not match:
        raise ValueError(f"missing input function {name}")
    return {
        int(index): int(value)
        for index, value in re.findall(
            rf"\b(\d+)\s*:\s*{name}\s*=\s*(\d+)\s*;",
            match.group("body"),
        )
    }


def _hex24(value: int) -> str:
    return f"24'h{value & DATA_MASK:06X}"


def _emit_int_function(lines: list[str], name: str, values: Sequence[int], default: int = 0) -> None:
    lines.append(f"function integer {name};")
    lines.append("input integer case_idx; begin case(case_idx)")
    for index, value in enumerate(values):
        lines.append(f"  {index}: {name} = {value};")
    lines.append(f"  default: {name} = {default}; endcase end endfunction")


def generate_golden(output_path: Path = DEFAULT_GOLDEN) -> str:
    """Generate the sole hardware RTL golden from this implementation."""

    frozen = IMMUTABLE_INPUT.read_text(errors="ignore")
    y_function = _parse_hex_function(frozen, "gold_y")
    seed = _parse_int_function(frozen, "gold_case_seed").get(0, 17)
    scale_q = _parse_hex_function(frozen, "gold_case_scale").get(0, 0x4000)
    phi_kind = _parse_hex_function(frozen, "gold_case_phi_kind").get(0, 0)
    y64 = [s24(y_function.get(index, 0)) for index in range(64)]

    lines = [
        "// Auto-generated only by models/reference/hardware.py",
        "// Hardware contract: Q16 data, Q32 Gram/RHS/D, LDLT, Q16 inv(D).",
        "// Do not edit this include manually.",
        "localparam integer KSWEEP_GOLD_CASES = 8;",
        "localparam integer KSWEEP_GOLD_ALGS = 8;",
        "localparam integer KSWEEP_GOLD_MAX_N = 256;",
        "localparam integer KSWEEP_GOLD_TOL = 0;",
    ]
    for case_idx, (m_size, n_size, k_size) in enumerate(CASES):
        lines.extend([
            f"localparam integer KSHW_CASE_{case_idx}_M = {m_size};",
            f"localparam integer KSHW_CASE_{case_idx}_N = {n_size};",
            f"localparam integer KSHW_CASE_{case_idx}_K = {k_size};",
        ])

    _emit_int_function(lines, "hwgold_case_m", [case[0] for case in CASES])
    _emit_int_function(lines, "hwgold_case_n", [case[1] for case in CASES])
    _emit_int_function(lines, "hwgold_case_k", [case[2] for case in CASES])
    _emit_int_function(lines, "hwgold_case_seed", [seed] * len(CASES), seed)
    lines.append("function [23:0] hwgold_case_scale;")
    lines.append("input integer case_idx; begin case(case_idx)")
    for case_idx in range(len(CASES)):
        lines.append(f"  {case_idx}: hwgold_case_scale = {_hex24(scale_q)};")
    lines.append(f"  default: hwgold_case_scale = {_hex24(scale_q)}; endcase end endfunction")
    _emit_int_function(lines, "hwgold_case_phi_kind", [phi_kind] * len(CASES), phi_kind)

    lines.append("function [23:0] hwgold_y;")
    lines.append("input integer elem_idx; begin case(elem_idx)")
    for elem_idx, value in enumerate(y64):
        lines.append(f"  {elem_idx}: hwgold_y = {_hex24(value)};")
    lines.append("  default: hwgold_y = 24'h000000; endcase end endfunction")

    lines.append("function [23:0] hwgold_x_final;")
    lines.append("input integer case_idx; input integer alg_idx; input integer elem_idx; begin case(((case_idx * KSWEEP_GOLD_ALGS + alg_idx) * KSWEEP_GOLD_MAX_N) + elem_idx)")
    for case_idx, (m_size, n_size, k_size) in enumerate(CASES):
        phi = make_phi(m_size, n_size, seed, scale_q)
        y = y64[:m_size]
        for alg_idx, algorithm in enumerate(ALGORITHM_NAMES):
            result = run(algorithm, phi, y, k_size)
            for elem_idx, value in enumerate(result.x):
                if value:
                    flat_key = ((case_idx * len(ALGORITHM_NAMES) + alg_idx) * 256) + elem_idx
                    lines.append(f"  {flat_key}: hwgold_x_final = {_hex24(value)};")
    lines.append("  default: hwgold_x_final = 24'h000000; endcase end endfunction")

    generated = "\n".join(lines) + "\n"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(generated, newline="\n")
    return generated


def generate_c_header(output_path: Path = DEFAULT_C_GOLDEN) -> str:
    """Generate the SoC C runner's constants from the same hardware model."""

    frozen = IMMUTABLE_INPUT.read_text(errors="ignore")
    y_function = _parse_hex_function(frozen, "gold_y")
    seed = _parse_int_function(frozen, "gold_case_seed").get(0, 17)
    scale_q = _parse_hex_function(frozen, "gold_case_scale").get(0, 0x4000)
    phi_kind = _parse_hex_function(frozen, "gold_case_phi_kind").get(0, 0)
    y64 = [s24(y_function.get(index, 0)) & DATA_MASK for index in range(64)]

    def c_values(values: Sequence[int], per_line: int = 8) -> list[str]:
        rows = []
        for start in range(0, len(values), per_line):
            rows.append("    " + ", ".join(f"0x{value & DATA_MASK:06X}U" for value in values[start:start + per_line]) + ",")
        return rows

    results = []
    for case_idx, (m_size, n_size, k_size) in enumerate(CASES):
        phi = make_phi(m_size, n_size, seed, scale_q)
        y = [s24(value) for value in y64[:m_size]]
        results.append([run(algorithm, phi, y, k_size).x for algorithm in ALGORITHM_NAMES])

    lines = [
        "#ifndef CSCGRA_K_SWEEP_GOLDEN_H",
        "#define CSCGRA_K_SWEEP_GOLDEN_H",
        "",
        "/* Auto-generated by models/reference/hardware.py; do not edit. */",
        "/* This header is the hardware Python reference used by the v2 RTL. */",
        "#include <stdint.h>",
        "",
        "#define KSGOLD_MAX_M 64U",
        "#define KSGOLD_MAX_N 256U",
        f"#define KSGOLD_SEED {seed}U",
        f"#define KSGOLD_SCALE 0x{scale_q:08X}U",
        f"#define KSGOLD_PHI_KIND {phi_kind}U",
        "#define KSGOLD_TOL 0U",
        f"#define KSGOLD_ALG_COUNT {len(ALGORITHM_NAMES)}U",
        f"#define KSGOLD_CASE_COUNT {len(CASES)}U",
        "#define KSGOLD_SOURCE_TAG \"models/reference/hardware.py\"",
        "#define KSGOLD_MU_SHIFT 3U",
        "",
        'static const char * const ksgold_alg_names[KSGOLD_ALG_COUNT] = { "' + '", "'.join(ALGORITHM_NAMES) + '" };',
        "",
        "static const uint32_t ksgold_case_m[KSGOLD_CASE_COUNT] = { " + ", ".join(f"{case[0]}U" for case in CASES) + " };",
        "static const uint32_t ksgold_case_n[KSGOLD_CASE_COUNT] = { " + ", ".join(f"{case[1]}U" for case in CASES) + " };",
        "static const uint32_t ksgold_case_k[KSGOLD_CASE_COUNT] = { " + ", ".join(f"{case[2]}U" for case in CASES) + " };",
        "",
        "static const uint32_t ksgold_y[KSGOLD_MAX_M] = {",
        *c_values(y64),
        "};",
        "",
        "static const uint32_t ksgold_x_final[KSGOLD_ALG_COUNT][KSGOLD_CASE_COUNT][KSGOLD_MAX_N] = {",
    ]
    for alg_idx, _algorithm in enumerate(ALGORITHM_NAMES):
        lines.append("    {")
        for case_idx in range(len(CASES)):
            lines.append("        {")
            lines.extend("        " + row for row in c_values(results[case_idx][alg_idx]))
            lines.append("        },")
        lines.append("    },")
    lines.extend(["};", "", "#endif", ""])
    generated = "\n".join(lines)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(generated, newline="\n")
    return generated


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate/check the bit-exact hardware RTL golden.")
    parser.add_argument("--output", type=Path, default=DEFAULT_GOLDEN)
    parser.add_argument("--c-output", type=Path, default=None)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    if args.check:
        temporary = output.with_suffix(output.suffix + ".tmp")
        generated = generate_golden(temporary)
        existing = output.read_text() if output.exists() else None
        temporary.unlink()
        if existing != generated:
            raise SystemExit(f"hardware golden mismatch: {output}")
        if args.c_output is not None:
            c_output = args.c_output if args.c_output.is_absolute() else ROOT / args.c_output
            c_temp = c_output.with_suffix(c_output.suffix + ".tmp")
            c_generated = generate_c_header(c_temp)
            c_existing = c_output.read_text() if c_output.exists() else None
            c_temp.unlink()
            if c_existing != c_generated:
                raise SystemExit(f"C hardware golden mismatch: {c_output}")
        print(f"hardware golden check PASS: {output}")
    else:
        generate_golden(output)
        if args.c_output is not None:
            c_output = args.c_output if args.c_output.is_absolute() else ROOT / args.c_output
            generate_c_header(c_output)
        print(output)


if __name__ == "__main__":
    main()
