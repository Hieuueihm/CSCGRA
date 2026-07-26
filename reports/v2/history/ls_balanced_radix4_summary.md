# LS balanced radix-4 optimization summary

## Scope

- Baseline: the validated `div64` source in `CSCGRA_opt_architecture_opt2`.
- Target: reduce LS-refine cycle count without increasing DSP/BRAM and recover the LUT cost of the cycle-only back-solve first-read shortcut.
- Golden data, algorithm flow, fixed-point widths, support rules, and SDK data are unchanged.

## RTL changes

- `sparse_loop_controller.v` no longer launches the first upper-triangular read from `S_BACK_INIT`. The controller enters `S_BACK_ACC` normally, avoiding the large synthesized mux replication caused by that one-cycle-per-row shortcut.
- The inexpensive last-upper-term-to-diagonal prefetch in `S_BACK_ACC_READ` remains enabled.
- The shared restoring divider now consumes four quotient bits per clock instead of two. Divider latency falls from 32 to 16 step clocks while preserving the same bit order and final rounding operation.
- No second divider, multiplier, DSP, or memory bank was added.

## Functional validation

- GP-opt K=8: `3 PASS, 0 FAIL`.
- Noisy representative K=8: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`.
- Full K-sweep: `348 PASS, 0 FAIL`; CoSaMP/SP K=16 keep the existing `requires_2K_candidate_support` skip rule.
- Local logs (ignored by Git):
  - `runs/opt2/ls_balanced_radix4_gpopt/xsim.run.stdout.log`
  - `runs/opt2/ls_balanced_radix4_snr_k8_rep/xsim.run.stdout.log`
  - `runs/opt2/ls_balanced_radix4_ksweep/xsim.run.stdout.log`

## Representative K=8 cycle comparison

| Algorithm | Div64 baseline | Balanced radix-4 | Delta | Improvement |
|---|---:|---:|---:|---:|
| OMP | 82,773 | 80,897 | -1,876 | 2.27% |
| CoSaMP | 253,430 | 233,214 | -20,216 | 7.98% |
| IHT | 156,797 | 156,797 | 0 | 0.00% |
| HTP | 467,857 | 449,713 | -18,144 | 3.88% |
| SP | 258,564 | 238,348 | -20,216 | 7.82% |
| GP | 157,698 | 157,698 | 0 | 0.00% |
| GOMP | 44,635 | 43,539 | -1,096 | 2.46% |
| MP | 248,001 | 247,489 | -512 | 0.21% |

## Full K-sweep cycle comparison

- Compared entries: 62.
- Improved: 46; unchanged: 16; regressed: 0.
- Total cycles: 3,571,863 -> 3,389,961, a reduction of 181,902 cycles (5.09%).

| Algorithm ID | Count | Div64 baseline | Balanced radix-4 | Delta | Improvement |
|---:|---:|---:|---:|---:|---:|
| 0 (OMP) | 8 | 420,642 | 402,950 | -17,692 | 4.21% |
| 1 (CoSaMP) | 7 | 670,630 | 611,190 | -59,440 | 8.86% |
| 2 (IHT) | 8 | 345,034 | 345,034 | 0 | 0.00% |
| 3 (HTP) | 8 | 730,348 | 684,692 | -45,656 | 6.25% |
| 4 (SP) | 7 | 569,679 | 521,239 | -48,440 | 8.50% |
| 5 (GP) | 8 | 347,114 | 347,114 | 0 | 0.00% |
| 6 (GOMP) | 8 | 228,296 | 218,390 | -9,906 | 4.34% |
| 7 (MP) | 8 | 260,120 | 259,352 | -768 | 0.30% |

## OOC synthesis at 100 MHz

- Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.
- Script: `scripts/run_synth_ls_balanced_radix4_cgra_top.tcl`.
- Reports: `runs/opt2/synth_ls_balanced_radix4_cgra_top/` (local, ignored by Git).
- Synthesis completed with 0 errors and 0 critical warnings.

| Metric | Div64 baseline | Balanced radix-4 | Delta |
|---|---:|---:|---:|
| Total LUT | 75,718 | 73,303 | -2,415 (-3.19%) |
| Logic LUT | 74,374 | 71,959 | -2,415 (-3.25%) |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,751 | 24,768 | +17 (+0.07%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | +3.487 ns | +2.152 ns | -1.335 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Estimated Fmax | 153.54 MHz | 127.42 MHz | -26.12 MHz |

## Decision

Keep this candidate as the balanced LS release. Relative to the prior cycle-best source, it improves every measured LS-using case, reduces total K-sweep cycles by 5.09%, removes 2,415 LUTs, keeps DSP/BRAM unchanged, and remains timing-clean at 100 MHz. IHT and GP are unchanged because their configured flows do not invoke LS refine.
