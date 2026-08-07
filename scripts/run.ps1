param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("sim", "synth")]
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
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
