import argparse
import csv
import json
import math
from pathlib import Path
from statistics import mean, pstdev

OUT = Path(r"D:\vivado_pj\analysis\fair_quality_monte_carlo")
Q = 16
N = 256
M = 64
K = 8
SCALE_Q = 0x4000
TAPS = 0x80200003
PHI_SEED = 0xDEADBEEF
BASE_X_SEED = 20260711
BASE_NOISE_SEED = 2026071101
MU_SHIFT = 3
ALGORITHMS = ["OMP", "GOMP", "CoSaMP", "SP", "IHT", "HTP", "GP", "MP"]
IHT_ITERS = 2 * K
HTP_ITERS = 4 * K
GP_ITERS = 2 * K
MP_ITERS = 4 * K
COSAMP_ITERS = K
SP_ITERS = K
GOMP_GROUP = 2
MASK24 = (1 << 24) - 1
EPS = 1e-18


def s24(v):
    v = int(v) & MASK24
    return v - (1 << 24) if v & (1 << 23) else v


def sat_s24(v):
    return max(-0x800000, min(0x7FFFFF, int(round(v))))


def q24(v):
    return sat_s24(float(v) * (1 << Q))


def f24(v):
    return s24(v) / float(1 << Q)


def lfsr_step(st):
    shifted = (st >> 1) & 0x7FFFFFFF
    return ((shifted ^ TAPS) & 0xFFFFFFFF) if (st & 1) else shifted


def lfsr_advance(st, n):
    for _ in range(n):
        st = lfsr_step(st)
    return st & 0xFFFFFFFF


class Lcg:
    def __init__(self, seed):
        self.state = seed & 0xFFFFFFFF

    def rand(self):
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return self.state / 4294967296.0

    def randn(self):
        u1 = max(self.rand(), 1e-12)
        u2 = self.rand()
        return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def norm2(v):
    return dot(v, v)


def norm(v):
    return math.sqrt(norm2(v))


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


def add_noise(y_clean_q, snr_db, noise_seed):
    y = [f24(v) for v in y_clean_q]
    rng = Lcg(noise_seed)
    signal_power = norm2(y) / M
    noise_power = signal_power / (10.0 ** (snr_db / 10.0))
    sigma = math.sqrt(noise_power)
    return [q24(v + sigma * rng.randn()) for v in y]


def mat_vec(A, x):
    return [sum(row[j] * x[j] for j in range(N)) for row in A]


def residual(A, y, x):
    Ax = mat_vec(A, x)
    return [y[i] - Ax[i] for i in range(M)]


def trans_corr(A, r):
    return [sum(A[i][j] * r[i] for i in range(M)) for j in range(N)]


def top_abs(v, count, exclude=None):
    excluded = set() if exclude is None else set(exclude)
    order = [i for i in range(len(v)) if i not in excluded]
    order.sort(key=lambda i: (-abs(v[i]), i))
    return order[:count]


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


def best_update(x, r, best_x, best_norm):
    rn = norm(r)
    return (list(x), rn) if rn < best_norm else (best_x, best_norm)


def run_omp(A, y):
    S, x, r = [], [0.0] * N, list(y)
    for _ in range(K):
        S += top_abs(trans_corr(A, r), 1, S)
        x = ls_fit(A, y, S)
        r = residual(A, y, x)
    return x


def run_gomp(A, y):
    S, x, r = [], [0.0] * N, list(y)
    while len(S) < K:
        S += top_abs(trans_corr(A, r), min(GOMP_GROUP, K - len(S)), S)
        x = ls_fit(A, y, S)
        r = residual(A, y, x)
    return x


def run_cosamp(A, y):
    S, x, r = [], [0.0] * N, list(y)
    bx, bn = list(x), norm(r)
    for _ in range(COSAMP_ITERS):
        omega = top_abs(trans_corr(A, r), 2 * K)
        T = sorted(dict.fromkeys(S + omega))
        tmp = ls_fit(A, y, T)
        S = prune(tmp, K)
        x = ls_fit(A, y, S)
        r = residual(A, y, x)
        bx, bn = best_update(x, r, bx, bn)
    return bx


def run_sp(A, y):
    S = top_abs(trans_corr(A, y), K)
    x = ls_fit(A, y, S)
    r = residual(A, y, x)
    bx, bn = list(x), norm(r)
    for _ in range(SP_ITERS):
        T = sorted(dict.fromkeys(S + top_abs(trans_corr(A, r), K, S)))
        tmp = ls_fit(A, y, T)
        NS = prune(tmp, K)
        nx = ls_fit(A, y, NS)
        nr = residual(A, y, nx)
        if norm(nr) <= norm(r):
            S, x, r = NS, nx, nr
        bx, bn = best_update(x, r, bx, bn)
    return bx


