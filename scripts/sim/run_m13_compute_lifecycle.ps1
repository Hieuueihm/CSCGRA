param(
    [switch]$EnableProperties,
    [switch]$E2ESmoke,
    [switch]$CorrectnessMatrix,
    [int[]]$AlgorithmFilter = @(-1),
    [int[]]$ProfileFilter = @(-1),
    [int]$FixedOuterIterations = 0,
    [int]$FixedCosampIterations = 0,
    [int]$DebugTimeoutCycles = 0,
    [string]$RunTag = "",
    [switch]$FastSimulation,
    [string[]]$GeometryFilter = @(),
    [switch]$Resume,
    [switch]$SkipQualityPreflight,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin"
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$python = "D:\Holography\pybuild\python.exe"
$mode = if ($FixedOuterIterations -gt 0) {
    "fixed_outer_$($FixedOuterIterations)"
} elseif ($CorrectnessMatrix) { "correctness_sweep" } elseif ($E2ESmoke) {
    "e2e_smoke"
} elseif ($EnableProperties) {
    "property"
} else { "normal" }
if ($RunTag -and ($RunTag -notmatch "^[A-Za-z0-9._-]+$")) {
    throw "RunTag may contain only letters, digits, dot, underscore and dash"
}
$runSuffix = if ($RunTag) { "_$RunTag" } else { "" }
$workRoot = Join-Path $repoRoot "work\m13_compute_lifecycle_$mode$runSuffix"
$reportRoot = Join-Path $repoRoot "reports\v3\m13_vivado"
$matrixReportRoot = if ($FixedOuterIterations -gt 0) {
    Join-Path $repoRoot "reports\v3\m13_fixed_iteration_benchmark\outer$FixedOuterIterations$runSuffix"
} else {
    Join-Path $repoRoot "reports\v3\m13_correctness_sweep$runSuffix"
}
$logPath = Join-Path $reportRoot "compute_lifecycle_$($mode)_xsim.log"
New-Item -ItemType Directory -Force -Path $workRoot,$reportRoot | Out-Null
if ($CorrectnessMatrix) {
    New-Item -ItemType Directory -Force -Path $matrixReportRoot | Out-Null
}

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
$generator = Join-Path $repoRoot "scripts\golden\generate_m13_e2e_smoke.py"
$phaseGoldenGenerator = Join-Path $repoRoot "scripts\golden\generate_v3_phase_golden.py"
$generatedIncludeRoot = if ($FixedOuterIterations -gt 0) {
    Join-Path $workRoot "generated"
} else {
    Join-Path $repoRoot "verification\v3\m13\generated"
}
$generatedInclude = Join-Path $generatedIncludeRoot "e2e_smoke_golden.vh"
$algorithmNames = @("omp", "cosamp", "iht", "htp", "sp", "gp", "gomp", "mp")
$profileNames = @("strict_paper", "balanced_variant", "fast_variant")
$geometryNames = @(
    "m16_n24_k4_seed1",
    "m32_n64_k8_seed7",
    "m64_n128_k16_seed11",
    "m96_n256_k24_seed17",
    "m128_n512_k32_seed19",
    "m128_n1024_k32_seed23",
    "m128_n256_k8_seed29",
    "m64_n256_k8_seed41",
    "m32_n1024_k8_seed31",
    "m128_n256_k32_seed37"
)

if (@($AlgorithmFilter | Where-Object { ($_ -lt -1) -or
        ($_ -ge $algorithmNames.Count) }).Count -gt 0) {
    throw "AlgorithmFilter must be -1 or an algorithm id from 0 through 7"
}
if (@($ProfileFilter | Where-Object { ($_ -lt -1) -or
        ($_ -ge $profileNames.Count) }).Count -gt 0) {
    throw "ProfileFilter must be -1 or a profile id from 0 through 2"
}
if (($AlgorithmFilter -contains -1) -and ($AlgorithmFilter.Count -ne 1)) {
    throw "AlgorithmFilter -1 cannot be combined with explicit algorithm ids"
}
if (($ProfileFilter -contains -1) -and ($ProfileFilter.Count -ne 1)) {
    throw "ProfileFilter -1 cannot be combined with explicit profile ids"
}
if ($FixedCosampIterations -gt 0) {
    if ($FixedOuterIterations -gt 0 -and $FixedOuterIterations -ne $FixedCosampIterations) {
        throw "FixedCosampIterations conflicts with FixedOuterIterations"
    }
    $FixedOuterIterations = $FixedCosampIterations
}
if ($FixedOuterIterations -lt 0) {
    throw "FixedOuterIterations must be non-negative"
}
if (($FixedOuterIterations -gt 0) -and !$CorrectnessMatrix) {
    throw "FixedOuterIterations requires CorrectnessMatrix"
}
if ($GeometryFilter.Count -gt 0) {
    $unknownGeometries = @($GeometryFilter | Where-Object { $_ -notin $geometryNames })
    if ($unknownGeometries.Count -gt 0) {
        throw "Unknown geometry: $($unknownGeometries -join ', ')"
    }
    $geometryNames = @($geometryNames | Where-Object { $_ -in $GeometryFilter })
}

function Invoke-QualityPreflight {
    foreach ($suite in @("smoke", "scale", "correctness")) {
        & $python $phaseGoldenGenerator --suite $suite --check
        if ($LASTEXITCODE -ne 0) {
            throw "V3 $suite golden provenance check failed"
        }
    }
    & $python (Join-Path $repoRoot "scripts\numeric\v3_golden_quality_gate.py")
    if ($LASTEXITCODE -ne 0) { throw "V3 fixed-point quality gate failed" }
    & $python (Join-Path $repoRoot "scripts\numeric\v3_medical_scale_quality_gate.py")
    if ($LASTEXITCODE -ne 0) {
        throw "V3 production-scale medical quality gate failed"
    }
    & $python (Join-Path $repoRoot "scripts\numeric\v3_mri_paper_quality_gate.py") `
        --skip-global-stress
    if ($LASTEXITCODE -ne 0) { throw "V3 MRI paper-quality baseline gate failed" }
    & $python (Join-Path $repoRoot "scripts\numeric\v3_end_to_end_profile_sweep.py") `
        --profiles D18F14_S27F19_A62 --random-seeds 32 `
        --out-dir reports/v3/end_to_end_profile_quality_s27_stress32
    if ($LASTEXITCODE -ne 0) { throw "V3 fixed-point profile stress failed" }
}

function Invoke-GoldenGeneration {
    param(
        [string]$Geometry,
        [string]$SummaryPath
    )
    $generatorArgs = @($generator, "--case-name", $Geometry,
        "--out-vh", $generatedInclude, "--out-json", $SummaryPath)
    if ($FixedOuterIterations -gt 0) {
        $generatorArgs += @("--fixed-outer-iterations", $FixedOuterIterations)
    }
    & $python @generatorArgs
    if ($LASTEXITCODE -ne 0) {
        throw "M13 end-to-end golden generation failed: $Geometry"
    }
}

$sources = Get-Content (Join-Path $repoRoot "rtl\v3\files.f") |
    Where-Object { $_ -and -not $_.StartsWith("+") } |
    ForEach-Object { Join-Path $repoRoot $_ }
$sources += Join-Path $repoRoot "verification\v3\m13\tb_m13_compute_lifecycle.sv"
$defines = @()
if ($EnableProperties) { $defines += @("-d", "FORMAL") }
if ($E2ESmoke -or $CorrectnessMatrix) { $defines += @("-d", "M13_E2E_SMOKE") }

function Build-M13Snapshot {
    param(
        [string]$CaseWorkRoot,
        [string]$Snapshot
    )
    New-Item -ItemType Directory -Force -Path $CaseWorkRoot | Out-Null
    Push-Location $CaseWorkRoot
    try {
        $includeArgs = @("-i", (Join-Path $repoRoot "rtl\v3\include"))
        if ($E2ESmoke -or $CorrectnessMatrix) {
            $includeArgs += @("-i", $generatedIncludeRoot)
        }
        & $xvlog -sv @defines @includeArgs @sources
        if ($LASTEXITCODE -ne 0) { throw "M13 compute lifecycle compile failed" }
        $xelabArgs = @("tb_m13_compute_lifecycle", "-s", $Snapshot)
        if (!$FastSimulation) { $xelabArgs += @("-debug", "typical") }
        & $xelab @xelabArgs
        if ($LASTEXITCODE -ne 0) { throw "M13 compute lifecycle elaboration failed" }
    } finally {
        Pop-Location
    }
}

if ($CorrectnessMatrix) {
    if (!$SkipQualityPreflight) { Invoke-QualityPreflight }
    $resultsPath = Join-Path $matrixReportRoot "results.json"
    $csvPath = Join-Path $matrixReportRoot "results.csv"
    $matrixResults = @()
    if ($Resume -and (Test-Path -LiteralPath $resultsPath)) {
        $loadedResults = Get-Content -LiteralPath $resultsPath -Raw | ConvertFrom-Json
        if ($null -ne $loadedResults) { $matrixResults = @($loadedResults) }
    }

    foreach ($geometry in $geometryNames) {
        $summaryPath = Join-Path $matrixReportRoot "golden_$geometry.json"
        Invoke-GoldenGeneration -Geometry $geometry -SummaryPath $summaryPath
        $goldenSummary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $case = $goldenSummary.case
        $caseWorkRoot = $workRoot
        $snapshot = "m13_${geometry}_snapshot"
        Build-M13Snapshot -CaseWorkRoot $caseWorkRoot -Snapshot $snapshot

        foreach ($profile in 0..($profileNames.Count - 1)) {
            foreach ($algorithm in 0..($algorithmNames.Count - 1)) {
                if (($ProfileFilter -notcontains -1) -and
                        ($profile -notin $ProfileFilter)) { continue }
                if (($AlgorithmFilter -notcontains -1) -and
                        ($algorithm -notin $AlgorithmFilter)) {
                    continue
                }
                $profileName = $profileNames[$profile]
                $algorithmName = $algorithmNames[$algorithm]
                $alreadyPassed = @($matrixResults | Where-Object {
                    $_.geometry -eq $geometry -and $_.profile -eq $profileName -and
                    $_.algorithm -eq $algorithmName -and $_.status -eq "PASS"
                }).Count -gt 0
                if ($Resume -and $alreadyPassed) {
                    Write-Host "SKIP $geometry $profileName $algorithmName (already PASS)"
                    continue
                }

                $caseName = "${geometry}_${profileName}_${algorithmName}"
                $caseLog = Join-Path $matrixReportRoot "$caseName.xsim.log"
                $simArgsPath = Join-Path $caseWorkRoot "$caseName.args"
                $simArgs = @($snapshot, "-testplusarg", "+E2E_ALGORITHM=$algorithm",
                    "-testplusarg", "+E2E_PROFILE=$profile")
                if ($DebugTimeoutCycles -gt 0) {
                    $simArgs += @("-testplusarg",
                        "+E2E_TIMEOUT_OVERRIDE=$DebugTimeoutCycles")
                }
                $simArgs += "-runall"
                $simArgs | Set-Content -LiteralPath $simArgsPath
                Push-Location $caseWorkRoot
                try {
                    $output = & $xsim -f $simArgsPath 2>&1
                    $code = $LASTEXITCODE
                } finally {
                    Pop-Location
                }
                $output | Set-Content -LiteralPath $caseLog
                $text = $output -join "`n"
                if (($code -ne 0) -or
                        ($text -match "FAIL:|Fatal:|Assertion violation")) {
                    $output | Select-Object -Last 160 | ForEach-Object { Write-Host $_ }
                    throw "M13 correctness case failed: $caseName"
                }
                $match = [regex]::Match($text,
                    "M13 E2E CASE PASS m=(\d+) n=(\d+) k=(\d+) algorithm=(\d+) profile=(\d+) cycles=(\d+)")
                if (!$match.Success) {
                    $output | Select-Object -Last 80 | ForEach-Object { Write-Host $_ }
                    throw "M13 correctness PASS marker missing: $caseName"
                }
                if (([int]$match.Groups[1].Value -ne [int]$case.m) -or
                        ([int]$match.Groups[2].Value -ne [int]$case.n) -or
                        ([int]$match.Groups[3].Value -ne [int]$case.k) -or
                        ([int]$match.Groups[4].Value -ne $algorithm) -or
                        ([int]$match.Groups[5].Value -ne $profile)) {
                    throw "M13 correctness selection mismatch: $caseName"
                }
                $cycles = [int64]$match.Groups[6].Value
                $profileMatch = [regex]::Match($text,
                    "M13 PROFILE total_cycles=(\d+) phase_cycles=(\d+) execution_cycles=(\d+) writeback_cycles=(\d+) pe_useful_cycles=(\d+) stall_stream_input=(\d+) stall_stream_output=(\d+) stall_resource_request=(\d+) stall_resource_response=(\d+) stall_other=(\d+) phi_generate=(\d+) phi_replay=(\d+) selection=(\d+) dma_read_address=(\d+) dma_read_beats=(\d+) dma_write_address=(\d+) dma_write_beats=(\d+) dma_write_responses=(\d+) result_drain_cycles=(\d+) result_drain_beats=(\d+)")
                if (!$profileMatch.Success) {
                    throw "M13 profile marker missing: $caseName"
                }
                $rtlProfileMatch = [regex]::Match($text,
                    "M13 RTL PROFILE total=(\d+) phase=(\d+) execution=(\d+) commits=(\d+) stalls=(\d+) useful_cycles=(\d+) useful_slots=(\d+) resource_stalls=(\d+)")
                if (!$rtlProfileMatch.Success) {
                    throw "M13 RTL profile marker missing: $caseName"
                }
                if ([int64]$rtlProfileMatch.Groups[1].Value -ne $cycles) {
                    throw "M13 RTL profile total/cycle mismatch: $caseName"
                }
                $rtlEventMatch = [regex]::Match($text,
                    "M13 RTL EVENTS phi_generate=(\d+) phi_replay_requests=(\d+) phi_replay_responses=(\d+) phi_cache_fills=(\d+) phi_output_symbols=(\d+) selection=(\d+) dma_read_requests=(\d+) dma_read_beats=(\d+) dma_write_requests=(\d+) dma_write_beats=(\d+) dma_write_responses=(\d+) result_drain_cycles=(\d+) result_drain_beats=(\d+)")
                if (!$rtlEventMatch.Success) {
                    throw "M13 RTL event profile marker missing: $caseName"
                }
                $matrixResults = @($matrixResults | Where-Object {
                    !($_.geometry -eq $geometry -and $_.profile -eq $profileName -and
                      $_.algorithm -eq $algorithmName)
                })
                $matrixResults += [pscustomobject]@{
                    geometry = $geometry
                    m = [int]$case.m
                    n = [int]$case.n
                    k = [int]$case.k
                    seed = [int]$case.seed
                    outer_iteration_limit = [int]$case.outer_iteration_limit
                    profile = $profileName
                    algorithm = $algorithmName
                    cycles = $cycles
                    runtime_us_at_100mhz = $cycles / 100.0
                    phase_cycles = [int64]$profileMatch.Groups[2].Value
                    execution_cycles = [int64]$profileMatch.Groups[3].Value
                    writeback_cycles = [int64]$profileMatch.Groups[4].Value
                    pe_useful_cycles = [int64]$profileMatch.Groups[5].Value
                    stall_stream_input = [int64]$profileMatch.Groups[6].Value
                    stall_stream_output = [int64]$profileMatch.Groups[7].Value
                    stall_resource_request = [int64]$profileMatch.Groups[8].Value
                    stall_resource_response = [int64]$profileMatch.Groups[9].Value
                    stall_other = [int64]$profileMatch.Groups[10].Value
                    phi_generate = [int64]$profileMatch.Groups[11].Value
                    phi_replay = [int64]$profileMatch.Groups[12].Value
                    selection = [int64]$profileMatch.Groups[13].Value
                    dma_read_address = [int64]$profileMatch.Groups[14].Value
                    dma_read_beats = [int64]$profileMatch.Groups[15].Value
                    dma_write_address = [int64]$profileMatch.Groups[16].Value
                    dma_write_beats = [int64]$profileMatch.Groups[17].Value
                    dma_write_responses = [int64]$profileMatch.Groups[18].Value
                    result_drain_cycles = [int64]$profileMatch.Groups[19].Value
                    result_drain_beats = [int64]$profileMatch.Groups[20].Value
                    rtl_profile_total_cycles = [int64]$rtlProfileMatch.Groups[1].Value
                    rtl_profile_phase_cycles = [int64]$rtlProfileMatch.Groups[2].Value
                    rtl_profile_execution_cycles = [int64]$rtlProfileMatch.Groups[3].Value
                    rtl_profile_array_commit_cycles = [int64]$rtlProfileMatch.Groups[4].Value
                    rtl_profile_array_stall_cycles = [int64]$rtlProfileMatch.Groups[5].Value
                    rtl_profile_useful_pe_cycles = [int64]$rtlProfileMatch.Groups[6].Value
                    rtl_profile_useful_pe_slots = [int64]$rtlProfileMatch.Groups[7].Value
                    rtl_profile_resource_stall_cycles = [int64]$rtlProfileMatch.Groups[8].Value
                    rtl_event_phi_generate_requests = [int64]$rtlEventMatch.Groups[1].Value
                    rtl_event_phi_replay_requests = [int64]$rtlEventMatch.Groups[2].Value
                    rtl_event_phi_replay_responses = [int64]$rtlEventMatch.Groups[3].Value
                    rtl_event_phi_cache_fills = [int64]$rtlEventMatch.Groups[4].Value
                    rtl_event_phi_output_symbols = [int64]$rtlEventMatch.Groups[5].Value
                    rtl_event_selection_accepts = [int64]$rtlEventMatch.Groups[6].Value
                    rtl_event_dma_read_requests = [int64]$rtlEventMatch.Groups[7].Value
                    rtl_event_dma_read_beats = [int64]$rtlEventMatch.Groups[8].Value
                    rtl_event_dma_write_requests = [int64]$rtlEventMatch.Groups[9].Value
                    rtl_event_dma_write_beats = [int64]$rtlEventMatch.Groups[10].Value
                    rtl_event_dma_write_responses = [int64]$rtlEventMatch.Groups[11].Value
                    rtl_event_result_drain_cycles = [int64]$rtlEventMatch.Groups[12].Value
                    rtl_event_result_drain_beats = [int64]$rtlEventMatch.Groups[13].Value
                    status = "PASS"
                    log = $caseLog
                    golden_summary = $summaryPath
                }
                $matrixResults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultsPath
                $matrixResults | Export-Csv -NoTypeInformation -LiteralPath $csvPath
                Write-Host ("PASS {0,-26} {1,-18} {2,-6} cycles={3}" -f `
                    $geometry, $profileName, $algorithmName, $cycles)
            }
        }
    }

    $expectedAlgorithms = if ($AlgorithmFilter -contains -1) {
        $algorithmNames.Count
    } else { @($AlgorithmFilter | Select-Object -Unique).Count }
    $expectedProfiles = if ($ProfileFilter -contains -1) {
        $profileNames.Count
    } else { @($ProfileFilter | Select-Object -Unique).Count }
    $expectedCases = $geometryNames.Count * $expectedAlgorithms * $expectedProfiles
    $selectedPasses = @($matrixResults | Where-Object {
        $_.geometry -in $geometryNames -and
        (($AlgorithmFilter -contains -1) -or
         $_.algorithm -in @($AlgorithmFilter | ForEach-Object { $algorithmNames[$_] })) -and
        (($ProfileFilter -contains -1) -or
         $_.profile -in @($ProfileFilter | ForEach-Object { $profileNames[$_] })) -and
        $_.status -eq "PASS"
    }).Count
    if ($selectedPasses -ne $expectedCases) {
        throw "M13 correctness sweep incomplete: $selectedPasses/$expectedCases PASS"
    }
    Write-Host "M13 CORRECTNESS SWEEP $selectedPasses/$expectedCases PASS"
    exit 0
}

if ($E2ESmoke) {
    $summaryPath = Join-Path $repoRoot "reports\v3\m13_e2e_smoke\golden_summary.json"
    Invoke-GoldenGeneration -Geometry "m16_n24_k4_seed1" -SummaryPath $summaryPath
}
$snapshot = "m13_compute_lifecycle_$($mode)_snapshot"
Build-M13Snapshot -CaseWorkRoot $workRoot -Snapshot $snapshot
Push-Location $workRoot
try {
    $output = & $xsim $snapshot -runall 2>&1
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
$output | Set-Content -LiteralPath $logPath
$output | ForEach-Object { Write-Host $_ }
if ($code -ne 0) { throw "M13 compute lifecycle simulation failed" }
$text = Get-Content -LiteralPath $logPath -Raw
if ($text -match "FAIL:|Fatal:|Assertion violation") { throw "M13 failure marker" }
if ($E2ESmoke -and $text -notmatch "M13 E2E OMP STRICT PASS") {
    throw "M13 end-to-end PASS marker missing"
}
if (!$E2ESmoke -and $text -notmatch "M13 COMPUTE LIFECYCLE PASS") {
    throw "M13 PASS marker missing"
}
Write-Host "VIVADO M13 COMPUTE LIFECYCLE XSIM PASS"
