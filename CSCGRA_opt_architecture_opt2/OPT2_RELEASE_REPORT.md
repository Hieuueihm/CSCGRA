# CSCGRA opt2 release report

## Final release folder
- Opt2 RTL/SDK/TB folder: `D:\vivado_pj\CSCGRA_opt_architecture_opt2`
- Baseline preserved: `D:\vivado_pj\CSCGRA_opt_architecture`
- Final BD folder: `D:\vivado_pj\bd_release_opt2_20260708_ctx_bram`

## Final RTL optimization kept
- Main resource optimization: moved context memory in `configmem` from distributed LUTRAM/asynchronous read to BRAM/synchronous read.
- Sequencer was updated with one fetch-wait state so the synchronous BRAM context read is functionally correct.
- PE hierarchy optimization blockers were removed so Vivado can optimize across PE module boundaries.
- `ENABLE_MESH_CTX` plumbing remains available, but final top keeps `ENABLE_MESH_CTX(1)` because disabling mesh context failed golden validation.
- Golden/reference data was not changed to match RTL.
- GP remains the gradient-step flow using `SOP_GRAD_STEP`, not `SOP_GP_NO_LS_UPDATE`.

## Files changed for final RTL
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\configmem.v`
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sequencer.v`
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\pe_core.v`
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\pe_tile.v`
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\pe_cluster_4x4.v`
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\pearray.v`
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\cgra_top.v`

## SDK/checker updates
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\check_sdk_tb_sync_opt_architecture.py` now uses the local opt2 root.
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\export_k_sweep_c_header_opt_architecture.py` now uses the local opt2 root.
- `D:\vivado_pj\CSCGRA_opt_architecture_opt2\sdk_app\src\cscgra_k_sweep_golden.h` was regenerated from opt2 golden data.
- Sync checker result: PASS.

## Vivado xsim validation
- `tb_run1_noisy24_k8_rep`: PASS, `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - Log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\snr_k8_rep_ctx_bram_trial\xsim.log`
- `tb_run1_k_sweep`: PASS, `348 PASS, 0 FAIL`
  - Log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\ksweep_ctx_bram_trial\xsim.log`
  - CoSaMP/SP at K=16 are skipped with `requires_2K_candidate_support`.
- `tb_run1_noisy24_k8_rep_gpopt`: PASS, `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - Log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\snr_k8_gpopt_ctx_bram_trial\xsim.log`

## OOC synth cgra_top
- Tool: Vivado 2018.1
- Part: `xczu7ev-ffvc1156-2-e`
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_incr_cgra_top.tcl`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_ctx_bram_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_ctx_bram_cgra_top\cgra_top_timing.rpt`

| Metric | Baseline | Opt2 final | Delta |
|---|---:|---:|---:|
| LUT total | 80,318 | 73,078 | -7,240 (-9.01%) |
| Logic LUT | 73,854 | 71,734 | -2,120 (-2.87%) |
| LUTRAM | 6,464 | 1,344 | -5,120 (-79.21%) |
| FF | 25,602 | 24,865 | -737 (-2.88%) |
| BRAM36 | 16 | 24 | +8 (+50.00%) |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

## Cycle impact for representative K=8 SNR TB
- OMP: 87,629 -> 87,673 (+44)
- CoSaMP: 270,170 -> 270,430 (+260)
- IHT: 164,093 -> 164,577 (+484)
- HTP: 491,761 -> 492,725 (+964)
- SP: 275,304 -> 275,780 (+476)
- GP: 164,994 -> 165,510 (+516)
- GOMP: 47,129 -> 47,161 (+32)
- MP: 262,401 -> 262,565 (+164)

## BD ZCU106
- BD project: `D:\vivado_pj\bd_release_opt2_20260708_ctx_bram\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.xpr`
- BD file: `D:\vivado_pj\bd_release_opt2_20260708_ctx_bram\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\cscgra_soc_bd.bd`
- Wrapper: `D:\vivado_pj\bd_release_opt2_20260708_ctx_bram\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\hdl\cscgra_soc_bd_wrapper.v`
- Handoff: `D:\vivado_pj\bd_release_opt2_20260708_ctx_bram\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\hw_handoff\cscgra_soc_bd.hwh`
- BD build log: `D:\vivado_pj\bd_release_opt2_20260708_ctx_bram\bd_build.log`
- BD build log has no `ERROR:` or `CRITICAL WARNING:`.

## Failed trial intentionally not kept
- Tried setting PE mesh context off with `ENABLE_MESH_CTX(0)`.
- Result: OMP/CoSaMP golden mismatches in `tb_run1_noisy24_k8_rep`.
- Action: reverted final top to `ENABLE_MESH_CTX(1)`.

