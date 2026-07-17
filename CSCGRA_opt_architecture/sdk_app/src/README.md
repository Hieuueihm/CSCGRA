CSCGRA opt_architecture SDK sources
===================================

This folder is intentionally kept minimal for the validated `ls_serial_write` RTL.

Keep only these active SDK files here:

- `main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c`
  - SNR representative K=8 runner.
  - Golden data is embedded directly in the C file.
- `main_tb_soc_program_k_sweep_all_ls_serial_write.c`
  - k-sweep runner for all supported cases/algorithms.
  - Mirrors the Verilog TB skip rule for K=16 CoSaMP/SP.
- `cscgra_k_sweep_golden.h`
  - Golden data header required by the k-sweep runner.

To use in Vitis/SDK, copy the wanted runner to `main.c` or set it as the app source.

Sync check:

```powershell
python scripts\check_sdk_tb_sync_opt_architecture.py
```
