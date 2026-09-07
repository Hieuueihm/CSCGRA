param(
    [switch]$EnableProperties
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) {
    "m1_m4_integration_property_xsim"
} else {
    "m1_m4_integration_xsim"
}
$workRoot = Join-Path $repoRoot "work\$workName"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

Push-Location $repoRoot
try {
    $python = Resolve-PythonCommand -RequiredModules @("numpy")
    Invoke-PythonScript -Python $python `
        -ScriptPath "compiler\v3\generate_architecture_package.py" `
        -FailureMessage "M1-M4 architecture package generation failed"
    Invoke-PythonScript -Python $python `
        -ScriptPath "compiler\v3\m3_control_image.py" `
        -FailureMessage "M1-M4 control image generation failed"
} finally {
    Pop-Location
}

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
    "rtl\v3\host_interface\axi4lite_slave.v",
    "rtl\v3\host_interface\reconstruction_csr.v",
    "rtl\v3\reconstruction_control\configuration_fetch_unit.v",
    "rtl\v3\reconstruction_control\configuration_check_unit.v",
    "rtl\v3\reconstruction_control\active_configuration_store.v",
    "rtl\v3\reconstruction_control\reconstruction_configuration_unit.v",
    "rtl\v3\reconstruction_control\reconstruction_phase_controller.v",
    "rtl\v3\context_control\context_write_certifier.v",
    "rtl\v3\context_control\context_image_store.v",
    "rtl\v3\context_control\memory_configuration_store.v",
    "rtl\v3\context_control\context_reservation_guard.v",
    "rtl\v3\context_control\array_context_sequencer.v",
    "rtl\v3\data_movement\axi_read_burst_engine.v",
    "rtl\v3\data_movement\axi_write_burst_engine.v",
    "rtl\v3\data_movement\dma_request_arbiter.v",
    "rtl\v3\data_movement\dma_element_normalizer.v",
    "rtl\v3\data_movement\memory_dma_engine.v",
    "rtl\v3\data_movement\scratchpad_preload_engine.v",
    "rtl\v3\data_movement\scratchpad_residency_tracker.v",
    "rtl\v3\data_movement\vector_scratchpad.v",
    "rtl\v3\data_movement\vector_stream_engine.v",
    "rtl\v3\data_movement\scratchpad_word_codec.v",
    "rtl\v3\cgra\stream_context_router.v",
    "verification\v3\integration\m1_m4_integration_harness.sv",
    "verification\v3\integration\tb_m1_m4_integration.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }

$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$generatedRoot = Join-Path $repoRoot "verification\v3\m3\generated"
$logPath = Join-Path $workRoot "m1_m4_integration_console.log"

Push-Location $workRoot
try {
    & $xvlog -sv @defines -i $includeRoot -i $generatedRoot @sources
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado M1-M4 compile failed"
    }
    & $xelab tb_m1_m4_integration -s m1_m4_integration_snapshot `
        -debug typical
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado M1-M4 elaboration failed"
    }
    $simulationOutput = & $xsim m1_m4_integration_snapshot -runall 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado M1-M4 simulation failed"
    }
    $simulationOutput | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $simulationOutput
} finally {
    Pop-Location
}

$consoleText = Get-Content -Raw $logPath
if ($consoleText -match "FAIL:" -or
        $consoleText -match "Assertion violation") {
    throw "M1-M4 integration reported a failure; see $logPath"
}
if ($consoleText -notmatch "M1-M4 INTEGRATION PASS") {
    throw "M1-M4 PASS marker missing from $logPath"
}

$evidenceDir = Join-Path $repoRoot "reports\v3\m1_m4_integration_vivado"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$evidenceName = if ($EnableProperties) {
    "xsim_properties.log"
} else {
    "xsim.log"
}
Copy-Item -LiteralPath $logPath -Destination (
    Join-Path $evidenceDir $evidenceName) -Force
Write-Host "VIVADO M1-M4 INTEGRATION XSIM PASS"
if ($EnableProperties) {
    Write-Host "Embedded FORMAL assertions executed in the integration run."
}
