param(
    [ValidateSet("all", "dma", "factor", "matrix", "wide")]
    [string]$Task = "all",
    [string]$RunId = "",
    [switch]$LintOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\common\project_context.ps1")

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd-HHmmss"
}
if ($RunId -notmatch "^[A-Za-z0-9._-]+$") {
    throw "RunId may contain only letters, digits, dot, underscore, and dash"
}

$tasks = if ($Task -eq "all") { @("dma", "factor", "matrix", "wide") } else { @($Task) }
$formalRoot = Join-Path $repoRoot "verification\formal"
$workRoot = Join-Path $repoRoot "work\formal\$RunId"
$logRoot = Join-Path $repoRoot "logs\formal\$RunId"
New-Item -ItemType Directory -Force -Path $workRoot, $logRoot | Out-Null

$identity = Get-ProjectSourceIdentity -RepoRoot $repoRoot -RtlVersion "v2"
$metadata = [ordered]@{
    flow = if ($LintOnly) { "formal-syntax" } else { "formal-prove" }
    run_id = $RunId
    tasks = $tasks
    source_identity = $identity
    started_at = (Get-Date).ToString("o")
}
$metadata | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $logRoot "metadata.json")

$sources = @{
    dma = @(
        (Join-Path $repoRoot "rtl\v2\control\dma_ctrl.v"),
        (Join-Path $formalRoot "dma_ctrl_formal.sv")
    )
    factor = @(
        (Join-Path $repoRoot "rtl\v2\control\factor_check_unit.v"),
        (Join-Path $formalRoot "factor_check_unit_formal.sv")
    )
    matrix = @(
        (Join-Path $repoRoot "rtl\v2\solver\ls_matrix_service.v"),
        (Join-Path $formalRoot "ls_matrix_service_formal.sv")
    )
    wide = @(
        (Join-Path $repoRoot "rtl\v2\control\wide_mul_sequencer.v"),
        (Join-Path $formalRoot "wide_mul_sequencer_formal.sv")
    )
}
$tops = @{
    dma = "dma_ctrl_formal"
    factor = "factor_check_unit_formal"
    matrix = "ls_matrix_service_formal"
    wide = "wide_mul_sequencer_formal"
}

if ($LintOnly) {
    $iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
    if ($null -eq $iverilog) {
        throw "iverilog is required for formal syntax elaboration"
    }
    foreach ($name in $tasks) {
        $output = Join-Path $workRoot "$name.vvp"
        & $iverilog.Source -g2012 -D FORMAL -s $tops[$name] -o $output @($sources[$name])
        if ($LASTEXITCODE -ne 0) {
            throw "Formal syntax elaboration failed: $name"
        }
        Write-Host "FORMAL SYNTAX PASS: $name"
    }
    Write-Host "Formal harness syntax PASS; no mathematical proof was run."
    exit 0
}

$sby = Get-Command sby -ErrorAction SilentlyContinue
if ($null -eq $sby) {
    throw "SymbiYosys (sby) is not installed. Install an OSS CAD Suite toolchain, then rerun; use -LintOnly only for syntax elaboration."
}

$manifest = Join-Path $formalRoot "formal.sby"
foreach ($name in $tasks) {
    $taskWork = Join-Path $workRoot $name
    & $sby.Source -f -d $taskWork $manifest $name
    if ($LASTEXITCODE -ne 0) {
        throw "Formal proof failed: $name"
    }
    Write-Host "FORMAL PROOF PASS: $name"
}

Write-Host "All requested formal proofs PASS"
Write-Host "RTL SHA-256: $($identity.rtl_sha256)"
