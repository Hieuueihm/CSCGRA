param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("check", "formal", "sim", "synth", "impl")]
    [string]$Flow,

    [ValidateSet("v1", "v2")]
    [string]$RtlVersion = "v2",

    [int[]]$Cases = @(0, 1, 2, 3, 4, 5, 6, 7),
    [int[]]$Algorithms = @(),
    [switch]$ProfileStates,
    [string]$Top = "cgra_top",
    [string]$RunId = "",
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

switch ($Flow) {
    "check" {
        & python (Join-Path $PSScriptRoot "maintenance\check_project_consistency.py")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & (Join-Path $PSScriptRoot "maintenance\check_layout.ps1")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & (Join-Path $PSScriptRoot "maintenance\lint_rtl.ps1") -RunId $RunId
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & (Join-Path $PSScriptRoot "formal\run_formal.ps1") -Task all -LintOnly -RunId $RunId
    }
    "formal" {
        & (Join-Path $PSScriptRoot "formal\run_formal.ps1") -Task all -RunId $RunId
    }
    "sim" {
        & (Join-Path $PSScriptRoot "sim\run_regression.ps1") `
            -RtlVersion $RtlVersion `
            -Cases $Cases `
            -Algorithms $Algorithms `
            -ProfileStates:$ProfileStates `
            -RunId $RunId `
            -VivadoBin $VivadoBin
    }
    "synth" {
        & (Join-Path $PSScriptRoot "synth\run_ooc.ps1") `
            -RtlVersion $RtlVersion `
            -Top $Top `
            -RunId $RunId `
            -VivadoBin $VivadoBin
    }
    "impl" {
        & (Join-Path $PSScriptRoot "impl\run_ooc.ps1") `
            -RtlVersion $RtlVersion `
            -Top $Top `
            -RunId $RunId `
            -VivadoBin $VivadoBin
    }
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
