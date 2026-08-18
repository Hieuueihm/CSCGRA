# Verification

- `v2` contains the active testbenches and golden vectors for the public/paper
  flow.
- Archived v1 and research benches are under `archive/` and are not canonical.

Canonical K-sweep regression is launched through `scripts/run.ps1`. Compile
file paths are resolved from the repository root; simulation output belongs
under `work/` and `logs/`.

See `verification/v2/README.md` for the current eight-case matrix, expected
K16 skips, profiling coverage, and golden-data rules.
