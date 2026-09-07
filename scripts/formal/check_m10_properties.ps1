param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
& (Join-Path (Split-Path -Parent $PSScriptRoot) "sim\run_m10.ps1") `
    -EnableProperties -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path (Split-Path -Parent $PSScriptRoot) "sim\run_m10_integration.ps1") `
    -EnableProperties -VivadoBin $VivadoBin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "VIVADO M10 PROPERTY ELABORATION/DIRECTED ASSERTION PASS"
