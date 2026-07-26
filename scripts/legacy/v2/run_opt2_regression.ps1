param(
    [int[]]$Cases = @(0, 1, 2, 3, 4, 5, 6, 7),
    [int[]]$Algorithms = @(),
    [string]$OutDir = "runs/opt2_regression",
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$fileList = Join-Path $repoRoot "tests\run1\tb_run1_k_sweep_files.f"
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$snapshot = "tb_opt2_regression"
$failurePattern = "X_MISM|FAIL irq|FAIL golden|FAIL pc|FAIL nonzero|FAIL ctx|FAIL cf_loop|FAIL done|TIMEOUT|FATAL|ERROR:"

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado tool not found: $tool"
    }
}

$resolvedOutDir = if ([IO.Path]::IsPathRooted($OutDir)) {
    $OutDir
} else {
    Join-Path $repoRoot $OutDir
}
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
$workDir = Join-Path $resolvedOutDir "work"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$sourceFiles = @(
    Get-Content -LiteralPath $fileList |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Join-Path $repoRoot $_ }
)

Push-Location $workDir
try {
    & $xvlog -sv -i $repoRoot @sourceFiles --log (Join-Path $resolvedOutDir "xvlog.log")
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

    & $xelab --timescale 1ns/1ps --override_timeunit --override_timeprecision `
        tb_run1_k_sweep -s $snapshot --log (Join-Path $resolvedOutDir "xelab.log")
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }

    $rows = @()
    foreach ($case in $Cases) {
        $algList = if ($Algorithms.Count -eq 0) { @(-1) } else { $Algorithms }
        foreach ($alg in $algList) {
            $allAlgorithms = $alg -eq -1
            $suffix = if ($allAlgorithms) { "all" } else { "alg$alg" }
            $name = "case${case}_$suffix"
            $log = Join-Path $resolvedOutDir "$name.log"
            $caseArg = '"CASE={0}"' -f $case
            $args = @($snapshot, "-runall", "-testplusarg", $caseArg, "--log", $log)
            if (-not $allAlgorithms) {
                $args += @("-testplusarg", ('"ALG={0}"' -f $alg))
            }

            & $xsim @args
            if ($LASTEXITCODE -ne 0) { throw "xsim failed for $name with exit code $LASTEXITCODE" }

            $text = Get-Content -LiteralPath $log -Raw
            $result = if ($text -match $failurePattern) {
                "FAIL"
            } elseif ($text -match "tb_run1_k_sweep: \d+ PASS, 0 FAIL") {
                "PASS"
            } else {
                "UNKNOWN"
            }
            $cycleLines = @(
                Select-String -LiteralPath $log -Pattern "SOC_ITER_RESULT" |
                    ForEach-Object { $_.Line }
            )
            $rows += [pscustomobject]@{
                Case = $case
                Algorithm = if ($allAlgorithms) { "all" } else { $alg }
                Result = $result
                CycleRecords = $cycleLines.Count
                Log = $log
            }
            Write-Host "$name $result ($($cycleLines.Count) cycle records)"
        }
    }

    $rows | Export-Csv (Join-Path $resolvedOutDir "summary.csv") -NoTypeInformation
    $rows | Format-Table -AutoSize | Out-String |
        Set-Content (Join-Path $resolvedOutDir "summary.txt")
    if (@($rows | Where-Object Result -ne "PASS").Count -ne 0) {
        throw "One or more regression runs did not pass"
    }
} finally {
    Pop-Location
}
