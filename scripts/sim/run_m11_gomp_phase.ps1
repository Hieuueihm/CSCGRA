param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workName = if ($EnableProperties) { "m11_gomp_phase_property_xsim" } else { "m11_gomp_phase_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
$reportRoot = Join-Path $repoRoot "reports\v3\m11_vivado"
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null
& py -3 (Join-Path $repoRoot "compiler\v3\generate_architecture_package.py")
if ($LASTEXITCODE -ne 0) { throw "M11 gOMP generation failed" }
Copy-Item -Force (Join-Path $repoRoot "reports\v3\context_images\program_06_phase.mem") $workRoot
$defines = @("-d", "GOMP_PHASE")
if ($EnableProperties) { $defines += @("-d", "FORMAL") }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$sources = @(
    "rtl\v3\reconstruction_control\reconstruction_phase_controller.v",
    "verification\v3\m11\tb_m11_htp_phase_replay.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }
Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & (Join-Path $VivadoBin "xvlog.bat") -sv @defines -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M11 gOMP phase compile failed" }
    }
    $snapshot = if ($EnableProperties) { "m11_gomp_phase_property_snapshot" } else { "m11_gomp_phase_snapshot" }
    & (Join-Path $VivadoBin "xelab.bat") tb_m11_htp_phase_replay -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M11 gOMP phase elaboration failed" }
    $output = & (Join-Path $VivadoBin "xsim.bat") $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
} finally { Pop-Location }
$name = if ($EnableProperties) { "gomp_phase_property_xsim.log" } else { "gomp_phase_xsim.log" }
Set-Content (Join-Path $reportRoot $name) $output
$joined = $output -join "`n"
if ($code -ne 0 -or $joined -match "FAIL:|Assertion violation" -or
    $joined -notmatch "M11 GOMP PHASE IMAGE REPLAY PASS") {
    throw "M11 gOMP phase replay failed"
}
Write-Host "VIVADO M11 GOMP PHASE XSIM PASS"