## Next deeper RTL optimization candidates
- `sparse_loop_controller`: largest remaining LUT hotspot and best next target.
- `support_set_service`: candidate for control/resource reduction.
- `pe_stream_topk_serial_service`: candidate for top-k control simplification.
- LS refine/control path: possible cycle reduction, but higher functional risk and needs full validation.

## Trial not kept: top-k lane absolute sharing
- File trialed: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\pe_stream_topk_serial_service.v`
- Change: shared the lane absolute-value expression through wires in `S_LANE`.
- Validation passed:
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Synth result was identical to ctx-BRAM final: LUT total `73,078`, FF `24,865`, BRAM36 `24`, DSP `102`, WNS `3.487 ns`.
- Decision: rolled back because it gives no measurable resource/timing/cycle benefit.

## Final candidate update: support mask16
- File changed: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_kernel_service_engine.v`
- Change: `support_lane_mask` now compares only the valid path0 support range up to `MAX_K_COUNT`/16; `selected_lane_mask` still scans the full 32-entry selected path to preserve 2K candidate behavior.
- Rationale: current valid support output to `sparse_loop_controller` is 16-wide; CoSaMP/SP K=16 remain skipped, so path0 support mask does not need 32-way compare.
- Validation passed:
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`, with CoSaMP/SP K=16 skipped using `requires_2K_candidate_support`.
- SDK/TB sync checker: PASS.

### support mask16 synth result
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_support_mask16_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_support_mask16_cgra_top\cgra_top_timing.rpt`

| Metric | Baseline | Opt2 ctx-BRAM | Opt2 support-mask16 | Delta vs ctx-BRAM |
|---|---:|---:|---:|---:|
| LUT total | 80,318 | 73,078 | 72,617 | -461 |
| Logic LUT | 73,854 | 71,734 | 71,273 | -461 |
| LUTRAM | 6,464 | 1,344 | 1,344 | 0 |
| FF | 25,602 | 24,865 | 24,891 | +26 |
| BRAM36 | 16 | 24 | 24 | 0 |
| DSP | 102 | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 153.54 MHz | 0 MHz |

### support mask16 cycle impact
- Representative K=8 cycles are unchanged versus ctx-BRAM because this is combinational mask pruning only.
- OMP 87,673; CoSaMP 270,430; IHT 164,577; HTP 492,725; SP 275,780; GP 165,510; GOMP 47,161; MP 262,565.

## BD update for support mask16
- BD folder: `D:\vivado_pj\bd_release_opt2_20260708_support_mask16`
- BD project: `D:\vivado_pj\bd_release_opt2_20260708_support_mask16\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.xpr`
- BD file: `D:\vivado_pj\bd_release_opt2_20260708_support_mask16\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\cscgra_soc_bd.bd`
- Wrapper: `D:\vivado_pj\bd_release_opt2_20260708_support_mask16\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\hdl\cscgra_soc_bd_wrapper.v`
- Handoff: `D:\vivado_pj\bd_release_opt2_20260708_support_mask16\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\hw_handoff\cscgra_soc_bd.hwh`
- BD build log: `D:\vivado_pj\bd_release_opt2_20260708_support_mask16\bd_build.log`
- BD build completed with no `ERROR:` and no `CRITICAL WARNING:`.

## Seq-prefetch cycle update
- File changed: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sequencer.v`
- Change: context address for the next sequential/branch target is driven in `S_RETIRE`, then the sequencer goes directly to `S_FETCH_WAIT`. This removes the extra `S_FETCH` address-issue cycle introduced by synchronous context BRAM while keeping the BRAM read latency model intact.
- Validation passed:
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`, with CoSaMP/SP K=16 skipped using `requires_2K_candidate_support`.
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\seq_prefetch_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\seq_prefetch_snr_k8_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\seq_prefetch_ksweep\xsim.stdout.log`

### seq-prefetch K=8 representative cycles
| Algorithm | Iterations | Cycles |
|---|---:|---:|
| OMP | 8 | 87,629 |
| CoSaMP | 8 | 270,170 |
| IHT | 16 | 164,093 |
| HTP | 32 | 491,761 |
| SP | 8 | 275,304 |
| GP | 16 | 164,994 |
| GOMP | 4 | 47,129 |
| MP | 32 | 262,401 |

### seq-prefetch synth result
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_seq_prefetch_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_seq_prefetch_cgra_top\cgra_top_timing.rpt`

| Metric | Opt2 support-mask16 | Opt2 seq-prefetch | Delta |
|---|---:|---:|---:|
| LUT total | 72,617 | 72,593 | -24 |
| Logic LUT | 71,273 | 71,249 | -24 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,891 | 24,886 | -5 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

