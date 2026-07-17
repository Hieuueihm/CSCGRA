# SDK C / TB sync check - opt architecture

Date: 2026-07-02
Project: D:\vivado_pj\CSCGRA_opt_architecture
RTL baseline for these C files: ls_serial_write validated RTL

## Active files kept in sdk_app/src

The SDK source folder was cleaned to keep only files needed for the current validated RTL:

- D:\vivado_pj\CSCGRA_opt_architecture\sdk_app\src\main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c
- D:\vivado_pj\CSCGRA_opt_architecture\sdk_app\src\main_tb_soc_program_k_sweep_all_ls_serial_write.c
- D:\vivado_pj\CSCGRA_opt_architecture\sdk_app\src\cscgra_k_sweep_golden.h
- D:\vivado_pj\CSCGRA_opt_architecture\sdk_app\src\README.md

Old/debug/per-alg/case-wrapper C files and unused golden headers were removed from `sdk_app/src`.

## Checked invariants

The checker validates:

- SNR TB is M=64, N=256, K=8.
- SNR C source tag uses noisy_lfsr_24bit_per_algorithm_seed_k8.json.
- Algorithm IDs remain 0..7: OMP, CoSaMP, IHT, HTP, SP, GP, GOMP, MP.
- k-sweep case list is:
  - m64n256k16
  - m64n256k8
  - m64n256k4
  - m32n128k8
  - m32n128k4
  - m32n128k2
  - m16n64k4
  - m16n64k2
- k-sweep C mirrors TB skip behavior for K=16 CoSaMP/SP because they require 2K candidate support.
- skip return code 2 is ignored, not counted as pass/fail.
- sweep golden header points to CSCGRA_opt_architecture/tests/run1/k_sweep_golden_mu3.vh.

## Check command

From D:\vivado_pj\CSCGRA_opt_architecture:

```powershell
python scripts\check_sdk_tb_sync_opt_architecture.py
```

Latest result:

```text
PASS: SNR K8 and k-sweep SDK C mirror the checked TB/golden invariants, including ls_serial_write copies.
```
