param(
    [string[]]$CurrentResults = @(
        "reports\v3\m13_correctness_sweep_p06_event_small_20260907\results.json",
        "reports\v3\m13_correctness_sweep_p06_event_scale_20260907\results.json"
    ),
    [string[]]$BaselineResults = @(
        "reports\v3\m13_correctness_sweep_p05_profile_small_20260906\results.json",
        "reports\v3\m13_correctness_sweep_p05_profile_scale_20260906\results.json"
    ),
    [string]$OutputPath =
        "reports\v3\optimization_follow_20260906\p0\P07_COUNTER_CONTRACT_AUDIT.json"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Resolve-RepoPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $repoRoot $Path
}

function Read-ResultRecords {
    param([string[]]$Paths)
    $records = @()
    foreach ($path in $Paths) {
        $resolved = Resolve-RepoPath $path
        if (!(Test-Path -LiteralPath $resolved)) {
            throw "Result file not found: $resolved"
        }
        $records += @(Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json)
    }
    return @($records)
}

$current = Read-ResultRecords $CurrentResults
$baseline = Read-ResultRecords $BaselineResults
$baselineByKey = @{}
foreach ($record in $baseline) {
    $key = "$($record.geometry)|$($record.profile)|$($record.algorithm)"
    $baselineByKey[$key] = $record
}

$eventFields = @(
    "rtl_event_phi_generate_requests",
    "rtl_event_phi_replay_requests",
    "rtl_event_phi_replay_responses",
    "rtl_event_phi_cache_fills",
    "rtl_event_phi_output_symbols",
    "rtl_event_selection_accepts",
    "rtl_event_dma_read_requests",
    "rtl_event_dma_read_beats",
    "rtl_event_dma_write_requests",
    "rtl_event_dma_write_beats",
    "rtl_event_dma_write_responses",
    "rtl_event_result_drain_cycles",
    "rtl_event_result_drain_beats"
)
$referencePairs = @(
    @("rtl_event_phi_generate_requests", "phi_generate"),
    @("rtl_event_phi_replay_requests", "phi_replay"),
    @("rtl_event_selection_accepts", "selection"),
    @("rtl_event_dma_read_requests", "dma_read_address"),
    @("rtl_event_dma_read_beats", "dma_read_beats"),
    @("rtl_event_dma_write_requests", "dma_write_address"),
    @("rtl_event_dma_write_beats", "dma_write_beats"),
    @("rtl_event_dma_write_responses", "dma_write_responses"),
    @("rtl_event_result_drain_cycles", "result_drain_cycles"),
    @("rtl_event_result_drain_beats", "result_drain_beats")
)

$violations = New-Object System.Collections.Generic.List[string]
$cycleDeltas = @()
foreach ($record in $current) {
    $key = "$($record.geometry)|$($record.profile)|$($record.algorithm)"
    if (!$baselineByKey.ContainsKey($key)) {
        $violations.Add("missing baseline: $key")
        continue
    }
    $cycleDeltas += [int64]$record.cycles - [int64]$baselineByKey[$key].cycles
    if ($record.status -ne "PASS") { $violations.Add("non-PASS status: $key") }
    foreach ($field in $eventFields) {
        if ($null -eq $record.$field) {
            $violations.Add("missing field $($field): $key")
        }
    }
    foreach ($pair in $referencePairs) {
        if ([int64]$record.($pair[0]) -ne [int64]$record.($pair[1])) {
            $violations.Add("RTL/TB mismatch $($pair[0]): $key")
        }
    }
    if ([int64]$record.rtl_profile_total_cycles -ne [int64]$record.cycles) {
        $violations.Add("profile total mismatch: $key")
    }
    if ([int64]$record.rtl_event_phi_replay_responses -ne
            [int64]$record.rtl_event_phi_replay_requests) {
        $violations.Add("incomplete replay traffic: $key")
    }
    if ([int64]$record.rtl_event_phi_cache_fills -gt
            [int64]$record.rtl_event_phi_output_symbols) {
        $violations.Add("cache fill exceeds Phi output: $key")
    }
    if ([int64]$record.rtl_event_dma_read_requests -gt
            [int64]$record.rtl_event_dma_read_beats) {
        $violations.Add("DMA read request/beat bound: $key")
    }
    if ([int64]$record.rtl_event_dma_write_responses -ne
            [int64]$record.rtl_event_dma_write_requests) {
        $violations.Add("incomplete DMA write traffic: $key")
    }
    if ([int64]$record.rtl_event_result_drain_beats -gt
            [int64]$record.rtl_event_dma_write_beats) {
        $violations.Add("result drain/DMA write bound: $key")
    }
    if ([int64]$record.rtl_event_result_drain_cycles -lt
            [int64]$record.rtl_event_result_drain_beats) {
        $violations.Add("result drain cycle/beat bound: $key")
    }
}

$audit = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    records = $current.Count
    pass_records = @($current | Where-Object status -eq "PASS").Count
    event_field_count = $eventFields.Count
    complete_event_records = @($current | Where-Object {
        $complete = $true
        foreach ($field in $eventFields) {
            if ($null -eq $_.$field) { $complete = $false }
        }
        $complete
    }).Count
    nonzero_cycle_deltas = @($cycleDeltas | Where-Object { $_ -ne 0 }).Count
    min_cycle_delta = ($cycleDeltas | Measure-Object -Minimum).Minimum
    max_cycle_delta = ($cycleDeltas | Measure-Object -Maximum).Maximum
    invariant_violations = $violations.Count
    violations = @($violations)
    ranges = [ordered]@{}
}
foreach ($field in $eventFields) {
    $measure = $current | Measure-Object -Property $field -Minimum -Maximum -Sum
    $audit.ranges[$field] = [ordered]@{
        minimum = [int64]$measure.Minimum
        maximum = [int64]$measure.Maximum
        sum = [int64]$measure.Sum
    }
}

$resolvedOutput = Resolve-RepoPath $OutputPath
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutput) |
    Out-Null
$audit | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 $resolvedOutput
$audit | ConvertTo-Json -Depth 8 | Write-Host
if ($violations.Count -ne 0) {
    throw "Execution profile counter audit failed with $($violations.Count) violation(s)"
}
Write-Host "EXECUTION PROFILE COUNTER AUDIT PASS $($current.Count)/$($current.Count)"
