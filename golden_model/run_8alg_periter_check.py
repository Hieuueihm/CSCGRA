import csv
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
RTL_DIR = ROOT / "CSCGRA" / "CSCGRA.srcs" / "sources_1" / "new"
TB_DIR = ROOT / "analysis" / "m64n256k16"
GOLDEN_DIR = ROOT / "golden_model"
OUT_DIR = GOLDEN_DIR / "verified_runs"
VIVADO_BIN = Path(r"C:\Xilinx\Vivado\2024.2\bin")
ALGS = ["omp", "mp", "gomp", "iht", "gp", "sp", "cosamp", "htp"]
ALG_INDEX = {"omp": 0, "gomp": 1, "cosamp": 2, "sp": 3, "iht": 4, "htp": 5, "gp": 6, "mp": 7}
MAX_THREADS = int(os.environ.get("CSCGRA_MAX_THREADS", os.cpu_count() or 8))


def read_text(path: Path) -> str:
    return path.read_text(errors="ignore")


def parse_golden():
    text = read_text(GOLDEN_DIR / "golden_cases.vh")
    vals = {}
    for key in ["GOLD_CASE_0_M", "GOLD_CASE_0_N", "GOLD_CASE_0_K", "GOLD_MAX_N"]:
        m = re.search(rf"localparam\s+integer\s+{key}\s*=\s*(\d+)\s*;", text)
        vals[key] = int(m.group(1)) if m else None
    iters = {}
    fn = re.search(r"function\s+integer\s+gold_alg_iters;(?P<body>.*?)endfunction", text, re.S)
    if fn:
        for idx, val in re.findall(r"\b\d+\s*,\s*(\d+)\s*\)?:\s*gold_alg_iters\s*=\s*(\d+)\s*;", fn.group("body")):
            iters[int(idx)] = int(val)
        # Fallback for flattened case entries like '1: gold_alg_iters = 16;'
        if not iters:
            for flat, val in re.findall(r"\b(\d+)\s*:\s*gold_alg_iters\s*=\s*(\d+)\s*;", fn.group("body")):
                iters[int(flat)] = int(val)
    vals["iters"] = iters
    return vals

def parse_flat_assignments(text: str, fname: str) -> dict[int, str]:
    m = re.search(rf"function\s+(?:integer|\[[^\]]+\])\s+{fname};(?P<body>.*?)endfunction", text, re.S)
    if not m:
        return {}
    out = {}
    for flat, value in re.findall(rf"\b(\d+)\s*:\s*{fname}\s*=\s*([^;]+);", m.group("body")):
        out[int(flat)] = value.strip()
    return out


def span_equal(values: dict[int, str], lhs: int, rhs: int, count: int) -> bool:
    for off in range(count):
        if values.get(lhs + off) != values.get(rhs + off):
            return False
    return True


def detect_stale_golden_pairs() -> dict[str, str]:
    text = read_text(GOLDEN_DIR / "golden_cases.vh")

    def localparam(name: str, default: int) -> int:
        m = re.search(rf"localparam\s+integer\s+{name}\s*=\s*(\d+)\s*;", text)
        return int(m.group(1)) if m else default

    max_n = localparam("GOLD_MAX_N", 256)
    max_k = localparam("GOLD_MAX_K", 32)
    max_iters = localparam("GOLD_MAX_ITERS", 16)
    checks = [
        ("gold_support_len", max_iters, "iter"),
        ("gold_support_idx", max_iters * max_k, "support"),
        ("gold_iter_x_hat", max_iters * max_n, "vector"),
        ("gold_iter_residual", max_iters * max_n, "vector"),
        ("gold_iter_ls_x_hat", max_iters * max_n, "vector"),
        ("gold_iter_ls_residual", max_iters * max_n, "vector"),
    ]
    flat_maps = {name: parse_flat_assignments(text, name) for name, _, _ in checks}

    def alg_blocks_equal(lhs_alg: int, rhs_alg: int) -> bool:
        compared = 0
        for name, count, kind in checks:
            values = flat_maps[name]
            if not values:
                continue
            compared += 1
            if kind == "iter":
                lhs_base = lhs_alg * max_iters
                rhs_base = rhs_alg * max_iters
            elif kind == "support":
                lhs_base = lhs_alg * max_iters * max_k
                rhs_base = rhs_alg * max_iters * max_k
            else:
                lhs_base = lhs_alg * max_iters * max_n
                rhs_base = rhs_alg * max_iters * max_n
            if not span_equal(values, lhs_base, rhs_base, count):
                return False
        return compared > 0

    stale = {}
    if alg_blocks_equal(ALG_INDEX["omp"], ALG_INDEX["mp"]):
        stale["mp"] = "GOLDEN_STALE: MP golden block is identical to OMP"
    if alg_blocks_equal(ALG_INDEX["iht"], ALG_INDEX["gp"]):
        stale["gp"] = "GOLDEN_STALE: GP golden block is identical to IHT"
    return stale


def classify_status(summary_line: str | None, log_text: str, returncode: int, dataset_ok: bool, iter_ok: bool):
    if returncode != 0 or re.search(r"\b(ERROR|FATAL)\b", log_text):
        return "ERROR"
    if not summary_line:
        return "NO_SUMMARY"
    m = re.search(r":\s*(\d+)\s+PASS,\s*(\d+)\s+FAIL", summary_line)
    if not m:
        return "NO_SUMMARY"
    fail_count = int(m.group(2))
    if fail_count > 0:
        return "FAIL_TRUE"
    if not dataset_ok:
        return "DATASET_UNVERIFIED"
    if not iter_ok:
        return "INCOMPLETE_ITER"
    return "PASS"


