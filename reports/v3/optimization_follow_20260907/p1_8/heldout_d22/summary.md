# V3 D22 Held-out Candidate Sweep

- Date: `2026-09-07`
- Result: **FAIL**
- Candidate: `quality_d22` (`D22F18/S31F23/ACC70`).
- Frozen manifest: `config\v3_p1_heldout_manifest.json`.
- Coverage: `162` blocks × `3` Phi seeds × `8` algorithms = `3888` evaluations.
- Scope: held-out BrainWeb source-domain 8x8 blocks with the V3 real Bernoulli operator; this is not raw-k-space RTL or clinical validation.

## Gate

| Metric | Result |
| --- | ---: |
| Evaluations | `3873/3888` |
| Exact support | `3861/3888` |
| Rollbacks | `1` |
| Numeric events | `0` |
| Worst SNR loss | `15.851678 dB` |
| Worst MSE ratio | `38.474042` |
| Worst NMSE ratio | `38.474042` |
| Worst SSIM drop | `0.422898` |

## By Algorithm

| Algorithm | Passed | Support | Rollback | Max SNR loss | Max MSE ratio | Max SSIM drop |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `OMP` | 486/486 | 486/486 | 0 | 0.011211 | 1.002585 | 0.000147 |
| `CoSaMP` | 471/486 | 464/486 | 1 | 15.851678 | 38.474042 | 0.422898 |
| `IHT` | 486/486 | 486/486 | 0 | 0.000188 | 1.000043 | 0.000012 |
| `HTP` | 486/486 | 486/486 | 0 | 0.004003 | 1.000922 | 0.000154 |
| `SP` | 486/486 | 485/486 | 0 | 0.010349 | 1.002386 | 0.000830 |
| `GP` | 486/486 | 485/486 | 0 | 0.008073 | 1.001861 | 0.000120 |
| `GOMP` | 486/486 | 483/486 | 0 | 0.108090 | 1.025201 | 0.000866 |
| `MP` | 486/486 | 486/486 | 0 | 0.014990 | 1.003457 | 0.000173 |

## Thresholds

- SNR loss <= `0.500 dB`.
- MSE ratio <= `1.100`; NMSE ratio <= `1.100`.
- SSIM drop <= `0.005`.
- Numeric events and refinement rollbacks must both be zero.

## Non-claims

- A PASS here closes candidate fixed-point held-out quality only; it does not close candidate end-to-end RTL/model bit-exact behavior.
- D22 remains inactive in production `rtl/v3/files.f`; synthesis, timing, LUT/FF/BRAM/DSP and 100 MHz claims are not made.

## Reproduction

```text
py -3 scripts/numeric/v3_freeze_heldout_manifest.py check
py -3 scripts/numeric/v3_candidate_heldout_sweep.py --numeric-candidate quality_d22 --workers 8 --out-dir reports/v3/optimization_follow_20260907/p1_8/heldout_d22
```
