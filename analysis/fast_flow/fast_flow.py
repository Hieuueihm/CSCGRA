import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(r"D:\vivado_pj")
RTL_DIR = ROOT / "CSCGRA" / "CSCGRA.srcs" / "sources_1" / "new"
OUT_DIR = ROOT / "analysis" / "fast_flow" / "runs"
VIVADO = Path(r"C:\Xilinx\Vivado\2024.2\bin\vivado.bat")
XVLOG = Path(r"C:\Xilinx\Vivado\2024.2\bin\xvlog.bat")
XELAB = Path(r"C:\Xilinx\Vivado\2024.2\bin\xelab.bat")
PART = "xczu7ev-ffvc1156-2-e"
CLOCK_NS = "10.000"
MAX_THREADS = int(os.environ.get("CSCGRA_MAX_THREADS", os.cpu_count() or 8))


def run(cmd, cwd):
    proc = subprocess.run(cmd, cwd=str(cwd), shell=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc.returncode, proc.stdout


def rtl_files():
    return sorted(RTL_DIR.glob("*.v"))


def ooc_synth(top):
    out = OUT_DIR / f"ooc_{top}"
    out.mkdir(parents=True, exist_ok=True)
    tcl = out / f"run_ooc_{top}.tcl"
    files = " ".join(str(p).replace("\\", "/") for p in rtl_files())
    tcl.write_text(f"""
set_param general.maxThreads {MAX_THREADS}
set part {PART}
read_verilog {{{files}}}
synth_design -top {top} -part $part -mode out_of_context -flatten_hierarchy rebuilt -directive RuntimeOptimized
create_clock -period {CLOCK_NS} -name clk100 [get_ports clk]
report_utilization -hierarchical -hierarchical_percentages -file {str(out / 'hier_util.rpt').replace('\\', '/')}
report_utilization -file {str(out / 'util.rpt').replace('\\', '/')}
report_timing -delay_type max -max_paths 5 -sort_by slack -file {str(out / 'timing_top5.rpt').replace('\\', '/')}
report_timing_summary -delay_type max -max_paths 1 -file {str(out / 'timing_summary.rpt').replace('\\', '/')}
exit
""".strip() + "\n")
    rc, text = run(f'"{VIVADO}" -mode batch -source "{tcl}"', ROOT)
    (out / "vivado.log").write_text(text, errors="ignore")
    return rc, out


def compile_elab(tb_name):
    out = OUT_DIR / f"elab_{tb_name}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    tb = ROOT / "analysis" / "verification" / f"{tb_name}.v"
    rtl_args = " ".join(f'"{p}"' for p in rtl_files())
    cmd = (
        f'call "{XVLOG}" -sv -i D:/vivado_pj/analysis/verification {rtl_args} "{tb}" && '
        f'call "{XELAB}" -mt {MAX_THREADS} --timescale 1ns/1ps --override_timeunit --override_timeprecision {tb_name} -s {tb_name}'
    )
    rc, text = run(f'cmd /c "{cmd}"', out)
    (out / "compile_elab.log").write_text(text, errors="ignore")
    return rc, out


def parse_number(line):
    m = re.search(r"\|\s*([^|]+?)\s*\|\s*(\d+)", line)
    return int(m.group(2)) if m else None


def summarize_ooc(top):
    out = OUT_DIR / f"ooc_{top}"
    util = out / "util.rpt"
    hier = out / "hier_util.rpt"
    timing = out / "timing_top5.rpt"
    summary = {"top": top}
    if util.exists():
        text = util.read_text(errors="ignore")
        for key, pat in {
            "lut": r"^\| CLB LUTs\*\s+\|\s+(\d+)",
            "ff": r"^\| CLB Registers\s+\|\s+(\d+)",
            "bram36": r"^\|\s+RAMB36/FIFO\*\s+\|\s+(\d+)",
            "dsp": r"^\| DSPs\s+\|\s+(\d+)",
        }.items():
            m = re.search(pat, text, re.M)
            summary[key] = int(m.group(1)) if m else ""
    if timing.exists():
        text = timing.read_text(errors="ignore")
        m = re.search(r"Slack \((?:VIOLATED|MET)\) :\s+(-?\d+\.\d+)ns", text)
        summary["wns"] = m.group(1) if m else ""
        src = re.search(r"^\s*Source:\s*(.*)$", text, re.M)
        dst = re.search(r"^\s*Destination:\s*(.*)$", text, re.M)
        summary["src"] = src.group(1).strip() if src else ""
        summary["dst"] = dst.group(1).strip() if dst else ""
    return summary


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("ooc")
    s.add_argument("tops", nargs="+")
    e = sub.add_parser("elab")
    e.add_argument("tbs", nargs="+")
    sub.add_parser("summary")
    args = ap.parse_args()
    if args.cmd == "ooc":
        rows = []
        for top in args.tops:
            rc, out = ooc_synth(top)
            row = summarize_ooc(top)
            row["rc"] = rc
            rows.append(row)
            print(row)
        (OUT_DIR / "ooc_summary.txt").write_text("\n".join(str(r) for r in rows), errors="ignore")
    elif args.cmd == "elab":
        for tb in args.tbs:
            rc, out = compile_elab(tb)
            print({"tb": tb, "rc": rc, "out": str(out)})
            if rc:
                print((out / "compile_elab.log").read_text(errors="ignore")[-4000:])
                raise SystemExit(rc)
    elif args.cmd == "summary":
        for top in ["sparse_loop_controller", "sparse_kernel_service_engine", "score_select_service"]:
            print(summarize_ooc(top))

if __name__ == "__main__":
    main()
