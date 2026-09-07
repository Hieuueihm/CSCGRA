# CoSaMP Policy Candidate Frozen Full Sweep

- Date: `2026-09-07`
- Quality result: **PASS**.
- Candidate closure result: **PASS**.
- Candidate: `cosamp_data_d27_shift18_r32`.
- Frozen coverage: `162` blocks × `3` Phi seeds × `8` algorithms = `3888` evaluations.
- Only CoSaMP uses the new policy; seven other algorithms use the unchanged quality_d22 baseline records.
- Global exact-support count is reported separately because five known non-CoSaMP baseline cases remain support-mismatched.
- D22 RTL remains inactive; this is software-model evidence only.

## Gate

| Scope | Pass | Support | Rollbacks | Numeric events | Max SNR gap | Max MSE ratio | Max SSIM drop |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `All 8 algorithms` | 3888/3888 | 3883/3888 | 0 | 0 | 0.108090 | 1.025201 | 0.000866 |
| `CoSaMP candidate` | 486/486 | 486/486 | 0 | 0 | 0.002354 | 1.000542 | 0.000095 |
| `Other algorithms baseline` | 3402/3402 | 3397/3402 | 0 | 0 | 0.108090 | 1.025201 | 0.000866 |

## Decision

- The candidate is eligible for the next candidate-golden/model closure step only if the aggregate gate is PASS.
- No production model, golden, RTL file or D22 activation is changed by this sweep.

## Reproduction

```text
py -3 scripts/numeric/v3_cosamp_policy_candidate_full_sweep.py --records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl --manifest config/v3_p1_heldout_manifest.json --out-dir reports/v3/optimization_follow_20260907/p1_8/cosamp_policy_candidate_full
```
