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
  - Auto-generated hardware golden header required by the k-sweep runner.

Regenerate and verify the C header together with the RTL include:

```powershell
python models/reference/hardware.py --c-output sw/v2/src/cscgra_k_sweep_golden.h
python models/reference/hardware.py --check --c-output sw/v2/src/cscgra_k_sweep_golden.h
```

The C runner uses the same fixed-point/LDLT/factor-cache outputs as the v2
testbench and uses zero tolerance for final coefficients. K16 CoSaMP/SP are
skipped for the same 16-entry 2K support-capacity rule as the RTL testbench.

To use in Vitis/SDK, copy the wanted runner to `main.c` or set it as the app source.

Sync check:

```powershell
python scripts\maintenance\check_sdk_tb_sync.py
```
