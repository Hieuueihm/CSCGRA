# Medium PE Pipeline Optimization Notes

Scope: this project keeps the existing 2-cluster 4x4 PE fabric and the combinational column connection (CC). The context format and all golden data are unchanged.

## Implemented changes

- **Row2 block-8 prune/threshold:** `sparse_loop_controller.v` instantiates `pe_row2_prune_threshold`, which evaluates all 8 banks in the current vector block. For base `write_idx`, row2 checks `write_idx + lane`, computes per-lane `abs(x)`, checks support membership, and emits `keep_mask[7:0]` for `OP_PRUNE_X`.
- **Row3 block-8 prune writeback:** `row3_pack_writeback` uses `keep_mask[7:0]` to write all valid lanes in the block in one step: keep the original `rd_data` lane when the mask bit is set, otherwise write zero. Tail lanes are disabled with `(write_idx + lane) < write_limit`.
- **Row3 block writeback packer:** writeback packing is centralized in `row3_pack_writeback`, which drives the 8-bank `wr_addr`, `wr_data`, and `wr_en` lanes. Correlation writes still use all 8 lanes in parallel; scalar/vector updates select the target bank lane without changing fixed-point results.
- **Prune FSM block stride:** `OP_PRUNE_X` advances `write_idx` by 8 and uses the block address `write_idx[IDX_W-1:3]`. This keeps the context format and fixed-point results unchanged while removing per-element prune writeback cycles.
- **Update primitive:** IHT/GP-style update keeps the same saturated add-shift behavior for `x + (score >>> mu_shift)`.
- **LS stage naming:** `ls_matrix_service.v` documents and tracks the 4-row role split: row0/row1 Gram/RHS accumulation, row2 Gaussian row/RHS update, row3 coefficient/writeback. The Gaussian/LS numerical flow is unchanged.

## Validation

- `runs/logs_current/medium_opt_k8_rep_xsim.log`: noisy24 representative before block-8 prune, `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`.
- `runs/logs_current/medium_opt_k_sweep_xsim.log`: full k-sweep before block-8 prune, `348 PASS, 0 FAIL`; CoSaMP/SP at K=16 skip correctly because they need 2K candidate support.
- `runs/logs_current/medium_opt_m128n256k8_xsim.log`: M=128, N=256, K=8 before block-8 prune, `45 PASS, 0 FAIL`.
- `runs/logs_current/prune_block8_k8_rep_xsim.log`: noisy24 representative after block-8 prune, `runs 8 PASS, 0 FAIL | checks 20 PASS, 0 FAIL`.
- `runs/logs_current/prune_block8_k_sweep_xsim.log`: full k-sweep after block-8 prune, `348 PASS, 0 FAIL`; CoSaMP/SP at K=16 still skip correctly because they need 2K candidate support.
- `runs/logs_current/prune_block8_m128n256k8_xsim.log`: M=128, N=256, K=8 after block-8 prune, `45 PASS, 0 FAIL`.

## Prune block-8 cycle comparison

For the M=64, N=256, K=8 k-sweep case:

| Algorithm | Before | After | Delta |
| --- | ---: | ---: | ---: |
| CoSaMP | 260,704 | 260,704 | 0 |
| IHT | 75,843 | 72,259 | -3,584 |
| HTP | 114,019 | 110,435 | -3,584 |
| SP | 241,766 | 241,766 | 0 |

For noisy24 K=8 representative final configured runs:

| Algorithm | Before | After | Delta |
| --- | ---: | ---: | ---: |
| CoSaMP | 236,590 | 236,590 | 0 |
| IHT | 149,757 | 142,589 | -7,168 |
| HTP | 450,641 | 436,305 | -14,336 |
| SP | 241,724 | 241,724 | 0 |

For the M=128, N=256, K=8 case:

| Algorithm | Before | After | Delta |
| --- | ---: | ---: | ---: |
| CoSaMP | 373,222 | 373,222 | 0 |
| IHT | 132,177 | 128,593 | -3,584 |
| HTP | 185,204 | 181,620 | -3,584 |
| SP | 351,969 | 351,969 | 0 |

## Cycles after prune block-8 optimization

For the required M=64, N=256, K=8 k-sweep case:

- OMP: 79,337 cycles
- CoSaMP: 260,704 cycles
- IHT: 72,259 cycles
- HTP: 110,435 cycles
- SP: 241,766 cycles
- GP: 72,667 cycles
- GOMP: 42,870 cycles
- MP: 59,801 cycles

For noisy24 K=8 representative:

- OMP: 79,337 cycles
- CoSaMP: 236,590 cycles
- IHT: 142,589 cycles
- HTP: 436,305 cycles
- SP: 241,724 cycles
- GP: 143,523 cycles
- GOMP: 42,871 cycles
- MP: 233,729 cycles

For M=128, N=256, K=8:

- OMP: 146,921 cycles
- CoSaMP: 373,222 cycles
- IHT: 128,593 cycles
- HTP: 181,620 cycles
- SP: 351,969 cycles
- GP: 129,001 cycles
- GOMP: 76,923 cycles
- MP: 116,121 cycles

## Resource and timing snapshot

OOC synthesis of `cgra_top` on `xczu7ev-ffvc1156-2-e` at 100 MHz before block-8 prune:

- Total LUTs: 76,980
- Logic LUTs: 70,516
- LUTRAMs: 6,464
- FFs: 23,826
- RAMB36: 16
- DSP48: 102
- Timing WNS: 3.010 ns, no setup violations at 10 ns period

Reports:

- `runs/reports_medium_opt/cgra_top_util_medium_opt.rpt`
- `runs/reports_medium_opt/cgra_top_timing_medium_opt.rpt`
- `runs/logs_current/medium_opt_synth_reports.log`