def run_iht(A, y):
    x, r = [0.0] * N, list(y)
    bx, bn = list(x), norm(r)
    mu = 1.0 / (1 << MU_SHIFT)
    for _ in range(IHT_ITERS):
        c = trans_corr(A, r)
        z = [v + mu * c[i] for i, v in enumerate(x)]
        S = prune(z, K)
        x = [0.0] * N
        for j in S:
            x[j] = z[j]
        r = residual(A, y, x)
        bx, bn = best_update(x, r, bx, bn)
    return bx


def run_htp(A, y):
    x, r = [0.0] * N, list(y)
    bx, bn = list(x), norm(r)
    mu = 1.0 / (1 << MU_SHIFT)
    for _ in range(HTP_ITERS):
        c = trans_corr(A, r)
        z = [v + mu * c[i] for i, v in enumerate(x)]
        x = ls_fit(A, y, prune(z, K))
        r = residual(A, y, x)
        bx, bn = best_update(x, r, bx, bn)
    return bx


def run_gp(A, y):
    # Algorithm-level mirror of the RTL GP context: select/append one candidate, gradient step, prune, residual.
    x, r, support = [0.0] * N, list(y), []
    bx, bn = list(x), norm(r)
    mu = 1.0 / (1 << MU_SHIFT)
    for _ in range(GP_ITERS):
        corr = trans_corr(A, r)
        pick = top_abs(corr, 1, support)
        if pick:
            support += pick
        z = [v + mu * corr[i] for i, v in enumerate(x)]
        S = prune(z, K)
        support = list(dict.fromkeys(support + S))[:K]
        x = [0.0] * N
        for j in S:
            x[j] = z[j]
        r = residual(A, y, x)
        bx, bn = best_update(x, r, bx, bn)
    return bx


def run_mp(A, y):
    col_norm = [sum(A[i][j] * A[i][j] for i in range(M)) for j in range(N)]
    x, r = [0.0] * N, list(y)
    bx, bn = list(x), norm(r)
    for _ in range(MP_ITERS):
        c = trans_corr(A, r)
        score = [c[i] / max(col_norm[i], EPS) for i in range(N)]
        j = top_abs(score, 1)[0]
        if col_norm[j] > EPS:
            x[j] += c[j] / col_norm[j]
        r = residual(A, y, x)
        bx, bn = best_update(x, r, bx, bn)
    return bx


RUNNERS = {
    "OMP": run_omp,
    "GOMP": run_gomp,
    "CoSaMP": run_cosamp,
    "SP": run_sp,
    "IHT": run_iht,
    "HTP": run_htp,
    "GP": run_gp,
    "MP": run_mp,
}


def metrics(x_true, x_hat, true_support):
    err = [x_true[i] - x_hat[i] for i in range(N)]
    signal_energy = max(norm2(x_true), EPS)
    err_energy = max(norm2(err), EPS)
    mse = err_energy / N
    nmse = err_energy / signal_energy
    snr = 10.0 * math.log10(signal_energy / err_energy)
    est_support = set(top_abs(x_hat, K))
    true_set = set(true_support)
    overlap = len(true_set & est_support)
    exact = int(est_support == true_set)
    success = int(exact and nmse <= 1e-2)
    return mse, nmse, snr, overlap, exact, success


def summarize(rows):
    out = []
    for snr_db in sorted({r["noise_snr_db"] for r in rows}):
        for alg in ALGORITHMS:
            sub = [r for r in rows if r["noise_snr_db"] == snr_db and r["algorithm"] == alg]
            out.append({
                "noise_snr_db": snr_db,
                "algorithm": alg,
                "trials": len(sub),
                "snr_mean_db": mean(r["snr_db"] for r in sub),
                "snr_std_db": pstdev(r["snr_db"] for r in sub),
                "mse_mean": mean(r["mse"] for r in sub),
                "nmse_mean": mean(r["nmse"] for r in sub),
                "support_overlap_mean": mean(r["support_overlap"] for r in sub),
                "support_exact_rate": mean(r["support_exact"] for r in sub),
                "success_rate": mean(r["success"] for r in sub),
            })
    return out


