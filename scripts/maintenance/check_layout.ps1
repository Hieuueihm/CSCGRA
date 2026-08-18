param(
    [switch]$IncludeLegacy
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$errors = @()

foreach ($version in @("v1", "v2")) {
    $configPath = Join-Path $repoRoot "config\rtl-$version.json"
    if (-not (Test-Path -LiteralPath $configPath)) {
        $errors += "Missing config: $configPath"
        continue
    }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $filelist = Join-Path $repoRoot ($config.rtl_filelist -replace "/", "\")
    foreach ($entry in Get-Content -LiteralPath $filelist) {
        if ([string]::IsNullOrWhiteSpace($entry) -or $entry.Trim().StartsWith("#")) {
            continue
        }
        $source = Join-Path $repoRoot ($entry -replace "/", "\")
        if (-not (Test-Path -LiteralPath $source)) {
            $errors += "Missing source in ${version} manifest: $entry"
        }
    }
}

$scanPaths = @(
    (Join-Path $repoRoot "rtl"),
    (Join-Path $repoRoot "verification\v1"),
    (Join-Path $repoRoot "verification\v2"),
    (Join-Path $repoRoot "sw"),
    (Join-Path $repoRoot "scripts\run.ps1"),
    (Join-Path $repoRoot "scripts\sim"),
    (Join-Path $repoRoot "scripts\synth"),
    (Join-Path $repoRoot "config")
)

$goldenManifestPath = Join-Path $repoRoot "models\golden\manifest.json"
if (Test-Path -LiteralPath $goldenManifestPath) {
    $goldenManifest = Get-Content -LiteralPath $goldenManifestPath -Raw | ConvertFrom-Json
    foreach ($goldenEntry in $goldenManifest.sha256.PSObject.Properties) {
        $goldenPath = Join-Path $repoRoot (Join-Path "models\golden" $goldenEntry.Name)
        if (-not (Test-Path -LiteralPath $goldenPath)) {
            $errors += "Missing golden file: $($goldenEntry.Name)"
            continue
        }
        $actualHash = (Get-FileHash -LiteralPath $goldenPath -Algorithm SHA256).Hash.ToUpperInvariant()
        $expectedHash = ([string]$goldenEntry.Value).ToUpperInvariant()
        if ($actualHash -ne $expectedHash) {
            $errors += "Golden hash mismatch: $($goldenEntry.Name)"
        }
    }
}
if ($IncludeLegacy) {
    $scanPaths += Join-Path $repoRoot "scripts\legacy"
}

$patterns = @(
    "D:/vivado_pj",
    "D:\\vivado_pj",
    "CSCGRA.srcs/sources",
    "CSCGRA.srcs\sources"
)
foreach ($scanPath in $scanPaths) {
    if (-not (Test-Path -LiteralPath $scanPath)) {
        continue
    }
    $items = if ((Get-Item -LiteralPath $scanPath) -is [IO.FileInfo]) {
        @(Get-Item -LiteralPath $scanPath)
    } else {
        @(Get-ChildItem -LiteralPath $scanPath -File -Recurse)
    }
    foreach ($item in $items) {
        if ($item.Extension -notin @(".v", ".vh", ".sv", ".f", ".ps1", ".tcl", ".py", ".c", ".h", ".json")) {
            continue
        }
        foreach ($pattern in $patterns) {
            if (Select-String -LiteralPath $item.FullName -SimpleMatch $pattern -Quiet) {
                $errors += "Stale active path '$pattern': $($item.FullName)"
            }
        }
    }
}

if ($errors.Count -ne 0) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Layout validation failed with $($errors.Count) error(s)"
}

Write-Host "Layout validation PASS"
