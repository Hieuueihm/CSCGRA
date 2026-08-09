# IHT/GP post-update x stream sign-off

Date: 2026-08-09

Baseline: HTP post-update x checkpoint `6734b3c`, documented in
`POST_UPDATE_X_HTP_SIGNOFF_20260809.md`.

## Outcome

IHT and GP now consume the exact post-update `x` stream already used by HTP.
Each program fills shadow support path P1 while `SOP_CORR_UPDATE` commits the
updated vector, copies the complete support to P0, then executes prune and
residual. This removes K repeated full-vector reduce/append scans. GP also
removes an argmax/append pair whose result was immediately discarded by the
following support clear.

The earlier streamed IHT/GP failures were not caused by exact top-K ordering.
At a residual block boundary, the controller asserted the residual mesh
context during ISSUE, every WAIT cycle, and COMMIT. The first token was issued
on the same clock that the new block payload was captured, so PE0 could receive
the previous block. It only corrupted lane 0 of the following block in the
failing trace. The retained fix captures the payload in `S_WR`, emits exactly
one token on the first `S_WR_MESH_WAIT` cycle, and lets that token advance down
the registered PE0 -> PE1 -> PE2 -> PE3 path.

## Four-row and strict-ingress contract

- Updated-x and residual mesh transactions enter only PE0.
- Registered vertical links advance the transaction through PE1 and PE2.
- PE3 produces the committed block; no controller payload is injected into a
  lower row.
- Residual dot-product rank ownership remains striped across the four rows.
- Exact top-K candidate ownership remains `index mod 4`, with PE3 committing
  the global result.

## Correctness

Final run: `logs/sim/v2/post-update-x-iht-gp-full-signoff`

- 348 PASS / 0 FAIL;
- 62 cycle records across cases 0 through 7, including K=2/4/8/16;
- 2 expected K=16 skips for CoSaMP and SP because their 2K candidate set is
  larger than the current 24-entry support capacity;
- repository layout validation PASS.

## Cycle results

Aggregate cycle count is 1,581,856, down from 1,633,124 by 51,268 cycles
(3.14%).

| Algorithm | Runs | Baseline | Final | Delta | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| OMP | 8 | 199,256 | 199,256 | 0 | 0.00% |
| CoSaMP | 7 | 345,989 | 345,989 | 0 | 0.00% |
| IHT | 8 | 163,278 | 138,684 | -24,594 | -15.06% |
| HTP | 8 | 242,078 | 242,078 | 0 | 0.00% |
| SP | 7 | 284,337 | 284,337 | 0 | 0.00% |
| GP | 8 | 165,358 | 138,684 | -26,674 | -16.13% |
| GOMP | 8 | 111,920 | 111,920 | 0 | 0.00% |
| MP | 8 | 120,908 | 120,908 | 0 | 0.00% |

The complete 62-row matrix is in
`post_update_x_iht_gp_k_sweep_20260809.csv`.

## Timing and resources

OOC synthesis: `logs/synth/v2/post-update-x-iht-gp-signoff`

| Metric | Baseline | Final | Delta |
| --- | ---: | ---: | ---: |
| WNS at 100 MHz | +0.417 ns | +0.538 ns | +0.121 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |
| Total LUT | 112,023 | 113,051 | +1,028 (+0.92%) |
| FF | 51,159 | 51,078 | -81 |
| RAMB36 | 24 | 24 | 0 |
| DSP48 | 71 | 71 | 0 |

The design passes the hard positive-WNS gate and the preferred +0.2 ns margin.
The retained trade-off is a 0.92% LUT increase for a 3.14% aggregate cycle
reduction, with improved timing and no BRAM/DSP growth.

## Rejected trials

- Switching HTP K<=2 back to the legacy reduce path was slower: case 5 rose
  from 4,995 to 5,093 cycles and case 7 from 2,383 to 2,451.
- Sorted support insertion was unnecessary after the residual fix and raised
  HTP aggregate cycles from 242,078 to 247,406. It was removed.
- Adding a generic setup cycle after residual commit did not fix lane 0 and
  only added cycle overhead. It was removed.
- QR remains an unimplemented robustness study; LDLT/factor reuse is unchanged.

## Reproduction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow sim -RtlVersion v2 -RunId post-update-x-iht-gp-full-signoff

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1 `
  -Flow synth -RtlVersion v2 -Top cgra_top `
  -RunId post-update-x-iht-gp-signoff
```

Raw simulation and synthesis artifacts remain under ignored `logs/` and
`work/` directories.
