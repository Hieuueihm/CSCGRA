param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference="Stop"; Set-StrictMode -Version Latest
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot); $vivado=Join-Path $VivadoBin "vivado.bat"; $report=Join-Path $repoRoot "reports\v3\m8_vivado"; $work=Join-Path $repoRoot "work\synth\m8"; New-Item -ItemType Directory -Force -Path $report,$work|Out-Null
Push-Location $work; try { & $vivado -mode batch -journal (Join-Path $report "vivado.jou") -log (Join-Path $report "vivado.log") -source (Join-Path $PSScriptRoot "check_m8.tcl") -tclargs $repoRoot $report; if($LASTEXITCODE-ne 0){throw "M8 OOC failed"} } finally { Pop-Location }; Write-Host "M8 Vivado OOC PASS"
