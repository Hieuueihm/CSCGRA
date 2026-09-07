param(
    [switch]$EnableProperties
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) { "m3_property_xsim" } else { "m3_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$python = Resolve-PythonCommand -RequiredModules @("numpy")
Push-Location $repoRoot
try {
    Invoke-PythonScript -Python $python `
        -ScriptPath "compiler\v3\generate_architecture_package.py" `
        -FailureMessage "M3 architecture package generation failed"
    Invoke-PythonScript -Python $python `
        -ScriptPath "compiler\v3\m3_control_image.py" `
        -FailureMessage "M3 control-image generation failed"
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
    "rtl\v3\context_control\context_write_certifier.v",
    "rtl\v3\context_control\context_image_store.v",
    "rtl\v3\context_control\memory_configuration_store.v",
    "rtl\v3\context_control\context_reservation_guard.v",
    "rtl\v3\context_control\array_context_sequencer.v",
    "rtl\v3\reconstruction_control\reconstruction_phase_controller.v",
    "verification\v3\m3\tb_m3_context_execution.sv",
    "verification\v3\m3\tb_reconstruction_phase_controller.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$imageIncludeRoot = Join-Path $repoRoot "verification\v3\m3\generated"
$logPath = Join-Path $workRoot "m3_console.log"
$combinedOutput = ""

Push-Location $workRoot
try {
    # Vivado 2018.1 can spend minutes in the VRFC front end when FORMAL is
    # enabled for a multi-file invocation.  Compile one self-contained source
    # at a time; this is functionally equivalent and makes failures local.
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot -i $imageIncludeRoot $source
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado M3 compile failed for $source"
        }
    }
    Set-Content -LiteralPath $logPath -Value ""
    foreach ($topName in @(
        "tb_m3_context_execution",
        "tb_reconstruction_phase_controller"
    )) {
        $snapshot = if ($EnableProperties) {
            $topName + "_property_snapshot"
        } else {
            $topName + "_snapshot"
        }
        & $xelab $topName -s $snapshot -debug typical
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado M3 elaboration failed for $topName"
        }
        $simulationOutput = & $xsim $snapshot -runall 2>&1
        $simulationExitCode = $LASTEXITCODE
        $simulationOutput | ForEach-Object { Write-Host $_ }
        Add-Content -LiteralPath $logPath -Value $simulationOutput
        $combinedOutput += ($simulationOutput -join "`n") + "`n"
        if ($simulationExitCode -ne 0) {
            throw "Vivado M3 simulation failed for $topName"
        }
    }
} finally {
    Pop-Location
}

if ($combinedOutput -match "FAIL:") {
    throw "M3 simulation reported a FAIL marker; see $logPath"
}
if ($combinedOutput -match "Assertion violation") {
    throw "M3 simulation reported an assertion violation; see $logPath"
}
if ($combinedOutput -notmatch "M3 CONTEXT EXECUTION PASS") {
    throw "M3 context execution PASS marker missing from $logPath"
}
if ($combinedOutput -notmatch "M3 CONTROL SEQUENCER PASS") {
    throw "M3 control sequencer PASS marker missing from $logPath"
}
Write-Host "VIVADO M3 XSIM PASS"
if ($EnableProperties) {
    Write-Host "Embedded FORMAL assertions executed in directed XSim scenarios."
}