def run_cmd(cmd: str, cwd: Path) -> tuple[int, str]:
    p = subprocess.run(cmd, cwd=str(cwd), shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    golden = parse_golden()
    stale_golden = detect_stale_golden_pairs()
    rtl_files = sorted(str(p) for p in RTL_DIR.glob("*.v"))
    rows = []
    for alg in ALGS:
        tb = TB_DIR / f"tb_{alg}_m64n256k16_cycle.v"
        name = tb.stem
        run_dir = OUT_DIR / name
        if run_dir.exists():
            shutil.rmtree(run_dir)
        run_dir.mkdir(parents=True)
        tb_text = read_text(tb) if tb.exists() else ""
        dataset_ok = (
            golden.get("GOLD_CASE_0_M") == 64 and
            golden.get("GOLD_CASE_0_N") == 256 and
            golden.get("GOLD_CASE_0_K") == 16 and
            golden.get("GOLD_MAX_N") == 256 and
            ('golden_cases.vh' in tb_text or 'golden_cases_array.vh' in tb_text)
        )
        expected_iters = golden.get("iters", {}).get(ALG_INDEX[alg])
        if expected_iters is None and alg in ["omp", "mp"]:
            expected_iters = golden.get("GOLD_CASE_0_K")
        rtl_args = " ".join(f'"{x}"' for x in rtl_files)
        cmd = (
            f'call "{VIVADO_BIN / "xvlog.bat"}" -sv '
            f'-i D:/vivado_pj/golden_model -i D:/vivado_pj/analysis/m64n256k16 -i D:/vivado_pj/analysis/verification '
            f'{rtl_args} "{tb}" && '
            f'call "{VIVADO_BIN / "xelab.bat"}" -mt {MAX_THREADS} -L xpm --timescale 1ns/1ps --override_timeunit --override_timeprecision {name} -s {name} && '
            f'call "{VIVADO_BIN / "xsim.bat"}" {name} -runall'
        )
        rc, out = run_cmd(f'cmd /c "{cmd}"', run_dir)
        (run_dir / "run.stdout.log").write_text(out, errors="ignore")
        xsim_log = run_dir / "xsim.log"
        log_text = read_text(xsim_log) if xsim_log.exists() else out
        cycles = [int(x) for x in re.findall(r"MEASURED_CYCLES\s+(\d+)", log_text)]
        iter_runs = [int(x) for x in re.findall(r"ITER_RUN\s+iter=(\d+)", log_text)]
        summary_match = re.findall(rf"{re.escape(name)}:\s*\d+\s+PASS,\s*\d+\s+FAIL", log_text)
        summary = summary_match[-1] if summary_match else ""
        # Full-program OMP/gOMP/MP do one measured run but internally unroll expected iterations in context.
        full_program = alg in {"omp", "gomp", "mp"}
        if full_program:
            context_loop_ok = bool(re.search(r"iter_idx\s*<\s*(gold_case_k\(0\)|gold_alg_iters\(0,\s*\d+\))", tb_text))
            iter_ok = (len(cycles) == 1 and context_loop_ok)
            iter_count = 1
            notes_iter = "single_full_program"
        else:
            iter_ok = expected_iters is not None and len(iter_runs) == expected_iters and len(cycles) == expected_iters
            iter_count = len(cycles)
            notes_iter = f"ITER_RUN={len(iter_runs)}/expected={expected_iters}"
        total = sum(cycles) if cycles else None
        last = cycles[-1] if cycles else None
        avg = (total / len(cycles)) if cycles else None
        status = classify_status(summary, log_text, rc, dataset_ok, iter_ok)
        fail_lines = re.findall(r".*(?:MISM|FAIL|ERROR).*", log_text)
        real_fail_hint = "; ".join(line.strip() for line in fail_lines[:5] if not re.search(r"0\s+FAIL", line))
        notes = []
        notes.append(notes_iter)
        if not dataset_ok:
            notes.append("DATASET_UNVERIFIED")
        if not iter_ok:
            notes.append("INCOMPLETE_ITER")
        if real_fail_hint:
            notes.append(real_fail_hint[:240])
        if alg in stale_golden:
            notes.append(stale_golden[alg])
            if status == "FAIL_TRUE":
                status = "FAIL_GOLDEN_STALE"
        rows.append({
            "alg": alg,
            "M": golden.get("GOLD_CASE_0_M"),
            "N": golden.get("GOLD_CASE_0_N"),
            "K": golden.get("GOLD_CASE_0_K"),
            "total_cycles": total if total is not None else "",
            "num_measured_runs": len(cycles),
            "last_cycle": last if last is not None else "",
            "avg_cycle_per_run": f"{avg:.2f}" if avg is not None else "",
            "expected_iters": expected_iters if expected_iters is not None else "",
            "status": status,
            "summary": summary,
            "notes": " | ".join(notes),
        })
        print(f"{alg}: status={status} total={total} runs={len(cycles)} summary={summary}")
    csv_path = OUT_DIR / "large_cycle_verified_summary.csv"
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    md_path = OUT_DIR / "large_cycle_verified_summary.md"
    with md_path.open("w") as f:
        f.write("# M64/N256/K16 Verified Cycle Summary\n\n")
        f.write("| alg | M | N | K | total_cycles | runs | last_cycle | avg/run | status | summary | notes |\n")
        f.write("|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|\n")
        for r in rows:
            f.write(f"| {r['alg']} | {r['M']} | {r['N']} | {r['K']} | {r['total_cycles']} | {r['num_measured_runs']} | {r['last_cycle']} | {r['avg_cycle_per_run']} | {r['status']} | {r['summary']} | {r['notes']} |\n")
    print(f"WROTE {csv_path}")
    print(f"WROTE {md_path}")

if __name__ == "__main__":
    main()


