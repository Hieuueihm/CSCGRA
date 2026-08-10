# LDLT diagonal READ2 chain sign-off

Date: 2026-08-11

Baseline: guarded residual first-block preload checkpoint `43abb69`, documented
in `RESIDUAL_FIRST_PRELOAD_SIGNOFF_20260810.md`.

## Profile and selected target

The representative M64/N256/K8 profile was split across factor-check, LDLT
diagonal/READ2, top-K, and residual control before changing RTL.

- Factor-check costs only 38-172 clocks per affected algorithm.  Removing its
  final state would require a next-value seen-mask/fingerprint acceptance path,
  adding timing risk for roughly one clock per refine request.
- Exact top-K issue is already one PE0 token per clock.  Its large capture count
  is producer wait time rather than a removable controller bubble.
- `S_LDL_DIAG_GATHER` is a pure command/padding state.  At K8 it costs 40
  clocks for OMP, 1,312 for CoSaMP, 80 for HTP, 1,088 for SP, and 40 for GOMP.
- `S_LDL_DIAG_GATHER_WAIT` and both four-lane multiply phases contain real
  service/datapath latency and were left unchanged.

The accepted optimization chains the next same-row READ2 request from the
previous completion pulse.  The first gather starts on diagonal-read
completion; later lanes start on the preceding gather completion; lane zero of
the next four-value batch starts when the previous PE multiply completes.
Inactive tail lanes are zero-filled together when the last valid response
arrives instead of spending one controller clock per lane.

## Single-request and PE provenance

`ls_start_q` is asserted only when the previous matrix-service request has
completed, or while the service has remained idle through the multiply phase.
There is no queue and never more than one active LS request.

READ2 only fetches matrix operands.  Diagonal products still use the existing
four-lane wide multiply path with fixed physical PE-row ownership.  All sparse
arithmetic ingress remains PE0-only and propagates PE0 -> PE1 -> PE2 -> PE3.
LDLT values, pivot order, factor reuse, top-K order, residual scheduling, and
the ACC4 queue are unchanged.

## Profile proof

Profile run: `logs/sim/v2/ldlt_diag_chain_k8_smoke_20260811`

- 45 PASS / 0 FAIL across all eight algorithms.
- State 61 falls to zero for every affected algorithm, saving 2,560 K8 clocks.
- States 59/60 (diagonal READ2), 62 (gather READ2 wait), and 63-66 (two
  multiply phases and waits) are cycle-identical to the baseline.
- The complete K8 cycle reduction equals the removed state-61 count exactly.

## Correctness

Final unified run: `logs/sim/v2/ldlt_diag_chain_full_20260811`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K16 SP/CoSaMP skips from the existing expanded-support capacity
  limit;
- no mismatch, timeout, or simulation error lines.

The complete cycle matrix is in
`ldlt_diag_read2_chain_k_sweep_20260811.csv`.

## Cycle results

Total cycles fall from 1,344,523 to 1,336,899: 7,624 cycles saved (0.57%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 166,912 | 166,644 | -268 | -0.16% |
| CoSaMP | 7 | 278,578 | 274,962 | -3,616 | -1.30% |
| IHT | 8 | 125,244 | 125,244 | 0 | 0.00% |
| HTP | 8 | 212,564 | 211,740 | -824 | -0.39% |
| SP | 7 | 231,049 | 228,401 | -2,648 | -1.15% |
| GP | 8 | 125,244 | 125,244 | 0 | 0.00% |
| GOMP | 8 | 95,672 | 95,404 | -268 | -0.28% |
| MP | 8 | 109,260 | 109,260 | 0 | 0.00% |

At M64/N256/K8:

| Algorithm | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| OMP | 34,624 | 34,584 | -40 |
| CoSaMP | 109,512 | 108,200 | -1,312 |
| IHT | 28,633 | 28,633 | 0 |
| HTP | 39,887 | 39,807 | -80 |
| SP | 97,829 | 96,741 | -1,088 |
| GP | 28,633 | 28,633 | 0 |
| GOMP | 19,681 | 19,641 | -40 |
| MP | 25,673 | 25,673 | 0 |

## Timing and resources

Primary OOC run: `logs/synth/v2/ldlt_diag_chain_ooc_20260811`

Independent confirmation: `logs/synth/v2/ldlt_diag_chain_ooc_retry_20260811`
produced the same timing and utilization totals.

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.678 ns | +0.054 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 125,666 | +2,493 |
| Logic LUT | 123,504 | +2,478 |
| FF | 53,417 | -3 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

Timing remains above the preferred +0.2 ns margin.  No BRAM or DSP is added.
The LUT delta is the complete synthesized mapping difference; the RTL change
itself adds only controller address/termination selection and no arithmetic
datapath.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -Cases 1 -ProfileStates `
  -RunId ldlt_diag_chain_k8_smoke_20260811

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId ldlt_diag_chain_full_20260811

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -Top cgra_top -RunId ldlt_diag_chain_ooc_20260811
```

Raw simulation, profile, and synthesis artifacts remain under ignored `logs/`
and `work/` directories.
