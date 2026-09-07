param(
    [string]$RunId = ""
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

$verilator = Get-Command verilator_bin -ErrorAction SilentlyContinue
if ($null -eq $verilator) {
    $candidate = "C:\msys64\ucrt64\bin\verilator_bin.exe"
    if (Test-Path -LiteralPath $candidate) {
        $verilatorPath = $candidate
        if ([string]::IsNullOrWhiteSpace($env:VERILATOR_ROOT)) {
            $env:VERILATOR_ROOT = "C:\msys64\ucrt64\share\verilator"
        }
    } else {
        $wrapper = Get-Command verilator -ErrorAction SilentlyContinue
        if ($null -eq $wrapper) { throw "Verilator is required for the RTL lint gate" }
        $verilatorPath = $wrapper.Source
    }
} else {
    $verilatorPath = $verilator.Source
}

$verilatorPrefix = Split-Path -Parent (Split-Path -Parent $verilatorPath)
$bundledRoot = Join-Path $verilatorPrefix "share\verilator"
if (Test-Path -LiteralPath $bundledRoot) {
    $env:VERILATOR_ROOT = $bundledRoot
}

$policyPath = Join-Path $repoRoot "config\verilator-lint-policy.json"
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$filelist = Join-Path $repoRoot "rtl\v2\files.f"
$rtlFiles = @(Get-Content -LiteralPath $filelist |
    Where-Object { $_ -and -not $_.Trim().StartsWith("#") } |
    ForEach-Object { Join-Path $repoRoot ($_ -replace "/", "\") })
$args = @(
    "--lint-only", "--top-module", "cgra_top", "-Wall", "-Wno-fatal",
    "-I$(Join-Path $repoRoot 'rtl\v2\control')",
    "-I$(Join-Path $repoRoot 'rtl\v2\solver')"
) + $rtlFiles

$output = @(& $verilatorPath @args 2>&1 | ForEach-Object { $_.ToString() })
$counts = @{}
foreach ($line in $output) {
    if ($line -match '^%Warning-([A-Z0-9_]+):') {
        $name = $Matches[1]
        if (-not $counts.ContainsKey($name)) { $counts[$name] = 0 }
        $counts[$name]++
    }
}

$errors = @($output | Where-Object { $_ -match '^%Error' })
$policyNames = @($policy.allowed_max.PSObject.Properties.Name)
foreach ($name in @($counts.Keys)) {
    if ($name -in @($policy.always_fatal)) {
        $errors += "Fatal warning category present: $name ($($counts[$name]))"
    } elseif ($name -notin $policyNames) {
        $errors += "Unreviewed warning category: $name ($($counts[$name]))"
    } else {
        $maximum = [int]$policy.allowed_max.$name
        if ($counts[$name] -gt $maximum) {
            $errors += "Warning backlog increased: $name $($counts[$name]) > $maximum"
        }
    }
}

$logDir = Join-Path $repoRoot "logs\lint\v2\$RunId"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$output | Set-Content -LiteralPath (Join-Path $logDir "verilator.log")
$identity = Get-ProjectSourceIdentity -RepoRoot $repoRoot -RtlVersion "v2"
[ordered]@{
    flow = "lint"
    run_id = $RunId
    source_identity = $identity
    warning_counts = $counts
    policy = "config/verilator-lint-policy.json"
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logDir "metadata.json")

$counts.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Write-Host ("LINT {0}={1}" -f $_.Name, $_.Value)
}
if ($errors.Count -ne 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "RTL lint policy failed"
}

Write-Host "RTL LINT POLICY: PASS"
