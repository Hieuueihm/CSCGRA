param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\m11_iht_support_xsim"
$logPath = Join-Path $workRoot "m11_iht_support_console.log"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$sources = @(
    "rtl\v3\phi\support_phi_symbol_cache.v",
    "rtl\v3\memory\recon_sdp_ram.v",
    "rtl\v3\memory\recon_1w2r_ram.v",
    "rtl\v3\memory\support_coefficient_stripe_store.v",
    "rtl\v3\selection\support_workspace.v",
    "rtl\v3\selection\support_coefficient_remapper.v",
    "rtl\v3\selection\support_state_manager.v",
    "verification\v3\m11\tb_m11_iht_support_replace.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & (Join-Path $VivadoBin "xvlog.bat") -sv -i (Join-Path $repoRoot "rtl\v3\include") $source
        if ($LASTEXITCODE -ne 0) { throw "M11 IHT support compile failed" }
    }
    & (Join-Path $VivadoBin "xelab.bat") tb_m11_iht_support_replace -s m11_iht_support_snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M11 IHT support elaboration failed" }
    $output = & (Join-Path $VivadoBin "xsim.bat") m11_iht_support_snapshot -runall 2>&1
    $output | ForEach-Object { Write-Host $_ }
    $joined = [string]::Join([Environment]::NewLine, $output)
    Set-Content -LiteralPath $logPath -Value $output
    if ($LASTEXITCODE -ne 0 -or $joined -notmatch "M11 IHT SUPPORT REPLACE/PHI REFILL PASS") {
        throw "M11 IHT support replay failed"
    }
} finally { Pop-Location }