## Mesh wait6 cycle update
- File changed: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: `MESH_CTX_WAIT_CYCLES` reduced from 12 to 6. This trims the PE mesh-context residual/write-back wait while keeping enough latency margin for the pipelined 4-row PE mesh.
- Failed lower-bound trials:
  - `wait=4`: GP `REPORT_1K` passed but final GP mismatched golden, so not kept.
  - `wait=5`: GP `REPORT_1K` passed but final GP mismatched golden, so not kept.
- Validation passed for kept `wait=6`:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`, with CoSaMP/SP K=16 skipped using `requires_2K_candidate_support`.
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\meshwait6_snr_k8_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\meshwait6_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\meshwait6_ksweep\xsim.stdout.log`

### meshwait6 K=8 representative cycles
| Algorithm | Seq-prefetch cycles | Meshwait6 cycles | Delta |
|---|---:|---:|---:|
| OMP | 87,629 | 84,557 | -3,072 |
| CoSaMP | 270,170 | 264,026 | -6,144 |
| IHT | 164,093 | 157,949 | -6,144 |
| HTP | 491,761 | 479,473 | -12,288 |
| SP | 275,304 | 269,160 | -6,144 |
| GP | 164,994 | 158,850 | -6,144 |
| GOMP | 47,129 | 45,593 | -1,536 |
| MP | 262,401 | 250,113 | -12,288 |

### meshwait6 synth result
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_meshwait6_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_meshwait6_cgra_top\cgra_top_timing.rpt`

| Metric | Seq-prefetch | Meshwait6 | Delta |
|---|---:|---:|---:|
| LUT total | 72,593 | 72,593 | 0 |
| Logic LUT | 71,249 | 71,249 | 0 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,886 | 24,886 | 0 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

## Scan-direct fast-entry cycle update
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: remove the extra `S_SCAN_DIRECT` setup cycle on scan/residual entry by loading `phi_scan_col_q` and `phi_scan_state_q` at the previous state and jumping directly to `S_SCAN_DIRECT_STEP`.
- This is kept on top of `MESH_CTX_WAIT_CYCLES=6`.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`, with CoSaMP/SP K=16 skipped using `requires_2K_candidate_support`.
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\scanfast_snr_k8_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\scanfast_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\scanfast_ksweep\xsim.stdout.log`

### scanfast K=8 representative cycles
| Algorithm | Meshwait6 cycles | Scanfast cycles | Delta |
|---|---:|---:|---:|
| OMP | 84,557 | 83,541 | -1,016 |
| CoSaMP | 264,026 | 261,994 | -2,032 |
| IHT | 157,949 | 156,925 | -1,024 |
| HTP | 479,473 | 475,409 | -4,064 |
| SP | 269,160 | 267,128 | -2,032 |
| GP | 158,850 | 157,826 | -1,024 |
| GOMP | 45,593 | 45,085 | -508 |
| MP | 250,113 | 248,065 | -2,048 |

### scanfast synth result
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_scanfast_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_scanfast_cgra_top\cgra_top_timing.rpt`

| Metric | Meshwait6 | Scanfast | Delta |
|---|---:|---:|---:|
| LUT total | 72,593 | 72,010 | -583 |
| Logic LUT | 71,249 | 70,666 | -583 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,886 | 24,871 | -15 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 2.481 ns | -1.006 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 132.99 MHz | -20.55 MHz |

### scanfast timing note
- New worst path is `support_cache_reg[7][2] -> phi_cache_reg[7][10]` inside `sparse_loop_controller`.
- The path is still timing-clean at 100 MHz with WNS `2.481 ns`, but scanfast trades about `1.006 ns` WNS for lower cycle count and `583` fewer LUTs.

## Recheck after rejected acc-wait trial
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Kept: scan-direct fast-entry flow, including direct entry from the residual write commit path.
- Reverted: the attempted `S_ACC_PE_WAIT -> S_ACC_RHS` shortcut, because it caused CoSaMP golden mismatch in `tb_run1_noisy24_k8_rep`.
- Restored safe path: `S_ACC_PE_WAIT -> S_ACC_PE_WAIT2 -> S_ACC_RHS`.
- Validation passed after revert:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`, with CoSaMP/SP K=16 skipped using `requires_2K_candidate_support`.
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\recheck_gpopt_after_revert\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\recheck_snr_k8_after_revert\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\recheck_ksweep_after_revert\xsim.stdout.log`

### Rechecked K=8 representative cycles
| Algorithm | Cycles |
|---|---:|
| OMP | 83,533 |
| CoSaMP | 261,978 |
| IHT | 156,925 |
| HTP | 475,377 |
| SP | 267,112 |
| GP | 157,826 |
| GOMP | 45,081 |
| MP | 248,065 |

