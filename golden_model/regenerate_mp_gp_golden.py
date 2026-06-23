import math
import re
import shutil
from pathlib import Path


ROOT = Path(r"D:\vivado_pj")
GOLDEN_DIR = ROOT / "golden_model"
FUNC_GOLDEN = GOLDEN_DIR / "golden_cases.vh"
ARRAY_GOLDEN = GOLDEN_DIR / "golden_cases_array.vh"

SYNC_FUNC = [
    ROOT / "analysis" / "m64n256k16" / "golden_cases.vh",
    ROOT / "CSCGRA" / "tests" / "golden_cases.vh",
    ROOT / "analysis" / "m64n256k16" / "verilator_tbs" / "golden_cases.vh",
]
SYNC_ARRAY = [
    ROOT / "analysis" / "m64n256k16" / "golden_cases_array.vh",
]

ALG_GP = 6
ALG_MP = 7
Q = 16
DATA_MASK = (1 << 24) - 1
TAPS = 0x80200003
DEFAULT_SEED = 0xDEADBEEF


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
    return f"24'h{(value & DATA_MASK):06x}"


def dec10(value: int) -> str:
    return f"10'd{value}"


def parse_int_param(text: str, name: str) -> int:
    m = re.search(rf"localparam\s+integer\s+{name}\s*=\s*(\d+)\s*;", text)
    if not m:
        raise ValueError(f"missing {name}")
    return int(m.group(1))


