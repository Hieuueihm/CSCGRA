# CoSaMP Numeric Policy Candidate Experiment

- Date: `2026-09-07`
- Candidate: `cosamp_data_d27_shift18_r32`.
- Scope: frozen 15 failures plus 15 passing controls.
- This is a software-model experiment; D22 RTL remains inactive.

## Policy

- Data/residual path: `D27/F23` instead of `D22/F18`.
- Solver: `S31/F23`; accumulator: `ACC70`.
- Strict certificate residual shift: `18`; reliable recompute interval: `32`.
- Iteration budget, rounding, saturation, raw-proxy ranking and lowest-index tie break are unchanged.

## Result

| Set | Quality pass | Exact support | Rollbacks | Numeric events | Max SNR gap | Max MSE ratio | Max SSIM drop |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `Failures` | 15/15 | 15/15 | 0 | 0 | 0.002354 | 1.000542 | 0.000022 |
| `Controls` | 15/15 | 15/15 | 0 | 0 | 0.000415 | 1.000096 | 0.000006 |

## Decision

- Diagnostic improvement only; not promoted to RTL.
- Required failure-set gate is `15/15`; this candidate does not close it.
- Full `3888` sweep, candidate golden regeneration and RTL implementation are deferred.
- D22 remains inactive.

## Reproduction

```text
py -3 scripts/numeric/v3_cosamp_policy_candidate_experiment.py --records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl --manifest config/v3_p1_heldout_manifest.json --controls 15 --out-dir reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_d27_r32
```
