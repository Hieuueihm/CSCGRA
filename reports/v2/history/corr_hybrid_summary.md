# Sparse correlation hybrid-bypass optimization summary

## Scope and baseline

- Baseline: commit `d9bd414`, after the LS streamed block-8 optimization.
- Objective: reduce cycles on the shared correlation path, especially for IHT, GP, and MP, without regressing any K-sweep entry or increasing FPGA resources materially.
- Golden data, fixed-point widths, algorithm programs, support rules, LS solver, and divider are unchanged.

## Cycle profile and bottleneck

The phase profiler added to `tb_run1_noisy24_k8_rep_iter_profile.v` counted controller states and uop classes. At representative K=8, correlation uop 8 consumed 146,672 cycles for both IHT and GP, and 243,904 cycles for MP. The main state counts were:

| Algorithm | Total cycles | CORR_ACC (36) | CORR_PE_WAIT (54) | CORR_LATCH (57) | SCAN_DIRECT_STEP (77) | WR_MESH_WAIT (114) |
|---|---:|---:|---:|---:|---:|---:|
| IHT | 156,797 | 32,768 | 32,768 | 32,768 | 8,192 | 7,168 |
| GP | 157,698 | 32,768 | 32,768 | 32,768 | 8,192 | 7,168 |
| MP | 247,489 | 65,536 | 65,536 | 65,536 | 16,384 | 14,336 |

`CORR_LATCH` was therefore a full one-cycle bubble for every correlation row and was the best shared optimization target.

## Design exploration and retained architecture

A full bypass of `CORR_LATCH` passed OMP, CoSaMP, SP, and GOMP but failed long IHT, GP, and MP runs. Trace instrumentation isolated the error to rows 8, 16, ..., 56: the first row after each 8-row SPM bank transition needs an extra address-settle cycle.

The retained hybrid bypass:

- exposes the already existing signed PE multiplier product through `pe_core`, `pe_tile`, and `pe_cluster_4x4`; it does not instantiate another multiplier;
- feeds the row-0 products directly into `pearray`'s correlation accumulator during `CORR_PE_WAIT`;
- skips `CORR_LATCH` for normal rows and retains it only at nonzero rows divisible by 8, the SPM bank boundaries;
- removes the unused controller-side `corr_acc_lane` register.

For M=64, this removes 57 of 64 latch bubbles per 8-column correlation block, or 1,824 cycles per full correlation iteration at N=256.

## Representative K=8 validation and cycles

All eight algorithms match the unchanged final golden data.

| Algorithm | `d9bd414` | Hybrid bypass | Delta | Improvement |
|---|---:|---:|---:|---:|
| OMP | 79,637 | 65,045 | -14,592 | 18.32% |
| CoSaMP | 197,766 | 183,174 | -14,592 | 7.38% |
| IHT | 156,797 | 127,613 | -29,184 | 18.61% |
| HTP | 432,689 | 374,321 | -58,368 | 13.49% |
| SP | 202,900 | 188,308 | -14,592 | 7.19% |
| GP | 157,698 | 128,514 | -29,184 | 18.51% |
| GOMP | 42,749 | 35,453 | -7,296 | 17.07% |
| MP | 247,489 | 189,121 | -58,368 | 23.58% |
| **Total** | **1,517,725** | **1,291,549** | **-226,176** | **14.90%** |

GP-opt also passes: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`, with 65,164 checkpoint cycles and 128,514 final cycles.

## Full K-sweep

- Result entries: 62 baseline and 62 candidate.
- Improved: 62; unchanged: 0; regressed: 0.
- Golden accounting: `33 + 45 + 45 + 45 + 180 = 348 PASS, 0 FAIL`.
- CoSaMP/SP at K=16 retain the existing `requires_2K_candidate_support` skip rule.
- Exact error scan for mismatch, timeout, and nonzero FAIL: 0 matches.

| Algorithm ID | Count | `d9bd414` | Hybrid bypass | Delta | Improvement |
|---:|---:|---:|---:|---:|---:|
| 0 (OMP) | 8 | 380,994 | 322,706 | -58,288 | 15.30% |
| 1 (CoSaMP) | 7 | 513,968 | 484,864 | -29,104 | 5.66% |
| 2 (IHT) | 8 | 345,034 | 286,746 | -58,288 | 16.89% |
| 3 (HTP) | 8 | 605,488 | 547,200 | -58,288 | 9.63% |
| 4 (SP) | 7 | 444,687 | 415,583 | -29,104 | 6.54% |
| 5 (GP) | 8 | 347,114 | 288,826 | -58,288 | 16.79% |
| 6 (GOMP) | 8 | 205,827 | 176,683 | -29,144 | 14.16% |
| 7 (MP) | 8 | 259,352 | 201,064 | -58,288 | 22.47% |
| **Total** | **62** | **3,102,464** | **2,723,672** | **-378,792** | **12.21%** |

Local reproducibility logs (ignored by Git):

- `runs/opt2/corr_hybrid_ksweep_case0/xsim.run.stdout.log`
- `runs/opt2/corr_hybrid_ksweep_case1/xsim.run.stdout.log`
- `runs/opt2/corr_hybrid_ksweep_case2_3/xsim.case2.final.stdout.log`
- `runs/opt2/corr_hybrid_ksweep_case4_7/xsim.case3.stdout.log`
- `runs/opt2/corr_hybrid_ksweep_case4_7/xsim.run.stdout.log`
- `runs/opt2/corr_hybrid_gpopt/xsim.run.stdout.log`

## OOC synthesis at 100 MHz

- Tool/part: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`.
- Script: `scripts/run_synth_corr_hybrid_cgra_top.tcl`.
- Reports: `runs/opt2/synth_corr_hybrid_cgra_top/` (local, ignored by Git).
- Synthesis completed with 0 errors and 0 critical warnings; all timing constraints are met.

| Metric | `d9bd414` | Hybrid bypass | Delta |
|---|---:|---:|---:|
| Total LUT | 75,213 | 74,656 | -557 (-0.74%) |
| Logic LUT | 73,421 | 72,864 | -557 (-0.76%) |
| LUTRAM | 1,792 | 1,792 | 0 |
| FF | 24,897 | 24,819 | -78 (-0.31%) |
| BRAM36 | 24 | 24 | 0 |
| DSP | 105 | 105 | 0 |
| WNS | +2.977 ns | +2.745 ns | -0.232 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |

The 7.245 ns critical path remains in the shared divider, not the correlation bypass.

## Decision and next optimization directions

Keep the hybrid bypass. It improves every measured entry, removes 12.21% of full-sweep cycles, lowers LUT/FF slightly, adds no DSP/BRAM, and preserves clean 100 MHz timing.

The next profile-driven candidates, in priority order, are:

1. overlap `SCAN_DIRECT_STEP` with the preceding correlation write/stream phase;
2. reduce `WR_MESH_WAIT` by forwarding the completed lane result instead of waiting for the mesh-visible register;
3. pipeline support merge/top-K selection so candidate scan and mask update overlap;
4. stream residual/vector updates across columns after correlation, with full fixed-point and K-sweep validation;
5. revisit LS factorization only if a shared-memory schedule can reduce cycles without adding another divider or matrix-bank multiplier set.
