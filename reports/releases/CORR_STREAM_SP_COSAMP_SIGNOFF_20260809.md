# SP/CoSaMP correlation stream sign-off

Date: 2026-08-09

Baseline: IHT/GP post-update x checkpoint `11f65af`, documented in
`POST_UPDATE_X_IHT_GP_SIGNOFF_20260809.md`.

## Outcome

SP and CoSaMP now use the existing lossless correlation-to-exact-top-K stream
for their first candidate-selection phase. SP streams K candidates into shadow
path P1; CoSaMP streams 2K. Both then merge P1 into active support P0 and keep
the proven post-REFINE `reduce_x_support` phase unchanged.

This removes K or 2K repeated full-vector correlation reduce/append scans from
every outer iteration. The change is microprogram-only: synthesizable `rtl/v2`
is byte-identical to the preceding checkpoint.

## Why the previous trial now passes

Earlier SP/CoSaMP stream activation produced the same top-K list and REFINE
inputs as the baseline, but residual lane 0 diverged at the next eight-sample
block. Checkpoint `11f65af` fixed that independent root cause by emitting one
registered residual mesh token after its payload is stable. With the corrected
PE0 transaction boundary, the previously failing M32/N128/K4 SP case and the
sequential SP/CoSaMP -> IHT/GP cases pass exactly.

## Strict PE0 and four-row contract

- Correlation blocks enter only PE0 and advance through the registered PE rows.
- Candidate ownership remains `index mod 4`; all four rows maintain exact local
  top-K contributions and PE3 commits the global result.
- P1 is cleared before stream start, so no partial candidate set is exposed to
  P0 before the top-K service completes.
- Residual keeps the signed-off one-token PE0 -> PE1 -> PE2 -> PE3 behavior.
- No lower PE row accepts controller data directly.

## Correctness

Final run: `logs/sim/v2/sp-cosamp-corr-stream-full-signoff`

- 348 PASS / 0 FAIL;
- 62 cycle records across cases 0 through 7, including K=2/4/8/16;
- 2 expected K=16 skips for SP and CoSaMP because their 2K support requirement
  exceeds the current 24-entry capacity;
- standalone smoke, formerly failing case 4, and sequential case 4/case 7 all
  pass with no state contamination.

## Cycle results

Aggregate cycles fall from 1,581,856 to 1,554,673: 27,183 cycles saved
(1.72%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 199,256 | 199,256 | 0 | 0.00% |
| CoSaMP | 7 | 345,989 | 327,268 | -18,721 | -5.41% |
| IHT | 8 | 138,684 | 138,684 | 0 | 0.00% |
| HTP | 8 | 242,078 | 242,078 | 0 | 0.00% |
| SP | 7 | 284,337 | 275,875 | -8,462 | -2.98% |
| GP | 8 | 138,684 | 138,684 | 0 | 0.00% |
| GOMP | 8 | 111,920 | 111,920 | 0 | 0.00% |
| MP | 8 | 120,908 | 120,908 | 0 | 0.00% |

At M64/N256/K8, CoSaMP falls from 141,900 to 133,908 cycles (-5.63%) and SP
falls from 124,694 to 121,022 (-2.94%). The complete matrix is in
`corr_stream_sp_cosamp_k_sweep_20260809.csv`.

## Timing and resources

`git diff 11f65af -- rtl/v2` is empty. Therefore the signed-off OOC netlist and
its implementation gates remain unchanged:

| Metric | Result |
| --- | ---: |
| WNS at 100 MHz | +0.538 ns |
| TNS / failing endpoints | 0 / 0 |
| Total LUT | 113,051 |
| FF | 51,078 |
| RAMB36 | 24 |
| DSP48 | 71 |

## Recommended next work

Build a support-limited post-REFINE producer for SP/CoSaMP. It should emit only
the merged P0 candidate set (at most 2K for SP and 3K for CoSaMP) into the exact
four-row top-K service, replacing K repeated `reduce_x_support` scans without
scanning the full N-vector. Keep the current legacy post-REFINE phase until that
producer independently passes exact tie-break, full K-sweep, strict PE0, and
WNS >= +0.2 ns gates.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId sp-cosamp-corr-stream-full-signoff
```

Raw simulation artifacts remain under ignored `logs/` and `work/` directories.
