import math
import re
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
IMMUTABLE = ROOT / "golden_model" / "golden_cases.vh"
OUT = ROOT / "CSCGRA_noisy_mu_peop8" / "tests" / "run1" / "k_sweep_golden_mu3.vh"

Q = 16
DATA_MASK = (1 << 24) - 1
TAPS = 0x80200003
DEFAULT_SEED = 0xDEADBEEF
MU_SHIFT = 3

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

TB_ALG_NAMES = ["OMP", "CoSaMP", "IHT", "HTP", "SP", "GP", "GOMP", "MP"]
TB_TO_IMMUTABLE_ALG = [0, 2, 4, 5, 3, 6, 1, 7]


def s24(value: int) -> int:
    value &= DATA_MASK
    if value & (1 << 23):
        value -= 1 << 24
    return value


def sat_s24(value: int) -> int:
    if value > 0x7FFFFF:
        return 0x7FFFFF
    if value < -0x800000:
        return -0x800000
    return value


def hex24(value: int) -> str:
    return f"24'h{value & DATA_MASK:06X}"


def parse_hex_func(text: str, fname: str) -> dict[int, int]:
    m = re.search(rf"function\s+\[[^\]]+\]\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise ValueError(f"missing {fname}")
    vals = {}
    for mm in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*\d+'h([0-9a-fA-F]+)\s*;", m.group("body")):
        vals[int(mm.group(1))] = int(mm.group(2), 16)
    return vals


def parse_int_func(text: str, fname: str) -> dict[int, int]:
    m = re.search(rf"function\s+integer\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise ValueError(f"missing {fname}")
    vals = {}
    for mm in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*(\d+)\s*;", m.group("body")):
        vals[int(mm.group(1))] = int(mm.group(2))
    return vals


def parse_int_param(text: str, name: str) -> int:
    m = re.search(rf"localparam\s+integer\s+{name}\s*=\s*(\d+)\s*;", text)
    if not m:
        raise ValueError(f"missing {name}")
    return int(m.group(1))


def galois_step(state: int) -> int:
    shifted = (state >> 1) & 0x7FFFFFFF
    return (shifted ^ TAPS) & 0xFFFFFFFF if (state & 1) else shifted


def lfsr_advance(state: int, steps: int) -> int:
    for _ in range(steps):
        state = galois_step(state)
    return state


def make_phi(m_size: int, n_size: int, seed: int, scale_q: int) -> list[list[int]]:
    seed = seed or DEFAULT_SEED
    phi = []
    for row_idx in range(m_size):
        row_state = lfsr_advance(seed, row_idx * n_size)
        row = []
        for col_idx in range(n_size):
            state = lfsr_advance(row_state, col_idx + 1)
            row.append(scale_q if (state & 1) else s24(-scale_q))
        phi.append(row)
    return phi


def score_abs(value: int) -> int:
    value = s24(value)
    if value == -0x800000:
        mag = 0x7FFFFF
    else:
        mag = abs(value)
    return 0 if mag <= 1 else mag


def reduce_pick(values: list[int], selected: set[int] | None = None) -> int:
    selected = selected or set()
    best_idx = 0
    best_score = -1
    found = False
    for idx, value in enumerate(values):
        if idx in selected:
            continue
        score = score_abs(value)
        if (not found) or (score > best_score) or (score == best_score and idx < best_idx):
            best_idx = idx
            best_score = score
            found = True
    return best_idx


def corr_scores(phi: list[list[int]], residual: list[int], n_size: int) -> list[int]:
    out = []
    for col_idx in range(n_size):
        acc = 0
        for row_idx, r_value in enumerate(residual):
            acc += phi[row_idx][col_idx] * s24(r_value)
        out.append(sat_s24(acc >> Q))
    return out


def div_round(num: int, den: int) -> int:
    if den == 0:
        return 0
    neg = (num < 0) ^ (den < 0)
    anum = abs(num)
    aden = abs(den)
    quot, rem = divmod(anum, aden)
    if (rem << 1) >= aden:
        quot += 1
    return -quot if neg else quot


def quantize_float(value: float) -> int:
    mag = int(math.floor(abs(value) * (1 << Q) + 0.5))
    return sat_s24(-mag if value < 0 else mag)


def solve_linear(a: list[list[float]], b: list[float]) -> list[float]:
    n = len(b)
    if n == 0:
        return []
    aug = [list(a[row_idx]) + [b[row_idx]] for row_idx in range(n)]
    for col_idx in range(n):
        piv = max(range(col_idx, n), key=lambda row_idx: abs(aug[row_idx][col_idx]))
        if abs(aug[piv][col_idx]) < 1e-15:
            continue
        if piv != col_idx:
            aug[col_idx], aug[piv] = aug[piv], aug[col_idx]
        div = aug[col_idx][col_idx]
        for k in range(col_idx, n + 1):
            aug[col_idx][k] /= div
        for row_idx in range(n):
            if row_idx == col_idx:
                continue
            factor = aug[row_idx][col_idx]
            if factor:
                for k in range(col_idx, n + 1):
                    aug[row_idx][k] -= factor * aug[col_idx][k]
    return [aug[row_idx][n] for row_idx in range(n)]


def unique_order(values: list[int]) -> list[int]:
    out = []
    seen = set()
    for value in values:
        if value not in seen:
            seen.add(value)
            out.append(value)
    return out


def ls_fit_quantized(phi: list[list[int]], y: list[int], support: list[int], n_size: int) -> tuple[list[int], list[int]]:
    support = unique_order(support)
    if not support:
        return [0] * n_size, list(y)
    scale = float(1 << Q)
    phi_f = [[value / scale for value in row] for row in phi]
    y_f = [value / scale for value in y]
    k_size = len(support)
    gram = [
        [sum(phi_f[row_idx][support[a]] * phi_f[row_idx][support[b]] for row_idx in range(len(y))) for b in range(k_size)]
        for a in range(k_size)
    ]
    rhs = [sum(phi_f[row_idx][support[a]] * y_f[row_idx] for row_idx in range(len(y))) for a in range(k_size)]
    coeff_q = [quantize_float(value) for value in solve_linear(gram, rhs)]
    x = [0] * n_size
    for idx, coeff in zip(support, coeff_q):
        x[idx] = coeff
    residual = []
    for row_idx, y_value in enumerate(y):
        acc = sum(phi[row_idx][support[pos]] * coeff_q[pos] for pos in range(k_size))
        residual.append(sat_s24(y_value - (acc >> Q)))
    return x, residual


def prune_by_abs(values: list[int], k_size: int) -> list[int]:
    selected = set()
    picks = []
    for _ in range(k_size):
        idx = reduce_pick(values, selected)
        selected.add(idx)
        picks.append(idx)
    return sorted(picks)


def resid_from_x(phi: list[list[int]], y: list[int], x: list[int], support: list[int]) -> list[int]:
    return [sat_s24(y[row_idx] - (sum(phi[row_idx][col_idx] * x[col_idx] for col_idx in support) >> Q)) for row_idx in range(len(y))]


def merge_support_hw(dest: list[int], src: list[int], max_support: int = 16) -> list[int]:
    merged = sorted(set(dest))
    for idx in src:
        if idx in merged:
            continue
        insert_pos = 0
        while insert_pos < len(merged) and merged[insert_pos] < idx:
            insert_pos += 1
        if len(merged) < max_support:
            merged.insert(insert_pos, idx)
        elif insert_pos < max_support:
            merged.insert(insert_pos, idx)
            merged = merged[:max_support]
    return merged

def run_reference_alg(tb_alg: int, phi: list[list[int]], y: list[int], n_size: int, k_size: int, scale_q: int) -> list[int]:
    x = [0] * n_size
    residual = list(y)
    support: list[int] = []
    den = (((scale_q * scale_q) + (1 << (Q - 1))) >> Q) * len(y)

    iter_limit = ((k_size + 1) // 2) if tb_alg == 6 else k_size
    for _ in range(iter_limit):
        if tb_alg == 0:  # OMP
            scores = corr_scores(phi, residual, n_size)
            support.append(reduce_pick(scores, set(support)))
            x, residual = ls_fit_quantized(phi, y, support, n_size)
        elif tb_alg == 1:  # CoSaMP
            scores = corr_scores(phi, residual, n_size)
            selected = set()
            candidates = []
            for _rank in range(min(2 * k_size, n_size)):
                idx = reduce_pick(scores, selected)
                selected.add(idx)
                candidates.append(idx)
            merged = merge_support_hw(support, candidates, 16)
            temp_x, _ = ls_fit_quantized(phi, y, merged, n_size)
            support = prune_by_abs(temp_x, k_size)
            x, residual = ls_fit_quantized(phi, y, support, n_size)
        elif tb_alg == 2:  # IHT, RTL uses generated MU_SHIFT
            scores = corr_scores(phi, residual, n_size)
            x = [sat_s24(x[col_idx] + (s24(scores[col_idx]) >> MU_SHIFT)) for col_idx in range(n_size)]
            support = prune_by_abs(x, k_size)
            keep = set(support)
            x = [x[col_idx] if col_idx in keep else 0 for col_idx in range(n_size)]
            residual = resid_from_x(phi, y, x, support)
        elif tb_alg == 3:  # HTP
            scores = corr_scores(phi, residual, n_size)
            temp_x = [sat_s24(x[col_idx] + (s24(scores[col_idx]) >> MU_SHIFT)) for col_idx in range(n_size)]
            support = prune_by_abs(temp_x, k_size)
            x, residual = ls_fit_quantized(phi, y, support, n_size)
        elif tb_alg == 4:  # SP
            scores = corr_scores(phi, residual, n_size)
            selected = set()
            candidates = []
            for _rank in range(min(k_size, n_size)):
                idx = reduce_pick(scores, selected)
                selected.add(idx)
                candidates.append(idx)
            merged = merge_support_hw(support, candidates, 16)
            temp_x, _ = ls_fit_quantized(phi, y, merged, n_size)
            support = prune_by_abs(temp_x, k_size)
            x, residual = ls_fit_quantized(phi, y, support, n_size)
        elif tb_alg == 5:  # GP no-LS in RTL: select one corr atom, then SOP_MP_UPDATE-style update
            scores = corr_scores(phi, residual, n_size)
            idx = reduce_pick(scores, set(support))
            support.append(idx)
            alpha = sat_s24(div_round(scores[idx] << Q, den or 1))
            x[idx] = sat_s24(x[idx] + alpha)
            for row_idx in range(len(residual)):
                residual[row_idx] = sat_s24(residual[row_idx] - ((phi[row_idx][idx] * alpha) >> Q))
        elif tb_alg == 6:  # GOMP, two atoms per iter
            scores = corr_scores(phi, residual, n_size)
            selected = set(support)
            for _rank in range(2):
                idx = reduce_pick(scores, selected)
                selected.add(idx)
                support.append(idx)
            x, residual = ls_fit_quantized(phi, y, support, n_size)
        elif tb_alg == 7:  # MP
            scores = corr_scores(phi, residual, n_size)
            idx = reduce_pick(scores)
            support.append(idx)
            alpha = sat_s24(div_round(scores[idx] << Q, den or 1))
            x[idx] = sat_s24(x[idx] + alpha)
            for row_idx in range(len(residual)):
                residual[row_idx] = sat_s24(residual[row_idx] - ((phi[row_idx][idx] * alpha) >> Q))
    return x


def abs_diff24_unsigned(a: int, b: int) -> int:
    return abs(s24(a) - s24(b))

def emit_int_func(lines: list[str], name: str, values: list[int], default: int) -> None:
    lines.append(f"function integer {name};")
    lines.append("input integer case_idx; begin case(case_idx)")
    for idx, value in enumerate(values):
        lines.append(f"  {idx}: {name} = {value};")
    lines.append(f"  default: {name} = {default}; endcase end endfunction")


def main() -> None:
    immutable = IMMUTABLE.read_text(errors="ignore")
    max_n = parse_int_param(immutable, "GOLD_MAX_N")
    max_iters = parse_int_param(immutable, "GOLD_MAX_ITERS")
    gold_algs = parse_int_param(immutable, "GOLD_ALGS")
    immutable_y = parse_hex_func(immutable, "gold_y")
    immutable_x = parse_hex_func(immutable, "gold_iter_x_hat")
    seed = parse_int_func(immutable, "gold_case_seed").get(0, 17)
    scale_q = parse_hex_func(immutable, "gold_case_scale").get(0, 0x4000)
    phi_kind = parse_hex_func(immutable, "gold_case_phi_kind").get(0, 0)
    y64 = [s24(immutable_y.get(idx, 0)) for idx in range(64)]

    lines: list[str] = []
    lines.append("// Auto-generated by scripts/export_k_sweep_golden_mu3.py")
    lines.append("// Generated for RTL mu_shift_cfg=3; case 0 is regenerated instead of using immutable mu2 golden.")
    lines.append("// All cases are generated by the same fixed-point reference flow for the requested m/n/k.")
    lines.append("localparam integer KSWEEP_GOLD_CASES = 8;")
    lines.append("localparam integer KSWEEP_GOLD_ALGS = 8;")
    lines.append("localparam integer KSWEEP_GOLD_MAX_N = 256;")
    lines.append("localparam integer KSWEEP_GOLD_TOL = 512;")
    for case_idx, (m_size, n_size, k_size) in enumerate(CASES):
        lines.append(f"localparam integer KSWEEP_CASE_{case_idx}_M = {m_size};")
        lines.append(f"localparam integer KSWEEP_CASE_{case_idx}_N = {n_size};")
        lines.append(f"localparam integer KSWEEP_CASE_{case_idx}_K = {k_size};")

    emit_int_func(lines, "ksgold_case_m", [case_item[0] for case_item in CASES], 0)
    emit_int_func(lines, "ksgold_case_n", [case_item[1] for case_item in CASES], 0)
    emit_int_func(lines, "ksgold_case_k", [case_item[2] for case_item in CASES], 0)
    emit_int_func(lines, "ksgold_case_seed", [seed] * len(CASES), seed)
    lines.append("function [23:0] ksgold_case_scale;")
    lines.append("input integer case_idx; begin case(case_idx)")
    for case_idx in range(len(CASES)):
        lines.append(f"  {case_idx}: ksgold_case_scale = {hex24(scale_q)};")
    lines.append(f"  default: ksgold_case_scale = {hex24(scale_q)}; endcase end endfunction")
    emit_int_func(lines, "ksgold_case_phi_kind", [phi_kind] * len(CASES), phi_kind)

    lines.append("function [23:0] ksgold_y;")
    lines.append("input integer elem_idx; begin case(elem_idx)")
    for elem_idx in range(64):
        lines.append(f"  {elem_idx}: ksgold_y = {hex24(y64[elem_idx])};")
    lines.append("  default: ksgold_y = 24'h000000; endcase end endfunction")

    lines.append("function [23:0] ksgold_x_final;")
    lines.append("input integer case_idx; input integer alg_idx; input integer elem_idx; begin case(((case_idx * KSWEEP_GOLD_ALGS + alg_idx) * KSWEEP_GOLD_MAX_N) + elem_idx)")

    for case_idx, (m_size, n_size, k_size) in enumerate(CASES):
        phi = make_phi(m_size, n_size, seed, scale_q)
        y = y64[:m_size]
        for tb_alg in range(len(TB_ALG_NAMES)):
            x = run_reference_alg(tb_alg, phi, y, n_size, k_size, scale_q)
            for elem_idx, value in enumerate(x):
                if value:
                    flat_key = ((case_idx * len(TB_ALG_NAMES) + tb_alg) * 256) + elem_idx
                    lines.append(f"  {flat_key}: ksgold_x_final = {hex24(value)};")

    lines.append("  default: ksgold_x_final = 24'h000000; endcase end endfunction")
    OUT.write_text("\n".join(lines) + "\n", newline="\n")
    print(OUT)


if __name__ == "__main__":
    main()
