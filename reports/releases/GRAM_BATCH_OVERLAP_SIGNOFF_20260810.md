# Gram batch-overlap sign-off

Date: 2026-08-10

Baseline: registered LS RHS timing checkpoint `242ded7`, documented in
`RHS_TIMING_ISOLATION_SIGNOFF_20260810.md`.

## Outcome

Preparation of the next four-column Gram transaction now overlaps the final
two writes of the current row-banked matrix-service drain.  The controller
guard changes from three clocks to the minimum safe two clocks, removing one
idle controller cycle per Gram batch.

## Transaction safety and PE roles

- The matrix service still drains all four columns of `OP_ACC4` before it
  accepts another request.
- `ls_start_q` is registered.  With two guard clocks, the controller prepares
  PE operands while columns two and three drain, asserts the next start while
  column four drains, and the service observes that start only after returning
  to idle on the following edge.
- Only one LS request is active at a time.  A one-clock guard would expose the
  start pulse while the service is still in `S_ACC4`, so it is intentionally
  not used.
- Data ingress remains PE0 only and follows PE0 -> PE1 -> PE2 -> PE3.
- Physical row `r` continues to own Gram column `acc_j + r`; all four PE rows
  participate in every full four-column transaction.
- Arithmetic, matrix write order, factor reuse, LDLT, and support ordering are
  unchanged.

## Correctness

Final run: `logs/sim/v2/gram_overlap_full_20260810`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K=16 SP/CoSaMP skips caused by the existing expanded-support
  capacity limit;
- representative profiled smoke tests passed for OMP, CoSaMP, HTP, SP, and
  GOMP before the full sweep.

The complete cycle matrix is in
`gram_batch_overlap_k_sweep_20260810.csv`.

## Cycle results

Total cycles fall from 1,536,277 to 1,514,273: 22,004 cycles saved (1.43%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 199,256 | 195,088 | -4,168 | -2.09% |
| CoSaMP | 7 | 318,322 | 310,482 | -7,840 | -2.46% |
| IHT | 8 | 138,684 | 138,684 | 0 | 0.00% |
| HTP | 8 | 242,078 | 239,874 | -2,204 | -0.91% |
| SP | 7 | 266,425 | 260,713 | -5,712 | -2.14% |
| GP | 8 | 138,684 | 138,684 | 0 | 0.00% |
| GOMP | 8 | 111,920 | 109,840 | -2,080 | -1.86% |
| MP | 8 | 120,908 | 120,908 | 0 | 0.00% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 42,345 | 41,592 | -753 |
| CoSaMP | 129,944 | 126,392 | -3,552 |
| HTP | 47,049 | 46,797 | -252 |
| SP | 116,981 | 114,069 | -2,912 |
| GOMP | 23,573 | 23,197 | -376 |

The CoSaMP controller profile confirms that `S_GRAM_ACC_WAIT` falls from
14,336 to 10,752 cycles at M64/N256/K8.  The Gram compute and four-row PE
transaction counts themselves are unchanged.

## Timing and resources

OOC run: `logs/synth/v2/gram_overlap_ooc_20260810`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.383 ns | 0 |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 115,132 | 0 |
| Logic LUT | 112,984 | 0 |
| FF | 51,470 | 0 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

All timing constraints are met and the +0.2 ns preferred margin remains
satisfied.  The critical endpoint remains `residual_acc`, outside the Gram
schedule change.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId gram_overlap_full_20260810

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId gram_overlap_ooc_20260810
```

Raw simulation, synthesis, and profile artifacts remain under ignored
`logs/` and `work/` directories.
