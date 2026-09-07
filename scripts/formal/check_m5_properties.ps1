param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\m5"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$sources = @(
    "rtl\v3\arithmetic\cluster_reduction_unit.v",
    "rtl\v3\arithmetic\global_reduction_merge.v",
    "rtl\v3\arithmetic\reduction_pipeline.v",
    "rtl\v3\arithmetic\scalar_register_file.v",
    "rtl\v3\arithmetic\scalar_state_subsystem.v",
    "rtl\v3\arithmetic\scalar_function_unit.v",
    "rtl\v3\arithmetic\shared_vector_arithmetic_unit.v",
    "rtl\v3\arithmetic\shared_vector_pipeline.v",
    "rtl\v3\arithmetic\array_resource_router.v",
    "rtl\v3\arithmetic\m5_arithmetic_subsystem.v",
    "verification\v3\m5\m5_arithmetic_ooc.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv -d FORMAL -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M5 property compile failed: $source" }
    }
    foreach ($topName in @(
        "cluster_reduction_unit", "global_reduction_merge", "reduction_pipeline",
        "scalar_register_file", "scalar_state_subsystem", "scalar_function_unit",
        "shared_vector_arithmetic_unit", "shared_vector_pipeline",
        "array_resource_router",
        "m5_arithmetic_ooc")) {
        & $xelab $topName -s ("property_" + $topName) -debug typical
        if ($LASTEXITCODE -ne 0) { throw "M5 property elaboration failed: $topName" }
    }
} finally {
    Pop-Location
}
Write-Host "VIVADO M5 PROPERTY ELABORATION PASS"
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
