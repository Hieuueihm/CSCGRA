# Frozen Golden Models for 8 Algorithms

The authoritative executable reference pair lives in `models/reference/`.
This directory does not define a third active reference model. The binding
contract is [`docs/REFERENCE_FLOW.md`](../../docs/REFERENCE_FLOW.md).

Source frozen from the repository's `models/golden` generated set on
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
- `models/reference/canonical.py`: independent floating-point textbook reference.
- canonical_fixed.py: legacy pre-contract signed-24-bit experiment; it is not
  an active generator or RTL sign-off source.
- abstract_rtl.py: legacy phase-level migration experiment built on
  canonical_fixed.py; it is not an active reference or golden.
- run_abstract_rtl.py and abstract_rtl_trace_manifest.json: reproducible
  per-phase digests and exact final-state checks for all cases/algorithms.
- `models/reference/hardware.py`: the only hardware reference source; it owns
  fixed-point, LDLT and quantisation behavior.
- generate_canonical_k_sweep.py: legacy fixed-canonical audit generator; its
  output is optional diagnostic data, not the default sign-off golden.
- canonical_audit.md: latest non-mutating comparison against the RTL-compatible flow.

Hashes:
- golden_cases.vh SHA256: `7D32AC98C5059548EA4CEC1CC892856D43B0F33E9F159951F937D0F4D7265E3E`
- golden_cases_array.vh SHA256: `CFBC7E19246752487B7F9F701211EE6D55CD45969F3F93D34A3BBE6FD5B97FC5`
- generated include hashes are recorded under `generated_sha256` in `manifest.json`.

## Active hardware K-sweep generator

`models/reference/hardware.py` is the sole generator for the active RTL
sign-off include, `verification/v2/run1/k_sweep_golden_hardware.vh`. It reads
only the frozen input data from `golden_cases.vh`; all algorithm, fixed-point,
LDLT, quantisation, factor-reuse, generation, and consistency-check behavior
is implemented in that one Python source.

The `float_vs_fixed` report is a checked-in numerical analysis of the frozen
reference. Older per-iteration simulator runners and their summaries are kept
under `scripts/legacy/v2/legacy_cross_project` as provenance only.

```powershell
python models/reference/hardware.py --check
python models/reference/hardware.py
python models/golden/audit_algorithm_semantics.py --output models/golden/canonical_audit.md
```

For RTL phase bring-up, add `-PhaseTrace` to `scripts/sim/run_regression.ps1`.
It emits controller/PE `PHASE_TOPK` and `PHASE_LS_DONE` records without
changing the normal regression or golden data.

The first command recomputes and verifies the checked-in hardware include
without changing it. The second regenerates it intentionally. The active
hardware golden uses zero tolerance, so every checked coefficient must match
the Python hardware contract bit-for-bit.

Rules:
- Treat these files as read-only golden references.
- The only active reference flow is `models/reference/canonical.py` →
  `models/reference/hardware.py` → generated hardware golden → RTL. Do not
  modify the hardware model merely to hide an RTL failure.
- LDLT, quantisation, fixed-width arithmetic, and hardware factor-cache
  behavior are explicit in `hardware.py`; there is no separate bridge model.
- OMP regression uses slow/reference context flow unless explicitly testing fast mode separately.
- The canonical audit is diagnostic for algorithms not yet migrated.
- `verification/v2/run1/k_sweep_golden_hardware.vh` is the default RTL sign-off
  include. `k_sweep_golden_canonical.vh` is an optional algorithm audit, and
  `k_sweep_golden_mu3.vh` is retained only as a legacy baseline.
