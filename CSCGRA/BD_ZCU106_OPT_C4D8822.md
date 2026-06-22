# ZCU106 BD result for CSCGRA_opt

Generated: 2026-06-22 19:38 Asia/Saigon
RTL commit: `c4d8822` (`Reduce Gram wait cycle`)
Repo: `D:/vivado_pj/CSCGRA_opt`

## 8-algorithm verification

| Algorithm | Total cycles | PASS/FAIL |
| --- | ---: | --- |
| OMP | 227216 | 338 / 0 |
| MP | 227216 | 338 / 0 |
| GOMP | 318747 | 354 / 0 |
| IHT | 159520 | 625 / 0 |
| GP | 159520 | 353 / 0 |
| SP | 730274 | 625 / 0 |
| CoSaMP | 762017 | 625 / 0 |
| HTP | 427710 | 353 / 0 |

## Routed BD signoff

Flow used the ZCU106 block design around `cgra_soc_top`, sourcing RTL from `CSCGRA_opt/CSCGRA.srcs/sources_1/new`.

| Metric | Value |
| --- | ---: |
| CLB LUTs | 89917 |
| CLB Registers | 26335 |
| BRAM Tile | 16 |
| DSP | 101 |
| WNS | +0.445 ns |
| TNS | 0.000 ns |
| WHS | +0.011 ns |
| THS | 0.000 ns |
| Route errors | 0 |
| DRC errors | 0 |

Notes:
- The regular `impl_1` run reached routed timing closure but Vivado marked the run failed before artifact export.
- Artifacts were exported successfully using a manual route/export flow from `cscgra_soc_bd_wrapper_physopt.dcp`.

Artifacts:
- `D:/vivado_pj/CSCGRA_opt/runs/bd_zcu106_opt_c4d8822/artifacts/cscgra_zcu106_soc_opt_c4d8822.bit`
- `D:/vivado_pj/CSCGRA_opt/runs/bd_zcu106_opt_c4d8822/artifacts/cscgra_zcu106_soc_opt_c4d8822.xsa`
- `D:/vivado_pj/CSCGRA_opt/runs/bd_zcu106_opt_c4d8822/artifacts/cscgra_zcu106_soc_opt_c4d8822_routed.dcp`
