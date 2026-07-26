# BD synth path-length fix

## Problem
- Original BD project path was too deep under CSCGRA_opt_architecture/runs/bd_zcu106_soc_opt_architecture_bd_only/...
- Vivado 2018.1 failed creating .Xil/incrSyn message files with [Common 17-222], which is typically Windows path-length related, not RTL permission.

## Fixed BD location
- Short run dir: D:\vivado_pj\bd_optarch
- Project: D:\vivado_pj\bd_optarch\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.xpr
- Wrapper: D:\vivado_pj\bd_optarch\vivado_zcu106_soc\cscgra_zcu106_soc_opt_architecture.srcs\sources_1\bd\cscgra_soc_bd\hdl\cscgra_soc_bd_wrapper.v

## How to rerun
```powershell
$env:CSCGRA_SOC_RUN_DIR="D:\vivado_pj\bd_optarch"
& "C:\Xilinx\Vivado\2018.1\bin\vivado.bat" -mode batch -source scripts\build_zcu106_soc_opt_architecture_bd_only.tcl
```
