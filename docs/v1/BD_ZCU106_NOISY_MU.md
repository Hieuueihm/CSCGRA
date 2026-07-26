# ZCU106 BD for CSCGRA_noisy_mu

Generated from `scripts/build_zcu106_soc_noisy_mu_bd_only.tcl`.

Key settings:
- Project: `cscgra_zcu106_soc_noisy_mu`
- RTL source: `D:/vivado_pj/CSCGRA_noisy_mu/CSCGRA.srcs/sources_1/new`
- UART0: enabled on `MIO 18 .. 19`, 115200 baud, 100 MHz ref clock from IOPLL
- UART1: enabled on `MIO 20 .. 21`, 115200 baud, 100 MHz ref clock from IOPLL
- AXI-Lite CGRA base: `0xA0000000`, range `16K`

Generated BD path:
`runs/bd_zcu106_soc_noisy_mu_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_noisy_mu.srcs/sources_1/bd/cscgra_soc_bd/cscgra_soc_bd.bd`

Generated wrapper path:
`runs/bd_zcu106_soc_noisy_mu_bd_only/vivado_zcu106_soc/cscgra_zcu106_soc_noisy_mu.srcs/sources_1/bd/cscgra_soc_bd/hdl/cscgra_soc_bd_wrapper.v`

To regenerate BD-only:

```powershell
$env:CSCGRA_SOC_RUN_DIR='D:\vivado_pj\CSCGRA_noisy_mu\runs\bd_zcu106_soc_noisy_mu_bd_only'
C:\Xilinx\Vivado\2018.1\bin\vivado.bat -mode batch -source D:\vivado_pj\CSCGRA_noisy_mu\scripts\build_zcu106_soc_noisy_mu_bd_only.tcl
```

For full synth/impl/bitstream flow, use:
`scripts/build_zcu106_soc_noisy_mu.tcl`
