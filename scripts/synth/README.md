# Synthesis scripts

Run the complete v3 M1-M7 regression, including all OOC synthesis gates, with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_v3_m1_m7.ps1
```

To run only synthesis after simulation/property gates already passed:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_v3_m1_m7.ps1 `
  -SkipModels -SkipSimulation -SkipProperties
```

- `run_ooc.ps1`: PowerShell entrypoint for out-of-context synthesis.
- `run_ooc.tcl`: Vivado implementation of the OOC flow.

Implementation is available through `scripts/run.ps1 -Flow impl`; it runs
OOC synthesis, optimization, placement, physical optimization, routing, DRC,
and writes utilization/timing/checkpoint reports under `logs/impl/`.

Normally invoke these through `scripts/run.ps1 -Flow synth`. Generated Vivado
state belongs under `work/`; raw reports belong under `logs/`; reviewed metrics
belong under `reports/releases/`.

Focused v3 M3 OOC synthesis:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m3.ps1
```

This gate checks the individual stores/sequencers/controller plus the real
`context BRAM -> reservation guard -> sequencer` harness on ZCU106. It enforces
the M3 RAM primitive mapping and a `+0.200 ns` post-synthesis WNS margin at
6.667 ns. It is OOC evidence, not post-route board-level sign-off.

Focused M1--M4 integration OOC synthesis:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m1_m4_integration.ps1
```

This synthesizes the verification harness, not `top.v`, and enforces the same
`+0.200 ns` post-synthesis margin plus zero DSP inference. It is the timing and
resource check for the currently connected control/memory spine, not final
implementation sign-off.

Focused M5/M6/M7 compute OOC synthesis:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m5.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m6.ps1
powershell -ExecutionPolicy Bypass -File scripts/synth/check_m7.ps1
```

M6 synthesizes one `pe_tile`, one 4x4 `cgra_cluster` and the two-cluster pair;
it is not a connected M1-M6 full-design resource or timing claim.

M7 synthesizes the folded Threefry core, generator, support cache, stream
provider and normalizer. It enforces one RAMB36 for the sign cache, zero DSP in
the generator/provider path, four DSP in the A62 runtime normalizer and a
`+0.200 ns` WNS margin.
