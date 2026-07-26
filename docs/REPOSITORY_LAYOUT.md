# Repository layout and ownership

## Source of truth

Synthesizable RTL exists only in `rtl/v1` and `rtl/v2`. Vivado-generated
`*.srcs`, `*.runs`, `*.sim`, `.Xil`, and `xsim.dir` directories are disposable
work products and must never be used as the source of truth.

The two RTL versions are deliberately independent. Files that currently have
identical contents are still duplicated so that a future v2 change cannot
silently alter the reproducibility of v1.

## RTL areas

- `control`: sequencers, configuration, CSR/DMA, and sparse-loop control.
- `datapath`: reduction and LFSR data generation.
- `interconnect`: CGRA switchbox.
- `memory`: scalar register file and scratchpad cluster.
- `pe`: PE core, tile, array, and PE services.
- `solver`: least-squares and sparse-kernel services.
- `top`: synthesizable top-level wrappers.

Each version has a `files.f` manifest. Canonical tools must use this manifest
instead of globbing a generated Vivado project directory.

## Generated data

- `work/<flow>/<version>/<run-id>` contains temporary tool state.
- `logs/<flow>/<version>/<run-id>` contains raw logs and run metadata.
- `reports/baselines` and `reports/releases` contain reviewed summaries only.

Large waveforms, checkpoints, bitstreams, XSA files, caches, and raw logs are
not committed. A release artifact that must be preserved should be attached to
a GitHub release together with its commit and manifest.

## Version policy

- v1 is a reproducible architecture snapshot. Behavioral changes require an
  explicit v1 change and a new baseline.
- v2 is the active optimization line.
- Pure layout changes must preserve file contents, algorithm results, cycle
  counts, PE0-to-lower-row data flow, and four-row PE participation.
- A future v3 must be added as another independent directory; it must not
  overwrite v1 or v2.

## Legacy material

One-off historical scripts are retained under `scripts/legacy`. They are kept
for provenance and are not canonical entrypoints. New work must use
`scripts/run.ps1` or a documented script in the active `scripts` subfolders.
