param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) { "m6_property_xsim" } else { "m6_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$logPath = Join-Path $workRoot "m6_console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

Push-Location $repoRoot
try {
    $python = Resolve-PythonCommand -RequiredModules @("numpy")
    Invoke-PythonScript -Python $python `
        -ScriptPath "scripts\golden\generate_m6_vectors.py" `
        -FailureMessage "M6 golden generation failed"
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
    "rtl\v3\cgra\pe_alu.v",
    "rtl\v3\cgra\phi_pe_alu.v",
    "rtl\v3\cgra\pe_local_register_file.v",
    "rtl\v3\cgra\registered_switchbox.v",
    "rtl\v3\cgra\pe_tile.v",
    "rtl\v3\cgra\phi_pe_tile.v",
    "rtl\v3\cgra\cgra_row.v",
    "rtl\v3\cgra\cgra_cluster.v",
    "rtl\v3\cgra\cgra_cluster_pair.v",
    "rtl\v3\cgra\cgra_result_buffer.v",
    "verification\v3\m6\tb_m6_cgra.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$goldenRoot = Join-Path $repoRoot "verification\v3\m6\generated"

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot -i $goldenRoot $source
        if ($LASTEXITCODE -ne 0) { throw "Vivado M6 compile failed: $source" }
    }
    $snapshot = if ($EnableProperties) {
        "tb_m6_cgra_property_snapshot"
    } else {
        "tb_m6_cgra_normal_snapshot"
    }
    & $xelab tb_m6_cgra -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "Vivado M6 elaboration failed" }
    $simulationOutput = & $xsim $snapshot -runall 2>&1
    $simulationExitCode = $LASTEXITCODE
    $simulationOutput | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $simulationOutput
    if ($simulationExitCode -ne 0) { throw "Vivado M6 simulation failed" }
} finally {
    Pop-Location
}

$combinedOutput = $simulationOutput -join "`n"
if ($combinedOutput -match "FAIL:") { throw "M6 simulation reported FAIL" }
if ($combinedOutput -match "Assertion violation") { throw "M6 assertion violation" }
if ($combinedOutput -notmatch "M6 PE ALU golden PASS") {
    throw "M6 PE ALU PASS missing"
}
if ($combinedOutput -notmatch "M6 CLUSTER PAIR PASS") {
    throw "M6 cluster-pair PASS missing"
}
if ($combinedOutput -notmatch "M6 RESULT BUFFER PASS") {
    throw "M6 result-buffer PASS missing"
}
Write-Host "VIVADO M6 XSIM PASS"
if ($EnableProperties) {
    Write-Host "Embedded FORMAL assertions executed in directed XSim scenarios."
}
