param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workName = if ($EnableProperties) { "m9b_integration_property_xsim" } else { "m9b_integration_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$logPath = Join-Path $workRoot "m9b_integration_console.log"
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
    "rtl\v3\phi\support_phi_symbol_cache.v",
    "rtl\v3\selection\topk_selection_unit.v",
    "rtl\v3\selection\proxy_candidate_collector.v",
    "rtl\v3\selection\support_workspace.v",
    "rtl\v3\selection\support_state_manager.v",
    "rtl\v3\selection\support_coefficient_remapper.v",
    "rtl\v3\refinement\certificate_limit_unit.v",
    "rtl\v3\refinement\normal_residual_checker.v",
    "rtl\v3\integration\m8_resource_dispatcher.v",
    "rtl\v3\integration\m9b_n3_integration.v",
    "verification\v3\m9b\tb_m9b_dispatcher_phi_cache.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M9b integration compile failed: $source" }
    }
    $snapshot = if ($EnableProperties) { "m9b_integration_property_snapshot" } else { "m9b_integration_snapshot" }
    & $xelab tb_m9b_dispatcher_phi_cache -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M9b integration elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $output
    if ($code -ne 0) { throw "M9b integration simulation failed" }
} finally { Pop-Location }
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Assertion violation") { throw "M9b integration failure marker" }
if ($text -notmatch "M9B DISPATCHER CONTEXT REPLAY/N3 PHI CACHE PASS") { throw "M9b integration PASS marker missing" }
Write-Host "VIVADO M9B DISPATCHER/N3 INTEGRATION XSIM PASS"
