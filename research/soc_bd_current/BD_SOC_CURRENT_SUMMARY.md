# ZCU106 BD SoC Baseline

Generated: 2026-06-22 10:00 Asia/Saigon
Branch: codex/board-baseline-omp298720
Baseline commit before BD evidence: 4073fbc

## RTL/Algorithm Baseline

Frozen 8-algorithm per-iteration regression uses `golden_model` M=64, N=256, K=16.

| Algorithm | Status | Total cycles | PASS/FAIL |
|---|---:|---:|---:|
| OMP | PASS | 298,720 | 338/0 |
| MP | PASS | 298,720 | 338/0 |
| gOMP | PASS | 408,103 | 354/0 |
| IHT | PASS | 199,968 | 625/0 |
| GP | PASS | 199,968 | 353/0 |
| SP | PASS | 909,218 | 625/0 |
| CoSaMP | PASS | 940,961 | 625/0 |
| HTP | PASS | 533,310 | 353/0 |

Source summary: `D:/vivado_pj/golden_model/verified_runs/large_cycle_verified_summary.md`.

## OOC `cgra_soc_top` Synthesis

Script: `D:/vivado_pj/analysis/synth_cgra_soc_top_current/run_synth_cgra_soc_top.tcl`
Timestamp: 2026-06-22 09:49

| Metric | Value |
|---|---:|
| CLB LUTs | 83,324 |
| CLB Registers | 23,834 |
| BRAM Tile | 16 |
| DSP | 101 |
| WNS | +2.456 ns |
| TNS | 0.000 ns |

## ZCU106 BD Manual Route/Export

Build script: `D:/vivado_pj/analysis/soc_bd_current/build_zcu106_soc_current.tcl`
Manual export script: `D:/vivado_pj/analysis/soc_bd_current/manual_route_export_from_physopt.tcl`
Timestamp: 2026-06-22 10:00

| Metric | Value |
|---|---:|
| CLB LUTs | 84,601 |
| CLB Registers | 26,370 |
| BRAM Tile | 16 |
| DSP | 101 |
| Routed WNS | +0.525 ns |
| Routed TNS | 0.000 ns |
| Routed WHS | +0.010 ns |
| Routing errors | 0 |

Generated local board artifacts:

- `D:/vivado_pj/analysis/soc_bd_current/artifacts/cscgra_zcu106_soc_current.bit`
- `D:/vivado_pj/analysis/soc_bd_current/artifacts/cscgra_zcu106_soc_current.xsa`
- `D:/vivado_pj/analysis/soc_bd_current/artifacts/cscgra_zcu106_soc_current_routed.dcp`

Note: large generated artifacts are intentionally not tracked by git due repository size policy.
