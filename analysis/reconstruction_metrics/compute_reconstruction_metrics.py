import csv
import json
import math
import re
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
GOLD = ROOT / "CSCGRA_opt" / "tests" / "golden_cases.vh"
OUT = ROOT / "analysis" / "reconstruction_metrics"
OUT.mkdir(parents=True, exist_ok=True)

M = 64
N = 256
K = 16
MAX_ITERS = 16
ALGS = ["OMP", "GOMP", "CoSaMP", "SP", "IHT", "HTP", "GP", "MP"]
Q = 16
DATA_MASK = (1 << 24) - 1


def s24(value: int) -> int:
    value &= DATA_MASK
    if value & (1 << 23):
        value -= 1 << 24
    return value


def q24_to_float(value: int) -> float:
    return s24(value) / float(1 << Q)


def parse_hex_func(text: str, fname: str) -> dict[int, int]:
    match = re.search(rf"function\s+\[[^\]]+\]\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not match:
        return {}
    vals = {}
    for item in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*\d+'h([0-9a-fA-F]+)\s*;", match.group("body")):
        vals[int(item.group(1))] = int(item.group(2), 16)
    return vals


def parse_dec_func(text: str, fname: str) -> dict[int, int]:
    match = re.search(rf"function\s+integer\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not match:
        return {}
    vals = {}
    for item in re.finditer(rf"\b(\d+)\s*:\s*{fname}\s*=\s*(\d+)\s*;", match.group("body")):
        vals[int(item.group(1))] = int(item.group(2))
    return vals


def mse(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) / len(a)


def snr_db(ref, est):
    signal = sum(x * x for x in ref)
    noise = sum((x - y) ** 2 for x, y in zip(ref, est))
    if noise == 0:
        return float("inf")
    return 10.0 * math.log10(signal / noise)


def read_final_x(x_map, alg_idx: int):
    base = ((0 * len(ALGS) + alg_idx) * MAX_ITERS + (MAX_ITERS - 1)) * N
    return [q24_to_float(x_map.get(base + i, 0)) for i in range(N)]


def main():
    text = GOLD.read_text(errors="ignore")
    x_map = parse_hex_func(text, "gold_iter_x_hat")
    if not x_map:
        raise SystemExit("ERROR: cannot find gold_iter_x_hat in golden_cases.vh")

    # Optional true sparse signal. The current golden file usually does not contain this.
    true_funcs = ["gold_x_true", "gold_true_x", "gold_case_x", "gold_x"]
    true_map = {}
    true_name = None
    for name in true_funcs:
        true_map = parse_hex_func(text, name)
        if true_map:
            true_name = name
            break

    rows = []
    if true_map:
        x_true = [q24_to_float(true_map.get(i, 0)) for i in range(N)]
        for alg_idx, alg in enumerate(ALGS):
            x_hat = read_final_x(x_map, alg_idx)
            rows.append({
                "algorithm": alg,
                "reference": true_name,
                "mse": mse(x_true, x_hat),
                "snr_db": snr_db(x_true, x_hat),
            })
        csv_path = OUT / "reconstruction_quality_vs_true.csv"
    else:
        # Fall back to numerical consistency against OMP/HTP references, but mark it clearly.
        # This is NOT true recovery SNR; it is consistency relative to an internal reference.
        ref_alg = "HTP"
        ref_idx = ALGS.index(ref_alg)
        x_ref = read_final_x(x_map, ref_idx)
        for alg_idx, alg in enumerate(ALGS):
            x_hat = read_final_x(x_map, alg_idx)
            rows.append({
                "algorithm": alg,
                "reference": f"internal_{ref_alg}_fixed_point_reference",
                "mse": mse(x_ref, x_hat),
                "snr_db": snr_db(x_ref, x_hat),
            })
        csv_path = OUT / "fixed_point_consistency_vs_htp.csv"

    with csv_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["algorithm", "reference", "mse", "snr_db"])
        writer.writeheader()
        writer.writerows(rows)

    (OUT / "reconstruction_quality_summary.json").write_text(json.dumps({
        "N": N,
        "M": M,
        "K": K,
        "source": str(GOLD),
        "has_true_signal": bool(true_map),
        "output_csv": str(csv_path),
        "warning": None if true_map else "No x_true function found. Reported values are fixed-point consistency vs HTP, not true reconstruction SNR.",
        "rows": rows,
    }, indent=2))

    print(f"WROTE {csv_path}")
    if not true_map:
        print("WARNING: No x_true found. Do not use these values as true reconstruction SNR.")
    for row in rows:
        snr = row["snr_db"]
        snr_text = "inf" if math.isinf(snr) else f"{snr:.2f}"
        print(f"{row['algorithm']:6s} MSE={row['mse']:.6e} SNR={snr_text} dB ref={row['reference']}")


if __name__ == "__main__":
    main()
