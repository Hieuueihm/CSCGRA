# P1.8 CoSaMP Candidate Profile Screen

- Date: `2026-09-07`
- Scope: `failures` on the frozen manifest.
- Candidate count: `6`.
- Candidate-independent input: **True**.

## Results

| Candidate | Profile | Pass | Support | Rollback | Max SNR gap dB | Max MSE ratio | Max SSIM drop |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `production` | `D18F14/S27F19/ACC62` | **FAIL** | 7/15 | 0 | 9.498304 | 8.909030 | 0.679828 |
| `quality_f17` | `D18F17/S27F22/ACC62` | **FAIL** | 7/15 | 0 | 7.860058 | 6.109502 | 0.414785 |
| `quality_f17_floor2` | `D18F17/S27F22/ACC62` | **FAIL** | 2/15 | 1 | 15.851534 | 38.472762 | 0.422927 |
| `quality_f17_floor4` | `D18F17/S27F22/ACC62` | **FAIL** | 9/15 | 1 | 15.851932 | 38.476290 | 0.422974 |
| `quality_f17_s23` | `D18F17/S27F23/ACC62` | **FAIL** | 5/15 | 1 | 15.851591 | 38.473273 | 0.422951 |
| `quality_d22` | `D22F18/S31F23/ACC70` | **FAIL** | 0/15 | 1 | 15.851678 | 38.474042 | 0.422898 |

## Contract

- Candidates are the existing entries in `models/v3/numerical_candidate.py`; no new profile or threshold is introduced.
- All evaluations use the frozen blocks, Phi seeds and source hashes from `config/v3_p1_heldout_manifest.json`.
- This is a diagnostic screen. It does not activate D22 or modify production RTL/goldens.

## Reproduction

```text
py -3 scripts/numeric/v3_candidate_profile_sweep.py --records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl --manifest config/v3_p1_heldout_manifest.json --scope failures --out-dir reports/v3/optimization_follow_20260907/p1_8/candidate_profile_screen
```
