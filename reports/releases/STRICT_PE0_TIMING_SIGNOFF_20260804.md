# Strict PE0 ingress and timing-closure sign-off

Date: 2026-08-04

## Checkpoint

- Branch: `codex/strict-pe0-timing`
- Starting source checkpoint: repository-layout commit `3ed6436`, whose v2
  RTL descends from factor-reuse commit `96305d1`.
- Target: Vivado 2018.1, `xczu7ev-ffvc1156-2-e`, 100 MHz.
- Raw generated work and logs are intentionally ignored. Reproducible compact
  results are recorded in this report and
  `reports/releases/strict_pe0_timing_k_sweep_20260804.csv`.

## Result

This checkpoint closes the P0 architecture gap: large sparse operands enter
the physical array at PE row 0 and advance through registered, tagged row
hops to rows 1, 2, and 3. The full configured regression passes and OOC timing
is positive at 100 MHz.

| Check | Result |
| --- | ---: |
| K-sweep correctness | 348 PASS, 0 FAIL |
| Result records | 62 |
| Expected K16 skips | 2 (CoSaMP and SP need 2K support) |
| WNS | +0.109 ns |
| TNS | 0.000 ns |
| Failing endpoints | 0 |
| Synthesis errors / critical warnings | 0 / 0 |
| Total LUT / logic LUT / LUTRAM | 114728 / 113190 / 1536 |
| FF | 47345 |
| RAMB36 / DSP48 | 24 / 71 |

The final critical path ends at `rhs_reg[10]` with a 9.881 ns data path; it is
no longer on the strict vertical LDLT result path.

## Implemented architecture changes

### Strict four-row provenance

- Correlation, residual, factor comparison, exact top-K traffic, and wide LDLT
  payloads carry valid/owner/tag information through registered PE0 -> PE1 ->
  PE2 -> PE3 links.
- Lower rows select locally registered token-valid state instead of using a
  direct controller opcode as their transaction source.
- Simulation assertions reject residual or LDLT results that retire before
  their required vertical hop history.
- Every physical row has an explicit role: row 0 accepts the transaction;
  rows 1 and 2 process tagged middle stages/lanes; row 3 retires or commits the
  final tagged result.

### Timing pipeline

- The MAC output Q conversion reads the registered accumulator. This removes
  multiply -> saturating 64-bit add -> Q rounding from one timing stage without
  changing observed cycles in the smoke test.
- Residual block-8 processing first registers the eight PE products, then
  reduces them, then commits the 128-bit residual accumulator. This adds one
  cycle per residual block and separates the multiplier from the reduction
  tree.
- The four-row LDLT 64x64 limb engine registers the eight PE products per row
  before shift/reduction. A final commit state separates product capture,
  partial reduction, sign correction, and 128-bit result retirement.
- The earlier wide-result and residual critical paths were removed rather than
  relaxed by changing the clock target.

### Cycle optimization retained

- Correlation/writeback fusion for IHT and GP is present in this source.
- Factor reuse remains collision-safe: signature checks are reject filters and
  exact support checks still authorize reuse.
- QR is not substituted for LDLT. It remains a separate robustness study only.

## Timing progression

| Checkpoint | WNS | Critical area |
| --- | ---: | --- |
| Strict ingress source trial | -2.458 ns | wide LDLT result |
| Wide-result commit pipeline | -1.799 ns | residual accumulator |
| Residual accumulator commit stage | -1.720 ns | lower-row PE MAC |
| Local lower-row token-valid selection | -1.418 ns | lower-row MAC output |
| Registered MAC Q conversion | -0.860 ns | residual block reduction |
| Registered residual products | -0.491 ns | LDLT limb reduction |
| Registered per-row LDLT limb products | **+0.109 ns** | RHS register |

## Configured K-sweep cycles

| M | N | K | OMP | CoSaMP | IHT | HTP | SP | GP | GOMP | MP | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 256 | 16 | 116233 | skip | 105082 | 183978 | skip | 105898 | 63610 | 56689 | 631490 |
| 64 | 256 | 8 | 43955 | 172272 | 45379 | 61029 | 148749 | 45787 | 24748 | 29257 | 571176 |
| 64 | 256 | 4 | 20839 | 56302 | 22486 | 27853 | 39511 | 22690 | 12158 | 15541 | 217380 |
| 32 | 128 | 8 | 18067 | 121081 | 18801 | 28586 | 101191 | 19081 | 10777 | 9769 | 327353 |
| 32 | 128 | 4 | 7831 | 33129 | 9037 | 11644 | 19374 | 9177 | 4920 | 5349 | 100461 |
| 32 | 128 | 2 | 4212 | 8779 | 4785 | 5991 | 6932 | 4855 | 2820 | 3139 | 41513 |
| 16 | 64 | 4 | 3631 | 24413 | 4237 | 5849 | 12386 | 4345 | 2454 | 2173 | 59488 |
| 16 | 64 | 2 | 1888 | 4931 | 2191 | 2853 | 3520 | 2245 | 1363 | 1327 | 20318 |
| **Aggregate** | | | **216656** | **420907** | **211998** | **327783** | **331663** | **214078** | **122850** | **123244** | **1969179** |

Against the factor-reuse layout baseline (1902282 cycles), strict provenance
and timing closure cost 66907 cycles, or 3.52%, while preserving 71 DSP and 24
BRAM36. The retained IHT/GP fusion still reduces their aggregate configured
cycles from 216810/218890 to 211998/214078 respectively.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 -Flow sim -RtlVersion v2 `
  -RunId strict-pe0-widereg-full

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run.ps1 -Flow synth -RtlVersion v2 `
  -Top cgra_top -RunId strict-pe0-widereg-synth
```

Expected raw artifacts:

- `logs/sim/v2/strict-pe0-widereg-full/summary.csv`
- `logs/sim/v2/strict-pe0-widereg-full/case0_all.log` through
  `case7_all.log`
- `logs/synth/v2/strict-pe0-widereg-synth/cgra_top_timing.rpt`
- `logs/synth/v2/strict-pe0-widereg-synth/cgra_top_utilization.rpt`

## Next optimization checkpoints

1. Stream multiple tagged LDLT border transactions before the four-row drain;
   preserve in-order retirement and the new positive timing margin.
2. Chain residual block-8 transactions so product capture for block N+1
   overlaps reduction/commit for block N.
3. Measure and, if useful, extend correlation/update fusion outside the current
   IHT/GP path without weakening PE0 ingress.
4. Reduce exact top-K and factor-check cycles while retaining exact tie-breaks
   and collision-safe support validation.
5. Evaluate QR only as an opt-in robustness mode against ill-conditioned test
   matrices; do not replace the signed-off LDLT path without cycle, resource,
   numerical-error, and WNS evidence.
