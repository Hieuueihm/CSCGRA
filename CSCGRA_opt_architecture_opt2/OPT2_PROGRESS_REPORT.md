# CSCGRA opt2 progress report

## Folder
- Baseline copy: `D:\vivado_pj\CSCGRA_opt_architecture_opt2`
- Baseline source preserved: `D:\vivado_pj\CSCGRA_opt_architecture`

## RTL optimization applied
- Kept mesh-context functionally enabled after testing showed disabling it breaks OMP/CoSaMP golden.
- Removed synthesis blocking hierarchy attributes from PE hierarchy so Vivado can optimize across PE boundaries:
  - `CSCGRA.srcs/sources_1/new/pearray.v`
  - `CSCGRA.srcs/sources_1/new/pe_cluster_4x4.v`
  - `CSCGRA.srcs/sources_1/new/pe_tile.v`
- Added `ENABLE_MESH_CTX` parameter path but set top instance to enabled (`1`) because mesh-context is required for correctness.

## Failed/reverted attempt
- Attempt: set PE mesh-context disabled in `cgra_top`.
- Result: `tb_run1_noisy24_k8_rep` failed immediately on OMP/CoSaMP golden mismatches.
- Action: reverted top instance to `ENABLE_MESH_CTX(1)`; golden was not changed.

## Validation
- `tb_run1_noisy24_k8_rep`: PASS `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`
  - Log: `runs/opt2/snr_k8_rep_attr_unlocked/xsim.log`
- `tb_run1_k_sweep`: PASS `348 PASS, 0 FAIL`
  - Log: `runs/opt2/ksweep_attr_unlocked/xsim.log`
  - CoSaMP/SP at K=16 skipped by rule `requires_2K_candidate_support`.
- `tb_run1_noisy24_k8_rep_gpopt`: PASS `runs 1 PASS, 0 FAIL | checks 3 PASS, 0 FAIL`
  - Log: `runs/opt2/snr_k8_gpopt_attr_unlocked/xsim.log`
- SDK/TB sync checker now uses local opt2 root and PASS.

## OOC synth result for cgra_top
- Tool: Vivado 2018.1, part `xczu7ev-ffvc1156-2-e`, OOC synth.
- Script: `scripts/run_synth_incr_cgra_top.tcl`
- Reports:
  - `runs/opt2/synth_incr_cgra_top/cgra_top_util.rpt`
  - `runs/opt2/synth_incr_cgra_top/cgra_top_timing.rpt`
- Result:
  - LUT total: 79,534
  - Logic LUT: 73,070
  - LUTRAM: 6,464
  - FF: 25,218
  - BRAM36: 16
  - DSP: 102
  - WNS: 3.487 ns
  - TNS: 0.000 ns
  - Critical path delay: 6.503 ns
  - Fmax estimate: 153.54 MHz

## Comparison with current baseline
- LUT total: 80,318 -> 79,534, improvement 784 LUTs, about 0.98%.
- Logic LUT: 73,854 -> 73,070, improvement 784 LUTs, about 1.06%.
- LUTRAM: unchanged 6,464.
- FF: 25,602 -> 25,218, improvement 384 FFs, about 1.50%.
- BRAM36: unchanged 16.
- DSP: unchanged 102.
- WNS: unchanged 3.487 ns.
- Cycles: unchanged for checked K8/k_sweep cases.

## Not done yet
- BD ZCU106 for opt2 has not been generated yet.
- SDK C/header were not regenerated beyond sync-check/root fix; current copied SDK remains sync-valid.
- Further RTL optimization candidates remain: sparse loop controller state/control reduction, support/top-k service simplification, and LS service constant removal.
