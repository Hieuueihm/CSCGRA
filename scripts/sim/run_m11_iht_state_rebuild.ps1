param([string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workRoot = Join-Path $repoRoot "work\m11_iht_state_rebuild_xsim"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$sources = @(
    "rtl\v3\selection\support_vector_rebuilder.v",
    "verification\v3\m11\tb_m11_iht_state_rebuild.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & (Join-Path $VivadoBin "xvlog.bat") -sv -i (Join-Path $repoRoot "rtl\v3\include") $source
        if ($LASTEXITCODE -ne 0) { throw "M11 IHT state rebuild compile failed" }
    }
    & (Join-Path $VivadoBin "xelab.bat") tb_m11_iht_state_rebuild -s m11_iht_state_rebuild_snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M11 IHT state rebuild elaboration failed" }
    $output = & (Join-Path $VivadoBin "xsim.bat") m11_iht_state_rebuild_snapshot -runall 2>&1
    $output | ForEach-Object { Write-Host $_ }
    $joined = [string]::Join([Environment]::NewLine, $output)
    if ($LASTEXITCODE -ne 0 -or $joined -notmatch "M11 IHT DENSE/SUPPORT STATE REBUILD PASS") {
        throw "M11 IHT state rebuild replay failed"
    }
} finally { Pop-Location }
