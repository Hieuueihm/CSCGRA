param(
    [switch]$SkipModels,
    [switch]$SkipSimulation,
    [switch]$SkipProperties,
    [switch]$SkipSynthesis
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Script,
        [string[]]$Arguments = @()
    )

    Write-Host "=== $Name ==="
    & $powershell -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $repoRoot $Script) @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed"
    }
}

Push-Location $repoRoot
try {
    if (-not $SkipModels) {
        $python = Resolve-PythonCommand -RequiredModules @("numpy")
        Write-Host "=== Python model/compiler regression ==="
        & $python.Executable @($python.PrefixArguments) -m unittest discover `
            -s "verification\v3" -p "test_*.py"
        if ($LASTEXITCODE -ne 0) {
            throw "Python model/compiler regression failed"
        }
    }

    $verilator = Get-Command verilator -ErrorAction SilentlyContinue
    if ($verilator) {
        Write-Host "=== Verilator RTL lint ==="
        & $verilator.Source --lint-only --language 1800-2012 -Wall `
            -Wno-fatal -Irtl/v3/include -f rtl/v3/files.f --top-module top
        if (-not $?) {
            throw "Verilator RTL lint failed"
        }
    } else {
        Write-Warning "Verilator not found; RTL lint skipped"
    }

    if (-not $SkipSimulation) {
        Invoke-Gate "M1 AXI4-Lite simulation" `
            "scripts\sim\run_axilite_control.ps1"
        Invoke-Gate "M2 DMA/configuration simulation" `
            "scripts\sim\run_m2.ps1" @("-EnableProperties")
        Invoke-Gate "M3 context/control simulation" `
            "scripts\sim\run_m3.ps1" @("-EnableProperties")
        Invoke-Gate "M4 stream/preload simulation" `
            "scripts\sim\run_m4.ps1" @("-EnableProperties")
        Invoke-Gate "M1-M4 integration simulation" `
            "scripts\sim\run_m1_m4_integration.ps1" @("-EnableProperties")
        Invoke-Gate "M5 arithmetic simulation" `
            "scripts\sim\run_m5.ps1" @("-EnableProperties")
        Invoke-Gate "M6 CGRA simulation" `
            "scripts\sim\run_m6.ps1" @("-EnableProperties")
        Invoke-Gate "M7 generated Phi simulation" `
            "scripts\sim\run_m7.ps1" @("-EnableProperties")
    }

    if (-not $SkipProperties) {
        Invoke-Gate "M1 property elaboration" `
            "scripts\formal\check_axilite_control_properties.ps1"
        foreach ($milestone in 2..7) {
            Invoke-Gate "M$milestone property elaboration" `
                "scripts\formal\check_m${milestone}_properties.ps1"
        }
    }

    if (-not $SkipSynthesis) {
        Invoke-Gate "M1 OOC synthesis" `
            "scripts\synth\check_axilite_control.ps1"
        foreach ($milestone in 2..4) {
            Invoke-Gate "M$milestone OOC synthesis" `
                "scripts\synth\check_m${milestone}.ps1"
        }
        Invoke-Gate "M1-M4 integration OOC synthesis" `
            "scripts\synth\check_m1_m4_integration.ps1"
        foreach ($milestone in 5..7) {
            Invoke-Gate "M$milestone OOC synthesis" `
                "scripts\synth\check_m${milestone}.ps1"
        }
    }
} finally {
    Pop-Location
}

Write-Host "V3 M1-M7 REGRESSION PASS"
