param([string]$VivadoBin="C:\Xilinx\Vivado\2018.1\bin")
$ErrorActionPreference="Stop"
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$vivado=Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
$tops=@("reconstruction_result_writer", "m12_result_dma_integration", "m12_lifecycle_top")
foreach($top in $tops){
    $reportDir=Join-Path $repoRoot "reports\v3\m12_vivado\$top"
    $workDir=Join-Path $repoRoot "work\synth\m12\$top"
    New-Item -ItemType Directory -Force -Path $reportDir,$workDir | Out-Null
    Push-Location $workDir
    try {
        & $vivado -mode batch -journal (Join-Path $reportDir "vivado.jou") `
            -log (Join-Path $reportDir "vivado.log") `
            -source (Join-Path $PSScriptRoot "check_m12.tcl") `
            -tclargs $repoRoot $reportDir $top
        if($LASTEXITCODE -ne 0){throw "M12 synthesis failed: $top"}
    } finally { Pop-Location }
}
Write-Host "M12 OOC PASS"
