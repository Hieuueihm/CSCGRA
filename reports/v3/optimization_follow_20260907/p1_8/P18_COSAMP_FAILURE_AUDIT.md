# P1.8 CoSaMP Failure Audit

- Date: `2026-09-07`
- Status: **DIAGNOSTIC PASS / QUALITY GATE OPEN**
- Candidate: `quality_d22` (`D22F18/S31F23/ACC70`)
- Frozen manifest: `config/v3_p1_heldout_manifest.json`
- Baseline sweep: `3888` evaluations; `15` failing CoSaMP evaluations.

## Reproduction

The provenance-bound audit reproduces all baseline failures before classifying
the first semantic divergence:

- `9/15` begin at `PROXY -> IDENTIFY` because quantized residual/correlation
  changes the ordered `2K` candidate list.
- `6/15` begin at `LS -> PRUNE` because the restricted-refinement estimate
  changes the K-way prune result.
- No failure has a numeric event (`acc_overflow`, saturation, divide-by-zero or
  refinement breakdown) in the baseline D22 run.
- One case reaches `solver_max_iterations` and records one explicit rollback;
  it is not treated as convergence.

The complete per-case phase traces, source hashes and block hashes are stored
under `cosamp_failure_audit/traces/`. The machine-readable result is
`cosamp_failure_audit/results.json`.

## Candidate screen

The existing candidate profiles were screened on the same `15` frozen failure
cases. No new profile, threshold, geometry, block, seed or tolerance was used.

| Candidate | Result on failure set | Support exact | Max SNR gap | Max MSE ratio | Max SSIM drop |
| --- | ---: | ---: | ---: | ---: | ---: |
| `production` | `7/15` | `7/15` | `9.498304 dB` | `8.909030` | `0.679828` |
| `quality_f17` | `7/15` | `7/15` | `7.860058 dB` | `6.109502` | `0.414785` |
| `quality_f17_floor2` | `2/15` | `2/15` | `15.851534 dB` | `38.472762` | `0.422927` |
| `quality_f17_floor4` | `9/15` | `9/15` | `15.851932 dB` | `38.476290` | `0.422974` |
| `quality_f17_s23` | `5/15` | `5/15` | `15.851591 dB` | `38.473273` | `0.422951` |
| `quality_d22` | `0/15` | `0/15` | `15.851678 dB` | `38.474042` | `0.422898` |

Increasing only the refinement iteration budget to `256`, `512` or `1024`
improves only `1/15` cases; `14/15` remain failing. The failures are therefore
not closed by a larger solver budget.

## Decision

- The audit infrastructure is PASS: `15/15` failures reproduce and are
  classified without mutating production contracts.
- The held-out quality gate remains OPEN at `3873/3888`; D22 is not eligible
  for activation.
- Do not select an existing profile as a release candidate. None closes the
  failure set, and increasing iterations is ineffective.
- The next engineering task is a separately named CoSaMP numerical-policy
  candidate, with an explicit hardware-realizable rule for residual/correlation
  precision and a new candidate golden. It must first pass this `15`-case
  screen, then the complete frozen `3888` sweep, and finally RTL/model
  bit-exact closure.

## Policy candidate experiment

- Candidate `cosamp_data_d27_shift18_r32` was evaluated in an isolated software
  harness without changing the production model, golden files or RTL.
- The candidate uses `D27/F23` data/residual arithmetic, `S31/F23` solver,
  `ACC70`, strict certificate shift `18`, reliable recompute interval `32`,
  the existing bounded `128`-step refinement budget, signed saturation and
  lowest-index tie breaking.
- Result on the frozen failure set: `15/15` quality pass and `15/15` exact
  support, with zero numeric events and zero rollback. Result on `15/15`
  passing controls: `15/15` quality pass and `15/15` exact support.
- The complete frozen matrix is also closed for quality: `3888/3888` pass,
  zero numeric events and zero rollback. CoSaMP is `486/486` quality and exact
  support. Global exact support is `3883/3888` because five known non-CoSaMP
  baseline cases remain support-mismatched; those algorithms were unchanged.
- The numerical quality gate is closed for this CoSaMP candidate. Candidate
  golden regeneration, model closure and then RTL closure may proceed; D22
  remains inactive until those later gates pass.
- Reproduction script:
  `scripts/numeric/v3_cosamp_policy_candidate_experiment.py`; evidence:
  `cosamp_policy_candidate_d27_r32/` and
  `cosamp_policy_candidate_full_v2/`.

## Evidence

- Candidate golden audit: `P18_CANDIDATE_GOLDEN_AUDIT.md`
- Held-out baseline: `heldout_d22/summary.md`
- First-divergence audit: `cosamp_failure_audit/summary.md`
- Existing-profile screen: `candidate_profile_screen/summary.md`
- Full plan: `docs/v3/27_RTL_V3_OPTIMIZATION_FOLLOW_PLAN.md`
