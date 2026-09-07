param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) { "m7_property_xsim" } else { "m7_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$logPath = Join-Path $workRoot "m7_console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

Push-Location $repoRoot
try {
    $python = Resolve-PythonCommand -RequiredModules @("numpy")
    Invoke-PythonScript -Python $python `
        -ScriptPath "scripts\golden\generate_m7_vectors.py" `
        -FailureMessage "M7 golden generation failed"
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
$testbenches = @(
    "verification\v3\m7\tb_m7_phi_generator.sv",
    "verification\v3\m7\tb_m7_phi_cache_normalizer.sv",
    "verification\v3\m7\tb_m7_phi_stream_provider.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$tops = @(
    "tb_m7_phi_generator",
    "tb_m7_phi_cache_normalizer",
    "tb_m7_phi_stream_provider"
)
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$goldenRoot = Join-Path $repoRoot "verification\v3\m7\generated"
$allOutput = @()

Push-Location $workRoot
try {
    foreach ($source in @($sources + $testbenches)) {
        & $xvlog -sv @defines -i $includeRoot -i $goldenRoot $source
        if ($LASTEXITCODE -ne 0) { throw "Vivado M7 compile failed: $source" }
    }
    foreach ($top in $tops) {
        $snapshot = if ($EnableProperties) {
            "${top}_property_snapshot"
        } else {
            "${top}_normal_snapshot"
        }
        & $xelab $top -s $snapshot -debug typical
        if ($LASTEXITCODE -ne 0) { throw "Vivado M7 elaboration failed: $top" }
        $simulationOutput = & $xsim $snapshot -runall 2>&1
        $simulationExitCode = $LASTEXITCODE
        $simulationOutput | ForEach-Object { Write-Host $_ }
        $allOutput += $simulationOutput
        if ($simulationExitCode -ne 0) { throw "Vivado M7 simulation failed: $top" }
    }
} finally {
    Pop-Location
}

Set-Content -LiteralPath $logPath -Value $allOutput
$combinedOutput = $allOutput -join "`n"
if ($combinedOutput -match "FAIL:") { throw "M7 simulation reported FAIL" }
if ($combinedOutput -match "Assertion violation") { throw "M7 assertion violation" }
foreach ($marker in @(
    "M7 THREEFRY/GEARBOX PASS",
    "M7 NORMALIZER PASS",
    "M7 CACHE PIPELINED REPLAY PASS",
    "M7 CACHE FILL/REPLAY PASS",
    "M7 CANDIDATE CAPTURE/PROMOTE PASS",
    "M7 PROVIDER STOP PASS"
)) {
    if ($combinedOutput -notmatch [regex]::Escape($marker)) {
        throw "M7 PASS marker missing: $marker"
    }
}
Write-Host "VIVADO M7 XSIM PASS"
if ($EnableProperties) {
    Write-Host "Embedded FORMAL assertions executed in directed XSim scenarios."
}
