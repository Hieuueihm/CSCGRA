param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin",
    [string]$TopNames = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
$reportDir = Join-Path $repoRoot "reports\v3\m5_vivado"
$workDir = Join-Path $repoRoot "work\synth\m5"
New-Item -ItemType Directory -Force -Path $reportDir, $workDir | Out-Null
$tcl = Join-Path $PSScriptRoot "check_m5.tcl"

Push-Location $workDir
try {
    $arguments = @("-mode", "batch", "-journal", (Join-Path $reportDir "vivado.jou"),
        "-log", (Join-Path $reportDir "vivado.log"), "-source", $tcl,
        "-tclargs", $repoRoot, $reportDir)
    if (-not [string]::IsNullOrWhiteSpace($TopNames)) { $arguments += $TopNames }
    & $vivado @arguments
    if ($LASTEXITCODE -ne 0) { throw "M5 Vivado synthesis check failed" }
} finally {
    Pop-Location
}
Write-Host "M5 Vivado synthesis check PASS"
Write-Host "Reports: $reportDir"
