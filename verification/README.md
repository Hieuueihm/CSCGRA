# Verification

- `v2` contains the active testbenches and golden vectors for the public/paper
  flow. `v1` is retained only as a historical matching snapshot.
- `research` contains older diagnostic and per-iteration testbenches.

Canonical K-sweep regression is launched through `scripts/run.ps1`. Compile
file paths are resolved from the repository root; simulation output belongs
under `work/` and `logs/`.

See `verification/v2/README.md` for the current eight-case matrix, expected
K16 skips, profiling coverage, and golden-data rules.
