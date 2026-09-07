$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\property_compile\axilite_control"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$vivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
foreach ($toolPath in @($xvlog, $xelab)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Vivado 2018.1 tool not found: $toolPath"
    }
}
$sources = @(
    (Join-Path $repoRoot "rtl\v3\host_interface\axi4lite_slave.v"),
    (Join-Path $repoRoot "rtl\v3\host_interface\reconstruction_csr.v"),
    (Join-Path $repoRoot "rtl\v3\top\m1_control_top.v")
)

Push-Location $workRoot
try {
    & $xvlog -sv -d FORMAL -i (Join-Path $repoRoot "rtl\v3\include") @sources
    if ($LASTEXITCODE -ne 0) { throw "Vivado property compile failed" }
    & $xelab m1_control_top -s axilite_control_properties -debug typical
    if ($LASTEXITCODE -ne 0) { throw "Vivado property elaboration failed" }
} finally {
    Pop-Location
}

Write-Host "VIVADO PROPERTY COMPILE PASS"
Write-Host "No mathematical proof was run; Vivado 2018.1 is not a formal proof engine."