def write_outputs(rows, summary, snrs, trials):
    OUT.mkdir(parents=True, exist_ok=True)
    raw_csv = OUT / "fair_monte_carlo_raw.csv"
    with raw_csv.open("w", newline="") as f:
        fields = ["trial", "x_seed", "noise_seed", "noise_snr_db", "algorithm", "mse", "nmse", "snr_db", "support_overlap", "support_exact", "success"]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    summary_csv = OUT / "fair_monte_carlo_summary.csv"
    with summary_csv.open("w", newline="") as f:
        fields = ["noise_snr_db", "algorithm", "trials", "snr_mean_db", "snr_std_db", "mse_mean", "nmse_mean", "support_overlap_mean", "support_exact_rate", "success_rate"]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in summary:
            w.writerow({k: (f"{v:.8g}" if isinstance(v, float) else v) for k, v in r.items()})
    data_json = OUT / "fair_monte_carlo_summary.json"
    data_json.write_text(json.dumps({
        "N": N,
        "M": M,
        "K": K,
        "trials_per_snr": trials,
        "noise_snr_db": snrs,
        "phi_seed_hex": f"0x{PHI_SEED:X}",
        "x_seed_base": BASE_X_SEED,
        "noise_seed_base": BASE_NOISE_SEED,
        "mu_shift": MU_SHIFT,
        "iters": {"IHT": IHT_ITERS, "HTP": HTP_ITERS, "GP": GP_ITERS, "MP": MP_ITERS, "CoSaMP": COSAMP_ITERS, "SP": SP_ITERS},
        "summary": summary,
    }, indent=2))
    md = OUT / "fair_monte_carlo_summary.md"
    lines = []
    lines.append("# Fair Monte Carlo Reconstruction Quality")
    lines.append("")
    lines.append(f"Configuration: N={N}, M={M}, K={K}, trials per SNR={trials}, Phi seed=0x{PHI_SEED:X}, mu_shift={MU_SHIFT}.")
    lines.append("Each trial uses the same sparse signal, sensing matrix, and noise realization for all algorithms.")
    lines.append("")
    for snr_db in snrs:
        lines.append(f"## Measurement SNR {snr_db} dB")
        lines.append("| Algorithm | SNR mean (dB) | SNR std (dB) | MSE mean | NMSE mean | Support overlap | Exact support | Success |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in [x for x in summary if x["noise_snr_db"] == snr_db]:
            lines.append(f"| {r['algorithm']} | {r['snr_mean_db']:.2f} | {r['snr_std_db']:.2f} | {r['mse_mean']:.3e} | {r['nmse_mean']:.3e} | {r['support_overlap_mean']:.2f}/{K} | {100*r['support_exact_rate']:.1f}% | {100*r['success_rate']:.1f}% |")
        lines.append("")
    lines.append("Paper note: do not compare algorithms using different x-seeds. Use these aggregate statistics or an equivalent common-trial Monte Carlo setup.")
    md.write_text("\n".join(lines))
    tex = OUT / "fair_monte_carlo_summary_table.tex"
    tex_lines = [
        r"\begin{table*}[!t]",
        r"\centering",
        r"\caption{Fair Monte Carlo reconstruction quality using common sparse signals, sensing matrix, and noise realizations for all algorithms.}",
        r"\label{tab:fair_mc_quality}",
        r"\footnotesize",
        r"\begin{tabular}{llrrrrr}",
        r"\toprule",
        r"Noise & Algorithm & SNR mean & SNR std & NMSE mean & Exact supp. & Success \\",
        r"\midrule",
    ]
    for snr_db in snrs:
        first = True
        for r in [x for x in summary if x["noise_snr_db"] == snr_db]:
            noise = f"{snr_db} dB" if first else ""
            first = False
            tex_lines.append(
                f"{noise} & {r['algorithm']} & {r['snr_mean_db']:.2f} & {r['snr_std_db']:.2f} & "
                f"{r['nmse_mean']:.3e} & {100*r['support_exact_rate']:.1f}\\% & "
                f"{100*r['success_rate']:.1f}\\% " + r"\\"
            )
        tex_lines.append(r"\midrule")
    tex_lines[-1] = r"\bottomrule"
    tex_lines += [r"\end{tabular}", r"\end{table*}"]
    tex.write_text("\n".join(tex_lines))
    return raw_csv, summary_csv, data_json, md, tex


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=100)
    ap.add_argument("--snrs", default="10,20,30,40")
    args = ap.parse_args()
    snrs = [int(x.strip()) for x in args.snrs.split(",") if x.strip()]
    phi_q = make_phi_q()
    A = [[v / float(1 << Q) for v in row] for row in phi_q]
    rows = []
    for snr_db in snrs:
        for trial in range(args.trials):
            x_seed = BASE_X_SEED + trial
            noise_seed = BASE_NOISE_SEED + 100000 * snr_db + trial
            true_support, x_true_q = make_signal(x_seed)
            y_clean_q = quant_mat_vec(phi_q, x_true_q)
            y_noisy_q = add_noise(y_clean_q, snr_db, noise_seed)
            x_true = [f24(v) for v in x_true_q]
            y = [f24(v) for v in y_noisy_q]
            for alg in ALGORITHMS:
                x_hat = RUNNERS[alg](A, y)
                mse, nmse, out_snr, overlap, exact, success = metrics(x_true, x_hat, true_support)
                rows.append({
                    "trial": trial,
                    "x_seed": x_seed,
                    "noise_seed": noise_seed,
                    "noise_snr_db": snr_db,
                    "algorithm": alg,
                    "mse": mse,
                    "nmse": nmse,
                    "snr_db": out_snr,
                    "support_overlap": overlap,
                    "support_exact": exact,
                    "success": success,
                })
        print(f"finished SNR={snr_db} dB, trials={args.trials}")
    summary = summarize(rows)
    outputs = write_outputs(rows, summary, snrs, args.trials)
    for path in outputs:
        print(path)


if __name__ == "__main__":
    main()
