# Certified screening correlation: measured rejection (Stage 0)

Date: 2026-08-22. Decision: **NO-GO** — the certified bound prunes zero
columns on every case/algorithm of the canonical sweep.

## Idea

Cache the correlation vector c (already materialized in SPM 0x180).  After
each solve, coefficients change by delta, so
`|c_new[k] - c_cached[k]| <= ||delta|| * Gmax` with
`Gmax = M*scale^2 >> 16` the deterministic Rademacher upper bound on any
Gram entry.  A column can be skipped in the argmax scan when
`|c_cached[k]| + 2B < max_cached`.  If the rule never prunes a potential
winner the selection equals full OMP (golden unchanged).

Earlier analysis of the same idea in "incremental correlation" form also
showed the Gram-column-cache variant is cycle-neutral here, because Phi is
regenerated from the LFSR rather than stored: building one full Gram column
costs the same N*M generation+MAC pass as a correlation rescan.

## Measurement

Simulated every iteration of OMP and GOMP on all 8 canonical cases with the
real frozen inputs, tracking D1 = ||delta||_1 and D2 = ||delta||_2, both
bound variants, and the surviving-candidate count:

| Case | OMP reduction | GOMP reduction | Candidates each iteration |
|---|---:|---:|---|
| all 8 cases | 0.0% | 0.0% | N (no column pruned, ever) |

Numbers behind the failure (M=64, scale 0x4000): `Gmax = 2^18`,
`2*B2 = 2*||delta||_2*Gmax >> 16 ~= 2^20.4`, while `max_cached ~= 2^19.5`.
The certified threshold sits 2-4x above the top correlation value, so even
tail columns cannot be pruned.  Tighter uniform bounds do not exist for
Rademacher Phi (the M*scale^2 bound is attained on the diagonal), and
per-column bounds require the very Gram columns that are cycle-neutral to
build.

## Consequence

- Screening-based correlation acceleration is rejected by data, not by
  preference; this note is the provenance record.
- The next RTL-facing optimization candidates are correlation datapath
  widening (mechanical, timing risk) and the support-column scan mask
  (trivial, ~K/N).
- The session pivots to the phase-ISA tooling track (compiler + cost
  model), which needs no golden or datapath change.

## Addendum: support-column scan mask — rejected by analysis (same day)

The companion micro-idea (skip the K support columns in the correlation
scan, since selection excludes them) is **cycle-void** in the current
structure and was not implemented:

- `S_CORR_ACC` issues exactly `n_size/COLS` column words per measurement
  row; scan time is bound by the word walk, not by the MACs.  Masking
  individual lanes saves switching, not clocks, and support atoms are
  scattered so no fully-masked word exists at K<=16.
- Compacting the walk to candidate-only words requires per-lane
  variable-offset LFSR advance (`lfsr_advance(row_state, j+1)` with
  data-dependent j), a combinational chain the controller timing cone
  cannot absorb — the same class of change as the previously rejected
  scan fast-start forms.
- Scope is narrower than it looks anyway: CoSaMP/SP candidate top-K
  (exclude_support=0), IHT/HTP gradient updates (every c value consumed),
  and MP re-selection all read support-column correlations.  Only
  OMP/GOMP/GP could mask.

Remaining correlation-cycle lever: datapath widening (16 columns/clock),
a measured trial with explicit timing-risk gating.

Study script: ad-hoc harness over `models/reference/hardware.py`
(`_corr`/`_ldlt_solve` reuse, frozen inputs, both norm variants).
