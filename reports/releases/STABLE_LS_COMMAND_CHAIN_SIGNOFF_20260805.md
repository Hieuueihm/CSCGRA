# Stable LS command-chain sign-off

Date: 2026-08-05

Baseline: chained LDLT preload checkpoint `2a7ba9e`.

## Architecture

This checkpoint removes two remaining command-only bubbles without shortening
any arithmetic pipeline:

1. RHS initialization launches entry zero from `S_SOLVE_INIT`; each following
   RHS write is issued only from the preceding `ls_done` completion pulse.
2. The registered results of the final four-row LDLT multiply are captured
   directly into the matrix-service `WRITE4` command registers.  The separate
   staging/command state is no longer required.

Both changes retain exactly one LS matrix request in flight.  No extra memory
port, preload buffer, multiplier, or divider is added.  `WRITE4` still receives
four registered values: physical PE row `r` owns output lane `r`.

All large arithmetic remains strict PE0 ingress.  Work enters PE0 and advances
through PE0 -> PE1 -> PE2 -> PE3; the controller does not inject operands into
downstream rows.

## Sign-off result

| Metric | Preload chain `2a7ba9e` | Stable LS chain | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1779097 | 1774300 | -4797 (-0.27%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.090 ns | +0.309 ns | +0.219 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 109755 | 113628 | +3873 (+3.53%) |
| Logic LUT / LUTRAM | 107609 / 2144 | 111480 / 2144 | +3871 / 0 |
| SRL | 2 | 4 | +2 |
| FF | 50375 | 50762 | +387 (+0.77%) |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The 100 MHz out-of-context run completed with zero errors and zero critical
warnings.  The critical path remains the residual `write_idx -> residual_acc`
path, but its measured delay improves from the prior checkpoint: positive WNS
now exceeds the +0.2 ns preferred margin.

The added LUT cost is accepted for this stability-oriented checkpoint because
cycle count falls, WNS improves by 0.219 ns, and no scarce DSP or block-RAM
resource is added.  The lower-area `2a7ba9e` checkpoint remains available if
area becomes the dominant constraint.

## Per-algorithm aggregate cycles

| Algorithm | Preload chain | Stable LS chain | Delta |
| --- | ---: | ---: | ---: |
| OMP | 200712 | 200088 | -624 |
| CoSaMP | 347398 | 345649 | -1749 |
| IHT | 204542 | 204542 | 0 |
| HTP | 306477 | 305755 | -722 |
| SP | 278293 | 276931 | -1362 |
| GP | 206622 | 206622 | 0 |
| GOMP | 114145 | 113805 | -340 |
| MP | 120908 | 120908 | 0 |

IHT, GP, and MP do not use the modified LDLT/RHS command sequence in the tested
programs, so their unchanged cycle totals are expected.  The complete case
matrix is in
`reports/releases/stable_ls_command_chain_k_sweep_20260805.csv`.

Case 0 at K=16 retains the two explicit testbench skips for CoSaMP and SP
because those modes require 2K candidate support.  The other 62 algorithm/case
records complete successfully.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(0) -RunId 'stable-ls-chain-k16' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(1,3) -RunId 'stable-ls-chain-full-a' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(2,4,5,6) -RunId 'stable-ls-chain-full-b' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(7) -RunId 'stable-ls-chain-smoke-k2' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\synth\run_ooc.ps1 -RtlVersion v2 `
  -Top cgra_top -RunId stable-ls-chain-synth
```

Raw generated artifacts remain under ignored `logs/` and `work/` directories.
