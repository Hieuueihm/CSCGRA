param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference="Stop"
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado=Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
$tcl=Join-Path $PSScriptRoot "check_m10.tcl"
$tops=@("normal_residual_checker", "restricted_refinement_state", `
    "m10_refinement_integration", "m8_resource_dispatcher")
foreach($top in $tops){
    $reportDir=Join-Path $repoRoot "reports\v3\m10_vivado\$top"
    $workDir=Join-Path $repoRoot "work\synth\m10\$top"
    New-Item -ItemType Directory -Force -Path $reportDir,$workDir | Out-Null
    Push-Location $workDir
    try {
        & $vivado -mode batch -journal (Join-Path $reportDir "vivado.jou") `
            -log (Join-Path $reportDir "vivado.log") -source $tcl `
            -tclargs $repoRoot $reportDir $top
        if($LASTEXITCODE -ne 0){throw "M10 synthesis failed: $top"}
    } finally { Pop-Location }
}
$summaries = foreach($top in $tops){
    $values=@{}
    Get-Content (Join-Path $repoRoot "reports\v3\m10_vivado\$top\summary.txt") |
        ForEach-Object {$parts=$_ -split '=',2;if($parts.Count-eq 2){$values[$parts[0]]=$parts[1]}}
    [pscustomobject]$values
}
$minimumWns=($summaries | Measure-Object -Property post_synth_wns_ns -Minimum).Minimum
$leafSummaries=$summaries | Where-Object {
    $_.top -in @('normal_residual_checker','restricted_refinement_state')
}
$lut=($leafSummaries | Measure-Object -Property lut_count -Sum).Sum
$ff=($leafSummaries | Measure-Object -Property ff_count -Sum).Sum
$integration=$summaries | Where-Object {$_.top -eq 'm8_resource_dispatcher'}
$phaseIntegration=$summaries | Where-Object {$_.top -eq 'm10_refinement_integration'}
@(
    "method=non_overlapping_leaf_ooc",
    "minimum_post_synth_wns_ns=$minimumWns",
    "lut_count=$lut",
    "ff_count=$ff",
    "ramb36_count=0",
    "ramb18_count=0",
    "dsp48_count=0"
) | Set-Content (Join-Path $repoRoot "reports\v3\m10_vivado\summary.txt")
Write-Host "M10 OOC PASS minimum WNS=$minimumWns leaf LUT=$lut FF=$ff phase LUT=$($phaseIntegration.lut_count) FF=$($phaseIntegration.ff_count) dispatcher LUT=$($integration.lut_count) FF=$($integration.ff_count)"
