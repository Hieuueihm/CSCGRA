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
  - 1: CoSaMP
  - 2: IHT
  - 3: HTP
  - 4: SP
  - 5: GP
  - 6: gOMP
  - 7: MP

Files:
- golden_cases.vh: frozen function-based fixed-point golden for per-iter support/x/residual checks.
- golden_cases_array.vh: frozen array-form companion include.
- canonical_algorithms.py: independent floating-point textbook reference.
- canonical_fixed.py: independent signed-24-bit Q16 contract used by all
  canonical algorithms.
- abstract_rtl.py: phase-level executable RTL/controller model built on the
  frozen fixed contract; it is the migration intermediate, not a new golden.
- run_abstract_rtl.py and abstract_rtl_trace_manifest.json: reproducible
  per-phase digests and exact final-state checks for all cases/algorithms.
- hardware_fixed.py: independent hardware-aware fixed contract for LDLT,
  Q16/Q32 boundaries, regularisation and signed-24 quantisation.
- hardware_abstract.py and run_hardware_abstract.py: CoSaMP phase trace for
  the hardware LDLT contract; K16 entries are architectural traces, not RTL
  sign-off.
- HARDWARE_CONTRACT.md: boundary between algorithmic canonical and
  hardware-aware RTL contracts.
- generate_canonical_k_sweep.py: generates the canonical include without importing
  the RTL-compatible golden generator.
- canonical_audit.md: latest non-mutating comparison against the RTL-compatible flow.

Hashes:
- golden_cases.vh SHA256: `7D32AC98C5059548EA4CEC1CC892856D43B0F33E9F159951F937D0F4D7265E3E`
- golden_cases_array.vh SHA256: `CFBC7E19246752487B7F9F701211EE6D55CD45969F3F93D34A3BBE6FD5B97FC5`
- generated include hashes are recorded under `generated_sha256` in `manifest.json`.

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
python models/golden/generate_canonical_k_sweep.py --check
python models/golden/generate_canonical_k_sweep.py
python models/golden/audit_algorithm_semantics.py --output models/golden/canonical_audit.md
```

For RTL phase bring-up, add `-PhaseTrace` to `scripts/sim/run_regression.ps1`.
It emits controller/PE `PHASE_TOPK` and `PHASE_LS_DONE` records without
changing the normal regression or golden data.

The first command verifies the checked-in v2 include without changing it. The
second regenerates it intentionally.

Rules:
- Treat these files as read-only golden references.
- Canonical flow is algorithm → `canonical_fixed.py` → generated golden → RTL.
  Do not regenerate/modify the golden to fit RTL failures.
- Migration flow is canonical → `abstract_rtl.py` → phase trace comparison →
  real RTL. The abstract model must remain exact before RTL changes begin.
- Hardware-aware migration is canonical phase intent → `hardware_fixed.py` →
  `hardware_abstract.py` → RTL phase trace. LDLT and quantisation are explicit
  here; they are not hidden by changing the canonical golden.
- OMP regression uses slow/reference context flow unless explicitly testing fast mode separately.
- The canonical audit is diagnostic for algorithms not yet migrated.
- `verification/v2/run1/k_sweep_golden_canonical.vh` is the canonical reference
  for GP. `k_sweep_golden_mu3.vh` is retained only as a legacy baseline for the
  remaining un-migrated algorithms.
