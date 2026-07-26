param(
    [ValidateSet("v1", "v2")]
    [string]$RtlVersion = "v2",
    [string]$Top = "cgra_top",
    [string]$RunId = "",
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd-HHmmss"
}
if ($RunId -notmatch "^[A-Za-z0-9._-]+$") {
    throw "RunId may contain only letters, digits, dot, underscore, and dash"
}

$vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado tool not found: $vivado"
}

$workDir = Join-Path $repoRoot "work\synth\$RtlVersion\$RunId"
$logDir = Join-Path $repoRoot "logs\synth\$RtlVersion\$RunId"
New-Item -ItemType Directory -Force -Path $workDir, $logDir | Out-Null
$tcl = Join-Path $PSScriptRoot "run_ooc.tcl"

$metadata = [ordered]@{
    flow = "synth"
    rtl_version = $RtlVersion
    run_id = $RunId
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    top = $Top
    started_at = (Get-Date).ToString("o")
    work_dir = $workDir
    log_dir = $logDir
}
$metadata | ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath (Join-Path $logDir "metadata.json")

Push-Location $workDir
try {
    & $vivado -mode batch `
        -journal (Join-Path $logDir "vivado.jou") `
        -log (Join-Path $logDir "vivado.log") `
        -source $tcl `
        -tclargs $RtlVersion $Top $logDir
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado synthesis failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "Synthesis PASS"
Write-Host "Reports: $logDir"
