param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mode = if ($EnableProperties) { "property" } else { "normal" }
$workRoot = Join-Path $repoRoot "work\m12_lifecycle_$mode"
$reportRoot = Join-Path $repoRoot "reports\v3\m12_vivado"
$logPath = Join-Path $reportRoot "lifecycle_$($mode)_xsim.log"
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$sources = @(
    "rtl\v3\host_interface\axi4lite_slave.v",
    "rtl\v3\host_interface\reconstruction_csr.v",
    "rtl\v3\reconstruction_control\configuration_fetch_unit.v",
    "rtl\v3\reconstruction_control\configuration_check_unit.v",
    "rtl\v3\reconstruction_control\active_configuration_store.v",
    "rtl\v3\reconstruction_control\reconstruction_configuration_unit.v",
    "rtl\v3\reconstruction_control\reconstruction_phase_controller.v",
    "rtl\v3\data_movement\axi_read_burst_engine.v",
    "rtl\v3\data_movement\axi_write_burst_engine.v",
    "rtl\v3\data_movement\dma_request_arbiter.v",
    "rtl\v3\data_movement\memory_dma_engine.v",
    "rtl\v3\data_movement\reconstruction_result_writer.v",
    "rtl\v3\integration\m12_result_dma_integration.v",
    "rtl\v3\integration\m12_lifecycle_top.v",
    "rtl\v3\top\top.v",
    "verification\v3\m12\tb_m12_lifecycle_top.sv"
)
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i (Join-Path $repoRoot "rtl\v3\include") (Join-Path $repoRoot $source)
        if ($LASTEXITCODE -ne 0) { throw "M12 lifecycle compile failed: $source" }
    }
    $snapshot = "m12_lifecycle_$($mode)_snapshot"
    & $xelab tb_m12_lifecycle_top -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M12 lifecycle elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath $logPath
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) { throw "M12 lifecycle simulation failed" }
} finally { Pop-Location }
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Assertion violation") { throw "M12 lifecycle failure marker" }
if ($text -notmatch "M12 LIFECYCLE TOP PASS") { throw "M12 lifecycle PASS marker missing" }
Write-Host "VIVADO M12 LIFECYCLE XSIM PASS"
