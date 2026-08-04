# Tagged residual block-8 chaining sign-off

Date: 2026-08-04

Baseline: strict PE0 timing checkpoint `a38646a`.

## Result

Residual dot-product blocks now enter PE0 at initiation interval one. Each PE
row owns the two lanes whose support index modulo four equals that row. The
running 128-bit partial sum follows the transaction tag down the registered
PE0 -> PE1 -> PE2 -> PE3 wavefront, and PE3 retires blocks in order.

| Metric | Strict P0 | Residual chain | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1969179 | 1904934 | -64245 (-3.26%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| WNS | +0.109 ns | +0.249 ns | +0.140 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 114728 | 105383 | -9345 |
| Logic LUT / LUTRAM | 113190 / 1536 | 103846 / 1536 | -9344 / 0 |
| FF | 47345 | 39884 | -7461 |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The resource reduction occurs because the registered issue-valid makes the
old hold/wait/reduction path unreachable and Vivado removes its wide temporary
buffers. Synthesis has zero errors and zero critical warnings.

## Per-algorithm aggregate cycles

| Algorithm | Strict P0 | Residual chain | Delta |
| --- | ---: | ---: | ---: |
| OMP | 216656 | 209424 | -7232 |
| CoSaMP | 420907 | 410164 | -10743 |
| IHT | 211998 | 202206 | -9792 |
| HTP | 327783 | 317991 | -9792 |
| SP | 331663 | 323057 | -8606 |
| GP | 214078 | 204286 | -9792 |
| GOMP | 122850 | 119234 | -3616 |
| MP | 123244 | 118572 | -4672 |

The full matrix is in
`reports/releases/residual_chain_k_sweep_20260804.csv`.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 -Flow sim -RtlVersion v2 `
  -RunId residual-chain-full

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 -Flow synth -RtlVersion v2 `
  -Top cgra_top -RunId residual-chain-validq-synth
```

Raw generated artifacts stay in ignored `logs/` and `work/`. QR remains out of
the datapath and is still reserved for a separate robustness comparison.
