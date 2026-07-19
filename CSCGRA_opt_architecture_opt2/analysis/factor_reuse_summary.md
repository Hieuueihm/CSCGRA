# Collision-checked Cholesky factor reuse

This checkpoint adds persistent support/factor reuse to the four-row
regularized Cholesky LDLT solver.  The representative K=8 suite passes all
eight strict functional checks and all eight profiler checks.  It decreases
aggregate cycles from 951,907 to 874,555, an additional 8.13% reduction.

## Reuse rules

Reuse is authorized only when `M`, `N`, effective seed, Phi scale, Phi kind,
and the active support all match the cached sensing-matrix configuration.

- A commutative 32-bit support fingerprint rejects obvious misses.
- A sequential full-entry scan verifies the support set before every hit, so a
  fingerprint collision cannot authorize reuse.
- The ordered fast path checks one entry per clock for exact HTP-style matches
  and OMP-style prefix growth.
- A one-comparator fallback handles sorted GOMP support.  It preserves the old
  factor order locally and appends only new support entries, turning a sorted
  set extension into a bordered Cholesky extension.
- Exact hits rebuild RHS but skip matrix clear, Gram, and LDLT factorization.
- Extension hits rebuild RHS, accumulate all old/new and new/new Gram border
  terms, then replay each cached pivot across only the appended rows.  This
  computes `L(new,old)` before factoring the new diagonal while preserving the
  cached old/old triangle.

The inverse diagonal is retained in four distributed banks.  Each physical PE
row reads its matching bank during the four-lane diagonal solve; this avoids
four large 16:1 register muxes.

## Representative M=64, N=256, K=8 cycles

| Algorithm | Iterations | Four-row checkpoint | Factor reuse | Delta | Improvement |
|---|---:|---:|---:|---:|---:|
| OMP | 8 | 46,385 | 44,751 | -1,634 | 3.52% |
| CoSaMP | 8 | 143,300 | 129,395 | -13,905 | 9.70% |
| IHT | 16 | 92,285 | 92,285 | 0 | 0.00% |
| HTP | 32 | 284,081 | 236,277 | -47,804 | 16.83% |
| SP | 8 | 148,434 | 135,093 | -13,341 | 8.99% |
| GP | 16 | 93,186 | 93,186 | 0 | 0.00% |
| GOMP | 4 | 25,771 | 25,103 | -668 | 2.59% |
| MP | 32 | 118,465 | 118,465 | 0 | 0.00% |
| **Total** | | **951,907** | **874,555** | **-77,352** | **8.13%** |

Relative to commit `920d4ec`, the total falls from 1,035,895 to 874,555
cycles, a reduction of 161,340 cycles or 15.57%.

The per-phase data is in `analysis/factor_reuse_phase_cycles.csv`.  The largest
direct reductions are HTP Gram/RHS (51,392 to 29,684 cycles) and factorization
(31,584 to 4,935 cycles).  Forward, diagonal, and backward solve equations are
unchanged.

## OOC synthesis at 100 MHz

Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.

| Metric | Four-row checkpoint | Factor reuse | Delta |
|---|---:|---:|---:|
| Total LUT | 94,063 | 96,755 | +2,692 (+2.86%) |
| Logic LUT | 92,527 | 95,219 | +2,692 (+2.91%) |
| LUTRAM | 1,536 | 1,536 | 0 |
| FF | 31,102 | 32,558 | +1,456 (+4.68%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |
| WNS | +2.486 ns | +3.001 ns | +0.515 ns |

Factor reuse therefore trades 2.86% more LUT and 4.68% more FF for an 8.13%
aggregate cycle reduction.  BRAM/DSP usage is unchanged and the 100 MHz timing
margin improves by 0.515 ns.

## Reproducibility

- Profiler log: `runs/opt2/factor_bordertri_profile_all/xsim.log` (local, ignored).
- Functional log: `runs/opt2/factor_bordertri_k8_final/xsim.log` (local, ignored).
- Cycle CSV: `analysis/factor_reuse_k8_cycles.csv`.
- Phase CSV: `analysis/factor_reuse_phase_cycles.csv`.
- Synthesis reports:
  `runs/opt2/synth_factor_reuse_cgra_top/cgra_top_util.rpt` and
  `cgra_top_timing.rpt` (local, ignored).
- Synthesis script: `scripts/run_synth_factor_reuse_cgra_top.tcl`.

## Successor checkpoint

The four-row correlation-update fusion for IHT and GP is implemented and
documented in `analysis/corr_update_fused_summary.md`.
