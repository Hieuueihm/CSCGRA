# 8-Algorithm Golden Regression (M64/N256/K16)

Generated: 2026-06-23 07:02 Asia/Saigon
Source run directory: `D:/vivado_pj/golden_model/verified_runs`

This regression was rerun after rebuilding MP/GP golden vectors and fixing the RTL/testbench dispatch for MP and GP. `detect_stale_golden_pairs()` is clean: MP is no longer identical to OMP, and GP is no longer identical to IHT.

| alg | status | total_cycles | runs | last_cycle | iter_run_count | summary |
|---|---|---:|---:|---:|---:|---|
| OMP | PASS | 227216 | 1 | 227216 | 0 | tb_omp_m64n256k16_cycle: 338 PASS, 0 FAIL |
| MP | PASS | 115888 | 1 | 115888 | 0 | tb_mp_m64n256k16_cycle: 338 PASS, 0 FAIL |
| GOMP | PASS | 318747 | 1 | 318747 | 0 | tb_gomp_m64n256k16_cycle: 354 PASS, 0 FAIL |
| IHT | PASS | 159520 | 16 | 9949 | 16 | tb_iht_m64n256k16_cycle: 625 PASS, 0 FAIL |
| GP | PASS | 428035 | 16 | 26758 | 16 | tb_gp_m64n256k16_cycle: 353 PASS, 0 FAIL |
| SP | PASS | 730274 | 16 | 45646 | 16 | tb_sp_m64n256k16_cycle: 625 PASS, 0 FAIL |
| CoSaMP | PASS | 762017 | 16 | 47640 | 16 | tb_cosamp_m64n256k16_cycle: 625 PASS, 0 FAIL |
| HTP | PASS | 427710 | 16 | 26729 | 16 | tb_htp_m64n256k16_cycle: 353 PASS, 0 FAIL |

Cycle sanity notes:

- OMP/MP now diverge because MP runs the dedicated MP update path and allows duplicate selected atoms.
- IHT/GP now diverge because GP uses the dedicated full-gradient update (`OP_GP_UPDATE`) while IHT/HTP use the scaled IHT update.
- GP and HTP are still close in cycle count because the current project GP flow shares the expensive correlation/topK/refinement structure with HTP.
