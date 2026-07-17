import csv, json, math
from pathlib import Path

OUT = Path(r"D:\vivado_pj\analysis\reconstruction_quality_noisy24")
TB_OUT = Path(r"D:\vivado_pj\CSCGRA_noisy_mu\tests")
Q = 16
N = 256
M = 64
K = 16
SCALE_Q = 0x4000
TAPS = 0x80200003
PHI_SEED = 0xDEADBEEF
NOISE_SEED = 20260628
MEAS_SNR_DB = 20
MU_SHIFT = 3
ALG_SEEDS = {"OMP": 52, "GOMP": 13, "CoSaMP": 77, "SP": 48, "IHT": 66, "HTP": 20, "GP": 77, "MP": 140}
ALGORITHMS = ["OMP", "GOMP", "CoSaMP", "SP", "IHT", "HTP", "GP", "MP"]
IHT_ITERS = 4 * K
HTP_ITERS = 4 * K
GP_ITERS = 2 * K
MP_ITERS = 4 * K
COSAMP_ITERS = K
SP_ITERS = K
GOMP_GROUP = 2
MASK24 = (1 << 24) - 1

def s24(v):
    v = int(v) & MASK24
    return v - (1 << 24) if v & (1 << 23) else v

def sat_s24(v):
    return max(-0x800000, min(0x7fffff, int(round(v))))

def q24(v):
    return sat_s24(float(v) * (1 << Q))

def f24(v):
    return s24(v) / float(1 << Q)

def lfsr_step(st):
    shifted = (st >> 1) & 0x7fffffff
    return ((shifted ^ TAPS) & 0xffffffff) if (st & 1) else shifted

def lfsr_advance(st, n):
    for _ in range(n):
        st = lfsr_step(st)
    return st & 0xffffffff

class Lcg:
    def __init__(self, seed):
        self.state = seed & 0xffffffff
    def rand(self):
        self.state = (1664525 * self.state + 1013904223) & 0xffffffff
        return self.state / 4294967296.0
    def randn(self):
        u1 = max(self.rand(), 1e-12)
        u2 = self.rand()
        return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)

def dot(a, b):
    return sum(x * y for x, y in zip(a, b))

def norm(v):
    return math.sqrt(dot(v, v))

def mat_vec(A, x):
    return [dot(row, x) for row in A]

def sub(a, b):
    return [x - y for x, y in zip(a, b)]

def trans_corr(A, r):
    return [sum(A[i][j] * r[i] for i in range(M)) for j in range(N)]

def top_abs(v, count, exclude=None):
    excluded = set() if exclude is None else set(exclude)
    order = [i for i in range(len(v)) if i not in excluded]
    order.sort(key=lambda i: (-abs(v[i]), i))
    return order[:count]

def make_phi_q():
    phi = []
    for row in range(M):
        row_state = lfsr_advance(PHI_SEED, row * N)
        phi.append([SCALE_Q if (lfsr_advance(row_state, col + 1) & 1) else -SCALE_Q for col in range(N)])
    return phi

def make_signal(seed):
    rng = Lcg(seed)
    idx = list(range(N))
    for i in range(N - 1, 0, -1):
        j = int(math.floor(rng.rand() * (i + 1)))
        idx[i], idx[j] = idx[j], idx[i]
    support = sorted(idx[:K])
    x = [0.0] * N
    for j in support:
        x[j] = (0.35 + 0.65 * rng.rand()) * (-1.0 if rng.rand() < 0.5 else 1.0)
    return support, [q24(v) for v in x]

def quant_mat_vec(phi_q, x_q):
    y = []
    for i in range(M):
        acc = sum(int(phi_q[i][j]) * int(x_q[j]) for j in range(N))
        y.append(sat_s24(acc >> Q))
    return y

def add_noise(y_clean_q):
    y = [f24(v) for v in y_clean_q]
    rng = Lcg(NOISE_SEED)
    signal_power = dot(y, y) / M
    noise_power = signal_power / (10.0 ** (MEAS_SNR_DB / 10.0))
    sigma = math.sqrt(noise_power)
    return [q24(v + sigma * rng.randn()) for v in y]

