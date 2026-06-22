# 8-Algorithm Golden Regression (M64/N256/K16)

| alg | status | total_cycles | runs | last_cycle | iter_run_count | summary |
|---|---|---:|---:|---:|---:|---|
| OMP | PASS | 298720 | 1 | 298720 | 0 | tb_omp_m64n256k16_cycle: 338 PASS, 0 FAIL |
| MP | PASS | 298720 | 1 | 298720 | 0 | tb_mp_m64n256k16_cycle: 338 PASS, 0 FAIL |
| GOMP | PASS | 408103 | 1 | 408103 | 0 | tb_gomp_m64n256k16_cycle: 354 PASS, 0 FAIL |
| IHT | PASS | 199968 | 16 | 12477 | 16 | tb_iht_m64n256k16_cycle: 625 PASS, 0 FAIL |
| GP | PASS | 199968 | 16 | 12477 | 16 | tb_gp_m64n256k16_cycle: 353 PASS, 0 FAIL |
| SP | PASS | 909218 | 16 | 56830 | 16 | tb_sp_m64n256k16_cycle: 625 PASS, 0 FAIL |
| CoSaMP | PASS | 940961 | 16 | 58824 | 16 | tb_cosamp_m64n256k16_cycle: 625 PASS, 0 FAIL |
| HTP | PASS | 533310 | 16 | 33329 | 16 | tb_htp_m64n256k16_cycle: 353 PASS, 0 FAIL |
