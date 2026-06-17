# M64/N256/K16 Verified Cycle Summary

| alg | M | N | K | total_cycles | runs | last_cycle | avg/run | status | summary | notes |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| omp | 64 | 256 | 16 | 170480 | 1 | 170480 | 170480.00 | PASS | tb_omp_m64n256k16_cycle: 338 PASS, 0 FAIL | single_full_program |
| gomp | 64 | 256 | 16 | 240153 | 1 | 240153 | 240153.00 | FAIL_TRUE | tb_gomp_m64n256k16_cycle: 343 PASS, 11 FAIL | single_full_program | X_MISM idx=147 rtl=014965 gold=000000; FAIL x_final; X_MISM idx=149 rtl=012fe5 gold=000000; FAIL x_final; X_MISM idx=165 rtl=00cb02 gold=000000 |
| mp | 64 | 256 | 16 | 170480 | 1 | 170480 | 170480.00 | PASS | tb_mp_m64n256k16_cycle: 338 PASS, 0 FAIL | single_full_program |
| iht | 64 | 256 | 16 | 183584 | 16 | 11453 | 11474.00 | PASS | tb_iht_m64n256k16_cycle: 625 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| gp | 64 | 256 | 16 | 183584 | 16 | 11453 | 11474.00 | PASS | tb_gp_m64n256k16_cycle: 353 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| sp | 64 | 256 | 16 | 348166 | 16 | 20484 | 21760.38 | PASS | tb_sp_m64n256k16_cycle: 625 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| cosamp | 64 | 256 | 16 | 385030 | 16 | 22478 | 24064.38 | PASS | tb_cosamp_m64n256k16_cycle: 625 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
| htp | 64 | 256 | 16 | 257905 | 16 | 15156 | 16119.06 | PASS | tb_htp_m64n256k16_cycle: 353 PASS, 0 FAIL | ITER_RUN=16/expected=16 |
