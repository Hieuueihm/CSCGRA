param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mode = if ($EnableProperties) { "property" } else { "normal" }
$workRoot = Join-Path $repoRoot "work\m12_result_writer_$mode"
$reportRoot = Join-Path $repoRoot "reports\v3\m12_vivado"
$logPath = Join-Path $reportRoot "result_writer_${mode}_xsim.log"
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
Push-Location $workRoot
try {
    & $xvlog -sv @defines -i (Join-Path $repoRoot "rtl\v3\include") `
        (Join-Path $repoRoot "rtl\v3\data_movement\reconstruction_result_writer.v") `
        (Join-Path $repoRoot "verification\v3\m12\tb_reconstruction_result_writer.sv")
    if ($LASTEXITCODE -ne 0) { throw "M12 compile failed" }
    $snapshot = "m12_result_writer_${mode}_snapshot"
    & $xelab tb_reconstruction_result_writer -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M12 elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath $logPath
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) { throw "M12 simulation failed" }
} finally {
    Pop-Location
}
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Assertion violation") { throw "M12 failure marker" }
if ($text -notmatch "M12 RESULT WRITER PASS") { throw "M12 PASS marker missing" }
Write-Host "VIVADO M12 $($mode.ToUpperInvariant()) XSIM PASS"
