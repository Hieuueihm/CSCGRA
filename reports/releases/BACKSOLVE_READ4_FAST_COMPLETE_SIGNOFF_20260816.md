# Back-solve READ4 fast-complete sign-off

Date: 2026-08-16

Baseline: LDLT WRITE4 completion-chain checkpoint `120a58f`, documented in
`LDLT_WRITE4_COMPLETION_CHAIN_SIGNOFF_20260812.md`.

## Selected optimization

The back-substitution READ4 command state previously registered `ls_start_q`
and then moved to its wait state.  Because the matrix service sampled that
registered pulse on the following edge, every four-row column read spent three
clocks in `S_BACK_RHS_READ_WAIT` after its command state.

The accepted change keeps `S_BACK_RHS_READ` as the only launch state, but
decodes that state at the matrix-service boundary.  On the READ-to-WAIT edge,
the service now samples:

- `LS_OP_READ4`;
- registered `ldlt_p_base_q` as both row addresses; and
- registered `back_i` as both column addresses.

All other LS operations retain the original registered command path.  The
change removes one service clock per back-solve READ4 without duplicating a
wide launch cone in `S_BACK_PREP` or `S_BACK_UPDATE`.

## Rejected direct-chain trial

A first trial launched READ4 directly from `S_BACK_PREP` and the PE multiply
completion branch.  It produced the same cycle reduction and passed the full
sweep, but synthesis increased total LUT from 127,248 to 131,977 (+4,729).
That trial was rejected because it violated the resource-neutral objective.

The accepted service-boundary fast-complete form instead reduces synthesized
LUT/FF relative to the baseline while retaining the same cycle result.

## Single-request and PE provenance

`S_BACK_RHS_READ` is reached only after the preceding LS request is complete or
after PE multiplication while the service is idle.  It issues one pulse on the
READ-to-WAIT edge; no queue and no second in-flight LS request are introduced.

READ4 only fetches coefficients.  Back-substitution multiplication still uses
the signed-off four-row PE path: row `r` owns candidate `base+r`.  Sparse
arithmetic ingress remains PE0-only and propagates PE0 -> PE1 -> PE2 -> PE3.
Factor reuse, pivot order, matrix contents, top-K, and residual scheduling are
unchanged.

## Profile proof

K8 profile run: `logs/sim/v2/backsolve_read4_fast_k8_smoke_20260816`

- 45 PASS / 0 FAIL across all eight algorithms;
- total K8 reduction: 844 cycles;
- state 106 (`S_BACK_RHS_READ`) retains 844 total command clocks;
- state 107 (`S_BACK_RHS_READ_WAIT`) falls from 2,532 to 1,688 clocks;
- the 844-clock wait reduction exactly equals the number of READ4 commands;
- multiply, factor, top-K, support, residual, and iteration counts are
  unchanged.

## Correctness

Final unified run: `logs/sim/v2/backsolve_read4_fast_full_20260816`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips from the existing expanded-support capacity
  limit;
- no mismatch, timeout, or simulation error lines.

The cycle matrix is in
`backsolve_read4_fast_complete_k_sweep_20260816.csv`.

## Cycle results

Total cycles fall from 1,334,819 to 1,331,717: 3,102 cycles saved (0.232%).

| Algorithm | Runs | Baseline | Final | Saved | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 166,448 | 166,140 | 308 | -0.185% |
| CoSaMP | 7 | 274,058 | 273,045 | 1,013 | -0.370% |
| IHT | 8 | 125,244 | 125,244 | 0 | 0.000% |
| HTP | 8 | 211,534 | 210,758 | 776 | -0.367% |
| SP | 7 | 227,737 | 226,906 | 831 | -0.365% |
| GP | 8 | 125,244 | 125,244 | 0 | 0.000% |
| GOMP | 8 | 95,294 | 95,120 | 174 | -0.183% |
| MP | 8 | 109,260 | 109,260 | 0 | 0.000% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Saved |
| --- | ---: | ---: | ---: |
| OMP | 34,556 | 34,522 | 34 |
| CoSaMP | 107,872 | 107,504 | 368 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,787 | 39,707 | 80 |
| SP | 96,469 | 96,127 | 342 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,625 | 19,605 | 20 |
| MP | 25,673 | 25,673 | 0 |

## Timing and resources

OOC run: `logs/synth/v2/backsolve_read4_fast_ooc_20260816`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.586 ns | -0.076 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 122,435 | -4,813 |
| Logic LUT | 120,279 | -4,821 |
| FF | 53,488 | -123 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing remains above the preferred +0.2 ns margin.  The optimization adds no
BRAM or DSP and is resource-neutral by the sign-off criterion.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -Cases 1 -ProfileStates `
  -RunId backsolve_read4_fast_k8_smoke_20260816

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId backsolve_read4_fast_full_20260816

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId backsolve_read4_fast_ooc_20260816
```

Raw profile, simulation, and synthesis artifacts remain under ignored `logs/`
and `work/` directories.
