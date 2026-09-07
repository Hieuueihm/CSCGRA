param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\p15_candidate_arithmetic_xsim"
$logPath = Join-Path $workRoot "console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($toolPath in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Vivado 2018.1 tool not found: $toolPath"
    }
}

$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$sources = @(
    "rtl\v3\arithmetic\scalar_function_unit.v",
    "rtl\v3\arithmetic\shared_vector_arithmetic_unit.v",
    "verification\v3\m5\tb_p15_candidate_arithmetic.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
$snapshot = "tb_p15_candidate_arithmetic_snapshot"

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "P1.5 compile failed: $source" }
    }
    & $xelab tb_p15_candidate_arithmetic -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "P1.5 elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $exitCode = $LASTEXITCODE
    $output | Tee-Object -FilePath $logPath | ForEach-Object { Write-Host $_ }
    $combinedOutput = $output -join "\n"
    if ($exitCode -ne 0) { throw "P1.5 simulation failed" }
} finally {
    Pop-Location
}

if ($combinedOutput -match "FAIL:") { throw "P1.5 directed arithmetic reported FAIL" }
if ($combinedOutput -notmatch "P1.5 CANDIDATE ARITHMETIC PASS") {
    throw "P1.5 candidate PASS marker missing"
}
Write-Host "P1.5 CANDIDATE XSIM PASS"
