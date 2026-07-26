# ZCU106 BD-only build for CSCGRA noisy_mu PE-op8

Generated from `scripts/build_zcu106_soc_peop8_bd_only.tcl`.

## Configuration

- Target: ZCU106 / `xczu7ev-ffvc1156-2-e`
- Top wrapper: `cscgra_soc_bd_wrapper`
- CGRA module: `cgra_soc_top`
- AXI-Lite base: `0xA0000000`, range `16K`
- PL clock: `100 MHz`
- UART0: enabled on `MIO 18 .. 19`, 115200 baud, 100 MHz ref clock from IOPLL
- UART1: enabled on `MIO 20 .. 21`, 115200 baud, 100 MHz ref clock from IOPLL

## Outputs

BD:
`runs/bd_zcu106_soc_peop8_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_peop8.srcs/sources_1/bd/cscgra_soc_bd/cscgra_soc_bd.bd`

Wrapper:
`runs/bd_zcu106_soc_peop8_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_peop8.srcs/sources_1/bd/cscgra_soc_bd/hdl/cscgra_soc_bd_wrapper.v`

HWH:
`runs/bd_zcu106_soc_peop8_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_peop8.srcs/sources_1/bd/cscgra_soc_bd/hw_handoff/cscgra_soc_bd.hwh`

Project:
`runs/bd_zcu106_soc_peop8_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_peop8.xpr`

## Re-run

```powershell
cd D:\vivado_pj\CSCGRA_noisy_mu_peop8
C:\Xilinx\Vivado\2018.1\bin\vivado.bat -mode batch -source D:\vivado_pj\CSCGRA_noisy_mu_peop8\scripts\build_zcu106_soc_peop8_bd_only.tcl
```
