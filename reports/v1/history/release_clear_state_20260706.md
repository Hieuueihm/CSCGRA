# CSCGRA Opt Architecture Release State

Date: 2026-07-06

## Current validated scope

- Vivado/xsim only; no Verilator flow is used.
- `tb_run1_k_sweep` passed: `348 PASS, 0 FAIL`.
- SNR K=8 testbenches passed:
  - `tb_run1_noisy24_k8_rep`: `8 PASS, 0 FAIL`.
  - `tb_run1_noisy24_k8_rep_gpopt`: `1 PASS, 0 FAIL`.
  - `tb_noisy24_k8_rep_final`: `8 PASS, 0 FAIL`.
- GP uses gradient step: `SOP_GRAD_STEP = 8'h87` / `0x87`.
- CoSaMP/SP at K=16 are skipped in k-sweep because they require 2K support.
- BD ZCU106 was generated in `D:/vivado_pj/bd_release_optarch_20260706`.

## SDK C entry points

- K-sweep SDK runner: `sdk_app/src/main_tb_soc_program_k_sweep_all_ls_serial_write.c`.
- SNR K=8 SDK runner: `sdk_app/src/main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c`.
- K-sweep golden header: `sdk_app/src/cscgra_k_sweep_golden.h`.
- Sync checker: `scripts/check_sdk_tb_sync_opt_architecture.py`.

## PE operation status

The PE still implements the generic op set:

- `OP_MAC`, `OP_ADD`, `OP_SUB`, `OP_ABS`, `OP_CMP`, `OP_SGN`, `OP_SHT`, `OP_PASS`, `OP_SAT_ADD_SHIFT`.
- Current sparse accelerated paths mainly use MAC/ADD/SUB/ABS/PASS/SAT_ADD_SHIFT through sparse and mesh contexts.
- `OP_CMP`, `OP_SGN`, and `OP_SHT` remain as generic PE ISA support. They are not removed in this release because removing them requires a full context/program audit beyond k-sweep and SNR K=8.

## Prune status

- IHT/HTP/GP use sparse op `SOP_PRUNE_X` after update/gradient and top-k/reduce selection.
- GP context uses `SOP_GRAD_STEP`, not `SOP_GP_NO_LS_UPDATE`.
- PE still contains `MESH_CTX_PRUNE`, but the validated TB/SDK path uses sparse-loop controlled prune. The mesh prune logic is retained as compatibility/legacy hardware rather than deleted.
- Do not regenerate golden from RTL output. Golden remains source-of-truth from Python/reference data.

## Timing/resource snapshot

Current OOC `cgra_top` synth report:

- LUT: 85,592
- FF: 27,099
- BRAM36: 16
- DSP: 190
- WNS: 2.459 ns
- TNS: 0.000 ns

Old baseline snapshot:

- LUT: 75,218
- FF: 23,803
- BRAM36: 16
- DSP: 102
- WNS: 3.010 ns

The current worst path is not DSP-bound; it is in sparse loop controller / phi-cache routing, so adding DSP does not directly improve WNS.

## Release rule

For paper/report numbers, use one consistent RTL snapshot and regenerate all cycle/resource tables from that snapshot. Do not mix the old paper cycle table with the current RTL logs.
