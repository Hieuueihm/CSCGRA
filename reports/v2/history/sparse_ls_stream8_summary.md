# Sparse LS streamed block-8 optimization summary

## Scope

- Baseline: the validated balanced radix-4 LS source in `CSCGRA_opt_architecture_opt2`.
- Target: reduce sparse-algorithm cycle count while keeping correctness and 100 MHz timing; small LUT/FF/DSP increases are acceptable.
- Golden data, algorithm flow, fixed-point widths, support rules, SDK data, and the shared radix-4 divider are unchanged.

## Design exploration

An initial block-4 candidate read and multiplied four row-update columns in parallel. It reduced cycle count, but synthesis reached 79,854 LUTs, 3,392 LUTRAMs, and 146 DSPs. The LS service alone grew from 21 to 65 DSPs, so that candidate was rejected as an unbalanced use of resources.

The retained candidate uses a streamed block-8 transaction:

- `sparse_loop_controller.v` issues one LS row-update request for up to eight consecutive columns and advances `solve_k` by eight.
- `lane_valid` marks the real columns in the final partial block, so K=2/K=4 and other short tails do not execute invalid writes.
- `ls_matrix_service.v` pipelines one read and one write per clock after startup while retaining one shared factor multiplier. The next column is read while the previous result is committed.
- The block finishes at the last valid lane rather than always waiting for lane 7.
- No extra matrix bank or divider was added.

## Functional validation

- GP-opt K=8: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`; 157,698 cycles, unchanged from baseline.
- Noisy representative K=8: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`.
- Full K-sweep: 62 result entries, `348 PASS, 0 FAIL`; no missing entry, extra entry, mismatch, timeout, or cycle regression.
- The full sweep was sharded with the existing `CASE`/`START_CASE` testbench controls. Pass accounting is 33 + 45 + 45 + 45 + 180 = 348.
- CoSaMP/SP K=16 retain the existing `requires_2K_candidate_support` skip rule.
- Local logs (ignored by Git):
  - `runs/opt2/sparse_ls_stream8_gpopt/xsim.run.stdout.log`
  - `runs/opt2/sparse_ls_stream8_snr_k8_rep/xsim.run.stdout.log`
  - `runs/opt2/sparse_ls_stream8_ksweep/xsim.run.stdout.log` (case 0)
  - `runs/opt2/sparse_ls_stream8_ksweep_case1_3/xsim.run.stdout.log` (case 1 results)
  - `runs/opt2/sparse_ls_stream8_ksweep_case2/xsim.run.stdout.log`
  - `runs/opt2/sparse_ls_stream8_ksweep_case3/xsim.run.stdout.log`
  - `runs/opt2/sparse_ls_stream8_ksweep_case4_7/xsim.run.stdout.log`

## Representative K=8 cycle comparison

| Algorithm | Balanced radix-4 baseline | Streamed block-8 | Delta | Improvement |
|---|---:|---:|---:|---:|
| OMP | 80,897 | 79,637 | -1,260 | 1.56% |
| CoSaMP | 233,214 | 197,766 | -35,448 | 15.20% |
| IHT | 156,797 | 156,797 | 0 | 0.00% |
| HTP | 449,713 | 432,689 | -17,024 | 3.79% |
| SP | 238,348 | 202,900 | -35,448 | 14.87% |
| GP | 157,698 | 157,698 | 0 | 0.00% |
| GOMP | 43,539 | 42,749 | -790 | 1.81% |
| MP | 247,489 | 247,489 | 0 | 0.00% |

## Full K-sweep cycle comparison

- Compared entries: 62.
- Improved: 38; unchanged: 24; regressed: 0.
- Total cycles: 3,389,961 -> 3,102,464, a reduction of 287,497 cycles (8.48%).

| Algorithm ID | Count | Balanced radix-4 | Streamed block-8 | Delta | Improvement |
|---:|---:|---:|---:|---:|---:|
| 0 (OMP) | 8 | 402,950 | 380,994 | -21,956 | 5.45% |
| 1 (CoSaMP) | 7 | 611,190 | 513,968 | -97,222 | 15.91% |
| 2 (IHT) | 8 | 345,034 | 345,034 | 0 | 0.00% |
| 3 (HTP) | 8 | 684,692 | 605,488 | -79,204 | 11.57% |
| 4 (SP) | 7 | 521,239 | 444,687 | -76,552 | 14.69% |
| 5 (GP) | 8 | 347,114 | 347,114 | 0 | 0.00% |
| 6 (GOMP) | 8 | 218,390 | 205,827 | -12,563 | 5.75% |
| 7 (MP) | 8 | 259,352 | 259,352 | 0 | 0.00% |

## OOC synthesis at 100 MHz

- Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.
- Script: `scripts/run_synth_sparse_ls_stream8_cgra_top.tcl`.
- Reports: `runs/opt2/synth_sparse_ls_stream8_cgra_top/` (local, ignored by Git).
- Synthesis completed with 0 errors and 0 critical warnings; all timing constraints are met.

| Metric | Balanced radix-4 | Streamed block-8 | Delta |
|---|---:|---:|---:|
| Total LUT | 73,303 | 75,213 | +1,910 (+2.61%) |
| Logic LUT | 71,959 | 73,421 | +1,462 (+2.03%) |
| LUTRAM | 1,344 | 1,792 | +448 (+33.33%) |
| FF | 24,768 | 24,897 | +129 (+0.52%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 105 | +3 (+2.94%) |
| WNS | +2.152 ns | +2.977 ns | +0.825 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |

The critical path remains in the shared divider, not the streamed row-update path. The synthesized LS service retains 21 DSPs; the three-DSP top-level increase comes from surrounding control/data-path remapping after enabling the block interface.

## Decision

Keep the streamed block-8 candidate as the new sparse/LS balanced release. It reduces the full-sweep cycle total by 8.48%, has no measured regression, preserves correctness and clean 100 MHz timing, and limits the resource cost to +2.61% LUT, +0.52% FF, unchanged BRAM, and +3 DSP. IHT, GP, and MP remain cycle-identical because their configured paths do not benefit from the LS row-update batching.
