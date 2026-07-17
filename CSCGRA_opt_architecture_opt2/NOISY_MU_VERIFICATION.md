# Noisy 24-bit MU_SHIFT verification

Project copy: `D:\vivado_pj\CSCGRA_noisy_mu`

## What changed

- `MU_SHIFT` is runtime configurable through AXI-Lite register `0x070`.
- Default reset value is `2`, and the noisy 24-bit test writes `3`.
- The dynamic shift is used by the IHT update path in `sparse_loop_controller.v`.
- The original `CSCGRA_opt` project is not modified.

## Golden setup

- `N=256`, `M=64`, `K=16`
- 24-bit fixed point, Q8.16
- measurement noise: 20 dB
- `PHI_SEED=0xDEADBEEF`
- `PHI_SCALE=0x4000`
- `MU_SHIFT=3`
- per-algorithm signal seeds are stored in `tests/noisy_lfsr_24bit_cases.vh`

## Run command

Run from PowerShell:

`powershell -ExecutionPolicy Bypass -File D:\vivado_pj\CSCGRA_noisy_mu\scripts\run_tb_soc_program_noisy24_mu_2018.ps1`

## Expected pass condition

The simulation should finish with:

`tb_soc_program_noisy24_mu: <PASS_COUNT> PASS, 0 FAIL`

The run directory is:

`D:\vivado_pj\CSCGRA_noisy_mu\runs\tb_soc_program_noisy24_mu_2018`

If it fails during compile, inspect:

- `xvlog.stdout.log`
- `xelab.stdout.log`

If it fails during simulation, inspect:

- `xsim.stdout.log`

## Note

This Codex session could not launch Vivado because the command approval service rejected shell execution with an internal `404 No active credentials` error. The files are prepared for a direct local run.
