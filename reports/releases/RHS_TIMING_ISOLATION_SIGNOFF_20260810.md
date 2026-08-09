# RHS timing-isolation sign-off

Date: 2026-08-10

Baseline: support-limited post-REFINE checkpoint `6495ec5`, documented in
`POST_REFINE_SUPPORT_STREAM_SIGNOFF_20260809.md`.

## Outcome

The four-row LS RHS product is now captured at the existing
`S_ACC_PE_WAIT2 -> S_ACC_RHS` boundary before it enters the 64-bit RHS
accumulator.  This removes the previous combinational PE/DSP-to-`rhs` path
without adding a controller state or an algorithm cycle.

## Architecture invariants

- LS operands still enter through PE0 and use the existing registered
  PE0 -> PE1 -> PE2 -> PE3 propagation path.
- Physical row `r` retains ownership of RHS lane `lane mod 4 == r`; all four
  PE rows therefore participate in each full block-8 RHS transaction.
- Factor reuse, LDLT ordering, exact top-K, support order, and fixed-point
  arithmetic are unchanged.
- The new register is only a timing boundary.  Products are captured while
  leaving the already-present second PE wait state and consumed in the
  already-present RHS accumulation state.

## Correctness and cycles

Final run: `logs/sim/v2/rhs_timing_pipe_full_20260810`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K=16 SP/CoSaMP skips caused by the existing expanded-support
  capacity limit;
- all 62 cycle records match
  `post_refine_support_stream_k_sweep_20260809.csv` exactly.

| Algorithm | Runs | Cycles | Delta |
| --- | ---: | ---: | ---: |
| OMP | 8 | 199,256 | 0 |
| CoSaMP | 7 | 318,322 | 0 |
| IHT | 8 | 138,684 | 0 |
| HTP | 8 | 242,078 | 0 |
| SP | 7 | 266,425 | 0 |
| GP | 8 | 138,684 | 0 |
| GOMP | 8 | 111,920 | 0 |
| MP | 8 | 120,908 | 0 |
| **Total** | **62** | **1,536,277** | **0** |

At M64/N256/K8, OMP remains 42,345 cycles, CoSaMP 129,944 cycles,
HTP 47,049 cycles, SP 116,981 cycles, and GOMP 23,573 cycles.

## Timing and resources

OOC run: `logs/synth/v2/rhs_timing_pipe_ooc_20260810`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.383 ns | +0.254 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 115,132 | -46 |
| Logic LUT | 112,984 | -46 |
| FF | 51,470 | +158 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

All timing constraints are met and the preferred +0.2 ns engineering margin
is restored.  The critical endpoint moved from `rhs` to `residual_acc`; WNS
is now +0.383 ns with a 9.607 ns data path.

## State-profile conclusion and next target

The representative M64/N256/K8 profile before this timing-only change showed:

- CoSaMP: 129,944 total cycles; controller states 36 and 77 each consume
  16,384 cycles, state 100 consumes 14,336 cycles.
- SP: 116,981 total cycles; controller states 36 and 77 each consume 16,384
  cycles, state 100 consumes 11,776 cycles.
- Gram batch preparation state 48 consumes 3,584 CoSaMP cycles and 2,944 SP
  cycles.

The next bounded cycle optimization is to pre-stage the next four-column Gram
transaction during the final matrix-drain cycles, eliminating one preparation
cycle between consecutive batches.  It must retain row ownership, strict PE0
ingress, single LS request ownership, exact fixed-point results, and positive
WNS.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId rhs_timing_pipe_full_20260810

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId rhs_timing_pipe_ooc_20260810
```

Raw simulation, synthesis, and profile artifacts remain under ignored
`logs/` and `work/` directories.
