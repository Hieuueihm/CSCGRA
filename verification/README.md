# Verification

- `v1` and `v2` contain the testbenches and golden vectors associated with
  each RTL version.
- `research` contains older diagnostic and per-iteration testbenches.

Canonical K-sweep regression is launched through `scripts/run.ps1`. Compile
file paths are resolved from the repository root; simulation output belongs
under `work/` and `logs/`.
