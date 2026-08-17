# Synthesis scripts

- `run_ooc.ps1`: PowerShell entrypoint for out-of-context synthesis.
- `run_ooc.tcl`: Vivado implementation of the OOC flow.

Normally invoke these through `scripts/run.ps1 -Flow synth`. Generated Vivado
state belongs under `work/`; raw reports belong under `logs/`; reviewed metrics
belong under `reports/releases/`.
