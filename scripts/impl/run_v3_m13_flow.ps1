[CmdletBinding()]
param(
    [ValidateSet("Preflight", "Synth", "Implement", "All", "ReportOnly")]
    [string]$Stage = "All",
    [string]$RunTag = "",
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin",
    [string]$ScratchRoot = "C:\vivado_scratch\v3_m13",
    [string]$ReportRoot = "",
    [ValidateRange(1, 64)][int]$Jobs = 8,
    [ValidateRange(1, 10080)][int]$TimeoutMinutes = 180,
    [ValidateRange(0.1, 1024.0)][double]$MinScratchFreeGB = 20.0,
    [ValidateRange(0.1, 1024.0)][double]$MinReportFreeGB = 0.5,
    [string]$CorrectnessSmallResults = "",
    [string]$CorrectnessScaleResults = "",
    [switch]$Resume,
    [switch]$SkipCorrectnessGate,
    [switch]$AllowConcurrentVivado,
    [switch]$PublishCheckpoints,
    [switch]$CleanScratchOnSuccess
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
if ([string]::IsNullOrWhiteSpace($ReportRoot)) {
    $ReportRoot = Join-Path $repoRoot "reports\v3\m13_vivado\managed_flow"
}
if ([string]::IsNullOrWhiteSpace($RunTag)) {
    $RunTag = Get-Date -Format "yyyyMMdd_HHmmss"
}
if ($RunTag -notmatch "^[A-Za-z0-9._-]+$") {
    throw "RunTag may contain only letters, digits, dot, underscore and dash"
}
if ([string]::IsNullOrWhiteSpace($CorrectnessSmallResults)) {
    $CorrectnessSmallResults = Join-Path $repoRoot `
        "reports\v3\m13_correctness_sweep_priority_mux_small_20260905\results.json"
}
if ([string]::IsNullOrWhiteSpace($CorrectnessScaleResults)) {
    $CorrectnessScaleResults = Join-Path $repoRoot `
        "reports\v3\m13_correctness_sweep_priority_mux_scale_20260905\results.json"
}

$vivado = Join-Path $VivadoBin "vivado.bat"
$flowTcl = Join-Path $PSScriptRoot "run_v3_m13_flow.tcl"
$manifestPath = Join-Path $repoRoot "rtl\v3\files.f"
$constraintPath = Join-Path $repoRoot "constraints\v3\m13_ooc.xdc"
$scratchRootFull = [System.IO.Path]::GetFullPath($ScratchRoot)
$reportRootFull = [System.IO.Path]::GetFullPath($ReportRoot)
$runRoot = Join-Path $scratchRootFull $RunTag
$publishedRoot = Join-Path $reportRootFull $RunTag
$metadataPath = Join-Path $runRoot "run_metadata.json"
$consoleLog = Join-Path $runRoot "vivado_console.log"
$commandFile = Join-Path $runRoot "invoke_vivado.cmd"
$statusJson = Join-Path $runRoot "run_status.json"

function Get-DriveFreeGB {
    param([Parameter(Mandatory)][string]$Path)
    $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    $drive = [System.IO.DriveInfo]::new($root)
    return [math]::Round($drive.AvailableFreeSpace / 1GB, 3)
}

function Assert-FreeSpace {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][double]$MinimumGB,
        [Parameter(Mandatory)][string]$Label
    )
    $freeGB = Get-DriveFreeGB -Path $Path
    if ($freeGB -lt $MinimumGB) {
        throw "$Label has only $freeGB GB free; at least $MinimumGB GB is required: $Path"
    }
    Write-Host "$Label free space: $freeGB GB"
}

function Get-ManifestSources {
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Missing source manifest: $manifestPath"
    }
    $sources = @()
    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        $trimmed = $line.Trim()
        if (!$trimmed -or $trimmed.StartsWith("+")) { continue }
        $source = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $trimmed))
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Manifest source does not exist: $source"
        }
        $sources += $source
    }
    if ($sources.Count -eq 0) { throw "Source manifest contains no RTL files" }
    return $sources
}

