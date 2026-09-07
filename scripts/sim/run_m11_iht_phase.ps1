param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workName = if ($EnableProperties) { "m11_iht_phase_property_xsim" } else { "m11_iht_phase_xsim" }
$workRoot = Join-Path $repoRoot "work\$workName"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$reportRoot = Join-Path $repoRoot "reports\v3\m11_vivado"
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }

& py -3 (Join-Path $repoRoot "compiler\v3\generate_architecture_package.py")
if ($LASTEXITCODE -ne 0) { throw "M11 IHT program generation failed" }
Copy-Item -Force -LiteralPath `
    (Join-Path $repoRoot "reports\v3\context_images\program_02_phase.mem") `
    -Destination $workRoot

$sources = @(
    "rtl\v3\reconstruction_control\reconstruction_phase_controller.v",
    "verification\v3\m11\tb_m11_iht_phase_replay.sv"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv @defines -i $includeRoot $source
        if ($LASTEXITCODE -ne 0) { throw "M11 IHT phase compile failed: $source" }
    }
    $snapshot = if ($EnableProperties) {
        "m11_iht_phase_property_snapshot"
    } else {
        "m11_iht_phase_snapshot"
    }
    & $xelab tb_m11_iht_phase_replay -s $snapshot -debug typical
    if ($LASTEXITCODE -ne 0) { throw "M11 IHT phase elaboration failed" }
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
} finally {
    Pop-Location
}

$joined = $output -join "`n"
$logName = if ($EnableProperties) {
    "iht_phase_property_xsim.log"
} else {
    "iht_phase_xsim.log"
}
Set-Content -LiteralPath (Join-Path $reportRoot $logName) -Value $output
if ($code -ne 0 -or $joined -match "FAIL:|Assertion violation") {
    throw "M11 IHT phase replay failed"
}
if ($joined -notmatch "M11 IHT PHASE IMAGE REPLAY PASS") {
    throw "M11 IHT phase PASS marker missing"
}
Write-Host "VIVADO M11 IHT PHASE XSIM PASS"
