# Synthesis scripts

- `run_ooc.ps1`: PowerShell entrypoint for out-of-context synthesis.
- `run_ooc.tcl`: Vivado implementation of the OOC flow.

Implementation is available through `scripts/run.ps1 -Flow impl`; it runs
OOC synthesis, optimization, placement, physical optimization, routing, DRC,
and writes utilization/timing/checkpoint reports under `logs/impl/`.

Normally invoke these through `scripts/run.ps1 -Flow synth`. Generated Vivado
state belongs under `work/`; raw reports belong under `logs/`; reviewed metrics
belong under `reports/releases/`.
