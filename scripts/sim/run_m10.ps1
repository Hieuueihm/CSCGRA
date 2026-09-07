param(
    [switch]$EnableProperties,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mode = if ($EnableProperties) { "property" } else { "normal" }
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$defines = if ($EnableProperties) { @("-d", "FORMAL") } else { @() }
$includeRoot = Join-Path $repoRoot "rtl\v3\include"
$tests = @(
    @{
        Name = "normal_residual_checker"
        Top = "tb_normal_residual_checker"
        Sources = @(
            "rtl\v3\refinement\certificate_limit_unit.v",
            "rtl\v3\refinement\normal_residual_checker.v",
            "verification\v3\m10\tb_normal_residual_checker.sv"
        )
        Marker = "M10 NORMAL RESIDUAL CHECKER PASS"
    },
    @{
        Name = "restricted_refinement_state"
        Top = "tb_restricted_refinement_state"
        Sources = @(
            "rtl\v3\refinement\restricted_refinement_state.v",
            "verification\v3\m10\tb_restricted_refinement_state.sv"
        )
        Marker = "M10 RESTRICTED REFINEMENT STATE PASS"
    },
    @{
        Name = "refinement_integration"
        Top = "tb_m10_refinement_integration"
        Sources = @(
            "rtl\v3\refinement\certificate_limit_unit.v",
            "rtl\v3\refinement\normal_residual_checker.v",
            "rtl\v3\refinement\restricted_refinement_state.v",
            "rtl\v3\integration\m10_refinement_integration.v",
            "verification\v3\m10\tb_m10_refinement_integration.sv"
        )
        Marker = "M10 REFINEMENT INTEGRATION PASS"
    }
)
foreach ($test in $tests) {
    $workRoot = Join-Path $repoRoot "work\m10_$($test.Name)_$mode"
    $logPath = Join-Path $workRoot "console.log"
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
    Push-Location $workRoot
    try {
        foreach ($source in $test.Sources) {
            $sourcePath = Join-Path $repoRoot $source
            & $xvlog -sv @defines -i $includeRoot $sourcePath
            if ($LASTEXITCODE -ne 0) { throw "M10 compile failed: $source" }
        }
        $snapshot = "m10_$($test.Name)_${mode}_snapshot"
        & $xelab $test.Top -s $snapshot -debug typical
        if ($LASTEXITCODE -ne 0) { throw "M10 elaboration failed: $($test.Top)" }
        $output = & $xsim $snapshot -runall 2>&1
        $code = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        Set-Content -LiteralPath $logPath -Value $output
        if ($code -ne 0) { throw "M10 simulation failed: $($test.Top)" }
    } finally {
        Pop-Location
    }
    $text = Get-Content -LiteralPath $logPath -Raw
    if ($text -match "FAIL:|Assertion violation") {
        throw "M10 failure marker: $($test.Top)"
    }
    if ($text -notmatch [regex]::Escape($test.Marker)) {
        throw "M10 PASS marker missing: $($test.Top)"
    }
}
Write-Host "VIVADO M10 $($mode.ToUpperInvariant()) XSIM PASS"
