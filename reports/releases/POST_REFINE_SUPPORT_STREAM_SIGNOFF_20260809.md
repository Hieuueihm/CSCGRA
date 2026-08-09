# Support-limited post-REFINE stream sign-off

Date: 2026-08-09

Baseline: SP/CoSaMP correlation-stream checkpoint `f6854e3`, documented in
`CORR_STREAM_SP_COSAMP_SIGNOFF_20260809.md`.

## Outcome

SP and CoSaMP no longer execute K repeated `reduce_x_support` plus candidate
append scans after their first REFINE.  A registered producer observes the
exact dense coefficient commits and publishes only entries in REFINE's cached
merged P0 support to the existing exact top-K service.

The candidate bound is 2K for SP and 3K for CoSaMP at the algorithm level,
clamped by the current 16-entry support/LS capacity.  The implementation does
not rescan all N lanes K times.

## Correctness-preserving details

- Every candidate transaction enters only at PE0.  The existing registered
  PE0 -> PE1 -> PE2 -> PE3 wavefront assigns ownership by `index mod 4`, and
  PE3 commits the exact global top-K result.
- The producer uses `ready/valid`; a dense commit is held when the one-entry
  producer slot is occupied, so no candidate can be dropped or overwritten.
- Candidate data comes from the dense commit indexed by the LDLT controller's
  internal support cache.  This preserves coefficient-to-index mapping when
  factor reuse changes internal support order.
- Top-K results are reordered sequentially by ascending index before P1
  append.  This reproduces the legacy `candidate_append_path_ctx` order and
  avoids fixed-point LDLT drift.  The reorder uses a small multi-cycle scan,
  not a wide combinational sorting network.
- Tiny/zero coefficients remain eligible, matching repeated reduce-x fill and
  tie behavior.

## Correctness

Final run: `logs/sim/v2/post_refine_support_full_retry_20260809`

- 348 PASS / 0 FAIL;
- 62 cycle records across K=2/4/8/16;
- 2 expected K=16 SP/CoSaMP skips caused by the existing expanded-support
  capacity limit;
- SP and CoSaMP smoke tests passed before the full sweep;
- temporary support-order traces were removed from the signed-off source.

## Cycle results

Total cycles fall from 1,554,673 to 1,536,277: 18,396 cycles saved (1.18%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 199,256 | 199,256 | 0 | 0.00% |
| CoSaMP | 7 | 327,268 | 318,322 | -8,946 | -2.73% |
| IHT | 8 | 138,684 | 138,684 | 0 | 0.00% |
| HTP | 8 | 242,078 | 242,078 | 0 | 0.00% |
| SP | 7 | 275,875 | 266,425 | -9,450 | -3.43% |
| GP | 8 | 138,684 | 138,684 | 0 | 0.00% |
| GOMP | 8 | 111,920 | 111,920 | 0 | 0.00% |
| MP | 8 | 120,908 | 120,908 | 0 | 0.00% |

At M64/N256/K8, CoSaMP falls from 133,908 to 129,944 cycles (-2.96%) and SP
falls from 121,022 to 116,981 (-3.34%).  The complete matrix is in
`post_refine_support_stream_k_sweep_20260809.csv`.

## Timing and resources

OOC run: `logs/synth/v2/post_refine_support_ooc_20260809`

| Metric | Result | Delta from baseline |
| --- | ---: | ---: |
| WNS at 100 MHz | +0.129 ns | -0.409 ns |
| TNS / failing endpoints | 0 / 0 | unchanged |
| Total LUT | 115,178 | +2,127 |
| Logic LUT | 113,030 | n/a |
| FF | 51,312 | +234 |
| RAMB36 | 24 | 0 |
| DSP48 | 71 | 0 |

All timing constraints are met.  WNS remains positive, although below the
preferred +0.2 ns engineering margin; further cycle work should first avoid
adding logic to the current LDLT/residual critical cone.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sim\run_regression.ps1 `
  -RtlVersion v2 -RunId post_refine_support_full_retry_20260809

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\synth\run_ooc.ps1 `
  -RtlVersion v2 -RunId post_refine_support_ooc_20260809
```

Raw simulation and synthesis artifacts remain under ignored `logs/` and
`work/` directories; this report and the cycle CSV preserve the sign-off.
