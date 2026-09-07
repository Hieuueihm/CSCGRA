param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) { "m5_property_xsim" } else { "m5_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$logPath = Join-Path $workRoot "m5_console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

Push-Location $repoRoot
try {
    $python = Resolve-PythonCommand -RequiredModules @("numpy")
    Invoke-PythonScript -Python $python `
        -ScriptPath "scripts\golden\generate_m5_vectors.py" `
        -FailureMessage "M5 golden generation failed"
} finally {
    Pop-Location
}

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($toolPath in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Vivado 2018.1 tool not found: $toolPath"
    }
}

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
    "verification\v3\m5\m5_arithmetic_ooc.sv",
    "verification\v3\m5\tb_m5_arithmetic.sv",
    "verification\v3\m5\tb_m5_resource_router.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$goldenRoot = Join-Path $repoRoot "verification\v3\m5\generated"
$combinedOutput = ""

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot -i $goldenRoot $source
        if ($LASTEXITCODE -ne 0) { throw "Vivado M5 compile failed: $source" }
    }
    Set-Content -LiteralPath $logPath -Value ""
    foreach ($topName in @("tb_m5_arithmetic", "tb_m5_resource_router")) {
        $suffix = if ($EnableProperties) { "property" } else { "normal" }
        $snapshot = $topName + "_" + $suffix + "_snapshot"
        & $xelab $topName -s $snapshot -debug typical
        if ($LASTEXITCODE -ne 0) { throw "Vivado M5 elaboration failed: $topName" }
        $simulationOutput = & $xsim $snapshot -runall 2>&1
        $simulationExitCode = $LASTEXITCODE
        $simulationOutput | ForEach-Object { Write-Host $_ }
        Add-Content -LiteralPath $logPath -Value $simulationOutput
        $combinedOutput += ($simulationOutput -join "`n") + "`n"
        if ($simulationExitCode -ne 0) { throw "Vivado M5 simulation failed: $topName" }
    }
} finally {
    Pop-Location
}

if ($combinedOutput -match "FAIL:") { throw "M5 simulation reported FAIL" }
if ($combinedOutput -match "Assertion violation") { throw "M5 assertion violation" }
if ($combinedOutput -notmatch "M5 ARITHMETIC PASS") { throw "M5 arithmetic PASS missing" }
if ($combinedOutput -notmatch "M5 RESOURCE ROUTER PASS") { throw "M5 router PASS missing" }
Write-Host "VIVADO M5 XSIM PASS"
if ($EnableProperties) {
    Write-Host "Embedded FORMAL assertions executed in directed XSim scenarios."
}
