param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference="Stop"
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado=Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
$reportDir=Join-Path $repoRoot "reports\v3\m9b_vivado\m9b_n3_integration"
$workDir=Join-Path $repoRoot "work\synth\m9b_n3_integration"
New-Item -ItemType Directory -Force -Path $reportDir,$workDir | Out-Null
Push-Location $workDir
try {
    & $vivado -mode batch -journal (Join-Path $reportDir "vivado.jou") -log (Join-Path $reportDir "vivado.log") -source (Join-Path $PSScriptRoot "check_m9b_n3.tcl") -tclargs $repoRoot $reportDir
    if($LASTEXITCODE -ne 0){throw "M9b N3 integration synthesis failed"}
} finally { Pop-Location }
Get-Content (Join-Path $reportDir "summary.txt")
