import json
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
REPO = ROOT / "CSCGRA_opt_architecture"
OLD_JSON = ROOT / "analysis" / "reconstruction_quality_noisy24" / "noisy_lfsr_24bit_per_algorithm_seed_python.json"
OUT_JSON = ROOT / "analysis" / "reconstruction_quality_noisy24" / "noisy_lfsr_24bit_gp_grad_step_k16.json"
VH_PATH = REPO / "tests" / "noisy_lfsr_24bit_cases.vh"

Q = 16
N = 256
M = 64
K = 16
SCALE_Q = 0x4000
TAPS = 0x80200003
PHI_SEED = 0xDEADBEEF
MU_SHIFT = 3
GP_ITERS = 2 * K
MASK24 = (1 << 24) - 1


def s24(value):
    value = int(value) & MASK24
    return value - (1 << 24) if value & (1 << 23) else value


def sat_s24(value):
    return max(-0x800000, min(0x7FFFFF, int(round(value))))


def q24(value):
    return sat_s24(float(value) * (1 << Q))


def f24(value):
    return s24(value) / float(1 << Q)


def lfsr_step(state):
    shifted = (state >> 1) & 0x7FFFFFFF
    return ((shifted ^ TAPS) & 0xFFFFFFFF) if (state & 1) else shifted


def lfsr_advance(state, count):
    for _ in range(count):
        state = lfsr_step(state)
    return state & 0xFFFFFFFF


def make_phi_q():
    phi = []
    row_state = PHI_SEED
    for _ in range(M):
        row_state = lfsr_advance(row_state, N)
        phi.append([SCALE_Q if (lfsr_advance(row_state, col + 1) & 1) else -SCALE_Q for col in range(N)])
    return phi


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def norm(v):
    return dot(v, v) ** 0.5


def mat_vec(A, x):
    return [dot(row, x) for row in A]


def residual(A, y, x):
    Ax = mat_vec(A, x)
    return [y_i - ax_i for y_i, ax_i in zip(y, Ax)]


def trans_corr(A, r):
    return [sum(A[row][col] * r[row] for row in range(M)) for col in range(N)]


def top_abs(values, count, exclude=None):
    excluded = set() if exclude is None else set(exclude)
    order = [idx for idx in range(len(values)) if idx not in excluded]
    order.sort(key=lambda idx: (-abs(values[idx]), idx))
    return order[:count]


def best_update(x, r, best_x, best_norm):
    rnorm = norm(r)
    return (list(x), rnorm) if rnorm < best_norm else (best_x, best_norm)


def run_gp_grad_step(A, y):
    x = [0.0] * N
    r = list(y)
    best_x = list(x)
    best_norm = norm(r)
    mu = 1.0 / (1 << MU_SHIFT)
    support = []
    for _ in range(GP_ITERS):
        corr = trans_corr(A, r)
        pick = top_abs(corr, 1, support)
        if pick:
            support.append(pick[0])
        z = [x[idx] + mu * corr[idx] for idx in range(N)]
        keep = set(top_abs(z, K))
        x = [z[idx] if idx in keep else 0.0 for idx in range(N)]
        r = residual(A, y, x)
        best_x, best_norm = best_update(x, r, best_x, best_norm)
    return best_x


def metrics(x_true, x_hat):
    err = [a - b for a, b in zip(x_true, x_hat)]
    mse = dot(err, err) / N
    snr = 10.0 * __import__("math").log10(dot(x_true, x_true) / dot(err, err))
    true_support = {idx for idx, value in enumerate(x_true) if abs(value) > 1e-8}
    est_support = {idx for idx, value in enumerate(x_hat) if abs(value) > 1e-8}
    return mse, snr, len(true_support & est_support)

old = json.loads(OLD_JSON.read_text())
gp_old = old["algorithms"]["GP"]
phi_q = make_phi_q()
A = [[value / float(1 << Q) for value in row] for row in phi_q]
y = [f24(value) for value in gp_old["y_noisy_q24"]]
x_true = [f24(value) for value in gp_old["x_true_q24"]]
x_hat_q = [q24(value) for value in run_gp_grad_step(A, y)]
x_hat = [f24(value) for value in x_hat_q]
mse, snr, overlap = metrics(x_true, x_hat)

OUT_JSON.write_text(json.dumps({
    "source_data_json": str(OLD_JSON),
    "algorithm": "GP_grad_step_scaled",
    "N": N,
    "M": M,
    "K": K,
    "q_fraction_bits": Q,
    "phi_seed_hex": "0x%X" % PHI_SEED,
    "phi_scale_q_hex": "0x%X" % SCALE_Q,
    "measurement_snr_db": old["measurement_snr_db"],
    "mu_shift": MU_SHIFT,
    "iters": GP_ITERS,
    "x_seed": gp_old["x_seed"],
    "true_support": gp_old["true_support"],
    "mse": mse,
    "snr_db": snr,
    "support_overlap": f"{overlap}/{K}",
    "x_true_q24": gp_old["x_true_q24"],
    "y_clean_q24": gp_old["y_clean_q24"],
    "y_noisy_q24": gp_old["y_noisy_q24"],
    "x_hat_q24": x_hat_q,
}, indent=2))

text = VH_PATH.read_text()
start = text.index("function signed [23:0] NOISY_GP_XHAT;")
case_start = text.index("        case(idx)", start)
default_line = "        default: NOISY_GP_XHAT = 24'sd0;"
end_default = text.index(default_line, case_start)
end_line = text.index("\n", end_default)
body = ["        case(idx)"]
for idx, value in enumerate(x_hat_q):
    body.append(f"        {idx}: NOISY_GP_XHAT = 24'sh{(int(value) & MASK24):06x};")
body.append(default_line)
new_text = text[:case_start] + "\n".join(body) + text[end_line:]
marker = "// GP golden override: Python grad-step reference"
if marker not in new_text:
    new_text = new_text.replace(
        "// Auto-generated reference data for tb_soc_program_noisy24_mu.v",
        "// Auto-generated reference data for tb_soc_program_noisy24_mu.v\n// GP golden override: Python grad-step reference, see analysis/reconstruction_quality_noisy24/noisy_lfsr_24bit_gp_grad_step_k16.json",
    )
VH_PATH.write_text(new_text)
print(f"patched {VH_PATH}")
print(f"wrote {OUT_JSON}")
print(f"GP grad-step K16: seed={gp_old['x_seed']} iter={GP_ITERS} mu_shift={MU_SHIFT} snr={snr:.4f} overlap={overlap}/{K}")