## Load-coeff single-wait candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: remove one extra wait state from the coefficient-load path by changing `S_LOAD_COEFF_READ -> S_LOAD_COEFF_CAP`; `S_LOAD_COEFF_WAIT` remains as a safe fallback state but is no longer on the normal path.
- Kept constraints:
  - Golden/testbench unchanged.
  - GP remains gradient-step flow.
  - CoSaMP/SP K=16 skip rule unchanged.
  - Safe `S_ACC_PE_WAIT -> S_ACC_PE_WAIT2 -> S_ACC_RHS` path unchanged.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\loadcoeff1_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\loadcoeff1_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\loadcoeff1_ksweep\xsim.stdout.log`

### loadcoeff1 K=8 representative cycles
| Algorithm | Rechecked scanfast | Loadcoeff1 | Delta |
|---|---:|---:|---:|
| OMP | 83,533 | 83,533 | 0 |
| CoSaMP | 261,978 | 261,978 | 0 |
| IHT | 156,925 | 156,797 | -128 |
| HTP | 475,377 | 475,377 | 0 |
| SP | 267,112 | 267,112 | 0 |
| GP | 157,826 | 157,698 | -128 |
| GOMP | 45,081 | 45,081 | 0 |
| MP | 248,065 | 248,065 | 0 |

### loadcoeff1 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_loadcoeff1_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_loadcoeff1_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_loadcoeff1_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_loadcoeff1_cgra_top\cgra_top_timing.rpt`

| Metric | Scanfast synth | Loadcoeff1 synth | Delta |
|---|---:|---:|---:|
| LUT total | 72,010 | 73,897 | +1,887 |
| Logic LUT | 70,666 | 72,553 | +1,887 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,871 | 24,874 | +3 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 2.481 ns | 2.683 ns | +0.202 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 132.99 MHz | 136.67 MHz | +3.68 MHz |

### loadcoeff1 conclusion
- Kept as a valid cycle candidate because all required xsim checks pass and timing remains clean at 100 MHz.
- Benefit is narrow: IHT/GP paths improve by 128 cycles in the representative K=8 SNR test; OMP/CoSaMP/HTP/SP/GOMP/MP are unchanged.
- Tradeoff: current synth result uses more LUTs than the previous scanfast synth, although WNS improves slightly.

## Div-prep bypass candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: bypass two one-cycle division-prep states in the LS solve path:
  - `S_ELIM_ROW_READ -> S_DIV_INIT` directly, while setting `div_return_back <= 1'b0`.
  - `S_BACK_RHS_READ_WAIT -> S_DIV_INIT` directly, while setting `div_return_back <= 1'b1`.
- Kept as fallback states but removed from the normal LS/refine path: `S_ELIM_PREP`, `S_BACK_DIV`.
- Kept constraints:
  - Golden/testbench unchanged.
  - GP remains gradient-step flow.
  - CoSaMP/SP K=16 skip rule unchanged.
  - Safe `S_ACC_PE_WAIT -> S_ACC_PE_WAIT2 -> S_ACC_RHS` path unchanged.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\divprep1_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\divprep1_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\divprep1_ksweep\xsim.stdout.log`

### divprep1 K=8 representative cycles
| Algorithm | Loadcoeff1 | Divprep1 | Delta |
|---|---:|---:|---:|
| OMP | 83,533 | 83,413 | -120 |
| CoSaMP | 261,978 | 260,702 | -1,276 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 475,377 | 474,225 | -1,152 |
| SP | 267,112 | 265,836 | -1,276 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 45,081 | 45,011 | -70 |
| MP | 248,065 | 248,065 | 0 |

### divprep1 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_divprep1_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_divprep1_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_divprep1_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_divprep1_cgra_top\cgra_top_timing.rpt`

| Metric | Loadcoeff1 synth | Divprep1 synth | Delta |
|---|---:|---:|---:|
| LUT total | 73,897 | 72,787 | -1,110 |
| Logic LUT | 72,553 | 71,443 | -1,110 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,874 | 24,870 | -4 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 2.683 ns | 3.487 ns | +0.804 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 136.67 MHz | 153.54 MHz | +16.87 MHz |

### divprep1 conclusion
- Kept as the current best validated cycle candidate.
- It improves the LS-heavy algorithms without changing golden data or algorithm context semantics.
- Timing is clean at 100 MHz and improves relative to loadcoeff1; resource also improves relative to loadcoeff1 while keeping DSP unchanged at 102.

