$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\toolchain.ps1")
$workRoot = Join-Path $repoRoot "work\property_compile\m3"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
$python = Resolve-PythonCommand -RequiredModules @("numpy")
Push-Location $repoRoot
try {
    Invoke-PythonScript -Python $python `
        -ScriptPath "compiler\v3\generate_architecture_package.py" `
        -FailureMessage "M3 architecture package generation failed"
} finally {
    Pop-Location
}
$vivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
foreach ($toolPath in @($xvlog, $xelab)) {
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Vivado 2018.1 tool not found: $toolPath"
    }
}

$sources = @(
    "rtl\v3\context_control\context_write_certifier.v",
    "rtl\v3\context_control\context_image_store.v",
    "rtl\v3\context_control\memory_configuration_store.v",
    "rtl\v3\context_control\context_reservation_guard.v",
    "rtl\v3\context_control\array_context_sequencer.v",
    "rtl\v3\reconstruction_control\reconstruction_phase_controller.v"
) | ForEach-Object { Join-Path $repoRoot $_ }

Push-Location $workRoot
try {
    foreach ($source in $sources) {
        & $xvlog -sv -d FORMAL -i (Join-Path $repoRoot "rtl\v3\include") $source
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado M3 property compile failed for $source"
        }
    }
    foreach ($topName in @(
        "context_image_store",
        "context_write_certifier",
        "memory_configuration_store",
        "array_context_sequencer",
        "reconstruction_phase_controller"
    )) {
        & $xelab $topName -s ("property_" + $topName) -debug typical
        if ($LASTEXITCODE -ne 0) {
            throw "Vivado M3 property elaboration failed for $topName"
        }
    }
} finally {
    Pop-Location
}

Write-Host "VIVADO M3 PROPERTY ELABORATION PASS"
Write-Host "Assertions are executed by scripts/sim/run_m3.ps1 -EnableProperties."
Write-Host "Vivado 2018.1 does not provide a mathematical formal proof engine."
