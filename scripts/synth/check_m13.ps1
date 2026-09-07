param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$reportRoot = Join-Path $repoRoot "reports\v3\m13_vivado\ooc"
New-Item -ItemType Directory -Force $reportRoot | Out-Null
$vivado = Join-Path $VivadoBin "vivado.bat"
& $vivado -mode batch -nolog -nojournal -notrace `
    -source (Join-Path $PSScriptRoot "check_m13.tcl") `
    -tclargs $repoRoot $reportRoot
if ($LASTEXITCODE -ne 0) { throw "M13 OOC failed" }
Write-Host "VIVADO M13 OOC PASS"
