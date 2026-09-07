param(
    [switch]$EnableProperties
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workName = if ($EnableProperties) { "m2_property_xsim" } else { "m2_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$vivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
$xsim = Join-Path $vivadoBin "xsim.bat"
foreach ($toolPath in @($xvlog, $xelab, $xsim)) {
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
    "rtl\v3\data_movement\memory_dma_engine.v",
    "verification\v3\m2\tb_m2_dma_and_run_configuration.sv",
    "verification\v3\m2\tb_configuration_check_unit.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$logPath = Join-Path $workRoot "m2_console.log"
$tclPath = (Join-Path $repoRoot "verification\v3\m2\run_all.tcl").Replace("\", "/")

$xsimText = ""

Push-Location $workRoot
try {
    & $xvlog -sv @defines -i (Join-Path $repoRoot "rtl\v3\include") @sources
    if ($LASTEXITCODE -ne 0) { throw "Vivado M2 compile failed" }
    Set-Content -LiteralPath $logPath -Value ""
    foreach ($topName in @("tb_m2_dma_and_run_configuration", "tb_configuration_check_unit")) {
        $snapshot = if ($EnableProperties) {
            $topName + "_property_snapshot"
        } else {
            $topName + "_snapshot"
        }
        & $xelab $topName -s $snapshot -debug typical
        if ($LASTEXITCODE -ne 0) { throw "Vivado M2 elaboration failed for $topName" }
        $xsimOutput = & $xsim $snapshot -tclbatch $tclPath 2>&1
        $xsimExitCode = $LASTEXITCODE
        $xsimOutput | ForEach-Object { Write-Host $_ }
        Add-Content -LiteralPath $logPath -Value $xsimOutput
        $xsimText += ($xsimOutput -join "`n") + "`n"
        if ($xsimExitCode -ne 0) { throw "Vivado M2 simulation failed for $topName" }
    }
} finally {
    Pop-Location
}

if ($xsimText -match "FAIL:") {
    throw "M2 simulation reported a FAIL marker; see $logPath"
}
if ($xsimText -match "Assertion violation") {
    throw "M2 simulation reported an assertion violation; see $logPath"
}
if ($xsimText -notmatch "PASS: complete M2 DMA and run-configuration testbench") {
    throw "M2 PASS marker missing from $logPath"
}
if ($xsimText -notmatch "PASS: exhaustive run-configuration validator testbench") {
    throw "M2 validator PASS marker missing from $logPath"
}
Write-Host "VIVADO M2 XSIM PASS"
