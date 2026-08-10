# OP_ACC4 one-entry queue sign-off

Date: 2026-08-10

Baseline: direct-Phi scan64 checkpoint `350a8f1`, documented in
`PHI_SCAN64_SIGNOFF_20260810.md`.

## Outcome

`ls_matrix_service` now contains a one-entry fall-through pending queue for
`OP_ACC4`.  The controller prepares the next four-column Gram transaction one
clock earlier and the service accepts it while the active transaction drains
column three.  The next transaction writes column zero on the immediately
following clock, with no idle matrix-write slot.

The controller Gram guard is reduced from two clocks to one.  This removes one
controller clock from each consecutive Gram batch while retaining the original
four-cycle bank drain for every transaction.

## Transaction safety and PE ownership

- The active transaction alone writes the matrix banks; the queue holds at
  most one pending transaction.
- If a request arrives before the last active column, it is stored in the
  pending slot.  On the final drain edge it is promoted atomically.
- If the pending slot is empty and the registered request arrives on the final
  drain edge, the queue operates in fall-through mode and loads the active slot
  directly.  The old column-three write still uses the pre-edge active data.
- Matrix column order, lane-valid masks, factor reuse, and LDLT arithmetic are
  unchanged.
- Data still enters only at PE0 and propagates PE0 -> PE1 -> PE2 -> PE3.
- Physical PE row `r` still owns Gram column `acc_j + r`; every full ACC4
  transaction therefore uses all four rows with a fixed role.

## Correctness

Profiled smoke run: `logs/sim/v2/acc4_queue_k8_smoke_20260810`

- M64/N256/K8: 45 PASS / 0 FAIL across all eight algorithms.

Final unified run: `logs/sim/v2/acc4_queue_full_20260810`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips caused by the existing expanded-support
  capacity limit.

The complete cycle matrix is in `acc4_queue_k_sweep_20260810.csv`.

## Cycle results

Total cycles fall from 1,418,017 to 1,395,803: 22,214 cycles saved (1.57%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 178,960 | 174,752 | -4,208 | -2.35% |
| CoSaMP | 7 | 294,610 | 286,706 | -7,904 | -2.68% |
| IHT | 8 | 130,620 | 130,620 | 0 | 0.00% |
| HTP | 8 | 223,746 | 221,524 | -2,222 | -0.99% |
| SP | 7 | 244,841 | 239,065 | -5,776 | -2.36% |
| GP | 8 | 130,620 | 130,620 | 0 | 0.00% |
| GOMP | 8 | 101,776 | 99,672 | -2,104 | -2.07% |
| MP | 8 | 112,844 | 112,844 | 0 | 0.00% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 37,496 | 36,736 | -760 |
| CoSaMP | 118,200 | 114,632 | -3,568 |
| IHT | 30,169 | 30,169 | 0 |
| HTP | 42,701 | 42,447 | -254 |
| SP | 105,877 | 102,949 | -2,928 |
| GP | 30,169 | 30,169 | 0 |
| GOMP | 21,149 | 20,769 | -380 |
| MP | 26,697 | 26,697 | 0 |

State profiling confirms that `S_GRAM_ACC_WAIT` falls by one third.  At K8 it
changes from 2,304 to 1,536 clocks for OMP, 10,752 to 7,168 for CoSaMP, 768 to
512 for HTP, 8,832 to 5,888 for SP, and 1,152 to 768 for GOMP.  Algorithms
without Gram/LS batches remain cycle-identical.

## Timing and resources

OOC run: `logs/synth/v2/acc4_queue_ooc_20260810`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.664 ns | -0.017 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 121,714 | +3,220 (+2.72%) |
| Logic LUT | 119,566 | +3,219 |
| FF | 53,600 | +2,142 (+4.16%) |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing passes with more than the preferred +0.2 ns margin.  The critical path
still ends in `residual_acc` and is outside the ACC4 queue cone.  The resource
increase is the expected cost of retaining one complete 2,048-bit Gram payload
plus masks and queue-selection logic; no arithmetic unit or memory macro is
duplicated.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId acc4_queue_full_20260810

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId acc4_queue_ooc_20260810
```

Raw simulation, profile, and synthesis artifacts remain under ignored `logs/`
and `work/` directories.
