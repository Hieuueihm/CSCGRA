"""Byte-identical equivalence check: phase_compiler vs the TB program builder.

Compiles the v2 RTL + canonical testbench once, runs each case in
DUMP_ONLY mode (no execution), and compares every emitted CTX_WORD against
sw/v2/tools/phase_compiler.py for the (algorithm, k) pairs of the canonical
sweep.  Fails on the first mismatch.
"""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIVADO = Path(r"C:\Xilinx\Vivado\2018.1\bin")
WORK = ROOT / "work" / "sim" / "v2" / "phase_check"


def load_compiler():
    spec = importlib.util.spec_from_file_location(
        "phase_compiler", ROOT / "sw" / "v2" / "tools" / "phase_compiler.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["phase_compiler"] = module
    spec.loader.exec_module(module)
    return module


def run_bat(tool: str, args: list[str], log: Path) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    # xsim.bat drops arguments when invoked through nested shells; a
    # generated runner .bat with plain quoting is the proven path.
    quoted = " ".join(
        f'"{a}"' if ("=" in a or a.startswith("-")) else a for a in args)
    runner = WORK / f"run_{tool}.bat"
    runner.write_text(
        f"@echo off\r\ncd /d {WORK}\r\n"
        f"{VIVADO / f'{tool}.bat'} {quoted} --log {log.name}\r\n",
        newline="")
    result = subprocess.run(["cmd", "/c", str(runner)],
                            cwd=WORK, capture_output=True, text=True,
                            timeout=1800)
    if result.returncode != 0 or not (WORK / log.name).exists():
        print(result.stdout[-2000:])
        raise SystemExit(f"{tool} failed, see {WORK / log.name}")


def main() -> int:
    config = json.loads((ROOT / "config" / "rtl-v2.json").read_text())
    files = [ROOT / config["default_testbench"]]
    for line in (ROOT / config["rtl_filelist"]).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(ROOT / line)
    includes = ["-i", str(ROOT), "-i", str(ROOT / "verification" / "v2"),
                "-i", str(ROOT / "verification" / "v2" / "run1"),
                "-i", str(ROOT / "rtl" / "v2" / "control"),
                "-i", str(ROOT / "rtl" / "v2" / "solver")]
    WORK.mkdir(parents=True, exist_ok=True)
    run_bat("xvlog", [*includes, *[str(f) for f in files]], WORK / "xvlog.log")
    run_bat("xelab", ["--timescale", "1ns/1ps", "tb_run1_k_sweep",
                      "-s", "tb_phase_check"], WORK / "xelab.log")

    compiler = load_compiler()
    cases = {0: (64, 256, 16), 1: (64, 256, 8), 2: (64, 256, 4),
             3: (32, 128, 8), 4: (32, 128, 4), 5: (32, 128, 2),
             6: (16, 64, 4), 7: (16, 64, 2)}
    checked = 0
    for case_idx, (m, n, k) in cases.items():
        log = WORK / f"dump_case{case_idx}.log"
        run_bat("xsim", ["tb_phase_check", "-runall",
                         "-testplusarg", f"CASE={case_idx}",
                         "-testplusarg", "DUMP_PROGRAM",
                         "-testplusarg", "DUMP_ONLY",
                         "--log", f"dump_case{case_idx}.log"], log)
        dumped: dict[tuple[int, int], dict[int, int]] = {}
        for match in re.finditer(
                r"CTX_WORD alg=(\d+) k=(\d+) idx=(\d+) word=([0-9A-Fa-f]+)",
                log.read_text(errors="replace")):
            alg, kp, idx, word = (int(match.group(1)), int(match.group(2)),
                                  int(match.group(3)), int(match.group(4), 16))
            dumped.setdefault((alg, kp), {})[idx] = word
        if not dumped:
            raise SystemExit(f"case {case_idx}: no CTX_WORD lines in {log}")
        for (alg, kp), words_by_idx in sorted(dumped.items()):
            expected = compiler.build_program(alg, kp)
            got = [words_by_idx[i] for i in range(len(expected))]
            if got != expected:
                for i, (g, e) in enumerate(zip(got, expected)):
                    if g != e:
                        raise SystemExit(
                            f"MISMATCH case={case_idx} alg={alg} k={kp} "
                            f"idx={i}: tb={g:016X} compiler={e:016X}")
                raise SystemExit(f"MISMATCH case={case_idx} alg={alg} k={kp}: "
                                 f"length tb={len(got)} compiler={len(expected)}")
            checked += 1
    print(f"Phase compiler equivalence PASS: {checked} program images "
          f"byte-identical to the testbench builder")
    return 0


if __name__ == "__main__":
    sys.exit(main())
