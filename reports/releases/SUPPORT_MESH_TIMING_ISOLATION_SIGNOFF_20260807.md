# Support-depth and PE0 mesh-ingress timing-isolation sign-off

Date: 2026-08-07

Baseline: strict-PE0 block-8 prune checkpoint `55b86cb`, recorded in
`STRICT_PE0_PRUNE_BLOCK8_SIGNOFF_20260806.md` and
`strict_pe0_prune_block8_k_sweep_20260806.csv`.

## Change

Two registered boundaries isolate controller state from the residual
arithmetic path:

1. The support depth used by the loop controller and the active-K value used
   by the controller/PE array are sampled on the same clock edge.  The
   support-service `depth_mem` no longer directly drives the high-fanout
   active-K and PE control cone.
2. Every controller-generated mesh transaction is registered at the top-level
   PE0 ingress boundary: valid, context word, mode, address metadata,
   x/delta payloads, keep mask, threshold, and shift travel together.

The second stage is before PE0, not an alternate ingress.  PE0 remains the
only row that accepts a controller transaction, and the existing registered
PE0 -> PE1 -> PE2 -> PE3 wavefront remains unchanged.  The pre-existing drain
budget absorbs the new boundary, so no controller wait count or program cycle
was added.

## Timing iterations

| Trial | WNS | Critical source | Result |
| --- | ---: | --- | --- |
| Block-8 prune baseline | +0.091 ns | support `depth_mem[0]` | starting point |
| Support/active-K samples only | +0.124 ns | controller `write_idx` | depth path removed, below +0.2 ns target |
| Plus registered PE0 mesh ingress | +0.325 ns | controller state register | retained |

The retained design has TNS 0 and zero failing endpoints at 100 MHz.  Its
worst data-path delay is 9.665 ns under the 10 ns constraint.  Neither
`depth_mem` nor `write_idx` is the source of the final worst path.

## Sign-off result

| Metric | Block-8 prune | Timing-isolated | Delta |
| --- | ---: | ---: | ---: |
| Full K-sweep cycles | 1,650,508 | 1,650,508 | 0 |
| Correctness | 348 PASS / 0 FAIL | 348 PASS / 0 FAIL | unchanged |
| Valid cycle records | 62 | 62 | unchanged |
| Expected K16 skips | 2 | 2 | unchanged |
| WNS | +0.091 ns | +0.325 ns | +0.234 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 112,478 | 112,516 | +38 (+0.03%) |
| FF | 50,606 | 51,122 | +516 (+1.02%) |
| RAMB36 / DSP48 | 24 / 71 | 24 / 71 | unchanged |

## Per-algorithm aggregate cycles

| Algorithm | Cycles | Delta |
| --- | ---: | ---: |
| OMP | 200,088 | 0 |
| CoSaMP | 345,649 | 0 |
| IHT | 163,278 | 0 |
| HTP | 264,491 | 0 |
| SP | 276,931 | 0 |
| GP | 165,358 | 0 |
| GOMP | 113,805 | 0 |
| MP | 120,908 | 0 |

All 62 cycle records match
`strict_pe0_prune_block8_k_sweep_20260806.csv` exactly.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId support-depth-mesh-ingress-pipe-full

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow synth -RtlVersion v2 -Top cgra_top `
  -RunId support-depth-mesh-ingress-pipe-synth
```

Raw simulation, timing, and utilization artifacts remain under ignored
`logs/` and `work/` directories.  With timing margin restored above +0.2 ns,
the next optimization may profile exact top-K/factor-check state residency;
positive WNS and strict PE0 ingress remain hard release gates.