def parse_case_int(text: str, fname: str, key: int) -> int:
    m = re.search(rf"function\s+integer\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise ValueError(f"missing function {fname}")
    mm = re.search(rf"\b{key}\s*:\s*{fname}\s*=\s*(\d+)\s*;", m.group("body"))
    if not mm:
        raise ValueError(f"missing {fname}({key})")
    return int(mm.group(1))


def parse_case_hex(text: str, fname: str, key: int) -> int:
    m = re.search(rf"function\s+\[[^\]]+\]\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise ValueError(f"missing function {fname}")
    mm = re.search(rf"\b{key}\s*:\s*{fname}\s*=\s*\d+'h([0-9a-fA-F]+)\s*;", m.group("body"))
    if not mm:
        raise ValueError(f"missing {fname}({key})")
    return s24(int(mm.group(1), 16))


def parse_hex_func(text: str, fname: str) -> dict[int, int]:
    m = re.search(rf"function\s+\[[^\]]+\]\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        raise ValueError(f"missing function {fname}")
    out = {}
    for mm in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*\d+'h([0-9a-fA-F]+)\s*;", m.group("body")):
        out[int(mm.group(1))] = s24(int(mm.group(2), 16))
    return out


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
    for i in range(m_size):
        row_state = lfsr_advance(seed, i * n_size)
        row = []
        for j in range(n_size):
            state = lfsr_advance(row_state, j + 1)
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
    best_idx = None
    best_score = -1
    for idx, value in enumerate(values):
        if idx in selected:
            continue
        score = score_abs(value)
        if best_idx is None or score > best_score or (score == best_score and idx < best_idx):
            best_idx = idx
            best_score = score
    if best_idx is None:
        return 0
    return best_idx


def corr_scores(phi: list[list[int]], residual: list[int], n_size: int) -> list[int]:
    scores = []
    for j in range(n_size):
        acc = 0
        for i, r_value in enumerate(residual):
            acc += phi[i][j] * s24(r_value)
        scores.append(sat_s24(acc >> Q))
    return scores


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
    aug = [list(a[i]) + [b[i]] for i in range(n)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(aug[r][c]))
        if abs(aug[piv][c]) < 1e-15:
            continue
        if piv != c:
            aug[c], aug[piv] = aug[piv], aug[c]
        div = aug[c][c]
        for k in range(c, n + 1):
            aug[c][k] /= div
        for r in range(n):
            if r == c:
                continue
            factor = aug[r][c]
            if factor:
                for k in range(c, n + 1):
                    aug[r][k] -= factor * aug[c][k]
    return [aug[i][n] for i in range(n)]


def ls_fit_quantized(phi: list[list[int]], y: list[int], support: list[int], n_size: int) -> tuple[list[int], list[int]]:
    if not support:
        return [0] * n_size, list(y)
    scale = float(1 << Q)
    phi_f = [[value / scale for value in row] for row in phi]
    y_f = [value / scale for value in y]
    k = len(support)
    gram = [
        [sum(phi_f[i][support[a]] * phi_f[i][support[b]] for i in range(len(y))) for b in range(k)]
        for a in range(k)
    ]
    rhs = [sum(phi_f[i][support[a]] * y_f[i] for i in range(len(y))) for a in range(k)]
    coeff_f = solve_linear(gram, rhs)
    coeff_q = [quantize_float(value) for value in coeff_f]
    x = [0] * n_size
    for idx, coeff in zip(support, coeff_q):
        x[idx] = coeff
    residual = []
    for i, y_value in enumerate(y):
        acc = sum(phi[i][support[pos]] * coeff_q[pos] for pos in range(k))
        residual.append(sat_s24(y_value - (acc >> Q)))
    return x, residual


def run_mp(phi: list[list[int]], y: list[int], n_size: int, k_size: int, scale_q: int) -> list[tuple[list[int], list[int], list[int]]]:
    x = [0] * n_size
    residual = list(y)
    support = []
    trace = []
    den = (((scale_q * scale_q) + (1 << (Q - 1))) >> Q) * len(y)
    for _ in range(k_size):
        scores = corr_scores(phi, residual, n_size)
        idx = reduce_pick(scores)
        support.append(idx)
        alpha = sat_s24(div_round(scores[idx] << Q, den or 1))
        x[idx] = sat_s24(x[idx] + alpha)
        for i in range(len(residual)):
            residual[i] = sat_s24(residual[i] - ((phi[i][idx] * alpha) >> Q))
        trace.append((list(support), list(x), list(residual)))
    return trace


def run_gp(phi: list[list[int]], y: list[int], n_size: int, k_size: int, iters: int) -> list[tuple[list[int], list[int], list[int]]]:
    x = [0] * n_size
    residual = list(y)
    trace = []
    for _ in range(iters):
        scores = corr_scores(phi, residual, n_size)
        x = [sat_s24(x[j] + scores[j]) for j in range(n_size)]
        selected = set()
        pick_order = []
        for _rank in range(k_size):
            idx = reduce_pick(x, selected)
            selected.add(idx)
            pick_order.append(idx)
        support = sorted(pick_order)
        x, residual = ls_fit_quantized(phi, y, support, n_size)
        trace.append((list(support), list(x), list(residual)))
    return trace


def replace_func_assignments(text: str, fname: str, updates: dict[int, str]) -> str:
    func_re = re.compile(rf"function\s+(?:integer|\[[^\]]+\])\s+{fname};(?P<body>.*?)endfunction", re.S)
    m = func_re.search(text)
    if not m:
        raise ValueError(f"missing function {fname}")
    body_start, body_end = m.start("body"), m.end("body")
    body = m.group("body")
    assign_re = re.compile(rf"(?m)^(\s*)(\d+)\s*:\s*{fname}\s*=\s*[^;]+;")
    existing = {int(mm.group(2)): (body_start + mm.start(), body_start + mm.end(), mm.group(1)) for mm in assign_re.finditer(body)}
    replacements = []
    missing = []
    for key in sorted(updates):
        value = updates[key]
        if key in existing:
            start, end, indent = existing[key]
            replacements.append((start, end, f"{indent}{key}: {fname} = {value};"))
        elif value not in {"0", "10'd0", "24'h000000"}:
            missing.append(f"  {key}: {fname} = {value};")
    for start, end, value in sorted(replacements, reverse=True):
        text = text[:start] + value + text[end:]
    if missing:
        m2 = func_re.search(text)
        body2 = m2.group("body")
        default = re.search(rf"(?m)^\s*default\s*:\s*{fname}\s*=", body2)
        if not default:
            raise ValueError(f"missing default in {fname}")
        insert_at = m2.start("body") + default.start()
        text = text[:insert_at] + "\n".join(missing) + "\n" + text[insert_at:]
    return text


def replace_array_assignments(text: str, mem_name: str, updates: dict[int, str]) -> str:
    assign_re = re.compile(rf"(?m)^(\s*){mem_name}\[(\d+)\]\s*=\s*[^;]+;")
    existing = {int(mm.group(2)): (mm.start(), mm.end(), mm.group(1)) for mm in assign_re.finditer(text)}
    replacements = []
    missing = []
    for key in sorted(updates):
        value = updates[key]
        if key in existing:
            start, end, indent = existing[key]
            replacements.append((start, end, f"{indent}{mem_name}[{key}] = {value};"))
        elif value not in {"0", "10'd0", "24'h000000"}:
            missing.append(f"  {mem_name}[{key}] = {value};")
    for start, end, value in sorted(replacements, reverse=True):
        text = text[:start] + value + text[end:]
    if missing:
        init = re.search(r"initial\s+begin(?P<body>.*?)^end\s*$", text, re.S | re.M)
        if not init:
            raise ValueError(f"missing initial block for {mem_name}")
        insert_at = init.end("body")
        text = text[:insert_at] + "\n".join(missing) + "\n" + text[insert_at:]
    return text


def build_updates(trace: list[tuple[list[int], list[int], list[int]]], alg_idx: int, max_iters: int, max_k: int, max_n: int, m_size: int) -> dict[str, dict[int, str]]:
    out = {
        "gold_support_len": {},
        "gold_support_idx": {},
        "gold_iter_x_hat": {},
        "gold_iter_residual": {},
    }
    for it, (support, x, residual) in enumerate(trace):
        iter_base = alg_idx * max_iters + it
        out["gold_support_len"][iter_base] = str(len(support))
        supp_base = (alg_idx * max_iters + it) * max_k
        for rank in range(max_k):
            value = support[rank] if rank < len(support) else 0
            out["gold_support_idx"][supp_base + rank] = dec10(value)
        vec_base = (alg_idx * max_iters + it) * max_n
        for idx in range(max_n):
            out["gold_iter_x_hat"][vec_base + idx] = hex24(x[idx] if idx < len(x) else 0)
            out["gold_iter_residual"][vec_base + idx] = hex24(residual[idx] if idx < m_size else 0)
    return out


def merge_updates(*items: dict[str, dict[int, str]]) -> dict[str, dict[int, str]]:
    merged = {"gold_support_len": {}, "gold_support_idx": {}, "gold_iter_x_hat": {}, "gold_iter_residual": {}}
    for item in items:
        for name, updates in item.items():
            merged[name].update(updates)
    return merged


def main() -> None:
    text = FUNC_GOLDEN.read_text(errors="ignore")
    m_size = parse_int_param(text, "GOLD_CASE_0_M")
    n_size = parse_int_param(text, "GOLD_CASE_0_N")
    k_size = parse_int_param(text, "GOLD_CASE_0_K")
    max_n = parse_int_param(text, "GOLD_MAX_N")
    max_k = parse_int_param(text, "GOLD_MAX_K")
    max_iters = parse_int_param(text, "GOLD_MAX_ITERS")
    if (m_size, n_size, k_size, max_n, max_k, max_iters) != (64, 256, 16, 256, 32, 16):
        raise ValueError("this script is scoped to the M64/N256/K16 frozen golden")
    seed = parse_case_int(text, "gold_case_seed", 0)
    scale_q = parse_case_hex(text, "gold_case_scale", 0)
    y_map = parse_hex_func(text, "gold_y")
    y = [y_map.get(i, 0) for i in range(m_size)]
    phi = make_phi(m_size, n_size, seed, scale_q)

    mp_trace = run_mp(phi, y, n_size, k_size, scale_q)
    gp_trace = run_gp(phi, y, n_size, k_size, max_iters)
    updates = merge_updates(
        build_updates(gp_trace, ALG_GP, max_iters, max_k, max_n, m_size),
        build_updates(mp_trace, ALG_MP, max_iters, max_k, max_n, m_size),
    )

    new_text = text
    for fname, fname_updates in updates.items():
        new_text = replace_func_assignments(new_text, fname, fname_updates)
    FUNC_GOLDEN.write_text(new_text, newline="\n")

    array_text = ARRAY_GOLDEN.read_text(errors="ignore")
    mem_map = {
        "gold_support_len": "gold_support_len_mem",
        "gold_support_idx": "gold_support_idx_mem",
        "gold_iter_x_hat": "gold_iter_x_hat_mem",
        "gold_iter_residual": "gold_iter_residual_mem",
    }
    for fname, mem_name in mem_map.items():
        array_text = replace_array_assignments(array_text, mem_name, updates[fname])
    ARRAY_GOLDEN.write_text(array_text, newline="\n")

    for dst in SYNC_FUNC:
        shutil.copyfile(FUNC_GOLDEN, dst)
    for dst in SYNC_ARRAY:
        shutil.copyfile(ARRAY_GOLDEN, dst)

    print("MP support final:", mp_trace[-1][0])
    print("GP support final:", gp_trace[-1][0])
    print("updated", FUNC_GOLDEN)
    print("updated", ARRAY_GOLDEN)


if __name__ == "__main__":
    main()
