param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mode = if ($EnableProperties) { "property" } else { "normal" }
$workRoot = Join-Path $repoRoot "work\m10_integration_$mode"
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
    "rtl\v3\selection\support_state_manager.v",
    "rtl\v3\selection\support_coefficient_remapper.v",
    "rtl\v3\refinement\certificate_limit_unit.v",
    "rtl\v3\refinement\normal_residual_checker.v",
    "rtl\v3\integration\m8_resource_dispatcher.v",
    "verification\v3\m10\tb_m10_dispatcher_integration.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M10 integration compile failed: $source" }
    }
    $snapshot = "m10_integration_${mode}_snapshot"
    & $xelab tb_m10_dispatcher_integration -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M10 integration elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    Set-Content -LiteralPath $logPath -Value $output
    if ($code -ne 0) { throw "M10 integration simulation failed" }
} finally { Pop-Location }
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Assertion violation") { throw "M10 integration failure marker" }
if ($text -notmatch "M10 DISPATCHER REFINEMENT/ROLLBACK PASS") {
    throw "M10 integration PASS marker missing"
}
Write-Host "VIVADO M10 INTEGRATION $($mode.ToUpperInvariant()) XSIM PASS"
