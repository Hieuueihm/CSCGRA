# Strict-PE0 block-8 prune sign-off

Date: 2026-08-06

Baseline: fused correlation-update checkpoint `a1c470e`, recorded in
`fused_corr_update_program_k_sweep_20260806.csv`.

## Change

`OP_PRUNE_X` now processes one eight-element x word per transaction instead
of iterating over eight scalar lanes.  The transaction preserves the strict
ingress and four-row ownership rule:

1. PE0 accepts the complete x word and transaction metadata for one cycle.
2. PE1 performs the absolute-value/threshold stage.
3. PE2 applies the exact support keep mask.
4. PE3 applies the range mask and commits all eight lanes.

The valid signal is intentionally a one-cycle PE0 token.  Registered mesh
mode, data, keep mask, and address metadata carry the transaction southward;
PE1, PE2, and PE3 do not receive a second controller ingress.  Holding the
controller valid signal throughout the wait and write states was tested first
and rejected at WNS -0.081 ns.  The retained pulse form removes the new
controller-to-PE timing coupling and restores positive timing.

## Sign-off result

| Metric | Fused baseline | Block-8 prune | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1,682,044 | 1,650,508 | -31,536 (-1.87%) |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| Valid cycle records | 62 | 62 | unchanged |
| Expected K16 skips | 2 | 2 | unchanged |
| WNS | +0.309 ns | +0.091 ns | -0.218 ns, still met |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 113,628 | 112,478 | -1,150 (-1.01%) |
| FF | 50,762 | 50,606 | -156 (-0.31%) |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

The retained critical path is from the support-service depth memory to the
controller residual accumulator, not from the new prune transaction.  Its
data-path delay is 9.899 ns at the 10 ns clock constraint.  Timing therefore
passes the hard WNS gate, although the +0.091 ns margin is below the preferred
+0.2 ns release margin and should be protected by the next change.

## Per-algorithm aggregate cycles

| Algorithm | Fused baseline | Block-8 prune | Delta |
| --- | ---: | ---: | ---: |
| OMP | 200,088 | 200,088 | 0 |
| CoSaMP | 345,649 | 345,649 | 0 |
| IHT | 173,790 | 163,278 | -10,512 (-6.05%) |
| HTP | 275,003 | 264,491 | -10,512 (-3.82%) |
| SP | 276,931 | 276,931 | 0 |
| GP | 175,870 | 165,358 | -10,512 (-5.98%) |
| GOMP | 113,805 | 113,805 | 0 |
| MP | 120,908 | 120,908 | 0 |

At M=64, N=256, K=16, IHT, HTP, and GP each save 4,608 cycles.  All
algorithms that do not execute `OP_PRUNE_X` match the baseline cycle matrix
exactly.  The complete result matrix is in
`strict_pe0_prune_block8_k_sweep_20260806.csv`.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId strict-pe0-prune8-pulse-full

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow synth -RtlVersion v2 -Top cgra_top `
  -RunId strict-pe0-prune8-pulse-synth
```

Raw simulation, timing, and utilization artifacts remain under ignored
`logs/` and `work/` directories.  The next optimization should first recover
timing margin by isolating the support-depth/residual-accumulator control path;
after WNS is comfortably above +0.2 ns, state residency should select between
exact top-K/factor-check control and further block scheduling.