## MP score-read wait bypass candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: bypass one MP score-read wait state by changing the normal path from `S_MP_X_READ -> S_MP_X_WAIT -> S_MP_SCORE_CAP` to `S_MP_X_READ -> S_MP_SCORE_CAP`.
- Kept `S_MP_X_WAIT` as fallback, but it is no longer on the normal MP update path.
- Kept constraints:
  - Golden/testbench unchanged.
  - GP remains gradient-step flow.
  - CoSaMP/SP K=16 skip rule unchanged.
  - Safe `S_ACC_PE_WAIT -> S_ACC_PE_WAIT2 -> S_ACC_RHS` path unchanged.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\mpwait1_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\mpwait1_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\mpwait1_ksweep\xsim.stdout.log`

### mpwait1 K=8 representative cycles
| Algorithm | Divprep1 | Mpwait1 | Delta |
|---|---:|---:|---:|
| OMP | 83,413 | 83,413 | 0 |
| CoSaMP | 260,702 | 260,702 | 0 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 474,225 | 474,225 | 0 |
| SP | 265,836 | 265,836 | 0 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 45,011 | 45,011 | 0 |
| MP | 248,065 | 248,033 | -32 |

### mpwait1 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_mpwait1_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_mpwait1_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_mpwait1_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_mpwait1_cgra_top\cgra_top_timing.rpt`

| Metric | Divprep1 synth | Mpwait1 synth | Delta |
|---|---:|---:|---:|
| LUT total | 72,787 | 73,230 | +443 |
| Logic LUT | 71,443 | 71,886 | +443 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,870 | 24,885 | +15 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 2.680 ns | -0.807 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 136.61 MHz | -16.93 MHz |

### mpwait1 conclusion
- Kept as a valid but small cycle improvement candidate because all required xsim checks pass.
- Benefit is limited to MP: representative K=8 MP improves by 32 cycles; k_sweep MP improves by 2 to 16 cycles depending on K/configuration.
- Timing remains clean at 100 MHz and DSP stays at 102, but LUT increases and WNS drops versus divprep1.

## Back-substitution multiply/update merge candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: merge the LS back-substitution multiply/update path by accumulating `A(i,j)*x(j)` directly in `S_BACK_ACC_READ`, bypassing the normal `S_BACK_MUL -> S_BACK_UPDATE` two-state path.
- Kept fallback states `S_BACK_MUL` and `S_BACK_UPDATE`, but they are no longer on the normal back-substitution path.
- Kept constraints:
  - Golden/testbench unchanged.
  - GP remains gradient-step flow.
  - CoSaMP/SP K=16 skip rule unchanged.
  - Safe `S_ACC_PE_WAIT -> S_ACC_PE_WAIT2 -> S_ACC_RHS` path unchanged.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backmul1_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backmul1_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backmul1_ksweep\xsim.stdout.log`

### backmul1 K=8 representative cycles
| Algorithm | Mpwait1 | Backmul1 | Delta |
|---|---:|---:|---:|
| OMP | 83,413 | 83,245 | -168 |
| CoSaMP | 260,702 | 258,518 | -2,184 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 474,225 | 472,433 | -1,792 |
| SP | 265,836 | 263,652 | -2,184 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 45,011 | 44,911 | -100 |
| MP | 248,033 | 248,033 | 0 |

### backmul1 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_backmul1_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backmul1_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backmul1_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backmul1_cgra_top\cgra_top_timing.rpt`

| Metric | Mpwait1 synth | Backmul1 synth | Delta |
|---|---:|---:|---:|
| LUT total | 73,230 | 73,195 | -35 |
| Logic LUT | 71,886 | 71,851 | -35 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,885 | 24,763 | -122 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 111 | +9 |
| WNS | 2.680 ns | 3.487 ns | +0.807 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 136.61 MHz | 153.54 MHz | +16.93 MHz |

### backmul1 conclusion
- Functionally valid and currently best for cycle reduction among tested candidates.
- It improves LS-heavy algorithms more than prior candidates, especially CoSaMP/SP/HTP.
- Resource tradeoff is significant: DSP increases from 102 to 111, although LUT/FF and WNS improve versus mpwait1 and timing remains clean at 100 MHz.
- If the release target must keep DSP at 102, prefer `mpwait1` or `divprep1`; if the priority is cycle only and DSP +9 is acceptable, `backmul1` is the fastest validated candidate so far.