function Test-CorrectnessMatrix {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Label correctness evidence: $Path"
    }
    $rows = @(Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json |
        ForEach-Object { $_ })
    if ($rows.Count -ne 24) {
        throw "$Label correctness evidence has $($rows.Count) rows; expected 24"
    }
    $failed = @($rows | Where-Object { $_.status -ne "PASS" })
    if ($failed.Count -ne 0) {
        throw "$Label correctness evidence contains $($failed.Count) non-PASS rows"
    }
    $keys = @($rows | ForEach-Object { "$($_.algorithm)|$($_.profile)" } |
        Sort-Object -Unique)
    if ($keys.Count -ne 24) {
        throw "$Label evidence does not contain 8 algorithms x 3 profiles"
    }
    $expectedAlgorithms = @("omp", "cosamp", "iht", "htp", "sp", "gp", "gomp", "mp")
    $expectedProfiles = @("strict_paper", "balanced_variant", "fast_variant")
    $actualAlgorithms = @($rows.algorithm | Sort-Object -Unique)
    $actualProfiles = @($rows.profile | Sort-Object -Unique)
    if (@(Compare-Object $expectedAlgorithms $actualAlgorithms).Count -ne 0 -or
            @(Compare-Object $expectedProfiles $actualProfiles).Count -ne 0) {
        throw "$Label evidence has an unexpected algorithm or profile set"
    }
    if (@($rows | Where-Object { [int64]$_.cycles -le 0 }).Count -ne 0) {
        throw "$Label correctness evidence contains non-positive cycle counts"
    }
    $missingArtifacts = @($rows | Where-Object {
        !(Test-Path -LiteralPath $_.log -PathType Leaf) -or
        !(Test-Path -LiteralPath $_.golden_summary -PathType Leaf)
    })
    if ($missingArtifacts.Count -ne 0) {
        throw "$Label correctness evidence references missing logs or golden summaries"
    }
    return Get-Item -LiteralPath $Path
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory)][string]$Child,
        [Parameter(Mandatory)][string]$Parent
    )
    $childFull = [System.IO.Path]::GetFullPath($Child).TrimEnd('\')
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    return $childFull.StartsWith($parentFull + '\',
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Publish-RunArtifacts {
    New-Item -ItemType Directory -Force -Path $publishedRoot | Out-Null
    foreach ($name in @("reports", "run_metadata.json", "run_status.json",
            "flow_status.txt", "vivado_console.log", "invoke_vivado.cmd")) {
        $source = Join-Path $runRoot $name
        if (Test-Path -LiteralPath $source) {
            $item = Get-Item -LiteralPath $source
            if ($item.PSIsContainer) {
                $destination = Join-Path $publishedRoot $name
                New-Item -ItemType Directory -Force -Path $destination | Out-Null
                Get-ChildItem -LiteralPath $source -Force | Copy-Item `
                    -Destination $destination -Recurse -Force
            } else {
                Copy-Item -LiteralPath $source -Destination $publishedRoot -Force
            }
        }
    }
    if ($PublishCheckpoints) {
        $checkpointSource = Join-Path $runRoot "checkpoints"
        if (Test-Path -LiteralPath $checkpointSource) {
            $checkpointDestination = Join-Path $publishedRoot "checkpoints"
            New-Item -ItemType Directory -Force -Path $checkpointDestination |
                Out-Null
            Get-ChildItem -LiteralPath $checkpointSource -Force | Copy-Item `
                -Destination $checkpointDestination -Recurse -Force
        }
    }
}

function Convert-SummaryTextToJson {
    $summaryText = Join-Path $runRoot "reports\summary.txt"
    if (!(Test-Path -LiteralPath $summaryText -PathType Leaf)) { return }
    $summary = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $summaryText) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $summary[$parts[0]] = $parts[1] }
    }
    $summary["flow_state"] = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    $summary["run_tag"] = $RunTag
    $summary["finish_time"] = (Get-Date).ToString("o")
    $summary | ConvertTo-Json | Set-Content `
        -LiteralPath (Join-Path $runRoot "reports\summary.json") -Encoding UTF8
}

foreach ($requiredFile in @($vivado, $flowTcl, $constraintPath)) {
    if (!(Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file not found: $requiredFile"
    }
}
$rtlSources = @(Get-ManifestSources)
$headerSources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "rtl\v3\include") `
    -Filter "*.vh" -File -Recurse | Select-Object -ExpandProperty FullName)
$designSources = @($rtlSources + $headerSources)
$topSource = Join-Path $repoRoot `
    "rtl\v3\integration\m13_compute_lifecycle_integration.v"
if (!(Test-Path -LiteralPath $topSource -PathType Leaf) -or
        !(Select-String -LiteralPath $topSource `
            -Pattern '^\s*module\s+m13_compute_lifecycle_integration\b' -Quiet)) {
    throw "Top module declaration not found: m13_compute_lifecycle_integration"
}
$xdcText = Get-Content -LiteralPath $constraintPath -Raw
if ($xdcText -notmatch 'create_clock.+-period\s+10\.000' -or
        $xdcText -notmatch 'set_clock_uncertainty\s+0\.200') {
    throw "M13 OOC constraint must remain 10.000 ns with 0.200 ns uncertainty"
}

