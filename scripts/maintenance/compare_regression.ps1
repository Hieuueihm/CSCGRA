param(
    [Parameter(Mandatory = $true)]
    [string]$BaselineLog,
    [Parameter(Mandatory = $true)]
    [string]$CurrentLogDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resultPattern = [regex]::new(
    "SOC_ITER_RESULT case=(?<case>\d+) m=(?<m>\d+) n=(?<n>\d+) k=(?<k>\d+) " +
    "alg=(?<alg>\d+) iter=(?<iter>\d+) cycles=(?<cycles>\d+) " +
    "status=(?<status>[0-9a-fA-F]+) pc_dbg=(?<pc>\d+) nz=(?<nz>\d+)"
)
$skipPattern = [regex]::new(
    "SKIP_CASE case=(?<case>\d+) m=(?<m>\d+) n=(?<n>\d+) k=(?<k>\d+) " +
    "alg=(?<alg>\d+) reason=(?<reason>\S+)"
)

function Read-RegressionRecords {
    param([string[]]$Paths)

    $results = @{}
    $skips = @{}
    foreach ($path in $Paths) {
        foreach ($line in Get-Content -LiteralPath $path) {
            $match = $resultPattern.Match($line)
            if ($match.Success) {
                $key = "$($match.Groups['case'].Value):$($match.Groups['alg'].Value)"
                $results[$key] = [ordered]@{
                    m = $match.Groups["m"].Value
                    n = $match.Groups["n"].Value
                    k = $match.Groups["k"].Value
                    iter = $match.Groups["iter"].Value
                    cycles = $match.Groups["cycles"].Value
                    status = $match.Groups["status"].Value.ToLowerInvariant()
                    pc = $match.Groups["pc"].Value
                    nz = $match.Groups["nz"].Value
                }
                continue
            }
            $match = $skipPattern.Match($line)
            if ($match.Success) {
                $key = "$($match.Groups['case'].Value):$($match.Groups['alg'].Value)"
                $skips[$key] = $match.Groups["reason"].Value
            }
        }
    }
    return @{ Results = $results; Skips = $skips }
}

$baselinePaths = @(
    if (Test-Path -LiteralPath $BaselineLog -PathType Container) {
        Get-ChildItem -LiteralPath $BaselineLog -Filter "case*_*.log" -File |
            Sort-Object Name |
            ForEach-Object FullName
    } else {
        $BaselineLog
    }
)
if ($baselinePaths.Count -eq 0) {
    throw "No baseline logs found at $BaselineLog"
}
$baseline = Read-RegressionRecords -Paths $baselinePaths
$currentLogs = @(
    Get-ChildItem -LiteralPath $CurrentLogDirectory -Filter "case*_*.log" -File |
        Sort-Object Name |
        ForEach-Object FullName
)
if ($currentLogs.Count -eq 0) {
    throw "No current case logs found in $CurrentLogDirectory"
}
$current = Read-RegressionRecords -Paths $currentLogs

$mismatches = @()
$allResultKeys = @($baseline.Results.Keys + $current.Results.Keys | Sort-Object -Unique)
foreach ($key in $allResultKeys) {
    if (-not $baseline.Results.ContainsKey($key)) {
        $mismatches += "Unexpected current result: $key"
        continue
    }
    if (-not $current.Results.ContainsKey($key)) {
        $mismatches += "Missing current result: $key"
        continue
    }
    $baselineJson = $baseline.Results[$key] | ConvertTo-Json -Compress
    $currentJson = $current.Results[$key] | ConvertTo-Json -Compress
    if ($baselineJson -ne $currentJson) {
        $mismatches += "Result mismatch ${key}: baseline=$baselineJson current=$currentJson"
    }
}

$allSkipKeys = @($baseline.Skips.Keys + $current.Skips.Keys | Sort-Object -Unique)
foreach ($key in $allSkipKeys) {
    if (-not $baseline.Skips.ContainsKey($key)) {
        $mismatches += "Unexpected current skip: $key"
    } elseif (-not $current.Skips.ContainsKey($key)) {
        $mismatches += "Missing current skip: $key"
    } elseif ($baseline.Skips[$key] -ne $current.Skips[$key]) {
        $mismatches += "Skip mismatch ${key}: baseline=$($baseline.Skips[$key]) current=$($current.Skips[$key])"
    }
}

Write-Host "BASELINE_RESULTS=$($baseline.Results.Count)"
Write-Host "CURRENT_RESULTS=$($current.Results.Count)"
Write-Host "BASELINE_SKIPS=$($baseline.Skips.Count)"
Write-Host "CURRENT_SKIPS=$($current.Skips.Count)"
Write-Host "MISMATCHES=$($mismatches.Count)"
$mismatches | ForEach-Object { Write-Error $_ }
if ($mismatches.Count -ne 0) {
    exit 1
}
Write-Host "REGRESSION_COMPARISON=PASS"
