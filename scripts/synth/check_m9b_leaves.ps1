param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference="Stop"
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado=Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
$tcl=Join-Path $PSScriptRoot "check_m9b_leaf.tcl"
$leaves=@(
    @{Top="proxy_candidate_collector"; BramMax=0; Aggregate=$true},
    @{Top="support_state_manager"; BramMax=1; Aggregate=$true},
    @{Top="support_coefficient_remapper"; BramMax=0; Aggregate=$false}
)
foreach($leaf in $leaves){
    $top=$leaf.Top
    $reportDir=Join-Path $repoRoot "reports\v3\m9b_vivado\$top"
    $workDir=Join-Path $repoRoot "work\synth\m9b_leaf\$top"
    New-Item -ItemType Directory -Force -Path $reportDir,$workDir | Out-Null
    Push-Location $workDir
    try {
        & $vivado -mode batch -journal (Join-Path $reportDir "vivado.jou") -log (Join-Path $reportDir "vivado.log") -source $tcl -tclargs $repoRoot $reportDir $top $leaf.BramMax
        if($LASTEXITCODE -ne 0){throw "M9b leaf synthesis failed: $top"}
    } finally { Pop-Location }
}
$totals=[ordered]@{lut_count=0;ff_count=0;ramb36_count=0;ramb18_count=0;dsp48_count=0}
$minimumWns=$null
foreach($leaf in $leaves){
    $summary=Get-Content (Join-Path $repoRoot "reports\v3\m9b_vivado\$($leaf.Top)\summary.txt")
    $values=@{}
    foreach($line in $summary){$parts=$line -split '=',2;if($parts.Count -eq 2){$values[$parts[0]]=$parts[1]}}
    if($leaf.Aggregate){
        foreach($key in @('lut_count','ff_count','ramb36_count','ramb18_count','dsp48_count')){$totals[$key]+=[int]$values[$key]}
        $wns=[double]$values['post_synth_wns_ns']; if($null -eq $minimumWns -or $wns -lt $minimumWns){$minimumWns=$wns}
    }
}
$aggregate=@(
    "method=non_overlapping_leaf_ooc",
    "minimum_post_synth_wns_ns=$minimumWns",
    "lut_count=$($totals.lut_count)",
    "ff_count=$($totals.ff_count)",
    "ramb36_count=$($totals.ramb36_count)",
    "ramb18_count=$($totals.ramb18_count)",
    "dsp48_count=$($totals.dsp48_count)"
)
$aggregate | Set-Content (Join-Path $repoRoot "reports\v3\m9b_vivado\summary.txt")
Write-Host "M9b non-overlapping leaf OOC PASS minimum WNS=$minimumWns LUT=$($totals.lut_count) FF=$($totals.ff_count) BRAM36=$($totals.ramb36_count) BRAM18=$($totals.ramb18_count) DSP=$($totals.dsp48_count)"
