# Residual first-block preload sign-off

Date: 2026-08-10

Baseline: direct-Phi scan128 checkpoint `a60d980`, documented in
`PHI_SCAN128_SIGNOFF_20260810.md`.

## Profile and selected target

The representative M64/N256/K8 profile was reviewed across LDLT, exact top-K,
and residual control before changing RTL.

- LDLT factor work is comparatively small: 79 profiled clocks for OMP and 172
  for CoSaMP.  Its existing request path remains serialized and factor reuse is
  unchanged.
- Exact top-K `S_ISSUE` already sends one PE0 token per clock.  Its large
  `S_CAPTURE` count is mainly producer wait time, so removing controller states
  would not provide a safe independent speedup.
- Residual `S_RESID_PE_WAIT` is material: 2,560 clocks for OMP, IHT, HTP, GP,
  and MP; 5,632 for CoSaMP; 5,568 for SP; and 1,280 for GOMP.
- Correlation is also already PE0-limited at II=1.  Direct-Phi scan256 in one
  clock was deliberately not attempted because N128/N64 callers still require
  the synchronous-SPM settle interval and a wider combinational scan would add
  timing risk.

The bounded optimization therefore removes the initial idle residual clock for
full eight-element support blocks.  `S_WR_ACC_INIT` now captures the first
registered Phi/coefficient payload while clearing the accumulator.  The first
`S_RESID_PE_WAIT` clock can inject that payload at PE0; subsequent blocks keep
the existing chained schedule.

## Correctness guards and rejected trial

An initial all-K preload trial passed the K8 smoke test but failed K4 with 23
IHT/HTP/GP mismatches.  Partial blocks require the old settle clock so inactive
lanes cannot retain stale products.  That trial was rejected.

The accepted implementation is gated by `active_k_count >= 8`:

- full blocks use the early registered preload;
- K2/K4/sub-block callers keep the signed-off settle schedule;
- expanded CoSaMP/SP support can still benefit once it reaches eight entries.

Final unified run: `logs/sim/v2/residual_preload_k8plus_full_20260810`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips from the existing expanded-support capacity
  limit.

The complete cycle matrix is in `residual_first_preload_k_sweep_20260810.csv`.

## Cycle results

Total cycles fall from 1,354,843 to 1,344,523: 10,320 cycles saved (0.76%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 167,584 | 166,912 | -672 | -0.40% |
| CoSaMP | 7 | 280,562 | 278,578 | -1,984 | -0.71% |
| IHT | 8 | 127,036 | 125,244 | -1,792 | -1.41% |
| HTP | 8 | 214,356 | 212,564 | -1,792 | -0.84% |
| SP | 7 | 232,921 | 231,049 | -1,872 | -0.80% |
| GP | 8 | 127,036 | 125,244 | -1,792 | -1.41% |
| GOMP | 8 | 96,088 | 95,672 | -416 | -0.43% |
| MP | 8 | 109,260 | 109,260 | 0 | 0.00% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 34,688 | 34,624 | -64 |
| CoSaMP | 110,536 | 109,512 | -1,024 |
| IHT | 29,145 | 28,633 | -512 |
| HTP | 40,399 | 39,887 | -512 |
| SP | 98,853 | 97,829 | -1,024 |
| GP | 29,145 | 28,633 | -512 |
| GOMP | 19,745 | 19,681 | -64 |
| MP | 25,673 | 25,673 | 0 |

MP keeps a support depth below one complete eight-entry block and therefore
correctly remains on the guarded legacy schedule.

## PE ingress and arithmetic ownership

The change only advances capture into an existing ingress register.  It does
not add a lower-row injection path.  Every residual payload still enters PE0,
then propagates PE0 -> PE1 -> PE2 -> PE3.  The four physical rows retain their
fixed modulo-4 lane ownership, and LDLT, exact top-K, factor reuse, and ACC4
queue semantics are unchanged.

## Timing and resources

OOC run: `logs/synth/v2/residual_preload_k8plus_ooc_20260810`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.624 ns | -0.102 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 123,173 | -2,120 |
| Logic LUT | 121,026 | -2,104 |
| FF | 53,420 | -173 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing remains above the preferred +0.2 ns margin.  The synthesized mapping
uses no additional BRAM or DSP; reported LUT/FF totals are the complete OOC
snapshot rather than an attribution of all mapping differences to the small
controller edit.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId residual_preload_k8plus_full_20260810

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId residual_preload_k8plus_ooc_20260810
```

Raw accepted and rejected run artifacts remain under ignored `logs/` and
`work/` directories.
