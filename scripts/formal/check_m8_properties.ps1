param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
& (Join-Path (Split-Path -Parent $PSScriptRoot) "sim\run_m8.ps1") -EnableProperties -VivadoBin $VivadoBin
if($LASTEXITCODE-ne 0){exit $LASTEXITCODE}; Write-Host "VIVADO M8 PROPERTY ELABORATION/DIRECTED ASSERTION PASS"
