$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
$xsim = Join-Path $vivadoBin "xsim.bat"
foreach ($toolPath in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Vivado 2018.1 simulation tool not found: $toolPath"
    }
}
$workRoot = Join-Path $repoRoot "work\sim\axilite_control"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$sources = @(
    (Join-Path $repoRoot "rtl\v3\host_interface\axi4lite_slave.v"),
    (Join-Path $repoRoot "rtl\v3\host_interface\reconstruction_csr.v"),
    (Join-Path $repoRoot "rtl\v3\top\m1_control_top.v"),
    (Join-Path $repoRoot "verification\v3\axi\tb_axilite_control.sv")
)
$runTcl = Join-Path $repoRoot "verification\v3\axi\run_all.tcl"
$runTclForVivado = $runTcl.Replace('\', '/')

Push-Location $workRoot
try {
    & $xvlog -sv -i (Join-Path $repoRoot "rtl\v3\include") @sources
    if ($LASTEXITCODE -ne 0) { throw "Vivado xvlog failed" }
    & $xelab tb_axilite_control -s tb_axilite_control_sim -debug typical
    if ($LASTEXITCODE -ne 0) { throw "Vivado xelab failed" }
    $xsimOutput = & $xsim tb_axilite_control_sim -tclbatch $runTclForVivado 2>&1
    $xsimExitCode = $LASTEXITCODE
    $xsimOutput | ForEach-Object { Write-Host $_ }
    if ($xsimExitCode -ne 0) { throw "Vivado XSim failed" }
    $xsimText = $xsimOutput -join "`n"
    if (($xsimText -notmatch "PASS: compact AXI4-Lite CSR revision 3") -or
        ($xsimText -match "FAIL:")) {
        throw "Vivado XSim completed without a clean testbench PASS marker"
    }
} finally {
    Pop-Location
}

Write-Host "VIVADO XSIM COMPACT AXI-LITE CSR TEST PASS"
