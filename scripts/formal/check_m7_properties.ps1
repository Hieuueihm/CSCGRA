param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\m7"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$sources = @(
    "rtl\v3\phi\phi_request_queue.v",
    "rtl\v3\phi\threefry2x32_folded_pipeline.v",
    "rtl\v3\phi\phi_symbol_builder.v",
    "rtl\v3\phi\phi_response_gearbox.v",
    "rtl\v3\phi\phi_symbol_generator.v",
    "rtl\v3\phi\support_phi_symbol_cache.v",
    "rtl\v3\phi\phi_stream_provider.v",
    "rtl\v3\phi\phi_stream_subsystem.v",
    "rtl\v3\phi\phi_operator_normalizer.v"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv -d FORMAL -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M7 property compile failed: $source" }
    }
    foreach ($topName in @(
        "phi_request_queue", "threefry2x32_folded_pipeline",
        "phi_symbol_builder", "phi_response_gearbox", "phi_symbol_generator",
        "support_phi_symbol_cache", "phi_stream_provider",
        "phi_operator_normalizer")) {
        & $xelab $topName -s ("property_" + $topName) -debug typical
        if ($LASTEXITCODE -ne 0) {
            throw "M7 property elaboration failed: $topName"
        }
    }
} finally {
    Pop-Location
}
Write-Host "VIVADO M7 PROPERTY ELABORATION PASS"
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