def solve_linear(G, b):
    n = len(b)
    aug = [list(G[i]) + [b[i]] for i in range(n)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if abs(aug[pivot][col]) < 1e-12:
            continue
        if pivot != col:
            aug[col], aug[pivot] = aug[pivot], aug[col]
        div = aug[col][col]
        for k in range(col, n + 1):
            aug[col][k] /= div
        for r in range(n):
            if r == col:
                continue
            fac = aug[r][col]
            if fac:
                for k in range(col, n + 1):
                    aug[r][k] -= fac * aug[col][k]
    return [row[n] if math.isfinite(row[n]) else 0.0 for row in aug]

def ls_fit(A, y, support):
    support = list(dict.fromkeys(support))
    x = [0.0] * N
    if not support:
        return x
    k = len(support)
    G = [[sum(A[i][support[a]] * A[i][support[b]] for i in range(M)) for b in range(k)] for a in range(k)]
    rhs = [sum(A[i][support[a]] * y[i] for i in range(M)) for a in range(k)]
    coeff = solve_linear(G, rhs)
    for j, v in zip(support, coeff):
        x[j] = v
    return x

def prune(x, k=K):
    return top_abs(x, k)

def residual(A, y, x):
    return sub(y, mat_vec(A, x))

def best_update(x, r, best_x, best_norm):
    rnorm = norm(r)
    return (list(x), rnorm) if rnorm < best_norm else (best_x, best_norm)

def run_omp(A, y):
    support = []
    x = [0.0] * N
    r = list(y)
    for _ in range(K):
        support += top_abs(trans_corr(A, r), 1, support)
        x = ls_fit(A, y, support)
        r = residual(A, y, x)
    return x

def run_gomp(A, y):
    support = []
    x = [0.0] * N
    r = list(y)
    while len(support) < K:
        support += top_abs(trans_corr(A, r), min(GOMP_GROUP, K - len(support)), support)
        x = ls_fit(A, y, support)
        r = residual(A, y, x)
    return x

def run_cosamp(A, y):
    support = []
    x = [0.0] * N
    r = list(y)
    best_x = list(x)
    best_norm = norm(r)
    for _ in range(COSAMP_ITERS):
        omega = top_abs(trans_corr(A, r), 2 * K)
        temp = ls_fit(A, y, sorted(set(support).union(omega)))
        support = prune(temp, K)
        x = ls_fit(A, y, support)
        r = residual(A, y, x)
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x

def run_sp(A, y):
    support = top_abs(trans_corr(A, y), K)
    x = ls_fit(A, y, support)
    r = residual(A, y, x)
    best_x = list(x)
    best_norm = norm(r)
    for _ in range(SP_ITERS):
        temp = ls_fit(A, y, sorted(set(support).union(top_abs(trans_corr(A, r), K, support))))
        next_support = prune(temp, K)
        next_x = ls_fit(A, y, next_support)
        next_r = residual(A, y, next_x)
        if norm(next_r) <= norm(r):
            support, x, r = next_support, next_x, next_r
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x

def run_iht(A, y):
    x = [0.0] * N
    r = list(y)
    best_x = list(x)
    best_norm = norm(r)
    mu = 1.0 / (1 << MU_SHIFT)
    for _ in range(IHT_ITERS):
        corr = trans_corr(A, r)
        z = [v + mu * corr[i] for i, v in enumerate(x)]
        support = prune(z, K)
        x = [0.0] * N
        for j in support:
            x[j] = z[j]
        r = residual(A, y, x)
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x

def run_htp(A, y):
    x = [0.0] * N
    r = list(y)
    best_x = list(x)
    best_norm = norm(r)
    mu = 1.0 / (1 << MU_SHIFT)
    for _ in range(HTP_ITERS):
        corr = trans_corr(A, r)
        z = [v + mu * corr[i] for i, v in enumerate(x)]
        x = ls_fit(A, y, prune(z, K))
        r = residual(A, y, x)
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x

def run_gp(A, y):
    support = []
    x = [0.0] * N
    r = list(y)
    best_x = list(x)
    best_norm = norm(r)
    for _ in range(GP_ITERS):
        pick = top_abs(trans_corr(A, r), 1, support)
        if not pick:
            break
        support = sorted(set(support).union(pick))
        if len(support) > K:
            support = prune(ls_fit(A, y, support), K)
        x = ls_fit(A, y, support)
        r = residual(A, y, x)
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x

def run_mp(A, y):
    col_norm = [sum(A[i][j] * A[i][j] for i in range(M)) for j in range(N)]
    x = [0.0] * N
    r = list(y)
    best_x = list(x)
    best_norm = norm(r)
    for _ in range(MP_ITERS):
        corr = trans_corr(A, r)
        scores = [corr[i] / max(col_norm[i], 1e-18) for i in range(N)]
        atom = top_abs(scores, 1)[0]
        if col_norm[atom] > 1e-18:
            x[atom] += corr[atom] / col_norm[atom]
        r = residual(A, y, x)
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x

def run_algorithm(name, A, y):
    return {"OMP": run_omp, "GOMP": run_gomp, "CoSaMP": run_cosamp, "SP": run_sp, "IHT": run_iht, "HTP": run_htp, "GP": run_gp, "MP": run_mp}[name](A, y)

def metrics(x_true, x_hat):
    err = [x_true[i] - x_hat[i] for i in range(N)]
    mse = dot(err, err) / N
    snr = 10.0 * math.log10(dot(x_true, x_true) / dot(err, err))
    true_support = {i for i, v in enumerate(x_true) if abs(v) > 1e-8}
    est_support = {i for i, v in enumerate(x_hat) if abs(v) > 1e-8}
    return mse, snr, len(true_support.intersection(est_support))

def fmt_exp(v):
    mantissa, exponent = ("%.3e" % v).split("e")
    return "%s\\times10^{%d}" % (mantissa, int(exponent))

def vh_int_array(name, values):
    body = ", ".join(str(int(v)) for v in values)
    return f"localparam signed [23:0] {name} [0:{len(values)-1}] = '{{{body}}};"

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    TB_OUT.mkdir(parents=True, exist_ok=True)
    phi_q = make_phi_q()
    A = [[v / float(1 << Q) for v in row] for row in phi_q]
    rows = []
    data = {"N": N, "M": M, "K": K, "q_fraction_bits": Q, "phi_seed_hex": "0x%X" % PHI_SEED,
            "phi_scale_q_hex": "0x%X" % SCALE_Q, "noise_seed": NOISE_SEED,
            "measurement_snr_db": MEAS_SNR_DB, "mu_shift": MU_SHIFT,
            "iters": {"IHT": IHT_ITERS, "HTP": HTP_ITERS, "GP": GP_ITERS, "MP": MP_ITERS, "CoSaMP": COSAMP_ITERS, "SP": SP_ITERS},
            "algorithms": {}}
    for alg in ALGORITHMS:
        seed = ALG_SEEDS[alg]
        support, x_true_q = make_signal(seed)
        y_clean_q = quant_mat_vec(phi_q, x_true_q)
        y_noisy_q = add_noise(y_clean_q)
        x_true = [f24(v) for v in x_true_q]
        y = [f24(v) for v in y_noisy_q]
        x_hat_q = [q24(v) for v in run_algorithm(alg, A, y)]
        x_hat = [f24(v) for v in x_hat_q]
        mse, snr, overlap = metrics(x_true, x_hat)
        rows.append({"algorithm": alg, "seed": seed, "mse": mse, "snr": snr, "overlap": overlap})
        data["algorithms"][alg] = {"x_seed": seed, "true_support": support, "mse": mse, "snr_db": snr,
                                    "support_overlap": "%d/%d" % (overlap, K), "x_true_q24": x_true_q,
                                    "y_clean_q24": y_clean_q, "y_noisy_q24": y_noisy_q, "x_hat_q24": x_hat_q}
    with (OUT / "noisy_lfsr_24bit_per_algorithm_seed_python.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["algorithm", "x_seed", "measurement_snr_db", "mu_shift", "mse", "snr_db", "support_overlap"])
        for r in rows:
            writer.writerow([r["algorithm"], r["seed"], MEAS_SNR_DB, MU_SHIFT, "%.10e" % r["mse"], "%.4f" % r["snr"], "%d/%d" % (r["overlap"], K)])
    with (OUT / "noisy_lfsr_24bit_per_algorithm_seed_python.json").open("w") as f:
        json.dump(data, f, indent=2)
    tex = [r"\begin{table}[!t]", r"\centering",
           r"\caption{Representative reconstruction quality for $(N,M,K)=(256,64,16)$ using 24-bit fixed-point arithmetic and 20-dB measurement noise. Each algorithm uses its own listed signal seed.}",
           r"\label{tab:reconstruction_quality_rep}", r"\begin{tabular}{lcccc}", r"\hline",
           "Algorithm & Seed & MSE & SNR (dB) & Support overlap \\\", r"\\hline"]
    for r in rows:
        tex.append("{} & {} & ${}$ & {:.2f} & {}/{} \\\".format(r["algorithm"], r["seed"], fmt_exp(r["mse"]), r["snr"], r["overlap"], K))
    tex += [r"\hline", r"\end{tabular}", r"\end{table}", ""]
    (OUT / "noisy_lfsr_24bit_per_algorithm_seed_python_table.tex").write_text("\n".join(tex))
    vh = ["// Auto-generated by noisy_lfsr_24bit_benchmark.py", "// N=256 M=64 K=16, 24-bit fixed point, 20-dB measurement noise", "localparam integer NOISY_CASES = 8;", ""]
    for case_idx, alg in enumerate(ALGORITHMS):
        d = data["algorithms"][alg]
        prefix = f"NOISY_{alg.upper()}"
        vh.append(f"localparam integer {prefix}_CASE = {case_idx};")
        vh.append(f"localparam integer {prefix}_SEED = {d['x_seed']};")
        vh.append(vh_int_array(f"{prefix}_Y", d["y_noisy_q24"]))
        vh.append(vh_int_array(f"{prefix}_XHAT", d["x_hat_q24"]))
        vh.append("")
    (TB_OUT / "noisy_lfsr_24bit_cases.vh").write_text("\n".join(vh))
    for r in rows:
        print("%-6s seed=%d mse=%.6e snr=%.2fdB overlap=%d/%d" % (r["algorithm"], r["seed"], r["mse"], r["snr"], r["overlap"], K))

if __name__ == "__main__":
    main()
