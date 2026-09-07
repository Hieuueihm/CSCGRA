param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado = Join-Path $VivadoBin "vivado.bat"
$checkpoint = Join-Path $repoRoot "reports\v3\m8_vivado\post_synth.dcp"
$reportDir = Join-Path $repoRoot "reports\v3\m8_vivado\analysis"
$workDir = Join-Path $repoRoot "work\synth\m8_analysis"
New-Item -ItemType Directory -Force -Path $reportDir, $workDir | Out-Null
Push-Location $workDir
try {
    & $vivado -mode batch -journal (Join-Path $reportDir "vivado.jou") `
        -log (Join-Path $reportDir "vivado.log") `
        -source (Join-Path $PSScriptRoot "analyze_m8_checkpoint.tcl") `
        -tclargs $checkpoint $reportDir
    if ($LASTEXITCODE -ne 0) { throw "M8 checkpoint analysis failed" }
} finally {
    Pop-Location
}
Write-Host "M8 checkpoint analysis PASS"
