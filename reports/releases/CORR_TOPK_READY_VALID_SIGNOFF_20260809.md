# Correlation-to-top-K ready/valid sign-off

Date: 2026-08-09

Baseline: streaming exact top-K checkpoint `b274f51`, documented in
`STREAM_TOPK_OMP_GOMP_SIGNOFF_20260807.md`.

## Outcome

The correlation producer and serial exact top-K consumer now have an explicit
ready/valid contract.

- A completed correlation block remains in the registered producer slot until
  the top-K service accepts it.
- Correlation stalls before overwriting an occupied slot when the consumer is
  not ready.
- Backpressure is active only for a pending streaming-select context; ordinary
  correlation uops do not acquire a new dependency on the top-K service.
- The existing fast path has no added cycle when the consumer is ready.

The 192-bit correlation data register is not conditionally gated. Only the
valid/done control bits are qualified by the active stream context. This avoids
the larger LUT increase measured in the rejected wide-bus gating trial.

## Strict ingress and four-row PE invariant

The change preserves the existing physical dataflow:

1. Correlation data is produced and registered at the controller/PE0 boundary.
2. The top-K consumer serializes each eight-lane block only at PE0.
3. Candidate tokens travel through registered PE0 -> PE1 -> PE2 -> PE3 hops.
4. Rows own candidate classes by `index mod 4`; all four rows participate.
5. PE3 commits the exact global top-K result.

No lower PE row receives an independent controller ingress.

## Correctness and cycle sign-off

Final full run: `logs/sim/v2/corr-topk-ready-valid-compact-full`

- 348 PASS / 0 FAIL;
- 62 valid cycle records;
- 2 expected K16 skips for SP and CoSaMP 2K candidate capacity;
- all eight sweep cases exercised through K=16.

The aggregate remains 1,647,780 cycles, byte-for-byte equal to the cycle
checkpoint. Per-algorithm totals are unchanged:

| Algorithm | Cycles |
| --- | ---: |
| OMP | 199,256 |
| CoSaMP | 345,626 |
| IHT | 163,278 |
| HTP | 264,491 |
| SP | 276,931 |
| GP | 165,358 |
| GOMP | 111,932 |
| MP | 120,908 |

## Timing and resources

Final OOC run: `logs/synth/v2/corr-topk-ready-valid-compact`

| Metric | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| WNS at 100 MHz | +0.325 ns | +0.621 ns | +0.296 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | 0 |
| Total LUT | 112,516 | 113,933 | +1,417 (+1.26%) |
| FF | 51,122 | 50,915 | -207 |
| RAMB36 | 24 | 24 | 0 |
| DSP48 | 71 | 71 | 0 |

The result passes the hard positive-WNS gate and the preferred +0.2 ns margin.
The LUT cost buys a lossless producer/consumer boundary without changing any
algorithm cycle total.

## SP activation trial

SP streaming was retried with the handshake at M32/N128/K4. It was not retained.

- The first streamed top-K list exactly matched the baseline: 94, 104, 30, 74.
- The support presented to both REFINE requests was identical to the baseline.
- The first REFINE coefficients were also identical.
- Residual block comparison then showed divergence in lane 0 after the first
  eight-sample block; the next correlation therefore selected different
  candidates and failed five exact-golden samples.
- Adding a four-cycle completion guard did not change the failure and was
  removed.

This proves the remaining SP issue is not dropped correlation transactions or
top-K ordering. It is a residual/mesh boundary state issue exposed when the
legacy reduce sequence is removed. SP and CoSaMP therefore remain on their
proven reduce/append programs.

## Rejected implementation trials

- Gating the complete correlation stream register by `stream_active` raised
  total LUT use to 115,197 and was rejected.
- Preserving idle one-cycle stream pulses while adding hold behavior raised
  total LUT use to 114,969 and was rejected.
- The retained control-only gating result uses 113,933 LUT and has the best
  resource/timing balance of the tested lossless-handshake variants.

## Recommended next work

1. Build the post-update `x` stream for IHT/HTP/GP, with PE0-only ingress and
   modulo-4 ownership across all four rows.
2. Before re-enabling SP/CoSaMP streaming, isolate the residual mesh lane-0
   block-transition state and add a direct residual-block equivalence check.
3. Keep WNS >= +0.2 ns and the complete K-sweep as mandatory release gates.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId corr-topk-ready-valid-compact-full

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow synth -RtlVersion v2 -Top cgra_top `
  -RunId corr-topk-ready-valid-compact
```

Raw simulation and synthesis artifacts remain under ignored `logs/` and
`work/` directories.
