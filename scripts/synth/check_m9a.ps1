param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
$reportDir = Join-Path $repoRoot "reports\v3\m9a_vivado"
$workDir = Join-Path $repoRoot "work\synth\m9a"
New-Item -ItemType Directory -Force -Path $reportDir, $workDir | Out-Null
$tcl = Join-Path $PSScriptRoot "check_m9a.tcl"
Push-Location $workDir
try {
    & $vivado -mode batch -journal (Join-Path $reportDir "vivado.jou") `
        -log (Join-Path $reportDir "vivado.log") -source $tcl `
        -tclargs $repoRoot $reportDir
    if ($LASTEXITCODE -ne 0) { throw "M9a Vivado synthesis check failed" }
} finally { Pop-Location }
Write-Host "M9a Vivado synthesis check PASS"
