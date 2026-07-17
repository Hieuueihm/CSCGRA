# Static audit for noisy MU project

Date: 2026-06-28
Project: `D:\vivado_pj\CSCGRA_noisy_mu`

## Requirement audit

| Requirement | Evidence | Status |
|---|---|---|
| New project copied from `CSCGRA_opt` | `D:\vivado_pj\CSCGRA_noisy_mu` exists with RTL, tests, scripts, sdk_app | Prepared |
| Runtime configurable `MU_SHIFT` | AXI register `A_MU_SHIFT = 12'h070` in `csr_regs.v` | Prepared |
| `MU_SHIFT` reaches sparse datapath | `mu_shift_cfg` port in `cgra_top.v`, `sparse_kernel_service_engine.v`, and `sparse_loop_controller.v` | Prepared |
| IHT update uses runtime shift | `>>> mu_shift_eff` in `sparse_loop_controller.v` | Prepared |
| Golden model follows paper table | `noisy_lfsr_24bit_per_algorithm_seed_python.csv` and `noisy_lfsr_24bit_cases.vh` contain the listed seeds/results | Prepared |
| New TB, old TB untouched | `tests/tb_soc_program_noisy24_mu.v` created | Prepared |
| TB writes `MU_SHIFT=3` | `axi_write(REG_MU_SHIFT,32'd3)` in the new TB | Prepared |
| RTL correctness tested | Requires Vivado/xsim run and `xsim.stdout.log` showing `0 FAIL` | Not yet verified |

## Static checks passed

- No leftover references to old `golden_cases.vh` in the new TB.
- No leftover `gold_case`, `gold_iter`, or `gold_alg` references in the new TB.
- Golden include uses Verilog functions, not unpacked array localparams, for better Vivado 2018 compatibility.
- The old fixed `parameter integer MU_SHIFT` was removed from `sparse_loop_controller.v`.

## Required command for final proof

`powershell -ExecutionPolicy Bypass -File D:\vivado_pj\CSCGRA_noisy_mu\scripts\run_tb_soc_program_noisy24_mu_2018.ps1`

Final completion requires the generated `xsim.stdout.log` to end with `0 FAIL`.
