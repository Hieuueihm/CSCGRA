# CSCGRA_opt_architecture pipeline result

## SNR Verilog
- Testbench: tests/tb_noisy24_k8_rep_final.v
- Case: M=64, N=256, K=8, 20-dB measurement noise
- Result: runs 8 PASS, 0 FAIL | checks 16 PASS, 0 FAIL
- Log copy: analysis/noisy24_k8_rep_xsim.log

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

## Sweep Verilog
- Full sweep was rerun before SNR on unchanged RTL: tb_run1_k_sweep: 348 PASS, 0 FAIL
- Per-case/per-alg tables remain in analysis/run1_cycles_opt_architecture.csv and analysis/run1_cycle_compare_gp_opt_vs_opt_architecture.csv

## SDK/Header
- Fixed SDK K8 label in sdk_app/src/main_tb_soc_program_noisy24_k8_rep.c
- Regenerated sdk_app/src/cscgra_k_sweep_golden.h from CSCGRA_opt_architecture/tests/run1/k_sweep_golden_mu3.vh
- Added script: scripts/export_k_sweep_c_header_opt_architecture.py

## BD
- Reran scripts/build_zcu106_soc_opt_architecture_bd_only.tcl successfully
- Project: runs/bd_zcu106_soc_opt_architecture_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_opt_architecture.xpr
- Wrapper: runs/bd_zcu106_soc_opt_architecture_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_opt_architecture.srcs/sources_1/bd/cscgra_soc_bd/hdl/cscgra_soc_bd_wrapper.v
