# P1.8 CoSaMP Held-out First-Divergence Audit

- Date: `2026-09-07`
- Status: **PASS**
- Candidate: `quality_d22` (`D22F18/S31F23/ACC70`).
- Baseline records: `D:\vivado_pj\reports\v3\optimization_follow_20260907\p1_8\heldout_d22\records.jsonl`.
- Frozen manifest: `D:\vivado_pj\config\v3_p1_heldout_manifest.json`.
- Reproduced failures: `15/15`.

## First divergence

| Stage | Cases | Interpretation |
| --- | ---: | --- |
| `ls_prune` | 6 | restricted refinement changes the K-way prune result |
| `proxy_identify` | 9 | quantized correlation changes the 2K candidate set |

## Cases

| Volume | Block | Phi seed | Stage | Iter | Support | Stop | Rollback | SNR gap dB | MSE ratio |
| --- | --- | ---: | --- | ---: | --- | --- | ---: | ---: | ---: |
| `ms_pd_1mm_pn0_rf0` | `slice112_r176_c72` | 9807629231048985872 | `ls_prune` | 1 | True | `max_iterations` | 0 | 1.222957 | 1.325244 |
| `ms_pd_1mm_pn3_rf20` | `slice112_r160_c168` | 8364576353906475338 | `ls_prune` | 1 | False | `max_iterations` | 0 | 4.950456 | 3.126407 |
| `ms_pd_1mm_pn3_rf20` | `slice112_r184_c168` | 8364576353906475338 | `proxy_identify` | 1 | False | `max_iterations` | 0 | 5.834000 | 3.831775 |
| `ms_pd_1mm_pn3_rf40` | `slice67_r160_c72` | 14361349100168186746 | `proxy_identify` | 2 | True | `max_iterations` | 0 | 0.208211 | 1.049110 |
| `ms_pd_1mm_pn3_rf40` | `slice67_r88_c64` | 8364576353906475338 | `proxy_identify` | 2 | False | `max_iterations` | 0 | 1.684278 | 1.473764 |
| `ms_pd_1mm_pn9_rf40` | `slice112_r64_c128` | 14361349100168186746 | `proxy_identify` | 2 | False | `max_iterations` | 0 | 1.218691 | 1.323942 |
| `ms_t1_1mm_pn3_rf20` | `slice67_r64_c120` | 8364576353906475338 | `proxy_identify` | 4 | False | `max_iterations` | 0 | 0.813874 | 1.206111 |
| `ms_t2_1mm_pn3_rf20` | `slice112_r136_c88` | 14361349100168186746 | `proxy_identify` | 1 | False | `max_iterations` | 0 | 1.012877 | 1.262664 |
| `normal_pd_1mm_pn0_rf20` | `slice67_r168_c136` | 9807629231048985872 | `ls_prune` | 0 | False | `max_iterations` | 0 | 3.865351 | 2.435203 |
| `normal_pd_1mm_pn0_rf20` | `slice67_r176_c184` | 9807629231048985872 | `ls_prune` | 1 | False | `max_iterations` | 0 | 7.950561 | 6.238155 |
| `normal_pd_1mm_pn0_rf40` | `slice112_r152_c136` | 14361349100168186746 | `proxy_identify` | 1 | False | `max_iterations` | 0 | 6.409591 | 4.374809 |
| `normal_pd_1mm_pn3_rf20` | `slice67_r144_c184` | 14361349100168186746 | `proxy_identify` | 2 | False | `max_iterations` | 0 | 0.775240 | 1.195430 |
| `normal_t1_1mm_pn0_rf20` | `slice67_r64_c88` | 8364576353906475338 | `ls_prune` | 1 | False | `solver_max_iterations` | 1 | 15.851678 | 38.474042 |
| `normal_t1_1mm_pn9_rf40` | `slice112_r152_c96` | 9807629231048985872 | `ls_prune` | 1 | False | `max_iterations` | 0 | 0.469913 | 1.114272 |
| `normal_t2_1mm_pn3_rf0` | `slice67_r120_c160` | 9807629231048985872 | `proxy_identify` | 1 | False | `max_iterations` | 0 | 3.766283 | 2.380281 |

## Interpretation

- This is a diagnostic replay only; it does not change thresholds, frozen blocks, Phi seeds or numeric profiles.
- The full phase trace is stored per case under `traces/`; source and block hashes are checked before every replay.
- D22 remains inactive. No RTL/model closure, synthesis, timing or PPA claim is made.

## Reproduction

```text
py -3 scripts/numeric/v3_cosamp_failure_audit.py --records reports/v3/optimization_follow_20260907/p1_8/heldout_d22/records.jsonl --manifest config/v3_p1_heldout_manifest.json --out-dir reports/v3/optimization_follow_20260907/p1_8/cosamp_failure_audit
```
