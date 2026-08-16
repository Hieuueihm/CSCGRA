# Forward-solve shared tail-completion sign-off

Date: 2026-08-16

Baseline: back-solve READ4 fast-complete checkpoint `918dcf6`, documented in
`BACKSOLVE_READ4_FAST_COMPLETE_SIGNOFF_20260816.md`.

## Selected optimization

The unit-lower LDLT forward solve fetched valid terms in four-lane blocks, then
spent one `S_ELIM_ROW` clock on each inactive lane at the end of a partial
block.  Those clocks only wrote zeros before the four-row multiply.

The accepted implementation detects the last valid READ2 completion and moves
directly to `S_ELIM_PREP`.  Inactive coefficient lanes are cleared on that same
edge.  Diagonal gather and forward solve share one tail-state decode, one
six-bit limit mux/comparator, and the existing 4x64-bit coefficient-lane clear
path.  Only the coefficient operand is cleared; the paired stale RHS operand is
safe because its product with zero is zero.

READ2 launch remains on the registered LS command path.  The matrix-service
latency is unchanged at three clocks per request, avoiding the large mux/decode
cost of a service-boundary fast-start.

## Rejected trials

Several faster forms passed correctness but were rejected on resources:

- a direct forward READ2 fast-start saved 9,527 aggregate cycles but used
  127,270 LUT;
- fast-start plus tail completion saved 12,408 cycles but used 128,434 LUT;
- parallel clearing of both coefficient and RHS tails used 125,595 LUT;
- clearing only the coefficient tail with a separate state write decode used
  128,748 LUT.

The selected shared comparator/write form uses 123,551 LUT.  It gives up the
READ2 fast-start saving, but bounds the increase to 1,116 LUT (+0.91%), reduces
FF by 65, and preserves positive timing margin.

## Single-request and PE provenance

`S_ELIM_ROW` remains the only forward READ2 launch state and uses `ls_start_q`.
The following request is not launched until `ls_done_w`, so exactly one LS
request remains active.

The change only removes invalid-lane setup clocks.  The four-row wide multiply
is unchanged: PE row `r` owns term `base+r`; inactive physical rows receive a
zero coefficient.  Sparse ingress remains PE0-only and propagates PE0 -> PE1 ->
PE2 -> PE3.  Factor contents, pivot order, support, top-K, residual scheduling,
and iteration counts are unchanged.

## Profile proof

K8 profile run:
`logs/sim/v2/forward_read2_shared_tailcmp_k8_smoke_20260816`

- 45 PASS / 0 FAIL across all eight algorithms;
- total K8 reduction: 742 cycles;
- state 92 (`S_ELIM_ROW_READ`) retains three clocks per valid READ2;
- state 13 (`S_ELIM_ROW`) contains only valid request launches;
- all saved clocks are inactive tail-lane writes;
- IHT, GP, and MP are cycle-identical because they do not use this forward
  LDLT solve.

## Correctness

Final unified run:
`logs/sim/v2/forward_read2_shared_tailcmp_full_20260816`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips from the existing expanded-support capacity
  limit;
- no mismatch, timeout, or simulation error lines.

The cycle matrix is in
`forward_solve_shared_tail_completion_k_sweep_20260816.csv`.

## Cycle results

Total cycles fall from 1,331,717 to 1,328,836: 2,881 cycles saved (0.216%).

| Algorithm | Runs | Baseline | Final | Saved | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 166,140 | 165,788 | 352 | -0.212% |
| CoSaMP | 7 | 273,045 | 272,157 | 888 | -0.325% |
| IHT | 8 | 125,244 | 125,244 | 0 | 0.000% |
| HTP | 8 | 210,758 | 210,098 | 660 | -0.313% |
| SP | 7 | 226,906 | 226,126 | 780 | -0.344% |
| GP | 8 | 125,244 | 125,244 | 0 | 0.000% |
| GOMP | 8 | 95,120 | 94,919 | 201 | -0.211% |
| MP | 8 | 109,260 | 109,260 | 0 | 0.000% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Saved |
| --- | ---: | ---: | ---: |
| OMP | 34,522 | 34,470 | 52 |
| CoSaMP | 107,504 | 107,216 | 288 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,707 | 39,611 | 96 |
| SP | 96,127 | 95,851 | 276 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,605 | 19,575 | 30 |
| MP | 25,673 | 25,673 | 0 |

## Timing and resources

OOC run: `logs/synth/v2/forward_read2_shared_tailcmp_ooc_20260816`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.605 ns | +0.019 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 123,551 | +1,116 |
| Logic LUT | 121,387 | +1,108 |
| FF | 53,423 | -65 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing remains above the preferred +0.2 ns margin.  The implementation adds no
BRAM or DSP, reduces FF, and keeps the LUT increase below one percent.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -Cases 1 -ProfileStates `
  -RunId forward_read2_shared_tailcmp_k8_smoke_20260816

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId forward_read2_shared_tailcmp_full_20260816

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top `
  -RunId forward_read2_shared_tailcmp_ooc_20260816
```

Raw profile, simulation, and synthesis artifacts remain under ignored `logs/`
and `work/` directories.
