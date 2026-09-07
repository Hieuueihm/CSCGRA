param(
    [switch]$RunProductionGuards,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\p17_packing_xsim"
$reportRoot = Join-Path $repoRoot "reports\v3\optimization_follow_20260906\p1\runs\p17"
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($toolPath in @($xvlog,$xelab,$xsim)) {
    if (-not (Test-Path -LiteralPath $toolPath)) { throw "Vivado tool not found: $toolPath" }
}
Push-Location $repoRoot
try {
    py -3 -m compiler.v3.numeric_packing (Join-Path $reportRoot "p17_packing_contract.json")
    if ($LASTEXITCODE -ne 0) { throw "P17 contract generation failed" }
} finally { Pop-Location }
Push-Location $workRoot
try {
    & $xvlog -sv -i (Join-Path $repoRoot "rtl\v3\include") `
        (Join-Path $repoRoot "rtl\v3\data_movement\candidate_scratchpad_word_codec.v") `
        (Join-Path $repoRoot "rtl\v3\data_movement\candidate_dma_element_normalizer.v") `
        (Join-Path $repoRoot "rtl\v3\data_movement\candidate_acc70_threshold_codec.v") `
        (Join-Path $repoRoot "verification\v3\m4\tb_p17_candidate_packing.sv")
    if ($LASTEXITCODE -ne 0) { throw "P17 candidate packing compile failed" }
    & $xelab tb_p17_candidate_packing -s p17_candidate_packing_snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "P17 candidate packing elaboration failed" }
    $packingOutput = & $xsim p17_candidate_packing_snapshot -runall 2>&1
    $packingOutput | Set-Content -LiteralPath (Join-Path $reportRoot "p17_candidate_packing_xsim.log")
    $packingOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or (($packingOutput -join "`n") -notmatch "P17 CANDIDATE PACKING PASS")) {
        throw "P17 candidate packing failed"
    }
    & $xvlog -sv -i (Join-Path $repoRoot "rtl\v3\include") `
        (Join-Path $repoRoot "rtl\v3\data_movement\reconstruction_result_writer.v") `
        (Join-Path $repoRoot "verification\v3\m12\tb_p17_candidate_result_writer.sv")
    if ($LASTEXITCODE -ne 0) { throw "P17 candidate result compile failed" }
    & $xelab tb_p17_candidate_result_writer -s p17_candidate_result_snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "P17 candidate result elaboration failed" }
    $resultOutput = & $xsim p17_candidate_result_snapshot -runall 2>&1
    $resultOutput | Set-Content -LiteralPath (Join-Path $reportRoot "p17_candidate_result_xsim.log")
    $resultOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or (($resultOutput -join "`n") -notmatch "P17 CANDIDATE RESULT PASS")) {
        throw "P17 candidate result path failed"
    }
} finally { Pop-Location }
if ($RunProductionGuards) {
    & (Join-Path $repoRoot "scripts\sim\run_m4.ps1")
    if ($LASTEXITCODE -ne 0) { throw "M4 production guard failed" }
    & (Join-Path $repoRoot "scripts\sim\run_m12.ps1")
    if ($LASTEXITCODE -ne 0) { throw "M12 production guard failed" }
}
Write-Host "VIVADO P17 PACKING PASS"
