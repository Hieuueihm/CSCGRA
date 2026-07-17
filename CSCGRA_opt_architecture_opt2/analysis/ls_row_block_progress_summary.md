# LS row block update progress

## RTL change
- `ls_matrix_service.v` adds `row_update_block` mode for `OP_ROW_UPDATE`.
- One controller command now covers up to 8 consecutive LS matrix columns from `col_a`/`solve_k`.
- `sparse_loop_controller.v` drives lane mask from `active_k_count` and increments `solve_k` by `COLS` instead of 1.
- RHS update is still separate (`OP_RHS_UPDATE`), not fused yet.

## SNR validation
- Test: `tb_noisy24_k8_rep_final`
- Result: `8 PASS, 0 FAIL | checks 16 PASS, 0 FAIL`
- CSV: `analysis/noisy24_k8_rep_snr_cycles_ls_row_block.csv`

| alg | old | new | delta | improvement |
| --- | ---: | ---: | ---: | ---: |
| OMP | 79337 | 78077 | 1260 | 1.59% |
| CoSaMP | 236590 | 201142 | 35448 | 14.98% |
| IHT | 128253 | 128253 | 0 | 0% |
| HTP | 407633 | 390609 | 17024 | 4.18% |
| SP | 241724 | 206276 | 35448 | 14.66% |
| GP | 117777 | 117777 | 0 | 0% |
| GOMP | 42871 | 42081 | 790 | 1.84% |
| MP | 233729 | 233729 | 0 | 0% |

## Sweep validation
- Test: `tb_run1_k_sweep`
- Result: `348 PASS, 0 FAIL`
- CSV: `analysis/run1_k_sweep_ls_row_block_cycles.csv`
- Compare CSV: `analysis/run1_k_sweep_ls_row_block_compare.csv`

Top improvements versus PE-pipe baseline include:
- case0 alg3: 417430 -> 347350, delta 70080, 16.79%
- case1 alg1: 260704 -> 221408, delta 39296, 15.07%
- case3 alg1: 181417 -> 142121, delta 39296, 21.66%
- case1 alg4: 241766 -> 206318, delta 35448, 14.66%
- case3 alg4: 164736 -> 129288, delta 35448, 21.52%
- case0 alg0: 229105 -> 209885, delta 19220, 8.39%

## Timing/util status
- Routed BD timing/util was started with `runs/run_bd_ls_row_block_route.tcl`.
- The flow was stopped before reports because OOC CGRA synth took too long after adding the block read/multiply mux.
- No routed `ls_row_block` timing/util report is available yet.
- Next step: reduce the LS block read mux or add pipeline/register staging before rerunning BD route.
