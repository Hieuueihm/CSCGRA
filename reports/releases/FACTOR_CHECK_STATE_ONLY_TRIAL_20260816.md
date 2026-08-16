# Factor-check state-only trial report

Date: 2026-08-16

Baseline: documentation checkpoint `44437f7`, with RTL behavior identical to
the signed-off `d487050` checkpoint.

## Trial

The trial bypassed `S_FACTOR_CHECK_DONE` only when reuse was already impossible
in `S_FACTOR_CHECK_INIT` because:

- the cached sensing configuration did not match;
- the requested support was smaller than the cached factor; or
- the effective request was empty.

The possible-reuse path was deliberately unchanged.  Request tokens still
entered only PE0, propagated through PE0 -> PE1 -> PE2 -> PE3, and returned
through the existing `factor_pipe_resp_valid` path.  The response seen-mask,
ordered-match, fingerprint, `SCAN -> DONE` transition, and exact/prefix reuse
decisions were not modified.

## Result

| Metric | Baseline | State-only trial | Delta |
| --- | ---: | ---: | ---: |
| K8 correctness | 45 PASS / 0 FAIL | 45 PASS / 0 FAIL | unchanged |
| K8 total cycles | 379662 | 379642 | -20 (-0.0053%) |
| Total LUT | 123551 | 125698 | +2147 (+1.74%) |
| Logic LUT | 121387 | 123552 | +2165 |
| FF | 53423 | 53411 | -12 |
| RAMB36 | 24 | 24 | 0 |
| DSP48 | 71 | 71 | 0 |
| WNS | +0.605 ns | +0.648 ns | +0.043 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 | unchanged |

Per-algorithm K8 cycle changes were OMP -1, CoSaMP -9, HTP -1, SP -8, and
GOMP -1.  IHT, GP, and MP do not use this factor-check path and were unchanged.
The 20 saved clocks exactly match known-miss DONE-state residency, so there is
no larger hidden gain available from this state-only bypass.

The trial is rejected.  A 1.74% LUT increase is not justified by a 0.0053%
K8 cycle reduction, even though timing remains positive.  RTL was restored to
the baseline after measurement.

## Reproduction artifacts

- Profile/smoke: `logs/sim/v2/factor_init_known_miss_k8_20260816`
- OOC synthesis: `logs/synth/v2/factor_init_known_miss_ooc_20260816`

Raw simulation and synthesis output remains ignored under `logs/` and `work/`.

## Decision

Do not optimize factor-check by bypassing INIT/DONE or by adding next-response
seen-mask/fingerprint logic.  Together with the rejected solve-setup trials,
the remaining controller bubbles in these two regions are now measured and do
not offer a resource-neutral cycle win.
