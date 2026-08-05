# LDLT per-row scoreboard LUTRAM sign-off

Date: 2026-08-05

Baseline: strict-PE0 timing-isolation checkpoint `623187c`.

## Architecture

The four-entry LDLT border scoreboard is split into four independent banks,
one bank for each physical PE row.  PE row `r` writes only bank `r`; the row-3
completion tag remains the transaction retirement point.  This removes the
wide packed-slot read/modify/write mux and keeps each row's partial result
local to its own storage bank.

Scoreboard payload storage is in a non-reset clocked process.  Capture and
completion metadata remain resettable, and the existing valid/tag pipeline
guarantees that an uninitialized payload is never read.  With the distributed
RAM attributes, Vivado maps the accumulator banks to `RAM16X1S` and the result
banks to `RAM32M16` instead of resettable FFs.

The controller still supplies large operands only to PE0.  Border work follows
PE0 -> PE1 -> PE2 -> PE3, with row `r` retaining ownership of its modulo-four
lanes.  The storage refactor adds no controller ingress to PE1, PE2, or PE3 and
does not change transaction issue or retirement latency.

The RHS lane bound now uses the kept, fan-out-limited local
`active_k_count_q` source already introduced by timing isolation.  Using the
unreplicated support-depth signal on this path reduced timing margin and is not
retained.

## Sign-off result

| Metric | Timing isolation | Per-row LUTRAM scoreboard | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1789828 | 1789828 | 0 |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.168 ns | +0.148 ns | -0.020 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 119105 | 110098 | -9007 (-7.56%) |
| Logic LUT / LUTRAM | 117565 / 1536 | 107950 / 2144 | -9615 / +608 |
| SRL | 4 | 4 | unchanged |
| FF | 53653 | 50413 | -3240 (-6.04%) |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The 100 MHz out-of-context run completed with zero errors and zero critical
warnings.  Positive WNS is preserved while total LUT and FF use both fall,
with no cycle cost.

## Per-algorithm aggregate cycles

| Algorithm | Aggregate cycles | Change from timing isolation |
| --- | ---: | ---: |
| OMP | 201592 | 0 |
| CoSaMP | 352250 | 0 |
| IHT | 204542 | 0 |
| HTP | 307513 | 0 |
| SP | 281761 | 0 |
| GP | 206622 | 0 |
| GOMP | 114640 | 0 |
| MP | 120908 | 0 |

The complete case matrix is in
`reports/releases/ldlt_scoreboard_lutram_k_sweep_20260805.csv`.

Case 0 at K=16 retains the two explicit testbench skips for CoSaMP and SP
because those modes require 2K candidate support.  The other 62 algorithm/case
records complete and match the timing-isolation cycle matrix exactly.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(0,3) -RunId 'ldlt-lutram-full-a' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
  "& { & '.\scripts\sim\run_regression.ps1' -RtlVersion v2 `
  -Cases @(1,2,4,5,6,7) -RunId 'ldlt-lutram-full-b' }"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\synth\run_ooc.ps1 -RtlVersion v2 `
  -Top cgra_top -RunId ldlt-lutram-synth
```

Raw generated artifacts remain under ignored `logs/` and `work/` directories.
