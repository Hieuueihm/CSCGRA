"""Host-side syntax check for the V2 SoC C runners.

The repository does not require a Xilinx SDK installation for CI.  When the
native headers are unavailable, this checker supplies a temporary, minimal
header shim and asks the host GCC to parse both runners with strict warnings.
It does not link or execute the MMIO code.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    ROOT / "sw" / "v2" / "src" / "main_tb_soc_program_k_sweep_all_ls_serial_write.c",
    ROOT / "sw" / "v2" / "src" / "main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c",
]


STUBS = {
    "xil_cache.h": """#ifndef XIL_CACHE_H
#define XIL_CACHE_H
#include <stdint.h>
static inline void Xil_DCacheFlushRange(uintptr_t a, unsigned n) {(void)a; (void)n;}
static inline void Xil_DCacheInvalidateRange(uintptr_t a, unsigned n) {(void)a; (void)n;}
#endif
""",
    "xil_io.h": """#ifndef XIL_IO_H
#define XIL_IO_H
#include <stdint.h>
static inline void Xil_Out32(uintptr_t a, uint32_t v) {(void)a; (void)v;}
static inline uint32_t Xil_In32(uintptr_t a) {(void)a; return 0U;}
#endif
""",
    "xil_printf.h": """#ifndef XIL_PRINTF_H
#define XIL_PRINTF_H
#include <stdarg.h>
static inline int xil_printf(const char *fmt, ...) {(void)fmt; return 0;}
#endif
""",
    "xparameters.h": """#ifndef XPARAMETERS_H
#define XPARAMETERS_H
#include <stdint.h>
#define UINTPTR uintptr_t
#define XPAR_CGRA_0_S_AXI_CONTROL_BASEADDR 0xA0000000U
#define COUNTS_PER_SECOND 100000000U
#endif
""",
    "xtime_l.h": """#ifndef XTIME_L_H
#define XTIME_L_H
#include <stdint.h>
typedef uint64_t XTime;
static inline void XTime_GetTime(XTime *value) {*value = 0U;}
#endif
""",
}


def main() -> int:
    compiler = os.environ.get("CC") or shutil.which("gcc")
    if compiler is None:
        print("SoC C syntax SKIP: gcc not found (native Vitis may be used instead)")
        return 2
    missing = [str(path) for path in SOURCES if not path.exists()]
    if missing:
        print("SoC C syntax FAIL: missing source(s): " + ", ".join(missing))
        return 1

    with tempfile.TemporaryDirectory(prefix="cscgra_sdk_stub_") as temp:
        include_dir = Path(temp)
        for name, text in STUBS.items():
            (include_dir / name).write_text(text, newline="\n")
        for source in SOURCES:
            command = [
                compiler,
                "-std=c11",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-fsyntax-only",
                "-I",
                str(include_dir),
                "-I",
                str(ROOT / "sw" / "v2" / "src"),
                str(source),
            ]
            result = subprocess.run(command, cwd=ROOT, text=True)
            if result.returncode:
                print(f"SoC C syntax FAIL: {source}")
                return result.returncode
            print(f"SoC C syntax PASS: {source.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
