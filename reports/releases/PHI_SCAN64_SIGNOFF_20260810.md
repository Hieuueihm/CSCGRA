# Direct-Phi scan64 sign-off

Date: 2026-08-10

Baseline: four-row Gram batch-overlap checkpoint `d4ba90d`, documented in
`GRAM_BATCH_OVERLAP_SIGNOFF_20260810.md`.

## Outcome

The direct Phi/support scanner processes two 32-column windows per controller
clock for N=128/256.  Fixed 32- and 64-step LFSR jump matrices advance the row
state without creating a 64-stage serial feedback chain.  State 77 therefore
falls by one half on the large configured problems.

For N<=64, the original 32-column schedule is retained.  Several callers
change a synchronous SPM address on the edge entering the scan; N=64 needs the
original two scan clocks to preserve that memory-settle interval.

## Correctness-preserving details

- The scan only regenerates deterministic Phi values for cached support
  indices.  It does not change support order, coefficient order, factor reuse,
  LDLT arithmetic, or matrix write order.
- Regenerated operands still enter the compute fabric only at PE0 and follow
  the existing PE0 -> PE1 -> PE2 -> PE3 path.
- All large LS MAC and Gram transactions keep their four-row ownership.  This
  change accelerates LFSR/address control, not the PE arithmetic topology.
- Correlation state 36 is unchanged because it already accepts one PE0 token
  per clock and pipelines those tokens through all four physical rows.
- The fixed jump matrices were checked bit-for-bit against 32 and 64 serial
  Galois LFSR steps.

An initial one-clock N=64 schedule was rejected after case 6 exposed 18 output
mismatches.  Adding the N<=64 scan32 guard restores the original schedule;
the final unified full sweep has no failures.

## Correctness

Final unified run: `logs/sim/v2/phi_scan64_final_full_20260810`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K=16 SP/CoSaMP skips caused by the existing expanded-support
  capacity limit.

The complete matrix is in `phi_scan64_k_sweep_20260810.csv`.

## Cycle results

Total cycles fall from 1,514,273 to 1,418,017: 96,256 cycles saved (6.36%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 195,088 | 178,960 | -16,128 | -8.27% |
| CoSaMP | 7 | 310,482 | 294,610 | -15,872 | -5.11% |
| IHT | 8 | 138,684 | 130,620 | -8,064 | -5.82% |
| HTP | 8 | 239,874 | 223,746 | -16,128 | -6.72% |
| SP | 7 | 260,713 | 244,841 | -15,872 | -6.09% |
| GP | 8 | 138,684 | 130,620 | -8,064 | -5.82% |
| GOMP | 8 | 109,840 | 101,776 | -8,064 | -7.34% |
| MP | 8 | 120,908 | 112,844 | -8,064 | -6.67% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 41,592 | 37,496 | -4,096 |
| CoSaMP | 126,392 | 118,200 | -8,192 |
| IHT | 32,217 | 30,169 | -2,048 |
| HTP | 46,797 | 42,701 | -4,096 |
| SP | 114,069 | 105,877 | -8,192 |
| GP | 32,217 | 30,169 | -2,048 |
| GOMP | 23,197 | 21,149 | -2,048 |
| MP | 28,745 | 26,697 | -2,048 |

The profiled CoSaMP K8 state 77 count falls from 16,384 to 8,192.  State 36
remains 16,384 and Gram wait state 100 remains 10,752.

## Timing and resources

OOC run: `logs/synth/v2/phi_scan64_n64_guard_ooc_20260810`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.681 ns | +0.298 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 118,494 | +3,362 (+2.92%) |
| Logic LUT | 116,347 | +3,363 |
| FF | 51,458 | -12 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

All timing constraints are met with substantially more than the preferred
+0.2 ns margin.  The critical endpoint remains in the residual accumulator,
outside the direct-Phi scan cone.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId phi_scan64_final_full_20260810

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId phi_scan64_n64_guard_ooc_20260810
```

Raw simulation, synthesis, rejected-trial, and profile artifacts remain under
ignored `logs/` and `work/` directories.
