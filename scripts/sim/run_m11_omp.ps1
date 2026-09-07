param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workName = if ($EnableProperties) { "m11_omp_property_xsim" } else { "m11_omp_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$logPath = Join-Path $workRoot "console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$sources = @(
    "rtl\v3\memory\recon_sdp_ram.v",
    "rtl\v3\memory\recon_1w2r_ram.v",
    "rtl\v3\memory\support_coefficient_stripe_store.v",
    "rtl\v3\selection\topk_selection_unit.v",
    "rtl\v3\selection\proxy_candidate_collector.v",
    "rtl\v3\selection\support_workspace.v",
    "rtl\v3\selection\support_coefficient_remapper.v",
    "rtl\v3\selection\support_state_manager.v",
    "rtl\v3\refinement\certificate_limit_unit.v",
    "rtl\v3\refinement\normal_residual_checker.v",
    "rtl\v3\integration\m8_resource_dispatcher.v",
    "verification\v3\m11\tb_m11_omp_selection_replay.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M11 OMP compile failed: $source" }
    }
    $snapshot = if ($EnableProperties) { "m11_omp_property_snapshot" } else { "m11_omp_snapshot" }
    & $xelab tb_m11_omp_selection_replay -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M11 OMP elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $output
    if ($code -ne 0) { throw "M11 OMP simulation failed" }
} finally { Pop-Location }
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Assertion violation") { throw "M11 OMP failure marker" }
if ($text -notmatch "M11 OMP SELECTION EPOCH/EXCLUSION REPLAY PASS") {
    throw "M11 OMP PASS marker missing"
}
Write-Host "VIVADO M11 OMP XSIM PASS"
