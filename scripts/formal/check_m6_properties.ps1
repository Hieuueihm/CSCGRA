param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\m6"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$sources = @(
    "rtl\v3\cgra\pe_alu.v",
    "rtl\v3\cgra\phi_pe_alu.v",
    "rtl\v3\cgra\pe_local_register_file.v",
    "rtl\v3\cgra\registered_switchbox.v",
    "rtl\v3\cgra\pe_tile.v",
    "rtl\v3\cgra\phi_pe_tile.v",
    "rtl\v3\cgra\cgra_row.v",
    "rtl\v3\cgra\cgra_cluster.v",
    "rtl\v3\cgra\cgra_cluster_pair.v",
    "rtl\v3\cgra\cgra_result_buffer.v"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv -d FORMAL -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M6 property compile failed: $source" }
    }
    foreach ($topName in @(
        "pe_alu", "phi_pe_alu", "pe_local_register_file",
        "registered_switchbox", "pe_tile", "phi_pe_tile",
        "cgra_row", "cgra_cluster", "cgra_cluster_pair",
        "cgra_result_buffer")) {
        & $xelab $topName -s ("property_" + $topName) -debug typical
        if ($LASTEXITCODE -ne 0) { throw "M6 property elaboration failed: $topName" }
    }
} finally {
    Pop-Location
}
Write-Host "VIVADO M6 PROPERTY ELABORATION PASS"
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
