param(
    [ValidateSet("v1", "v2")]
    [string]$RtlVersion = "v2",
    [int[]]$Cases = @(0, 1, 2, 3, 4, 5, 6, 7),
    [int[]]$Algorithms = @(),
    [switch]$ProfileStates,
    [switch]$CanonicalGolden,
    [string]$RunId = "",
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $repoRoot "config\rtl-$RtlVersion.json"
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$rtlFileList = Join-Path $repoRoot ($config.rtl_filelist -replace "/", "\")
$rtlRoot = Split-Path -Parent $rtlFileList
$verificationRoot = Join-Path $repoRoot ($config.verification_root -replace "/", "\")
$testbench = Join-Path $repoRoot ($config.default_testbench -replace "/", "\")

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd-HHmmss"
}
if ($RunId -notmatch "^[A-Za-z0-9._-]+$") {
    throw "RunId may contain only letters, digits, dot, underscore, and dash"
}

$workDir = Join-Path $repoRoot "work\sim\$RtlVersion\$RunId"
$logDir = Join-Path $repoRoot "logs\sim\$RtlVersion\$RunId"
New-Item -ItemType Directory -Force -Path $workDir, $logDir | Out-Null

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado tool not found: $tool"
    }
}

$rtlFiles = @(
    Get-Content -LiteralPath $rtlFileList |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.Trim().StartsWith("#") } |
        ForEach-Object { Join-Path $repoRoot ($_ -replace "/", "\") }
)
$sourceFiles = @($testbench) + $rtlFiles
foreach ($source in $sourceFiles) {
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Source file from manifest does not exist: $source"
    }
}

$includeDirs = @(
    $repoRoot,
    $verificationRoot,
    (Join-Path $verificationRoot "run1"),
    (Join-Path $rtlRoot "control"),
    (Join-Path $rtlRoot "solver")
)
$snapshot = "tb_${RtlVersion}_regression"
$failurePattern = "X_MISM|FAIL irq|FAIL golden|FAIL pc|FAIL nonzero|FAIL ctx|FAIL cf_loop|FAIL done|TIMEOUT|FATAL|ERROR:"
$gitCommit = (& git -C $repoRoot rev-parse HEAD).Trim()

$metadata = [ordered]@{
    flow = "sim"
    rtl_version = $RtlVersion
    run_id = $RunId
    git_commit = $gitCommit
    testbench = $config.default_testbench
    cases = @($Cases)
    algorithms = @($Algorithms)
    profile_states = $ProfileStates.IsPresent
    canonical_golden = $CanonicalGolden.IsPresent
    started_at = (Get-Date).ToString("o")
    work_dir = $workDir
    log_dir = $logDir
}
$metadata | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $logDir "metadata.json")

Push-Location $workDir
try {
    $xvlogArgs = @("-sv")
    if ($ProfileStates) {
        $xvlogArgs += @("-d", "TB_STATE_PROFILE")
    }
    if ($CanonicalGolden) {
        $xvlogArgs += @("-d", "TB_USE_CANONICAL_GOLDEN")
        $xvlogArgs += @("-d", "TB_CANONICAL_GP")
    }
    foreach ($includeDir in $includeDirs) {
        $xvlogArgs += @("-i", $includeDir)
    }
    $xvlogArgs += $sourceFiles
    $xvlogArgs += @("--log", (Join-Path $logDir "xvlog.log"))
    & $xvlog @xvlogArgs
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    & $xelab --timescale 1ns/1ps --override_timeunit --override_timeprecision `
        tb_run1_k_sweep -s $snapshot --log (Join-Path $logDir "xelab.log")
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
    }

    $rows = @()
    foreach ($case in $Cases) {
        $algorithmList = if ($Algorithms.Count -eq 0) { @(-1) } else { $Algorithms }
        foreach ($algorithm in $algorithmList) {
            $allAlgorithms = $algorithm -eq -1
            $suffix = if ($allAlgorithms) { "all" } else { "alg$algorithm" }
            $name = "case${case}_$suffix"
            $caseLog = Join-Path $logDir "$name.log"
            $xsimArgs = @(
                $snapshot,
                "-runall"
            )
            $runSelector = if ($allAlgorithms) { "CASE=$case" } else { "RUN_CASE_ALG=$(($case * 8) + $algorithm)" }
            $xsimArgs += @("-testplusarg", ('"{0}"' -f $runSelector), "--log", $caseLog)
            & $xsim @xsimArgs
            if ($LASTEXITCODE -ne 0) {
                throw "xsim failed for $name with exit code $LASTEXITCODE"
            }

            $text = Get-Content -LiteralPath $caseLog -Raw
            $result = if ($text -match $failurePattern) {
                "FAIL"
            } elseif ($text -match "tb_run1_k_sweep: \d+ PASS, 0 FAIL") {
                "PASS"
            } else {
                "UNKNOWN"
            }
            $cycleLines = @(
                Select-String -LiteralPath $caseLog -Pattern "SOC_ITER_RESULT" |
                    ForEach-Object { $_.Line }
            )
            $rows += [pscustomobject]@{
                Case = $case
                Algorithm = if ($allAlgorithms) { "all" } else { $algorithm }
                Result = $result
                CycleRecords = $cycleLines.Count
                Log = $caseLog
            }
            Write-Host "$name $result ($($cycleLines.Count) cycle records)"
        }
    }

    $rows | Export-Csv (Join-Path $logDir "summary.csv") -NoTypeInformation
    $rows | Format-Table -AutoSize | Out-String |
        Set-Content -LiteralPath (Join-Path $logDir "summary.txt")
    if (@($rows | Where-Object Result -ne "PASS").Count -ne 0) {
        throw "One or more regression runs did not pass"
    }
} finally {
    Pop-Location
}

Write-Host "Regression PASS"
Write-Host "Logs: $logDir"
