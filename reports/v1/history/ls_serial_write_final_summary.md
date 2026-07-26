# LS serial-write block update summary

## Backup
- `CSCGRA.srcs/sources_1/new/ls_matrix_service.v.ls_block_try_20260702_164314.bak`
- `CSCGRA.srcs/sources_1/new/sparse_loop_controller.v.ls_block_try_20260702_164314.bak`

## RTL
- `ls_matrix_service.v` adds `row_update_block` mode for `OP_ROW_UPDATE`.
- `sparse_loop_controller.v` issues row-update blocks with `solve_k += COLS`.
- To keep synth safe, LS matrix writeback is serial one lane per cycle after block compute.
- RHS update remains separate.

## Synth
- Direct `cgra_soc_top` OOC synth: PASS.
- `0 errors`, `0 critical warnings`.
- Direct synth util: LUT 72,399, FF 24,833, BRAM 16, DSP 112.

## SNR validation
- `tb_noisy24_k8_rep_final`: `8 PASS, 0 FAIL | checks 16 PASS, 0 FAIL`.
- CSV: `analysis/noisy24_k8_rep_snr_cycles_ls_serial_write.csv`.

| alg | old | new | delta | improvement |
| --- | ---: | ---: | ---: | ---: |
| OMP | 79337 | 78833 | 504 | 0.64% |
| CoSaMP | 236590 | 216766 | 19824 | 8.38% |
| IHT | 128253 | 128253 | 0 | 0% |
| HTP | 407633 | 398673 | 8960 | 2.20% |
| SP | 241724 | 221900 | 19824 | 8.20% |
| GP | 117777 | 117777 | 0 | 0% |
| GOMP | 42871 | 42531 | 340 | 0.79% |
| MP | 233729 | 233729 | 0 | 0% |

## Sweep validation
- `tb_run1_k_sweep`: `348 PASS, 0 FAIL`.
- CSV: `analysis/run1_k_sweep_ls_serial_write_cycles.csv`.
- Compare: `analysis/run1_k_sweep_ls_serial_write_compare.csv`.

Top deltas versus PE-pipe baseline:
- case0 alg3: 417430 -> 377878, delta 39552, 9.48%.
- case1 alg1: 260704 -> 238688, delta 22016, 8.44%.
- case3 alg1: 181417 -> 159401, delta 22016, 12.14%.
- case1 alg4: 241766 -> 221942, delta 19824, 8.20%.
- case3 alg4: 164736 -> 144912, delta 19824, 12.03%.
- case0 alg0: 229105 -> 219353, delta 9752, 4.26%.

Small regressions exist on small cases, worst around 22 cycles for alg4 K=2 and 20 cycles for OMP K=4.

## Routed BD
- Project: `D:/vivado_pj/bd_optarch/vivado_zcu106_soc/cscgra_zcu106_soc_opt_architecture.xpr`.
- Timing report: `analysis/ls_serial_write_bd_timing_summary_routed.rpt`.
- Util report: `analysis/ls_serial_write_bd_utilization_routed.rpt`.
- Routed WNS: +1.395 ns.
- Critical path remains SPM BRAM bank path, not LS/PE.
- Routed util: LUT 87,611, FF 36,513, BRAM 16, DSP 189.

## Note
This version is synth-safe and routed, but uses LS-service internal block compute plus serial RAM writeback. It is not yet a pure PE-returned block datapath.
