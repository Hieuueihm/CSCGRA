# Direct-Phi scan128 sign-off

Date: 2026-08-10

Baseline: one-entry ACC4 queue checkpoint `639ff39`, documented in
`ACC4_QUEUE_SIGNOFF_20260810.md`.

## Outcome

Direct Phi/support regeneration now processes four independent 32-column
windows per controller clock when N=256.  Fixed 32/64/96/128-step LFSR jump
matrices avoid a serial 128-step feedback path.  A 256-column row therefore
needs two scan clocks instead of four.

N=128 retains the signed-off 64-column path and N=64 retains the 32-column
path.  Those configurations need two controller clocks after several callers
change a synchronous SPM address; collapsing either to one clock would remove
the required settle interval.

## Correctness and PE provenance

- Phi signs are regenerated from the same LFSR state and support index.  The
  support order, coefficient order, LDLT arithmetic, and ACC4 queue are not
  changed.
- The scan only prepares operands.  Arithmetic data still enters at PE0 and
  propagates through PE1, PE2, and PE3.
- Correlation remains at PE0-limited II=1 with four round-robin row-owned
  partial sums.  Gram operations retain one fixed column per physical PE row.
- Separate N=128 and N=64 guard regressions are cycle-identical to the baseline.

Profiled K8 run: `logs/sim/v2/phi_scan128_k8_smoke_20260810`

- 45 PASS / 0 FAIL across all eight algorithms.
- State 77 falls exactly by half for every algorithm.

Guard runs:

- `logs/sim/v2/phi_scan128_n128_guard_20260810`: 45 PASS / 0 FAIL.
- `logs/sim/v2/phi_scan128_n64_guard_20260810`: 45 PASS / 0 FAIL.

Final unified run: `logs/sim/v2/phi_scan128_full_20260810`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips caused by the existing expanded-support
  capacity limit.

The complete cycle matrix is in `phi_scan128_k_sweep_20260810.csv`.

## Cycle results

Total cycles fall from 1,395,803 to 1,354,843: 40,960 cycles saved (2.93%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 174,752 | 167,584 | -7,168 | -4.10% |
| CoSaMP | 7 | 286,706 | 280,562 | -6,144 | -2.14% |
| IHT | 8 | 130,620 | 127,036 | -3,584 | -2.74% |
| HTP | 8 | 221,524 | 214,356 | -7,168 | -3.24% |
| SP | 7 | 239,065 | 232,921 | -6,144 | -2.57% |
| GP | 8 | 130,620 | 127,036 | -3,584 | -2.74% |
| GOMP | 8 | 99,672 | 96,088 | -3,584 | -3.60% |
| MP | 8 | 112,844 | 109,260 | -3,584 | -3.18% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 36,736 | 34,688 | -2,048 |
| CoSaMP | 114,632 | 110,536 | -4,096 |
| IHT | 30,169 | 29,145 | -1,024 |
| HTP | 42,447 | 40,399 | -2,048 |
| SP | 102,949 | 98,853 | -4,096 |
| GP | 30,169 | 29,145 | -1,024 |
| GOMP | 20,769 | 19,745 | -1,024 |
| MP | 26,697 | 25,673 | -1,024 |

At K8, state 77 changes from 4,096 to 2,048 clocks for OMP/HTP,
8,192 to 4,096 for CoSaMP/SP, and 2,048 to 1,024 for IHT/GP/GOMP/MP.

## Timing and resources

OOC run: `logs/synth/v2/phi_scan128_ooc_20260810`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.726 ns | +0.062 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 125,293 | +3,579 (+2.94%) |
| Logic LUT | 123,130 | +3,564 |
| FF | 53,593 | -7 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing passes with more than the preferred +0.2 ns margin.  The critical path
still ends in `residual_acc`, outside the scan128 cone.  The added LUTs implement
the two extra independent 32-column lookup windows; no PE arithmetic, BRAM, or
DSP resource is duplicated.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId phi_scan128_full_20260810

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId phi_scan128_ooc_20260810
```

Raw simulation, profile, guard, and synthesis artifacts remain under ignored
`logs/` and `work/` directories.
