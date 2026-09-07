$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\m4"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$vivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
foreach ($toolPath in @($xvlog, $xelab)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Vivado 2018.1 tool not found: $toolPath"
    }
}

$sources = @(
    "rtl\v3\data_movement\vector_scratchpad.v",
    "rtl\v3\data_movement\vector_stream_engine.v",
    "rtl\v3\data_movement\scratchpad_word_codec.v",
    "rtl\v3\data_movement\dma_element_normalizer.v",
    "rtl\v3\data_movement\scratchpad_preload_engine.v",
    "rtl\v3\data_movement\scratchpad_residency_tracker.v",
    "rtl\v3\cgra\stream_context_router.v"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    & $xvlog -sv -d FORMAL -i (Join-Path $repoRoot "rtl\v3\include") @sources
    if ($LASTEXITCODE -ne 0) { throw "Vivado M4 property compile failed" }
    foreach ($topName in @(
        "vector_scratchpad",
        "vector_stream_engine",
        "scratchpad_word_codec",
        "scratchpad_preload_engine",
        "scratchpad_residency_tracker",
        "stream_context_router"
    )) {
        & $xelab $topName -s ("property_" + $topName) -debug typical
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado M4 property elaboration failed for $topName"
        }
    }
} finally {
    Pop-Location
}

Write-Host "VIVADO M4 PROPERTY ELABORATION PASS"
Write-Host "Assertions are executed by scripts/sim/run_m4.ps1 -EnableProperties."
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
