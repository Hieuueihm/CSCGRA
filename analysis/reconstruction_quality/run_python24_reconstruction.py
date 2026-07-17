import csv
import math
from pathlib import Path

import numpy as np

ROOT = Path(r"D:\vivado_pj")
OUT = ROOT / "analysis" / "reconstruction_quality"
Q = 16
DATA_MASK = (1 << 24) - 1
TAPS = 0x80200003
DEFAULT_SEED = 0xDEADBEEF
N = 256
M = 64
K = 16
SCALE_Q = 0x4000
X_SEED = 20260627


def s24(value):
    value = int(value) & DATA_MASK
    return value - (1 << 24) if value & (1 << 23) else value


def sat_s24(value):
    value = int(value)
    return max(-0x800000, min(0x7FFFFF, value))


def q24(value):
    return sat_s24(round(float(value) * (1 << Q)))


def f24(value):
    return s24(value) / float(1 << Q)


def galois_step(state):
    shifted = (state >> 1) & 0x7FFFFFFF
    if state & 1:
        return (shifted ^ TAPS) & 0xFFFFFFFF
    return shifted


def lfsr_advance(state, steps):
    for _ in range(steps):
        state = galois_step(state)
    return state


def make_phi_q(m_size=M, n_size=N, seed=DEFAULT_SEED, scale_q=SCALE_Q):
    phi = np.zeros((m_size, n_size), dtype=np.int64)
    for row_idx in range(m_size):
        row_state = lfsr_advance(seed, row_idx * n_size)
        for col_idx in range(n_size):
            state = lfsr_advance(row_state, col_idx + 1)
            phi[row_idx, col_idx] = scale_q if state & 1 else -scale_q
    return phi


def quant_matvec(phi_q, x_q):
    y_values = []
    for row_idx in range(phi_q.shape[0]):
        acc = int(np.dot(phi_q[row_idx, :].astype(object), x_q.astype(object)))
        y_values.append(sat_s24(acc >> Q))
    return np.array(y_values, dtype=np.int64)


def top_abs(values, count, exclude=None):
    excluded = set() if exclude is None else set(exclude)
    order = sorted(
        [idx for idx in range(len(values)) if idx not in excluded],
        key=lambda idx: (-abs(values[idx]), idx),
    )
    return order[:count]


def ls_fit(matrix, y_values, support):
    x_values = np.zeros(matrix.shape[1])
    support = list(dict.fromkeys(support))
    if not support:
        return x_values
    coeff, *_ = np.linalg.lstsq(matrix[:, support], y_values, rcond=None)
    x_values[support] = coeff
    return x_values


def prune_topk(x_values, k_size):
    return top_abs(x_values, k_size)


