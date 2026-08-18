import csv
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GOLD = ROOT / "models" / "golden" / "golden_cases.vh"
OUT = ROOT / "models" / "golden" / "float_vs_fixed"
OUT.mkdir(parents=True, exist_ok=True)

ALGS = ["OMP", "gOMP", "CoSaMP", "SP", "IHT", "HTP", "GP", "MP"]
ALG_IDX = {name: i for i, name in enumerate(ALGS)}
M = 64
N = 256
K = 16
MAX_K = 32
MAX_ITERS = 16
Q = 16
TAPS = 0x80200003
DEFAULT_SEED = 0xDEADBEEF

def twos_to_int(v, bits):
    v &= (1 << bits) - 1
    if v & (1 << (bits - 1)):
        v -= 1 << bits
    return v

def q24_to_float(v):
    return twos_to_int(v, 24) / float(1 << Q)

def parse_func_hex(text, fname):
    m = re.search(rf"function\s+\[[^\]]+\]\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        return {}
    body = m.group("body")
    out = {}
    for key, val in re.findall(r"\b(\d+)\s*:\s*" + re.escape(fname) + r"\s*=\s*(?:\d+)?'h([0-9a-fA-F]+)", body):
        out[int(key)] = int(val, 16)
    return out

def parse_func_dec(text, fname):
    m = re.search(rf"function\s+(?:integer|\[[^\]]+\])\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        return {}
    body = m.group("body")
    out = {}
    for key, val in re.findall(r"\b(\d+)\s*:\s*" + re.escape(fname) + r"\s*=\s*(?:\d+)?'d(\d+)|\b(\d+)\s*:\s*" + re.escape(fname) + r"\s*=\s*(\d+)", body):
        if key:
            out[int(key)] = int(val)
        else:
            out[int(key or _)] = int(val or __)
    return out

def parse_dec_cases(text, fname):
    m = re.search(rf"function\s+(?:integer|\[[^\]]+\])\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    body = m.group("body") if m else ""
    out = {}
    # supports 10'd74 and plain integer assignments
    for mm in re.finditer(r"\b(\d+)\s*:\s*" + re.escape(fname) + r"\s*=\s*(?:(\d+)'d)?(\d+)", body):
        out[int(mm.group(1))] = int(mm.group(3))
    return out

def galois_step(state):
    shifted = (state >> 1) & 0x7fffffff
    return (shifted ^ TAPS) & 0xffffffff if (state & 1) else shifted

def lfsr_advance(state, steps):
    for _ in range(steps):
        state = galois_step(state)
    return state

def make_phi(seed, scale):
    seed = seed or DEFAULT_SEED
    phi = []
    for i in range(M):
        row_state = lfsr_advance(seed, i * N)
        row = []
        for j in range(N):
            s = lfsr_advance(row_state, j + 1)
            row.append(scale if (s & 1) else -scale)
        phi.append(row)
    return phi

def dot(a, b):
    return sum(x*y for x, y in zip(a, b))

def matvec_cols(phi, support, coeff):
    return [sum(phi[i][support[t]] * coeff[t] for t in range(len(support))) for i in range(M)]

def solve_linear(a, b):
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
        for k in range(c, n+1):
            aug[c][k] /= div
        for r in range(n):
            if r == c:
                continue
            f = aug[r][c]
            if f:
                for k in range(c, n+1):
                    aug[r][k] -= f * aug[c][k]
    return [aug[i][n] for i in range(n)]

def ls_fit(phi, y, support):
    s = list(support)
    n = len(s)
    if n == 0:
        return [0.0]*N, list(y)
    gram = [[sum(phi[i][s[a]] * phi[i][s[b]] for i in range(M)) for b in range(n)] for a in range(n)]
    rhs = [sum(phi[i][s[a]] * y[i] for i in range(M)) for a in range(n)]
    coeff = solve_linear(gram, rhs)
    x = [0.0]*N
    for idx, val in zip(s, coeff):
        x[idx] = val
    pred = matvec_cols(phi, s, coeff)
    r = [y[i] - pred[i] for i in range(M)]
    return x, r

def top_indices(scores, count, exclude=None):
    exclude = set(exclude or [])
    cand = [(abs(v), -j, j) for j, v in enumerate(scores) if j not in exclude and abs(v) > 1e-15]
    cand.sort(reverse=True)
    return [j for _, __, j in cand[:count]]

def prune_topk(x, k=K):
    cand = [(abs(v), -j, j) for j, v in enumerate(x) if abs(v) > 1e-15]
    cand.sort(reverse=True)
    return [j for _, __, j in cand[:k]]

def run_float_alg(name, phi, y):
    x = [0.0]*N
    r = list(y)
    support = []
    trace = []
    for it in range(MAX_ITERS):
        corr = [sum(phi[i][j] * r[i] for i in range(M)) for j in range(N)]
        if name == "OMP":
            pick = top_indices(corr, 1, support)
            support += pick
            x, r = ls_fit(phi, y, support)
        elif name == "MP":
            pick = top_indices(corr, 1, support)
            if pick:
                j = pick[0]
                support.append(j)
                den = sum(phi[i][j]*phi[i][j] for i in range(M)) or 1.0
                alpha = corr[j] / den
                x[j] += alpha
                r = [r[i] - alpha * phi[i][j] for i in range(M)]
        elif name == "gOMP":
            picks = top_indices(corr, 2, support)
            support += picks
            x, r = ls_fit(phi, y, support)
        elif name == "CoSaMP":
            picks = top_indices(corr, 2*K)
            merged = sorted(set(support).union(picks))
            xtmp, _ = ls_fit(phi, y, merged)
            support = prune_topk(xtmp, K)
            x, r = ls_fit(phi, y, support)
        elif name == "SP":
            picks = top_indices(corr, K)
            merged = sorted(set(support).union(picks))
            xtmp, _ = ls_fit(phi, y, merged)
            support = prune_topk(xtmp, K)
            x, r = ls_fit(phi, y, support)
        elif name == "IHT":
            mu = 1.0 / (M * (0.25**2))
            z = [x[j] + mu * corr[j] for j in range(N)]
            support = prune_topk(z, K)
            x = [0.0]*N
            for j in support:
                x[j] = z[j]
            pred = [sum(phi[i][j]*x[j] for j in support) for i in range(M)]
            r = [y[i] - pred[i] for i in range(M)]
        elif name == "HTP":
            mu = 1.0 / (M * (0.25**2))
            z = [x[j] + mu * corr[j] for j in range(N)]
            support = prune_topk(z, K)
            x, r = ls_fit(phi, y, support)
        elif name == "GP":
            # lightweight GP proxy: gradient top-K support followed by gradient update on selected support
            support = prune_topk([x[j] + corr[j] for j in range(N)], K)
            x, r = ls_fit(phi, y, support)
        trace.append((list(support), list(x), list(r)))
    return trace

def mse(a, b):
    return sum((x-y)**2 for x, y in zip(a, b)) / len(a)

def nmse(a, b):
    den = sum(y*y for y in b) / len(b)
    return mse(a, b) / den if den > 0 else float('inf')

def norm2(a):
    return math.sqrt(sum(x*x for x in a))

text = GOLD.read_text(errors="ignore")
seed = int(re.search(r"0:\s*gold_case_seed\s*=\s*(\d+)", text).group(1))
scale_hex = re.search(r"0:\s*gold_case_scale\s*=\s*24'h([0-9a-fA-F]+)", text).group(1)
scale = q24_to_float(int(scale_hex, 16))
y_map = parse_func_hex(text, "gold_y")
y = [q24_to_float(y_map.get(i, 0)) for i in range(M)]
x_map = parse_func_hex(text, "gold_iter_x_hat")
r_map = parse_func_hex(text, "gold_iter_residual")
support_map = parse_dec_cases(text, "gold_support_idx")
len_map = parse_dec_cases(text, "gold_support_len")
phi = make_phi(seed, scale)

rows = []
json_out = {"M": M, "N": N, "K": K, "seed": seed, "scale": scale, "algorithms": {}}
for alg in ALGS:
    ai = ALG_IDX[alg]
    fl_trace = run_float_alg(alg, phi, y)
    alg_rows = []
    for it in range(MAX_ITERS):
        base_x = ((0 * 8 + ai) * MAX_ITERS + it) * N
        base_r = ((0 * 8 + ai) * MAX_ITERS + it) * N
        fx = [q24_to_float(x_map.get(base_x + j, 0)) for j in range(N)]
        fr = [q24_to_float(r_map.get(base_r + i, 0)) for i in range(M)]
        fs_len = len_map.get((0 * 8 + ai) * MAX_ITERS + it, 0)
        fs = [support_map.get(((0 * 8 + ai) * MAX_ITERS + it) * MAX_K + k, -1) for k in range(fs_len)]
        ss, x, r = fl_trace[it]
        ov = len(set(fs).intersection(ss))
        row = {
            "algorithm": alg,
            "iter": it,
            "fixed_support_len": len(fs),
            "float_support_len": len(ss),
            "support_overlap": ov,
            "support_jaccard": ov / len(set(fs).union(ss)) if set(fs).union(ss) else 1.0,
            "x_mse_fixed_vs_float": mse(fx, x),
            "x_nmse_fixed_vs_float": nmse(fx, x),
            "r_mse_fixed_vs_float": mse(fr, r),
            "r_nmse_fixed_vs_float": nmse(fr, r),
            "fixed_res_norm": norm2(fr),
            "float_res_norm": norm2(r),
        }
        rows.append(row)
        alg_rows.append(row)
    json_out["algorithms"][alg] = alg_rows

csv_path = OUT / "fixed_vs_float_metrics.csv"
with csv_path.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)

summary_rows = []
for alg in ALGS:
    final = [r for r in rows if r["algorithm"] == alg and r["iter"] == MAX_ITERS-1][0]
    summary_rows.append(final)

md_path = OUT / "fixed_vs_float_summary.md"
with md_path.open("w") as f:
    f.write("# Fixed-Point Golden vs Floating-Point CS Metrics\n\n")
    f.write(f"Dataset: M={M}, N={N}, K={K}, seed={seed}, phi_scale={scale}\n\n")
    f.write("Note: floating models are textbook/reference CS flows using the same Bernoulli Phi and fixed golden y; fixed values are parsed from frozen `golden_cases.vh`.\n\n")
    f.write("| algorithm | final support overlap | final support jaccard | x MSE | x NMSE | r MSE | r NMSE | fixed ||r|| | float ||r|| |\n")
    f.write("|---|---:|---:|---:|---:|---:|---:|---:|---:|\n")
    for r in summary_rows:
        f.write(f"| {r['algorithm']} | {r['support_overlap']}/{r['fixed_support_len']} | {r['support_jaccard']:.4f} | {r['x_mse_fixed_vs_float']:.6e} | {r['x_nmse_fixed_vs_float']:.6e} | {r['r_mse_fixed_vs_float']:.6e} | {r['r_nmse_fixed_vs_float']:.6e} | {r['fixed_res_norm']:.6e} | {r['float_res_norm']:.6e} |\n")

json_path = OUT / "fixed_vs_float_metrics.json"
json_path.write_text(json.dumps(json_out, indent=2))
print(csv_path)
print(md_path)
print(json_path)
print(md_path.read_text())

