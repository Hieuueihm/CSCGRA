param(
    [switch]$EnableProperties
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) { "m4_property_xsim" } else { "m4_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$python = Resolve-PythonCommand -RequiredModules @("numpy")
Push-Location $repoRoot
try {
    Invoke-PythonScript -Python $python `
        -ScriptPath "compiler\v3\generate_architecture_package.py" `
        -FailureMessage "M4 architecture package generation failed"
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
    "rtl\v3\data_movement\axi_read_burst_engine.v",
    "rtl\v3\data_movement\axi_write_burst_engine.v",
    "rtl\v3\data_movement\dma_request_arbiter.v",
    "rtl\v3\data_movement\memory_dma_engine.v",
    "rtl\v3\data_movement\dma_element_normalizer.v",
    "rtl\v3\data_movement\vector_scratchpad.v",
    "rtl\v3\data_movement\vector_stream_engine.v",
    "rtl\v3\data_movement\scratchpad_word_codec.v",
    "rtl\v3\data_movement\scratchpad_preload_engine.v",
    "rtl\v3\data_movement\scratchpad_residency_tracker.v",
    "rtl\v3\cgra\stream_context_router.v",
    "verification\v3\m4\tb_m4_stream_transport.sv",
    "verification\v3\m4\tb_m4_dma_scratchpad.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$logPath = Join-Path $workRoot "m4_console.log"

Push-Location $workRoot
try {
    & $xvlog -sv @defines -i $includeRoot @sources
    if ($LASTEXITCODE -ne 0) { throw "Vivado M4 compile failed" }
    & $xelab tb_m4_stream_transport -s m4_stream_transport_snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "Vivado M4 elaboration failed" }
    $streamOutput = & $xsim m4_stream_transport_snapshot -runall 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Vivado M4 stream simulation failed" }
    & $xelab tb_m4_dma_scratchpad -s m4_dma_scratchpad_snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "Vivado M4.1 elaboration failed" }
    $dmaOutput = & $xsim m4_dma_scratchpad_snapshot -runall 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Vivado M4.1 simulation failed" }
    $simulationOutput = @($streamOutput) + @($dmaOutput)
    $simulationOutput | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $simulationOutput
} finally {
    Pop-Location
}

$consoleText = Get-Content -Raw $logPath
if ($consoleText -match "FAIL:" -or $consoleText -match "Assertion violation") {
    throw "M4 simulation reported a failure; see $logPath"
}
if ($consoleText -notmatch "M4 STREAM TRANSPORT PASS") {
    throw "M4 PASS marker missing from $logPath"
}
if ($consoleText -notmatch "M4.1 DMA SCRATCHPAD PASS") {
    throw "M4.1 PASS marker missing from $logPath"
}
$evidenceDirectory = Join-Path $repoRoot "reports\v3\m4_vivado"
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
$evidenceName = if ($EnableProperties) {
    "m4_xsim_properties.log"
} else {
    "m4_xsim.log"
}
Copy-Item -LiteralPath $logPath -Destination (
    Join-Path $evidenceDirectory $evidenceName) -Force
Write-Host "VIVADO M4 XSIM PASS"
if ($EnableProperties) {
    Write-Host "Embedded FORMAL assertions executed in directed XSim scenarios."
}
