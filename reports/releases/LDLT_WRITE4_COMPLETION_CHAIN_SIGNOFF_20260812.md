# LDLT WRITE4 completion chain sign-off

Date: 2026-08-12

Baseline: diagonal READ2-chain checkpoint `6bb6104`, documented in
`LDLT_DIAG_READ2_CHAIN_SIGNOFF_20260811.md`.

## Selected optimization

The LDLT four-row update previously returned from `S_LDL_ROW_WRITE_WAIT` to a
command/setup state after every committed WRITE4.  The accepted change uses the
WRITE4 completion pulse to perform the following transition directly:

- prepare four lane-valid and accumulator registers and launch READ4 for the
  next four-row block;
- for prefix-factor reuse, prepare the appended rows and launch READ4 for the
  next cached pivot; or
- after the last row block of a normal pivot, launch the next diagonal READ2.

The old setup state remains for initial factor/prefix entry.  Only repeated
completion-to-command bubbles are removed.

## Single-request and PE provenance

Every chained command is issued only when `ls_done_w` reports completion of the
preceding WRITE4.  The matrix service has returned to IDLE on that edge, so no
queue or second in-flight LS request is introduced.

READ4/READ2 only fetch operands.  All large LDLT arithmetic retains the signed-
off four-row PE path and fixed row ownership.  Sparse arithmetic ingress remains
PE0-only and propagates PE0 -> PE1 -> PE2 -> PE3.  Pivot order, matrix writes,
factor reuse, top-K, residual scheduling, and ACC4 behavior are unchanged.

## Profile proof

K8 profile run: `logs/sim/v2/ldlt_write4_chain_k8_smoke_20260812`

- 45 PASS / 0 FAIL across all eight algorithms;
- total K8 reduction: 664 cycles;
- the reduction equals the removed portions of state 59 (diagonal command) and
  state 80 (four-row setup) exactly;
- states 60, 82, 84, 85, 119, 121, 122, and 124 retain identical counts, so
  READ2/READ4 waits, both border multiplies, final multiply, and WRITE4 wait are
  unchanged.

## Correctness

Final unified run: `logs/sim/v2/ldlt_write4_chain_full_20260812`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips from the existing expanded-support capacity
  limit;
- no mismatch, timeout, or simulation error lines.

The cycle matrix is in
`ldlt_write4_completion_chain_k_sweep_20260812.csv`.

## Cycle results

Total cycles fall from 1,336,899 to 1,334,819: 2,080 cycles saved (0.16%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 166,644 | 166,448 | -196 | -0.12% |
| CoSaMP | 7 | 274,962 | 274,058 | -904 | -0.33% |
| IHT | 8 | 125,244 | 125,244 | 0 | 0.00% |
| HTP | 8 | 211,740 | 211,534 | -206 | -0.10% |
| SP | 7 | 228,401 | 227,737 | -664 | -0.29% |
| GP | 8 | 125,244 | 125,244 | 0 | 0.00% |
| GOMP | 8 | 95,404 | 95,294 | -110 | -0.12% |
| MP | 8 | 109,260 | 109,260 | 0 | 0.00% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 34,584 | 34,556 | -28 |
| CoSaMP | 108,200 | 107,872 | -328 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,807 | 39,787 | -20 |
| SP | 96,741 | 96,469 | -272 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,641 | 19,625 | -16 |
| MP | 25,673 | 25,673 | 0 |

## Timing and resources

OOC run: `logs/synth/v2/ldlt_write4_chain_ooc_20260812`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.662 ns | -0.016 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 127,248 | +1,582 |
| Logic LUT | 125,100 | +1,596 |
| FF | 53,611 | +194 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing remains above the preferred +0.2 ns margin.  No BRAM or DSP is added.
The resource cost comes from next-block/pivot selection and replicated lane
setup logic.  This is a modest cycle improvement with a measurable LUT/FF
tradeoff, so the next optimization should not add another wide control cone.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -Cases 1 -ProfileStates `
  -RunId ldlt_write4_chain_k8_smoke_20260812

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId ldlt_write4_chain_full_20260812

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId ldlt_write4_chain_ooc_20260812
```

Raw profile, simulation, and synthesis artifacts remain under ignored `logs/`
and `work/` directories.
