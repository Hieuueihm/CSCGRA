param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\m9a"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$source = Join-Path $repoRoot "rtl\v3\selection\topk_selection_unit.v"
Push-Location $workRoot
try {
    & $xvlog -sv -d FORMAL -i $includeRoot $source
    if ($LASTEXITCODE -ne 0) { throw "M9a property compile failed" }
    & $xelab topk_selection_unit -s property_topk_selection_unit -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M9a property elaboration failed" }
} finally { Pop-Location }
Write-Host "VIVADO M9A PROPERTY ELABORATION PASS"
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
