# Four-row Cholesky LS checkpoint

This checkpoint keeps regularized Cholesky LDLT as the only implemented LS
solver and increases useful participation of all four physical PE rows.  The
K=8 representative suite passes all eight algorithms and decreases aggregate
cycles from 1,035,895 at `920d4ec` to 951,907, an 8.11% reduction.

## Datapath changes

- `LS_OP_READ4` and `LS_OP_WRITE4` transfer four consecutive matrix rows in a
  single service request.
- The matrix store is organized as eight deep row banks.  This preserves the
  previous 24 BRAM36 footprint while enabling four-row access.
- Gram/RHS accumulation captures a 4x8 PE product batch and drains four Gram
  columns over four clocks into the row banks.
- LDLT reads four `A(i,k)` or `L(i,p)` values per request and writes four
  factor values per request.  Back substitution also uses four-row reads.
- Legacy Gaussian row-update and RHS-update multiplier hardware was removed;
  regularized Cholesky LDLT is the sole LS solver in this checkpoint.

## Distinct physical PE-row roles

| Operation | Row 0 | Row 1 | Row 2 | Row 3 |
|---|---|---|---|---|
| Correlation | sample slot `m mod 4 = 0` | slot 1 | slot 2 | slot 3 |
| RHS | lane `i mod 4 = 0` | lane 1 | lane 2 | lane 3 |
| Gram | column `j_base + 0` | column `j_base + 1` | column `j_base + 2` | column `j_base + 3` |
| LDLT/solve | factor lane `i_base + 0` | lane 1 | lane 2 | lane 3 |

The ownership is static for each batch, so every large dot-product or matrix
step has work assigned to all four rows rather than treating rows as duplicate
or idle resources.

## Representative M=64, N=256, K=8 cycles

| Algorithm | Iterations | `920d4ec` | Current | Delta | Improvement |
|---|---:|---:|---:|---:|---:|
| OMP | 8 | 47,447 | 46,385 | -1,062 | 2.24% |
| CoSaMP | 8 | 173,712 | 143,300 | -30,412 | 17.51% |
| IHT | 16 | 92,288 | 92,285 | -3 | 0.00% |
| HTP | 32 | 305,201 | 284,081 | -21,120 | 6.92% |
| SP | 8 | 178,919 | 148,434 | -30,485 | 17.04% |
| GP | 16 | 93,186 | 93,186 | 0 | 0.00% |
| GOMP | 4 | 26,677 | 25,771 | -906 | 3.40% |
| MP | 32 | 118,465 | 118,465 | 0 | 0.00% |
| **Total** | | **1,035,895** | **951,907** | **-83,988** | **8.11%** |

The detailed per-algorithm phase report is in
`analysis/ls_read4_gram4burst_phase_cycles.csv`.  Gram/RHS is zero for IHT,
GP, and MP because those algorithms do not invoke the LS service; shared
residual scans are deliberately excluded from that phase.

## OOC synthesis at 100 MHz

Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.

| Metric | `920d4ec` | Current | Delta |
|---|---:|---:|---:|
| Total LUT | 86,107 | 94,063 | +7,956 (+9.24%) |
| Logic LUT | 84,315 | 92,527 | +8,212 (+9.74%) |
| LUTRAM | 1,792 | 1,536 | -256 (-14.29%) |
| FF | 27,604 | 31,102 | +3,498 (+12.67%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 82 | 71 | -11 (-13.41%) |
| WNS | +2.733 ns | +2.486 ns | -0.247 ns |

The selected organization therefore trades 9.24% more LUT and 12.67% more FF
for the cycle reduction while also removing 11 DSPs and preserving BRAM and
positive 100 MHz timing.  A full 8x4 row-by-column bank experiment was rejected:
although faster, it synthesized to 138,747 LUT and 5,888 LUTRAM.

## Reproducibility

- Functional log: `runs/opt2/cholesky_only_k8_final/xsim.log` (local, ignored).
- Phase log: `runs/opt2/cholesky_only_profile_all/xsim.log` (local, ignored).
- Cycle CSV: `analysis/ls_read4_gram4burst_k8_cycles.csv`.
- Phase CSV: `analysis/ls_read4_gram4burst_phase_cycles.csv`.
- Synthesis reports:
  `runs/opt2/synth_ls_read4_gram4bank_cgra_top/cgra_top_util.rpt` and
  `cgra_top_timing.rpt` (local, ignored).
- Synthesis script: `scripts/run_synth_ls_read4_gram4bank_cgra_top.tcl`.

## Next optimization targets

1. Fuse correlation and coefficient/residual update for IHT and GP to remove
   redundant vector scans.
2. Replace the remaining divider latency with a verified fixed-point reciprocal
   refinement only after the factor-reuse paths pass the full regression.

Collision-checked exact/set-extension reuse is implemented in the successor
checkpoint documented by `analysis/factor_reuse_summary.md`.
