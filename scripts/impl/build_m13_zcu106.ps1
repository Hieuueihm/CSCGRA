param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin",
    [string]$RunDir = ""
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $RunDir = Join-Path $repoRoot "reports\v3\m13_vivado\full_device"
}
New-Item -ItemType Directory -Force $RunDir | Out-Null
$vivado = Join-Path $VivadoBin "vivado.bat"
$consoleLog = Join-Path $RunDir "vivado_console.log"
& $vivado -mode batch -nolog -nojournal -notrace `
    -source (Join-Path $PSScriptRoot "build_m13_zcu106.tcl") `
    -tclargs $repoRoot $RunDir 2>&1 | Tee-Object -FilePath $consoleLog
if ($LASTEXITCODE -ne 0) { throw "M13 ZCU106 full-device build failed" }
Write-Host "VIVADO M13 ZCU106 FULL-DEVICE PASS"
