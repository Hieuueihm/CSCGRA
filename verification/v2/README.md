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

- `run1/k_sweep_golden_mu3.vh`: legacy hardware-compatible baseline golden;
  it is not the canonical algorithm source.
- `run1/k_sweep_golden_canonical.vh`: capacity-unlimited textbook reference;
  generated from the independent canonical fixed-point model. GP selects its
  entries by default.
- Other `run1/*golden*.vh`: archived run1 golden includes.
- root `*_golden*.vh`: historical diagnostic includes used by legacy focused
  benches; the canonical K-sweep include is under `run1/`.
- `tb_omp_*`, `tb_mp_*`, and `tb_soc_program_*`: focused historical or
  diagnostic benches; they do not replace the canonical K-sweep sign-off.
- `*.f`: explicit focused-test file lists.

Never change golden values merely to match a failing RTL candidate. Determine
whether RTL, scheduling, or the test configuration is wrong first.

The default `run_regression.ps1` now selects canonical fixed-point GP and
compares algorithm 5 against `k_sweep_golden_canonical.vh`; the other
algorithms continue to use the legacy golden until their RTL migrations are
complete. `-CanonicalGolden` remains accepted as an explicit spelling. Use
`-LegacyHardwareGolden` only to reproduce the historical dense-gradient GP
baseline. CoSaMP/SP K16 remain deferred/skipped because the current 16-entry
candidate/support capacity is intentionally unchanged.
