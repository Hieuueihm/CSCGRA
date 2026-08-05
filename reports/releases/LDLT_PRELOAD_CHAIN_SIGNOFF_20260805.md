# LDLT preload command-chaining sign-off

Date: 2026-08-05

Baseline: per-row LUTRAM scoreboard checkpoint `7b9f3bc`.

## Architecture

The LDLT four-row border path previously inserted a controller-only state
before the initial `A(i+r,k)` read and before every `L(i+r,p), L(k,p)` preload.
Those states did no arithmetic and did not protect a memory conflict: the
preceding `ls_done` pulse already means that the single matrix service has
returned to IDLE.

The row initializer now launches the first four-row read directly.  Each
completed border read launches `p+1` on the same completion branch until the
preload is finished.  There is still at most one LS request in flight and no
second matrix port, ping-pong cache, or duplicated payload storage.  This is
command chaining, not concurrent multi-port access.

Only memory-side operand preload is changed.  Large LDLT products continue to
enter PE0 and move through PE0 -> PE1 -> PE2 -> PE3.  All four physical rows
retain their modulo-four lane ownership, tagged border streaming, per-row
scoreboard bank, and original retirement order.

## Sign-off result

| Metric | LUTRAM scoreboard | Chained preload | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1789828 | 1779097 | -10731 (-0.60%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.148 ns | +0.090 ns | -0.058 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 110098 | 109755 | -343 |
| Logic LUT / LUTRAM | 107950 / 2144 | 107609 / 2144 | -341 / 0 |
| SRL | 4 | 2 | -2 |
| FF | 50413 | 50375 | -38 |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The 100 MHz out-of-context run completed with zero errors and zero critical
warnings.  The critical path remains the residual `write_idx -> residual_acc`
path; it did not move onto the chained LS command/address path.  Positive WNS
is preserved and resources decrease slightly.

## Per-algorithm aggregate cycles

| Algorithm | LUTRAM scoreboard | Chained preload | Delta |
| --- | ---: | ---: | ---: |
| OMP | 201592 | 200712 | -880 |
| CoSaMP | 352250 | 347398 | -4852 |
| IHT | 204542 | 204542 | 0 |
| HTP | 307513 | 306477 | -1036 |
| SP | 281761 | 278293 | -3468 |
| GP | 206622 | 206622 | 0 |
| GOMP | 114640 | 114145 | -495 |
| MP | 120908 | 120908 | 0 |

IHT, GP, and MP do not traverse the refactored LDLT preload sequence in these
programs, so their unchanged cycle totals are expected.  The complete case
matrix is in
`reports/releases/ldlt_preload_chain_k_sweep_20260805.csv`.

Case 0 at K=16 retains the two explicit testbench skips for CoSaMP and SP
because those modes require 2K candidate support.  The other 62 algorithm/case
records complete successfully.

## Why no double buffer was added

A ping-pong preload cache could overlap one four-row block with PE work on the
preceding block, but it would duplicate wide LDLT payload storage, add ownership
tags and LS arbitration, and increase routing pressure while the WNS margin is
only +0.090 ns.  Command chaining captures a measurable portion of the idle
time without those costs.  Double buffering remains a measured follow-up only
if state-residency data shows enough uncovered preload time to justify it.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(0) -RunId 'ldlt-preload-chain-k16' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(1,3) -RunId 'ldlt-preload-chain-full-a' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(2,4,5,6) -RunId 'ldlt-preload-chain-full-b' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(7) -RunId 'ldlt-preload-chain-smoke-k2' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\synth\run_ooc.ps1 -RtlVersion v2 `
  -Top cgra_top -RunId ldlt-preload-chain-synth3
```

Raw generated artifacts remain under ignored `logs/` and `work/` directories.