## Backmul no-DSP synthesis hint candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: keep the `backmul1` cycle path but move the direct back-substitution product to a named wire with `(* use_dsp = "no" *)` synthesis hint.
- Goal: preserve cycle reduction while reducing the extra DSP cost introduced by `backmul1`.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backmul1_nodsp_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backmul1_nodsp_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backmul1_nodsp_ksweep\xsim.stdout.log`

### backmul1_nodsp K=8 representative cycles
| Algorithm | Backmul1 | Backmul1 nodsp | Delta |
|---|---:|---:|---:|
| OMP | 83,245 | 83,245 | 0 |
| CoSaMP | 258,518 | 258,518 | 0 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 472,433 | 472,433 | 0 |
| SP | 263,652 | 263,652 | 0 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 44,911 | 44,911 | 0 |
| MP | 248,033 | 248,033 | 0 |

### backmul1_nodsp synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_backmul1_nodsp_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backmul1_nodsp_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backmul1_nodsp_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backmul1_nodsp_cgra_top\cgra_top_timing.rpt`

| Metric | Backmul1 synth | Backmul1 nodsp synth | Delta |
|---|---:|---:|---:|
| LUT total | 73,195 | 76,743 | +3,548 |
| Logic LUT | 71,851 | 75,399 | +3,548 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,763 | 24,779 | +16 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 111 | 105 | -6 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

### backmul1_nodsp conclusion
- Functionally valid and preserves all `backmul1` cycle reductions.
- The synthesis hint partially reduces DSP usage from 111 to 105, but does not restore the original 102 DSP count.
- Tradeoff is worse LUT than `backmul1`: +3,548 LUT, while WNS remains 3.487 ns and timing still passes at 100 MHz.
- Current best cycle/resource balance remains a design choice: `backmul1` for best speed with 111 DSP, `backmul1_nodsp` for 105 DSP but higher LUT/lower WNS, or `divprep1`/`mpwait1` for 102 DSP.

## Elimination RHS-read bypass candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: bypass the unused RHS read between `S_ELIM_DIV_DONE` and `S_ELIM_UPDATE` on the normal Gaussian-elimination update path.
- Kept fallback `S_ELIM_RHS_READ_WAIT` state in RTL, but the normal path now goes directly from division completion to elimination update.
- Kept constraints:
  - Golden/testbench unchanged.
  - GP remains gradient-step flow.
  - CoSaMP/SP K=16 skip rule unchanged.
  - Safe `S_ACC_PE_WAIT -> S_ACC_PE_WAIT2 -> S_ACC_RHS` path unchanged.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\elimrhs0_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\elimrhs0_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\elimrhs0_ksweep\xsim.stdout.log`

### elimrhs0 K=8 representative cycles
| Algorithm | Backmul1 nodsp | Elimrhs0 | Delta |
|---|---:|---:|---:|
| OMP | 83,245 | 82,993 | -252 |
| CoSaMP | 258,518 | 255,242 | -3,276 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 472,433 | 469,745 | -2,688 |
| SP | 263,652 | 260,376 | -3,276 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 44,911 | 44,761 | -150 |
| MP | 248,033 | 248,033 | 0 |

### elimrhs0 K=8 k_sweep cycles
| Algorithm | Backmul1 nodsp | Elimrhs0 | Delta |
|---|---:|---:|---:|
| OMP | 83,245 | 82,993 | -252 |
| CoSaMP | 258,518 | 280,656 | +22,138 |
| IHT | 156,797 | 79,363 | -77,434 |
| HTP | 472,433 | 118,795 | -353,638 |
| SP | 263,652 | 260,418 | -3,234 |
| GP | 157,698 | 79,771 | -77,927 |
| GOMP | 44,911 | 44,760 | -151 |
| MP | 248,033 | 63,377 | -184,656 |

### elimrhs0 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_elimrhs0_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_elimrhs0_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_elimrhs0_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_elimrhs0_cgra_top\cgra_top_timing.rpt`

| Metric | Backmul1 nodsp synth | Elimrhs0 synth | Delta |
|---|---:|---:|---:|
| LUT total | 76,743 | 71,372 | -5,371 |
| Logic LUT | 75,399 | 70,028 | -5,371 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,779 | 24,756 | -23 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 105 | 102 | -3 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

### elimrhs0 conclusion
- Functionally valid across the required K=8 noisy checks and full `k_sweep`.
- Best current release candidate for combined cycle/resource/timing: it preserves timing at WNS 3.487 ns, restores DSP to 102, and reduces LUT/FF versus `backmul1_nodsp`.
- It improves LS-heavy representative K=8 runs for OMP/CoSaMP/HTP/SP/GOMP, and strongly improves k_sweep IHT/HTP/GP/MP cycle counts.
- Note: k_sweep CoSaMP K=8 increases versus `backmul1_nodsp`; keep this as the main remaining tradeoff if prioritizing CoSaMP-only cycle.