New-Item -ItemType Directory -Force -Path $scratchRootFull,$reportRootFull | Out-Null
Assert-FreeSpace -Path $scratchRootFull -MinimumGB $MinScratchFreeGB `
    -Label "Scratch drive"
$requiredReportFreeGB = if ($PublishCheckpoints) {
    [math]::Max($MinReportFreeGB, 2.0)
} else { $MinReportFreeGB }
Assert-FreeSpace -Path $reportRootFull -MinimumGB $requiredReportFreeGB `
    -Label "Report drive"

$activeTools = @(Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -in @("vivado", "vivado_lab", "xsim", "xelab", "xvlog") })
if ($activeTools.Count -ne 0 -and !$AllowConcurrentVivado) {
    $processText = ($activeTools | ForEach-Object {
        "$($_.ProcessName):$($_.Id)"
    }) -join ", "
    throw "Existing Vivado/XSim processes detected: $processText"
}

$runExists = Test-Path -LiteralPath $runRoot
if ($runExists -and !$Resume) {
    throw "Scratch RunTag exists; use -Resume or choose another RunTag: $runRoot"
}
if (!$runExists) {
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
}

$correctnessItems = @()
if (!$SkipCorrectnessGate) {
    $correctnessItems += Test-CorrectnessMatrix -Path $CorrectnessSmallResults `
        -Label "small"
    $correctnessItems += Test-CorrectnessMatrix -Path $CorrectnessScaleResults `
        -Label "scale"
    $newestRtl = $designSources | Get-Item | Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    $oldestEvidence = $correctnessItems | Sort-Object LastWriteTimeUtc |
        Select-Object -First 1
    if ($newestRtl.LastWriteTimeUtc -gt $oldestEvidence.LastWriteTimeUtc) {
        throw "Correctness evidence is stale: RTL $($newestRtl.FullName) is newer than $($oldestEvidence.FullName). Rerun both 24/24 matrices or use -SkipCorrectnessGate only for exploratory synthesis."
    }
    Write-Host "Correctness gate: 48/48 PASS and evidence is newer than RTL"
}

$hashInputs = @(
    $manifestPath,
    $constraintPath,
    $flowTcl,
    $PSCommandPath,
    (Join-Path $repoRoot "scripts\synth\load_v3_xpm_memory.tcl")
) + $designSources
$sourceHashes = foreach ($path in $hashInputs) {
    $item = Get-Item -LiteralPath $path
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    [ordered]@{
        path = $item.FullName
        sha256 = $hash.Hash.ToLowerInvariant()
        last_write_utc = $item.LastWriteTimeUtc.ToString("o")
    }
}

