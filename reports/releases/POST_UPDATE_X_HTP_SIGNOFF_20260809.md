# Post-update x stream sign-off

Date: 2026-08-09

Baseline: correlation-to-top-K ready/valid checkpoint `752080f`, documented in
`CORR_TOPK_READY_VALID_SIGNOFF_20260809.md`.

## Outcome

The sparse controller can now publish the exact updated `x` block committed by
`S_IHT_MESH_WRITE` directly to the ready/valid exact top-K service. Context bit
29 selects this post-update producer; zero preserves the existing correlation
producer. Context bit 30 retains legacy reduce-x handling of quantized tiny
values.

The optimized HTP program fills shadow support path P1 while `x` is updated,
copies the completed support to P0, then runs prune and refine. This removes K
repeated full-vector reduce/append scans without exposing a partially updated
support to the active algorithm.

The same hardware mode was tested for IHT and GP but is not enabled in their
programs. It changed the selected support in sweep cases 4 and 6 and therefore
failed exact golden correctness. IHT and GP retain their proven legacy
reduce-x sequence. Correctness takes priority over an unproven cycle win.

## Strict PE0 and four-row invariant

Post-update data is not injected into a lower row:

1. The correlation/update transaction enters only PE0.
2. The registered wavefront advances through PE1 and PE2.
3. PE3 produces `row3_wr_data`, the exact block committed to SPM.
4. That committed block is published to the existing serial exact top-K
   service at PE0.
5. Top-K candidate ownership remains `index mod 4`, so all four rows have a
   defined role before PE3 commits the global result.

## Correctness and run isolation

Final full run: `logs/sim/v2/post-update-x-htp-full-signoff`

- 348 PASS / 0 FAIL;
- 62 cycle records;
- all eight cases through K=16;
- 2 expected K=16 skips for SP and CoSaMP because their 2K candidate set
  exceeds the current 24-entry support capacity.

An important test/runtime correction is retained: each algorithm/case now
ends with `REG_CTRL[1]` soft reset, not only `REG_CTRL[2]` clear-error. The old
clear operation preserved SPM scratch and allowed a streamed HTP run to affect
the following SP/GP run. SP and GP passed individually, and both passed in the
sequence after the independent-run soft-reset boundary was applied. The reset
occurs outside the algorithm cycle counter; the next run reloads buffers,
configuration, and program memory. Both bare-metal C runners use the same
boundary.

## Cycle results

The final independently isolated aggregate is 1,633,124 cycles. Per-algorithm
totals are:

| Algorithm | Runs | Cycles |
| --- | ---: | ---: |
| OMP | 8 | 199,256 |
| CoSaMP | 7 | 345,989 |
| IHT | 8 | 163,278 |
| HTP | 8 | 242,078 |
| SP | 7 | 284,337 |
| GP | 8 | 165,358 |
| GOMP | 8 | 111,920 |
| MP | 8 | 120,908 |

HTP changes from 264,491 to 242,078 cycles: 22,413 cycles saved, or 8.47%.
The improvement is concentrated at larger K; K=2 has small fixed-control
overhead.

| Case | M/N/K | Baseline HTP | Stream HTP | Delta |
| ---: | --- | ---: | ---: | ---: |
| 0 | 64/256/16 | 147,022 | 130,613 | -16,409 |
| 1 | 64/256/8 | 50,687 | 47,049 | -3,638 |
| 2 | 64/256/4 | 23,027 | 22,927 | -100 |
| 3 | 32/128/8 | 22,980 | 20,393 | -2,587 |
| 4 | 32/128/4 | 9,186 | 9,151 | -35 |
| 5 | 32/128/2 | 4,780 | 4,995 | +215 |
| 6 | 16/64/4 | 4,575 | 4,567 | -8 |
| 7 | 16/64/2 | 2,234 | 2,383 | +149 |

The complete machine-readable cycle set is in
`post_update_x_htp_k_sweep_20260809.csv`.

## Timing and resources

Final OOC run: `logs/synth/v2/post-update-x-htp-signoff`

| Metric | Result |
| --- | ---: |
| WNS at 100 MHz | +0.417 ns |
| TNS / failing endpoints | 0 / 0 |
| Total LUT | 112,023 |
| FF | 51,159 |
| RAMB36 | 24 |
| DSP48 | 71 |

The result passes both the hard positive-WNS gate and the preferred +0.2 ns
margin.

## Rejected trials

- Directly enabling the stream for IHT failed cases 4 and 6.
- Enabling it for GP reproduced the same case-6 vector divergence.
- Allowing tiny values, preserving support through P1, and adding a
  block-boundary throttle did not restore IHT/GP equivalence.
- A second updated-x hold guard in `S_IHT_MESH_WAIT` passed correctness and
  raised WNS to +0.648 ns, but increased LUT use from 112,023 to 114,358. It
  was removed because the existing `S_CORR_PE_WAIT` already prevents a new
  update from overtaking an unconsumed stream slot.
- Resetting only sparse-engine and PE registers at clear-error did not remove
  cross-program SP/GP contamination and was removed. The correct independent
  program boundary is the existing full core soft reset.

## Recommended next work

1. Profile why one-pass updated-x ordering differs from repeated reduce-x for
   IHT/GP before enabling the mode for those algorithms.
2. Keep SP/CoSaMP on their current path until the residual lane-0 block
   transition has a direct equivalence check.
3. Preserve full K-sweep correctness, strict PE0 ingress, and WNS >= +0.2 ns
   as release gates.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId post-update-x-htp-full-signoff

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow synth -RtlVersion v2 -Top cgra_top `
  -RunId post-update-x-htp-signoff
```

Raw simulation and synthesis artifacts remain under ignored `logs/` and
`work/` directories.
