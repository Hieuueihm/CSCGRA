# Automation scripts

## Canonical entrypoints

- `run.ps1`: public wrapper for simulation and OOC synthesis.
- `sim/run_regression.ps1`: compiles once, runs selected K-sweep cases and
  algorithms, rejects known failure patterns, and writes metadata/summary.
- `synth/run_ooc.ps1` and `synth/run_ooc.tcl`: 100 MHz OOC synthesis,
  utilization, and timing reporting.
- `maintenance/check_layout.ps1`: repository layout checks.
- `python models/reference/hardware.py --check`: recomputes and verifies the
  active bit-exact v2 hardware sign-off golden.
- `python models/reference/hardware.py --check --c-output sw/v2/src/cscgra_k_sweep_golden.h`:
  verifies the matching SoC C header.
- `python models/golden/generate_canonical_k_sweep.py --check`: verifies the
  independent capacity-unlimited textbook reference.
- `maintenance/compare_regression.ps1`: compares measured regression records.
- `maintenance/audit_rtl.py`: RTL/source audit helper.

Examples:

```powershell
.\scripts\run.ps1 -Flow sim -RtlVersion v2 -RunId full
.\scripts\run.ps1 -Flow sim -RtlVersion v2 -Cases 1 -ProfileStates -RunId k8-profile
.\scripts\run.ps1 -Flow synth -RtlVersion v2 -Top cgra_top -RunId ooc
```

## Legacy archive

`legacy/v1` and `legacy/v2` preserve one-off experiments, old generated-project
paths, exporters, and debug scripts. They are provenance only. New automation
must not depend on a local `CSCGRA_opt_architecture*` workspace.
