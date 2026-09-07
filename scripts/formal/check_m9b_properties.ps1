param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
& (Join-Path (Split-Path -Parent $PSScriptRoot) "sim\run_m9b.ps1") -EnableProperties -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "VIVADO M9B PROPERTY ELABORATION/DIRECTED ASSERTION PASS"
