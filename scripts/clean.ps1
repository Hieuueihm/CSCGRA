param(
    [switch]$WhatIf,
    [switch]$PruneVivadoProjectsInReports
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd("\")
$targets = @()

foreach ($directory in @("work", "logs")) {
    $root = Join-Path $repoRoot $directory
    if (Test-Path -LiteralPath $root) {
        $targets += @(Get-ChildItem -LiteralPath $root -Force |
            Where-Object { $_.Name -ne "README.md" })
    }
}

foreach ($relative in @(".tmp_rtl_check", ".Xil", "xsim.dir", "obj_dir")) {
    $candidate = Join-Path $repoRoot $relative
    if (Test-Path -LiteralPath $candidate) {
        $targets += Get-Item -LiteralPath $candidate -Force
    }
}

if ($PruneVivadoProjectsInReports) {
    $vivadoReportRoot = Join-Path $repoRoot "reports\v3\m13_vivado"
    if (Test-Path -LiteralPath $vivadoReportRoot -PathType Container) {
        foreach ($runDirectory in Get-ChildItem -LiteralPath $vivadoReportRoot `
                -Force -Directory) {
            foreach ($generatedName in @("project", "package_project", "packaged_ip")) {
                $generatedPath = Join-Path $runDirectory.FullName $generatedName
                if (Test-Path -LiteralPath $generatedPath -PathType Container) {
                    $targets += Get-Item -LiteralPath $generatedPath -Force
                }
            }
        }
    }
}

$disposableExtensions = @(
    ".jou", ".log", ".pb", ".wdb", ".str", ".dmp", ".rpt", ".dcp",
    ".bit", ".ltx", ".exe", ".dll", ".o", ".obj"
)
$targets += @(Get-ChildItem -LiteralPath $repoRoot -Force -File |
    Where-Object {
        $_.Extension -in $disposableExtensions -or
        $_.Name -like "xvlog_*.out" -or $_.Name -like "xvlog_*.err"
    })

foreach ($target in @($targets | Sort-Object FullName -Unique)) {
    $resolved = [IO.Path]::GetFullPath($target.FullName)
    if (-not $resolved.StartsWith($repoRoot + "\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove path outside repository: $resolved"
    }
    if ($resolved -eq $repoRoot) {
        throw "Refusing to remove repository root"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force -WhatIf:$WhatIf
    if ($WhatIf) { Write-Host "Would remove $resolved" }
    else { Write-Host "Removed $resolved" }
}

$reportMessage = if ($PruneVivadoProjectsInReports) {
    "Report text, logs, summaries, artifacts, and checkpoints were preserved."
} else {
    "reports/ was preserved."
}
Write-Host "Generated project state is clean. Source, archive/, and .zcode/ were preserved. $reportMessage"
