# M64/N256/K16 Verified Cycle Summary

Generated: 2026-06-23 07:02 Asia/Saigon
Source run directory: `D:/vivado_pj/golden_model/verified_runs`

This run is after regenerating MP/GP golden data and separating the GP datapath from IHT. It also keeps the Vivado M64/N256/K16 testbenches on `golden_cases_array.vh` so large regenerated golden data elaborates reliably.

| alg | M | N | K | total_cycles | runs | last_cycle | avg/run | status | summary | notes |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| omp | 64 | 256 | 16 | 227216 | 1 | 227216 | 227216.00 | PASS | tb_omp_m64n256k16_cycle: 338 PASS, 0 FAIL | single_full_program |
| mp | 64 | 256 | 16 | 115888 | 1 | 115888 | 115888.00 | PASS | tb_mp_m64n256k16_cycle: 338 PASS, 0 FAIL | single_full_program |
| gomp | 64 | 256 | 16 | 318747 | 1 | 318747 | 318747.00 | PASS | tb_gomp_m64n256k16_cycle: 354 PASS, 0 FAIL | single_full_program |
| iht | 64 | 256 | 16 | 159520 | 16 | 9949 | 9970.00 | PASS | tb_iht_m64n256k16_cycle: 625 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| gp | 64 | 256 | 16 | 428035 | 16 | 26758 | 26752.19 | PASS | tb_gp_m64n256k16_cycle: 353 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| sp | 64 | 256 | 16 | 730274 | 16 | 45646 | 45642.12 | PASS | tb_sp_m64n256k16_cycle: 625 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| cosamp | 64 | 256 | 16 | 762017 | 16 | 47640 | 47626.06 | PASS | tb_cosamp_m64n256k16_cycle: 625 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| htp | 64 | 256 | 16 | 427710 | 16 | 26729 | 26731.88 | PASS | tb_htp_m64n256k16_cycle: 353 PASS, 0 FAIL | ITER_RUN=16/expected=16 |

Checks:

- MP no longer reuses the OMP result path: `115888 != 227216` cycles.
- GP no longer reuses the IHT update path: `428035 != 159520` cycles.
- GP and HTP remain close because both perform correlation/proxy selection plus support refinement in this project flow.
