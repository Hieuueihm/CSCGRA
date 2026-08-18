import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
RTL_DIR = ROOT / "CSCGRA" / "CSCGRA.srcs" / "sources_1" / "new"
TB_DIR = ROOT / "analysis" / "m64n256k16"
GOLDEN_DIR = ROOT / "golden_model"
OUT_DIR = GOLDEN_DIR / "verified_runs_stream"
VIVADO = Path(r"C:\Xilinx\Vivado\2024.2\bin")
ALGS = ["omp", "mp", "gomp", "iht", "gp", "sp", "cosamp", "htp"]
ALG_INDEX = {"omp":0,"gomp":1,"cosamp":2,"sp":3,"iht":4,"htp":5,"gp":6,"mp":7}
MAX_THREADS = 8
RTL_FILES = ['addrgen.v','cgra_soc_top.v','cgra_top.v','configmem.v','csr_regs.v','ctx_decoder.v','dma_ctrl.v','global_scalar_rf.v','lfsr_phi.v','ls_matrix_scratchpad.v','ls_matrix_service.v','ls_matrix_update_service.v','ls_row_update_service.v','ls_scratchpad.v','pe_array_top1_tree_4x8.v','pe_cluster_4x4.v','pe_core.v','pe_stream_top1_4x8_service.v','pe_stream_top1_service.v','pe_stream_topk_serial_service.v','pe_tile.v','pearray.v','reduce_scan.v','sequencer.v','sparse_kernel_service_engine.v','sparse_loop_controller.v','spm_cluster.v','switchbox.v']

def read(path):
    return Path(path).read_text(errors='ignore') if Path(path).exists() else ''

def run_step(cmd, cwd, log, timeout=None):
    with open(log, 'a', encoding='utf-8', errors='ignore') as f:
        f.write(f"\n$ {cmd}\n")
        f.flush()
        p = subprocess.Popen(cmd, cwd=str(cwd), shell=True, stdout=f, stderr=subprocess.STDOUT)
        try:
            return p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.kill()
            f.write(f"\nTIMEOUT after {timeout}s\n")
            return 124

def parse_golden():
    txt = read(GOLDEN_DIR / 'golden_cases.vh')
    vals = {}
    for k in ['GOLD_CASE_0_M','GOLD_CASE_0_N','GOLD_CASE_0_K','GOLD_MAX_N','GOLD_ALGS']:
        m = re.search(rf"localparam\s+integer\s+{k}\s*=\s*(\d+)\s*;", txt)
        vals[k] = int(m.group(1)) if m else None
    return vals

def classify(log, rc):
    summary = re.findall(r"(tb_\w+?:\s*\d+\s+PASS,\s*\d+\s+FAIL)", log)
    fail_lines = [x for x in re.findall(r".*(?:\bFAIL\b|MISM|ERROR|TIMEOUT).*", log) if not re.search(r"0\s+FAIL", x)]
    cycles = [int(x) for x in re.findall(r"MEASURED_CYCLES\s+(\d+)", log)]
    iter_runs = [int(x) for x in re.findall(r"ITER_RUN\s+iter=(\d+)", log)]
    status = 'PASS'
    if rc != 0 or any('TIMEOUT' in x for x in fail_lines): status = 'ERROR'
    if not summary: status = 'NO_SUMMARY'
    elif re.search(r",\s*[1-9]\d*\s+FAIL", summary[-1]): status = 'FAIL_TRUE'
    return status, (summary[-1] if summary else ''), cycles, iter_runs, '; '.join(fail_lines[:8])

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    golden = parse_golden()
    rows=[]
    for alg in ALGS:
        tb = TB_DIR / f"tb_{alg}_m64n256k16_cycle.v"
        name = tb.stem
        run_dir = OUT_DIR / name
        if run_dir.exists(): shutil.rmtree(run_dir)
        run_dir.mkdir(parents=True)
        log = run_dir / 'run.log'
        rtl_args = ' '.join(f'"{RTL_DIR / f}"' for f in RTL_FILES)
        inc = f'-i "{GOLDEN_DIR}" -i "{TB_DIR}" -i "{ROOT / "analysis" / "verification"}"'
        rc = run_step(f'"{VIVADO / "xvlog.bat"}" -sv {inc} {rtl_args} "{tb}"', run_dir, log, timeout=180)
        if rc == 0:
            rc = run_step(f'"{VIVADO / "xelab.bat"}" -mt {MAX_THREADS} -L xpm --timescale 1ns/1ps --override_timeunit --override_timeprecision {name} -s {name}', run_dir, log, timeout=900)
        if rc == 0:
            rc = run_step(f'"{VIVADO / "xsim.bat"}" {name} -runall', run_dir, log, timeout=1800)
        text=read(log)
        status, summary, cycles, iter_runs, fail_hint = classify(text, rc)
        rows.append({
            'alg': alg.upper() if alg != 'cosamp' else 'CoSaMP', 'M': golden.get('GOLD_CASE_0_M'), 'N': golden.get('GOLD_CASE_0_N'), 'K': golden.get('GOLD_CASE_0_K'),
            'status': status, 'summary': summary, 'total_cycles': sum(cycles) if cycles else '', 'num_runs': len(cycles), 'last_cycle': cycles[-1] if cycles else '',
            'iter_run_count': len(iter_runs), 'log': str(log), 'fail_hint': fail_hint[:300]
        })
        print(f"{alg}: {status} cycles={sum(cycles) if cycles else ''} runs={len(cycles)} iter_runs={len(iter_runs)} {summary}", flush=True)
    csv_path=OUT_DIR/'summary.csv'
    with csv_path.open('w', newline='', encoding='utf-8') as f:
        w=csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    md=OUT_DIR/'summary.md'
    with md.open('w', encoding='utf-8') as f:
        f.write('# 8-Algorithm Golden Regression (M64/N256/K16)\n\n')
        f.write('| alg | status | total_cycles | runs | last_cycle | iter_run_count | summary |\n|---|---|---:|---:|---:|---:|---|\n')
        for r in rows:
            f.write(f"| {r['alg']} | {r['status']} | {r['total_cycles']} | {r['num_runs']} | {r['last_cycle']} | {r['iter_run_count']} | {r['summary']} |\n")
    print(f"WROTE {csv_path}")
    print(f"WROTE {md}")

if __name__ == '__main__':
    main()
