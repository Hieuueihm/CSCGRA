param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workName = if ($EnableProperties) { "m9a_property_xsim" } else { "m9a_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$logPath = Join-Path $workRoot "m9a_console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

Push-Location $repoRoot
try {
    $python = Resolve-PythonCommand -RequiredModules @("numpy")
    Invoke-PythonScript -Python $python `
        -ScriptPath "scripts\golden\generate_m9a_vectors.py" `
        -FailureMessage "M9a golden generation failed"
} finally { Pop-Location }

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($toolPath in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $toolPath)) { throw "Vivado 2018.1 tool not found: $toolPath" }
}
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$goldenRoot = Join-Path $repoRoot "verification\v3\m9a\generated"
$sources = @(
    "rtl\v3\selection\topk_selection_unit.v",
    "verification\v3\m9a\tb_topk_selection_unit.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot -i $goldenRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M9a compile failed: $source" }
    }
    $snapshot = if ($EnableProperties) { "m9a_property_snapshot" } else { "m9a_normal_snapshot" }
    & $xelab tb_topk_selection_unit -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M9a elaboration failed" }
    $simulationOutput = & $xsim $snapshot -runall 2>&1
    $simulationExitCode = $LASTEXITCODE
    $simulationOutput | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $simulationOutput
    if ($simulationExitCode -ne 0) { throw "M9a simulation failed" }
} finally { Pop-Location }

$combinedOutput = Get-Content -LiteralPath $logPath -Raw
if ($combinedOutput -match "FAIL:") { Write-Error "M9a simulation reported FAIL"; exit 1 }
if ($combinedOutput -match "Assertion violation") { Write-Error "M9a assertion violation"; exit 1 }
if ($combinedOutput -notmatch "M9A TOPK SELECTION PASS") { Write-Error "M9a PASS marker missing"; exit 1 }
Write-Host "VIVADO M9A XSIM PASS"
if ($EnableProperties) { Write-Host "Embedded FORMAL assertions executed in directed XSim scenarios." }
