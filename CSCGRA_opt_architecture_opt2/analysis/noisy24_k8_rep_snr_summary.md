# noisy24_k8_rep SNR Verilog result

- Testbench: tests/tb_noisy24_k8_rep_final.v
- Case: M=64, N=256, K=8, 20-dB measurement noise
- Result: tb_noisy24_k8_rep_final: runs 8 PASS, 0 FAIL | checks 16 PASS, 0 FAIL

| alg | name | cycles | status |
|---:|---|---:|---|
| 0 | OMP | 79337 | PASS |
| 1 | CoSaMP | 236590 | PASS |
| 2 | IHT | 128253 | PASS |
| 3 | HTP | 407633 | PASS |
| 4 | SP | 241724 | PASS |
| 5 | GP | 117777 | PASS |
| 6 | GOMP | 42871 | PASS |
| 7 | MP | 233729 | PASS |
