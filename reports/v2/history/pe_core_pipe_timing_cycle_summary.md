# PE core OP_MAC output pipe result

## RTL patch
- File: CSCGRA.srcs/sources_1/new/pe_core.v
- Change: add mac_out_pipe and drive OP_MAC pe_out from the registered MAC output.
- Accumulator update remains same-cycle; only OP_MAC pe_out is decoupled from the long DSP/carry/output path.

## Functional regression
- SNR: tb_noisy24_k8_rep_final: runs 8 PASS, 0 FAIL | checks 16 PASS, 0 FAIL
- Sweep: tb_run1_k_sweep: 348 PASS, 0 FAIL

## Cycle impact
- SNR cycles: unchanged for all 8 algorithms.
- Sweep cycles: unchanged for all compared pass rows; no per-case/per-alg delta found.
- Tables: analysis/noisy24_k8_rep_snr_cycles_pe_core_pipe.csv, analysis/run1_k_sweep_pe_core_pipe_cycles.csv, analysis/run1_k_sweep_pe_core_pipe_compare.csv

## Routed BD timing
- Baseline WNS: +1.081 ns at 100 MHz
- New WNS: +1.395 ns at 100 MHz
- Improvement: +0.314 ns
- Approx Fmax: 116.2 MHz
- New critical path moved away from PE core to SPM/LS paths.
- Timing report: analysis/pe_core_pipe_bd_timing_summary_routed.rpt

## Decision
- Keep patch: yes. It improves routed WNS and causes zero measured cycle increase.
- Caveat: it does not reach the stretch target of +1.8 ns; next bottleneck is SPM/LS routing/datapath, not PE MAC output.