def run_algorithm(name, matrix, y_values, k_size):
    n_size = matrix.shape[1]
    x_values = np.zeros(n_size)
    residual = y_values.copy()
    support = []
    col_norm2 = np.sum(matrix * matrix, axis=0)
    lipschitz = np.linalg.norm(matrix, 2) ** 2
    mu = 0.95 / lipschitz if lipschitz > 0 else 1.0

    for _ in range(k_size):
        corr = matrix.T @ residual
        if name == "OMP":
            support += top_abs(corr, 1, support)
            x_values = ls_fit(matrix, y_values, support)
            support = [idx for idx in range(n_size) if abs(x_values[idx]) > 1e-12]
            residual = y_values - matrix @ x_values
        elif name == "GOMP":
            support += top_abs(corr, 2, support)
            if len(support) > k_size:
                support = prune_topk(ls_fit(matrix, y_values, support), k_size)
            x_values = ls_fit(matrix, y_values, support)
            residual = y_values - matrix @ x_values
        elif name == "CoSaMP":
            omega = top_abs(corr, 2 * k_size)
            merged = sorted(set(support).union(omega))
            estimate = ls_fit(matrix, y_values, merged)
            support = prune_topk(estimate, k_size)
            x_values = ls_fit(matrix, y_values, support)
            residual = y_values - matrix @ x_values
        elif name == "SP":
            omega = top_abs(corr, k_size, support)
            merged = sorted(set(support).union(omega))
            estimate = ls_fit(matrix, y_values, merged)
            next_support = prune_topk(estimate, k_size)
            next_x = ls_fit(matrix, y_values, next_support)
            next_residual = y_values - matrix @ next_x
            if np.linalg.norm(next_residual) <= np.linalg.norm(residual) or not support:
                support, x_values, residual = next_support, next_x, next_residual
        elif name == "IHT":
            z_values = x_values + mu * corr
            support = prune_topk(z_values, k_size)
            x_values = np.zeros(n_size)
            x_values[support] = z_values[support]
            residual = y_values - matrix @ x_values
        elif name == "HTP":
            z_values = x_values + mu * corr
            support = prune_topk(z_values, k_size)
            x_values = ls_fit(matrix, y_values, support)
            residual = y_values - matrix @ x_values
        elif name == "GP":
            atom_idx = top_abs(corr, 1)[0]
            direction = np.zeros(n_size)
            direction[atom_idx] = corr[atom_idx]
            projected = matrix @ direction
            denom = projected @ projected
            alpha = float((residual @ projected) / denom) if denom > 1e-18 else 0.0
            x_values = x_values + alpha * direction
            support = sorted(set(support).union([atom_idx]))
            if len(support) > k_size:
                support = prune_topk(x_values, k_size)
                x_values = ls_fit(matrix, y_values, support)
            residual = y_values - matrix @ x_values
        elif name == "MP":
            atom_idx = top_abs(corr / np.maximum(col_norm2, 1e-18), 1)[0]
            alpha = corr[atom_idx] / col_norm2[atom_idx] if col_norm2[atom_idx] > 1e-18 else 0.0
            x_values[atom_idx] += alpha
            residual = y_values - matrix @ x_values
    return x_values


def metrics(x_true, x_hat):
    error = x_true - x_hat
    mse = float(np.mean(error * error))
    signal_energy = float(np.sum(x_true * x_true))
    error_energy = float(np.sum(error * error))
    snr_db = 10 * math.log10(signal_energy / error_energy) if error_energy > 0 else float("inf")
    true_support = set(np.flatnonzero(abs(x_true) > 1e-12))
    est_support = set(np.flatnonzero(abs(x_hat) > 1e-8))
    return mse, snr_db, len(true_support.intersection(est_support))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    phi_q = make_phi_q()
    matrix = phi_q.astype(float) / (1 << Q)
    rng = np.random.default_rng(X_SEED)
    support = np.sort(rng.choice(N, K, replace=False))
    x_true = np.zeros(N)
    amplitudes = rng.uniform(0.35, 1.0, K) * rng.choice([-1.0, 1.0], K)
    x_true[support] = amplitudes
    x_true_q = np.array([q24(value) for value in x_true], dtype=np.int64)
    x_true_f = np.array([f24(value) for value in x_true_q])
    y_q = quant_matvec(phi_q, x_true_q)
    y_values = np.array([f24(value) for value in y_q])
    algorithms = ["OMP", "GOMP", "CoSaMP", "SP", "IHT", "HTP", "GP", "MP"]

    rows = []
    for algorithm in algorithms:
        x_hat = run_algorithm(algorithm, matrix, y_values, K)
        x_hat_q = np.array([q24(value) for value in x_hat], dtype=np.int64)
        x_hat_f = np.array([f24(value) for value in x_hat_q])
        mse, snr_db, overlap = metrics(x_true_f, x_hat_f)
        rows.append((algorithm, mse, snr_db, overlap))

    csv_path = OUT / "reconstruction_quality_python24.csv"
    with csv_path.open("w", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(["N", "M", "K", "x_seed", "algorithm", "mse", "snr_db", "support_overlap"])
        for algorithm, mse, snr_db, overlap in rows:
            writer.writerow([N, M, K, X_SEED, algorithm, f"{mse:.10e}", f"{snr_db:.4f}", f"{overlap}/{K}"])

    np.savez(OUT / "reconstruction_quality_python24_case.npz", phi_q=phi_q, x_true_q=x_true_q, y_q=y_q, support=support)
    print("support", support.tolist())
    for algorithm, mse, snr_db, overlap in rows:
        print(f"{algorithm:6s} mse={mse:.6e} snr={snr_db:.2f}dB overlap={overlap}/{K}")


if __name__ == "__main__":
    main()
