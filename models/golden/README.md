# Frozen Golden Models for 8 Algorithms

Source frozen from the repository's `models/golden` reference set on
2026-06-22. The paths in this README are repository-relative so a fresh clone
does not depend on a developer workstation.

Configuration:
- M = 64
- N = 256
- K = 16
- GOLD_ALGS = 8
- Algorithms / alg_idx:
  - 0: OMP
  - 1: gOMP
  - 2: CoSaMP
  - 3: SP
  - 4: IHT
  - 5: HTP
  - 6: GP
  - 7: MP

Files:
- golden_cases.vh: frozen function-based fixed-point golden for per-iter support/x/residual checks.
- golden_cases_array.vh: frozen array-form companion include.
- canonical_algorithms.py: independent textbook reference used for semantic audits.
- canonical_audit.md: latest non-mutating comparison against the RTL-compatible flow.

Hashes:
- golden_cases.vh SHA256: `7D32AC98C5059548EA4CEC1CC892856D43B0F33E9F159951F937D0F4D7265E3E`
- golden_cases_array.vh SHA256: `CFBC7E19246752487B7F9F701211EE6D55CD45969F3F93D34A3BBE6FD5B97FC5`

## Canonical K-sweep generator

`generate_k_sweep_golden.py` is the reproducible generator for
`verification/v2/run1/k_sweep_golden_mu3.vh`. It reads the frozen reference
from this directory and has no dependency on Vivado workspaces.

The `float_vs_fixed` report is a checked-in numerical analysis of the frozen
reference. Older per-iteration simulator runners and their summaries are kept
under `scripts/legacy/v2/legacy_cross_project` as provenance only.

```powershell
python models/golden/generate_k_sweep_golden.py --check
python models/golden/generate_k_sweep_golden.py
python models/golden/audit_algorithm_semantics.py --output models/golden/canonical_audit.md
```

The first command verifies the checked-in v2 include without changing it. The
second regenerates it intentionally.

Rules:
- Treat these files as read-only golden references.
- RTL/TB must follow this golden; do not regenerate/modify to fit RTL failures.
- OMP regression uses slow/reference context flow unless explicitly testing fast mode separately.
- The canonical audit is diagnostic. A mismatch must be resolved as an explicit
  hardware variant or a corrected algorithm before replacing the active golden.
