# RTL v2 verification

This directory contains version-matched testbenches and compiled golden data
for `rtl/v2`.

## Canonical regression

`run1/tb_run1_k_sweep.v` is the default testbench selected by
`config/rtl-v2.json`. It covers:

| Case | M | N | K |
|---:|---:|---:|---:|
| 0 | 64 | 256 | 16 |
| 1 | 64 | 256 | 8 |
| 2 | 64 | 256 | 4 |
| 3 | 32 | 128 | 8 |
| 4 | 32 | 128 | 4 |
| 5 | 32 | 128 | 2 |
| 6 | 16 | 64 | 4 |
| 7 | 16 | 64 | 2 |

Algorithms are OMP, CoSaMP, IHT, HTP, SP, GP, GOMP, and MP. CoSaMP/SP K16
are expected skips because their 2K candidate support exceeds the current
capacity. A full valid run is 348 PASS / 0 FAIL and 62 cycle records.

With `-ProfileStates`, the testbench reports controller, top-K, support, uop,
and internal wide-multiplier residency. Profiling is verification-only and is
not synthesized.

## Other files

- `run1/*golden*.vh`: active and archived run1 golden includes.
- root `*_golden*.vh`: shared version-matched vectors.
- `tb_omp_*`, `tb_mp_*`, and `tb_soc_program_*`: focused historical or
  diagnostic benches; they do not replace the canonical K-sweep sign-off.
- `*.f`: explicit focused-test file lists.

Never change golden values merely to match a failing RTL candidate. Determine
whether RTL, scheduling, or the test configuration is wrong first.
