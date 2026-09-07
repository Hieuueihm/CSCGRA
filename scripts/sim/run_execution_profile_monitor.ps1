param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\execution_profile_monitor"
$reportRoot = Join-Path $repoRoot "reports\v3\execution_profile_monitor"
$logPath = Join-Path $reportRoot "execution_profile_monitor_xsim.log"
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$snapshot = "execution_profile_monitor_snapshot"
$sources = @(
    "rtl\v3\debug\execution_profile_monitor.v",
    "verification\v3\debug\tb_execution_profile_monitor.sv"
)

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv -i (Join-Path $repoRoot "rtl\v3\include") `
            (Join-Path $repoRoot $source)
        if ($LASTEXITCODE -ne 0) {
            throw "Execution profile monitor compile failed: $source"
        }
    }
    & $xelab tb_execution_profile_monitor -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) {
        throw "Execution profile monitor elaboration failed"
    }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

$output | Set-Content -LiteralPath $logPath
$output | ForEach-Object { Write-Host $_ }
if ($code -ne 0) { throw "Execution profile monitor simulation failed" }
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Fatal:|Assertion violation") {
    throw "Execution profile monitor failure marker"
}
if ($text -notmatch "EXECUTION PROFILE MONITOR PASS") {
    throw "Execution profile monitor PASS marker missing"
}
Write-Host "VIVADO EXECUTION PROFILE MONITOR XSIM PASS"