if ($Resume) {
    if (!(Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Resume requires existing run metadata: $metadataPath"
    }
    $previousMetadata = Get-Content -LiteralPath $metadataPath -Raw |
        ConvertFrom-Json
    $previousHashes = @{}
    foreach ($entry in $previousMetadata.source_hashes) {
        $previousHashes[$entry.path.ToLowerInvariant()] = $entry.sha256
    }
    foreach ($entry in $sourceHashes) {
        $key = $entry.path.ToLowerInvariant()
        if (!$previousHashes.ContainsKey($key) -or
                $previousHashes[$key] -ne $entry.sha256) {
            throw "Resume rejected because source or constraint changed: $($entry.path)"
        }
    }
}

$vivadoVersion = "unknown"
Push-Location $scratchRootFull
try {
    $versionOutput = & $vivado -version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $vivadoVersion = ($versionOutput | Select-Object -First 1).ToString().Trim()
    }
} finally {
    Pop-Location
}
$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>$null)
$gitStatus = @(& git -C $repoRoot status --short 2>$null)
$metadata = [ordered]@{
    schema_version = 1
    run_tag = $RunTag
    requested_stage = $Stage
    start_time = (Get-Date).ToString("o")
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    repo_root = $repoRoot
    scratch_run_root = $runRoot
    published_root = $publishedRoot
    part = "xczu7ev-ffvc1156-2-e"
    top = "m13_compute_lifecycle_integration"
    target_clock_mhz = 100
    clock_period_ns = 10.000
    clock_uncertainty_ns = 0.200
    jobs = $Jobs
    timeout_minutes = $TimeoutMinutes
    vivado = $vivado
    vivado_version = $vivadoVersion
    git_commit = ($gitCommit -join "").Trim()
    git_status = $gitStatus
    correctness_gate_skipped = [bool]$SkipCorrectnessGate
    correctness_evidence = @($CorrectnessSmallResults, $CorrectnessScaleResults)
    source_hashes = $sourceHashes
    command = [Environment]::CommandLine
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath `
    -Encoding UTF8

$tclStage = if ($Stage -eq "Preflight") {
    "parsecheck"
} else { $Stage.ToLowerInvariant() }
$quotedVivado = '"' + $vivado + '"'
$quotedTcl = '"' + $flowTcl + '"'
$quotedRepo = '"' + $repoRoot + '"'
$quotedRun = '"' + $runRoot + '"'
$quotedLog = '"' + $consoleLog + '"'
@"
@echo off
call $quotedVivado -mode batch -nolog -nojournal -notrace -source $quotedTcl -tclargs $quotedRepo $quotedRun $tclStage $Jobs > $quotedLog 2>&1
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath $commandFile -Encoding ASCII

[ordered]@{
    state = "RUNNING"
    stage = $Stage
    start_time = (Get-Date).ToString("o")
    run_tag = $RunTag
} | ConvertTo-Json | Set-Content -LiteralPath $statusJson -Encoding UTF8

$process = Start-Process -FilePath "cmd.exe" `
    -ArgumentList @("/d", "/c", ('"' + $commandFile + '"')) `
    -WorkingDirectory $runRoot -WindowStyle Hidden -PassThru
$completed = $process.WaitForExit($TimeoutMinutes * 60 * 1000)
if (!$completed) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
    [ordered]@{
        state = "TIMEOUT"
        stage = $Stage
        finish_time = (Get-Date).ToString("o")
        run_tag = $RunTag
        pid = $process.Id
        timeout_minutes = $TimeoutMinutes
    } | ConvertTo-Json | Set-Content -LiteralPath $statusJson -Encoding UTF8
    Publish-RunArtifacts
    throw "Vivado exceeded $TimeoutMinutes minutes; exact process tree PID $($process.Id) was stopped. Scratch was retained: $runRoot"
}
$process.Refresh()
$exitCode = $process.ExitCode
$flowStatus = @{}
$flowStatusPath = Join-Path $runRoot "flow_status.txt"
if (Test-Path -LiteralPath $flowStatusPath) {
    foreach ($line in Get-Content -LiteralPath $flowStatusPath) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $flowStatus[$parts[0]] = $parts[1] }
    }
}
$completionStage = if ($flowStatus.ContainsKey("stage")) {
    $flowStatus["stage"]
} else { "unknown" }
$detail = if ($flowStatus.ContainsKey("detail")) {
    $flowStatus["detail"]
} else { "Vivado exited before writing flow status" }
[ordered]@{
    state = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    stage = $Stage
    completion_stage = $completionStage
    detail = $detail
    finish_time = (Get-Date).ToString("o")
    run_tag = $RunTag
    exit_code = $exitCode
    scratch_retained = $true
    checkpoints_published = [bool]$PublishCheckpoints
} | ConvertTo-Json | Set-Content -LiteralPath $statusJson -Encoding UTF8

Convert-SummaryTextToJson
Publish-RunArtifacts
if ($exitCode -ne 0) {
    Write-Host "Vivado log tail:"
    if (Test-Path -LiteralPath $consoleLog) {
        Get-Content -LiteralPath $consoleLog -Tail 80 |
            ForEach-Object { Write-Host $_ }
    }
    throw "V3 M13 $Stage failed; scratch retained at $runRoot"
}

if ($CleanScratchOnSuccess) {
    if (!(Test-PathWithin -Child $runRoot -Parent $scratchRootFull) -or
            ([System.IO.Path]::GetFileName($runRoot) -ne $RunTag)) {
        throw "Refusing cleanup because scratch path is outside the configured root: $runRoot"
    }
    Remove-Item -LiteralPath $runRoot -Recurse -Force
}

Write-Host "V3 M13 $Stage PASS"
Write-Host "Published evidence: $publishedRoot"
if (!$CleanScratchOnSuccess) { Write-Host "Scratch retained: $runRoot" }