## Back-solve diagonal read fast-entry candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: enter `S_BACK_PREP_READ` directly when the back-substitution loop has no more upper-triangular products to accumulate, and launch the diagonal `LS_OP_READ2` from `S_BACK_INIT` or the final `S_BACK_ACC_READ` cycle.
- Goal: remove one control cycle per back-solve row without changing LS math, golden data, GP gradient-step, or the CoSaMP/SP K=16 skip rule.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backprep0_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backprep0_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backprep0_ksweep\xsim.stdout.log`

### backprep0 K=8 representative cycles
| Algorithm | Elimrhs0 | Backprep0 | Delta |
|---|---:|---:|---:|
| OMP | 82,993 | 82,921 | -72 |
| CoSaMP | 255,242 | 254,874 | -368 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 469,745 | 469,233 | -512 |
| SP | 260,376 | 260,008 | -368 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 44,761 | 44,721 | -40 |
| MP | 248,033 | 248,033 | 0 |

### backprep0 K=8 k_sweep cycles
| Algorithm | Elimrhs0 | Backprep0 | Delta |
|---|---:|---:|---:|
| OMP | 82,993 | 82,921 | -72 |
| CoSaMP | 280,656 | 280,272 | -384 |
| IHT | 79,363 | 79,363 | 0 |
| HTP | 118,795 | 118,667 | -128 |
| SP | 260,418 | 260,050 | -368 |
| GP | 79,771 | 79,771 | 0 |
| GOMP | 44,760 | 44,720 | -40 |
| MP | 63,377 | 63,377 | 0 |

### backprep0 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_backprep0_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backprep0_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backprep0_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backprep0_cgra_top\cgra_top_timing.rpt`

| Metric | Elimrhs0 synth | Backprep0 synth | Delta |
|---|---:|---:|---:|
| LUT total | 71,372 | 70,677 | -695 |
| Logic LUT | 70,028 | 69,333 | -695 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,756 | 24,793 | +37 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

### backprep0 conclusion
- Functionally valid across the required K=8 noisy checks and full `k_sweep`.
- New best current release candidate for combined cycle/resource/timing: it preserves DSP 102 and WNS 3.487 ns, reduces LUT by 695 versus `elimrhs0`, and improves LS-heavy cycles without changing algorithm behavior.
- Cycle gain is modest but consistent for OMP/CoSaMP/HTP/SP/GOMP; IHT/GP/MP are unchanged because this path only affects LS back-solve.

## Back-solve first upper-read fast-entry candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: when entering `S_BACK_INIT`, launch the first upper-triangular `LS_OP_READ2` directly if `back_i+1 < active_k_count`; only jump directly to the diagonal read path when the row has no upper product.
- Goal: remove the extra `S_BACK_ACC` issue cycle for the first upper product in each back-substitution row.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backinit0_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backinit0_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\backinit0_ksweep\xsim.stdout.log`

### backinit0 K=8 representative cycles
| Algorithm | Backprep0 | Backinit0 | Delta |
|---|---:|---:|---:|
| OMP | 82,921 | 82,893 | -28 |
| CoSaMP | 254,874 | 254,706 | -168 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 469,233 | 469,009 | -224 |
| SP | 260,008 | 259,840 | -168 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 44,721 | 44,705 | -16 |
| MP | 248,033 | 248,033 | 0 |

### backinit0 K=8 k_sweep cycles
| Algorithm | Backprep0 | Backinit0 | Delta |
|---|---:|---:|---:|
| OMP | 82,921 | 82,893 | -28 |
| CoSaMP | 280,272 | 280,096 | -176 |
| IHT | 79,363 | 79,363 | 0 |
| HTP | 118,667 | 118,611 | -56 |
| SP | 260,050 | 259,882 | -168 |
| GP | 79,771 | 79,771 | 0 |
| GOMP | 44,720 | 44,704 | -16 |
| MP | 63,377 | 63,377 | 0 |

### backinit0 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_backinit0_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backinit0_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backinit0_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_backinit0_cgra_top\cgra_top_timing.rpt`

| Metric | Backprep0 synth | Backinit0 synth | Delta |
|---|---:|---:|---:|
| LUT total | 70,677 | 75,475 | +4,798 |
| Logic LUT | 69,333 | 74,131 | +4,798 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,793 | 24,755 | -38 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

### backinit0 conclusion
- Functionally valid and cycle-best among tested candidates for LS-heavy algorithms.
- Timing remains clean at 100 MHz and DSP stays 102.
- Tradeoff is not attractive for balanced release: cycle gain is small, but LUT increases by 4,798 versus `backprep0`.
- Recommendation: keep `backinit0` only for cycle-only reporting; prefer `backprep0` for balanced resource/cycle/timing release.

