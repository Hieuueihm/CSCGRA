# Software for RTL v2

Bare-metal C applications for the v2 hardware snapshot are in `src/`.

- `main_tb_soc_program_k_sweep_all_ls_serial_write.c`: K-sweep application.
- `main_tb_soc_program_noisy24_k8_rep_ls_serial_write.c`: noisy K=8 test.
- `cscgra_k_sweep_golden.h`: generated golden vectors.

Build these sources against a hardware platform exported from the matching v2
Vivado implementation. Generated BSP, SDK workspace, HDF/XSA, ELF, and object
files belong under `work/` and are not committed.
