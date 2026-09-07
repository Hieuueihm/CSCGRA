# V3 M13 Vivado Flow

`run_v3_m13_flow.ps1` is the reusable 100 MHz OOC synthesis and implementation
entry point for `m13_compute_lifecycle_integration` on
`xczu7ev-ffvc1156-2-e`.

The flow uses `C:\vivado_scratch\v3_m13` for Vivado working data so `.Xil`,
checkpoints, and temporary databases do not consume the repository drive.
Reviewed reports and metadata are published under
`reports/v3/m13_vivado/managed_flow/<RunTag>`.

## Normal Use

Preflight only:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/impl/run_v3_m13_flow.ps1 `
  -Stage Preflight -RunTag preflight_20260905
```

Synthesize, optimize, place, and route:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/impl/run_v3_m13_flow.ps1 `
  -Stage All -RunTag m13_100mhz_20260905
```

Resume from the newest checkpoint after an interruption:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/impl/run_v3_m13_flow.ps1 `
  -Stage All -RunTag m13_100mhz_20260905 -Resume
```

Regenerate reports without rerunning implementation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/impl/run_v3_m13_flow.ps1 `
  -Stage ReportOnly -RunTag m13_100mhz_20260905 -Resume
```

Monitor a running stage from another PowerShell window:

```powershell
Get-Content C:\vivado_scratch\v3_m13\m13_100mhz_20260905\flow_status.txt
Get-Content C:\vivado_scratch\v3_m13\m13_100mhz_20260905\vivado_console.log `
  -Tail 40 -Wait
```

## Safety and Sign-Off

- The default correctness gate requires two exact `24/24 PASS` matrices and
  rejects evidence older than any RTL source. `-SkipCorrectnessGate` is only
  for exploratory synthesis and must not be used for sign-off.
- Default free-space gates are 20 GB for scratch and 0.5 GB for reports. The
  report-drive minimum rises to 2 GB when `-PublishCheckpoints` is selected.
- Existing Vivado/XSim processes and duplicate run tags are rejected by default.
- A timeout stops only the exact launched process tree and retains scratch for
  diagnosis and resume. The default timeout is 180 minutes and can be changed
  with `-TimeoutMinutes`.
- Scratch cleanup is opt-in with `-CleanScratchOnSuccess` and is restricted to
  the resolved configured scratch root.
- Checkpoints remain on `C:` by default for resume. Use `-PublishCheckpoints`
  only when the report drive has at least 2 GB free.
- Checkpoints are written immediately after synthesis, optimization, placement,
  and routing. No synthesis, optimization, placement, or routing directives are
  used.
- Routed PASS requires setup WNS at least `+0.200 ns` and hold WHS at least
  `0.000 ns`. Utilization, hierarchical utilization, setup/hold timing, DRC,
  PDRC, methodology, clock, route-status, and `check_timing` reports are emitted
  before whole-design closure may be claimed.

If current RTL is newer than the default evidence, rerun the small and scale
M13 matrices and pass their `results.json` paths with
`-CorrectnessSmallResults` and `-CorrectnessScaleResults`.