## Divider 64-step start candidate
- Files changed:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\CSCGRA.srcs\sources_1\new\sparse_loop_controller.v`
- Change: start the restoring divider at `div_iter <= 7'd64` instead of `7'd65`.
- Rationale: `div_abs_num` is `{1'b0, abs_num}`; the original 65th bit is always the inserted zero. Starting at 64 removes one redundant divider micro-step while preserving the same quotient path for tested golden cases.
- Rejected related trials:
  - `meshwait5`: reducing global `MESH_CTX_WAIT_CYCLES` from 6 to 5 reduced cycle but failed GP golden.
  - `mpwait5`: reducing mesh wait only for `OP_MP_UPDATE` reduced MP cycle but failed MP golden.
- Validation passed:
  - `tb_run1_noisy24_k8_rep_gpopt`: `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - `tb_run1_noisy24_k8_rep`: `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - `tb_run1_k_sweep`: `348 PASS, 0 FAIL`
- Logs:
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\div64_gpopt\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\div64_snr_k8_rep\xsim.stdout.log`
  - `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\div64_ksweep\xsim.stdout.log`

### div64 K=8 representative cycles
| Algorithm | Backinit0 | Div64 | Delta |
|---|---:|---:|---:|
| OMP | 82,893 | 82,773 | -120 |
| CoSaMP | 254,706 | 253,430 | -1,276 |
| IHT | 156,797 | 156,797 | 0 |
| HTP | 469,009 | 467,857 | -1,152 |
| SP | 259,840 | 258,564 | -1,276 |
| GP | 157,698 | 157,698 | 0 |
| GOMP | 44,705 | 44,635 | -70 |
| MP | 248,033 | 248,001 | -32 |

### div64 K=8 k_sweep cycles
| Algorithm | Backinit0 | Div64 | Delta |
|---|---:|---:|---:|
| OMP | 82,893 | 82,773 | -120 |
| CoSaMP | 280,096 | 278,720 | -1,376 |
| IHT | 79,363 | 79,363 | 0 |
| HTP | 118,611 | 118,323 | -288 |
| SP | 259,882 | 258,606 | -1,276 |
| GP | 79,771 | 79,771 | 0 |
| GOMP | 44,704 | 44,634 | -70 |
| MP | 63,377 | 63,369 | -8 |

### div64 synth result
- Script: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\scripts\run_synth_div64_cgra_top.tcl`
- Vivado log: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_div64_cgra_top\vivado.stdout.log`
- Util report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_div64_cgra_top\cgra_top_util.rpt`
- Timing report: `D:\vivado_pj\CSCGRA_opt_architecture_opt2\runs\opt2\synth_div64_cgra_top\cgra_top_timing.rpt`

| Metric | Backinit0 synth | Div64 synth | Delta |
|---|---:|---:|---:|
| LUT total | 75,475 | 75,718 | +243 |
| Logic LUT | 74,131 | 74,374 | +243 |
| LUTRAM | 1,344 | 1,344 | 0 |
| FF | 24,755 | 24,751 | -4 |
| BRAM36 | 24 | 24 | 0 |
| DSP | 102 | 102 | 0 |
| WNS | 3.487 ns | 3.487 ns | 0 ns |
| TNS | 0.000 ns | 0.000 ns | 0 ns |
| Fmax estimate | 153.54 MHz | 153.54 MHz | 0 MHz |

### div64 conclusion
- Functionally valid across GP-opt, K=8 noisy representative, and full k_sweep.
- New cycle-best candidate among validated RTL versions.
- Timing remains clean at 100 MHz and DSP stays 102; LUT cost is small versus `backinit0` (+243 LUT).
- Best balanced-resource candidate remains `backprep0`; best cycle candidate is now `div64`.

## Final LS balanced radix-4 candidate (2026-07-17)

- Replaced the expensive first-upper-read back-solve shortcut with the compact `S_BACK_ACC` entry while retaining the cheap diagonal prefetch.
- Increased the single shared restoring divider from two to four quotient bits per clock (32 -> 16 step clocks).
- Validation: GP-opt `3 PASS, 0 FAIL`; K=8 representative `20 PASS, 0 FAIL`; full K-sweep `348 PASS, 0 FAIL`.
- Full K-sweep total: 3,571,863 -> 3,389,961 cycles, -181,902 (-5.09%); 46 entries improved, 16 unchanged, 0 regressed.
- OOC synthesis: LUT 75,718 -> 73,303 (-2,415), FF +17, BRAM36 unchanged at 24, DSP unchanged at 102, WNS +2.152 ns at 100 MHz.
- Kept as the new balanced LS release. Detailed tables and reproducible report paths are in `analysis/ls_balanced_radix4_summary.md`.
