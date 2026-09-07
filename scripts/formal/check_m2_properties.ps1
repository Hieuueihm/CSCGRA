$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\m2"
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
    "rtl\v3\reconstruction_control\configuration_fetch_unit.v",
    "rtl\v3\reconstruction_control\configuration_check_unit.v",
    "rtl\v3\reconstruction_control\active_configuration_store.v",
    "rtl\v3\reconstruction_control\reconstruction_configuration_unit.v",
    "rtl\v3\data_movement\axi_read_burst_engine.v",
    "rtl\v3\data_movement\axi_write_burst_engine.v",
    "rtl\v3\data_movement\dma_request_arbiter.v",
    "rtl\v3\data_movement\dma_element_normalizer.v",
    "rtl\v3\data_movement\memory_dma_engine.v"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    & $xvlog -sv -d FORMAL -i (Join-Path $repoRoot "rtl\v3\include") @sources
    if ($LASTEXITCODE -ne 0) { throw "Vivado M2 property compile failed" }
    foreach ($topName in @(
        "reconstruction_configuration_unit",
        "memory_dma_engine",
        "dma_element_normalizer"
    )) {
        & $xelab $topName -s ("property_" + $topName) -debug typical
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado M2 property elaboration failed for $topName"
        }
    }
} finally {
    Pop-Location
}

Write-Host "VIVADO M2 PROPERTY ELABORATION PASS"
Write-Host "Assertions are also executed by scripts/sim/run_m2.ps1 -EnableProperties."
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
