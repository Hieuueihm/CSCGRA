# Four-row fused correlation-update

This checkpoint adds sparse opcode `0x88` (`OP_CORR_UPDATE`).  It keeps the
normal correlation score writeback, then updates one eight-element `x` block
through the physical PE mesh.  IHT replaces separate correlation and scalar
update uops with this fused operation.  GP uses the fused operation before its
existing score argmax, so score/support semantics remain unchanged while the
later gradient-step uop is removed.

## Four physical PE-row roles

The correlation half keeps the existing round-robin ownership: physical row
`r` accumulates samples whose stream slot is `m mod 4 = r`.  The update half
uses all four rows as a vertical pipeline for every eight-lane block:

| Physical row | Fused-update role |
|---|---|
| Row 0 | Arithmetic shift of the correlation delta by configured `mu_shift` |
| Row 1 | Saturating addition `x + shifted_delta` |
| Row 2 | Apply the lane keep mask |
| Row 3 | Check global lane range and expose the commit block |

This turns the old 256-element scalar update scan into 32 eight-lane mesh
commits per iteration for `N=256`.  Legacy `OP_CORR`, `OP_IHT_UPDATE`, and
`OP_GRAD_STEP` remain supported for existing context programs.

## Representative M=64, N=256, K=8 cycles

| Algorithm | Iterations | Factor-reuse checkpoint | Fused | Delta | Improvement |
|---|---:|---:|---:|---:|---:|
| OMP | 8 | 44,751 | 44,751 | 0 | 0.00% |
| CoSaMP | 8 | 129,395 | 129,395 | 0 | 0.00% |
| IHT | 16 | 92,285 | 80,381 | -11,904 | 12.90% |
| HTP | 32 | 236,277 | 236,277 | 0 | 0.00% |
| SP | 8 | 135,093 | 135,093 | 0 | 0.00% |
| GP | 16 | 93,186 | 81,282 | -11,904 | 12.77% |
| GOMP | 4 | 25,103 | 25,103 | 0 | 0.00% |
| MP | 32 | 118,465 | 118,465 | 0 | 0.00% |
| **Total** | | **874,555** | **850,747** | **-23,808** | **2.72%** |

Relative to commit `920d4ec`, aggregate cycles fall from 1,035,895 to 850,747,
a reduction of 185,148 cycles or 17.87%.

For IHT and GP, the combined correlation-update phase is 39,920 cycles.  Their
remaining busy cycles fall from 46,464 to 30,048.  Cholesky/LDLT phase counts
for the LS-based algorithms are unchanged.  Detailed phase data is in
`analysis/corr_update_fused_phase_cycles.csv`.

## OOC synthesis at 100 MHz

Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.

| Metric | Factor-reuse checkpoint | Fused | Delta |
|---|---:|---:|---:|
| Total LUT | 96,755 | 94,899 | -1,856 (-1.92%) |
| Logic LUT | 95,219 | 93,363 | -1,856 (-1.95%) |
| LUTRAM | 1,536 | 1,536 | 0 |
| FF | 32,558 | 32,774 | +216 (+0.66%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 71 | 71 | 0 |
| WNS | +3.001 ns | +2.395 ns | -0.606 ns |

The fused implementation therefore reduces cycles and LUT count, adds 216 FF,
uses no extra BRAM/DSP, and retains positive 100 MHz timing margin.

## Verification and reproducibility

- Strict functional log: `runs/opt2/corr_update_fused_k8_final/xsim.log`
  (local, ignored): 8/8 algorithms and 16/16 checks pass.
- Phase profiler: `runs/opt2/corr_update_fused_profile_all/xsim.log`
  (local, ignored): 8/8 checks pass.
- Cycle CSV: `analysis/corr_update_fused_k8_cycles.csv`.
- Phase CSV: `analysis/corr_update_fused_phase_cycles.csv`.
- Synthesis reports:
  `runs/opt2/synth_corr_update_fused_cgra_top/cgra_top_util.rpt` and
  `cgra_top_timing.rpt` (local, ignored).
- Synthesis script: `scripts/run_synth_corr_update_fused_cgra_top.tcl`.

## Next target

Evaluate a fixed-point reciprocal Newton-Raphson unit against the existing
bit-exact restoring divider.  Cholesky/LDLT remains the only LS factorization.
