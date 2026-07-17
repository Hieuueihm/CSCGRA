param(
    [string]$Cases = "0,1,2,3,4,5,6,7",
    [string]$Algs = "0,1,2,3,4,5,6,7",
    [string]$OutRoot = "D:\vivado_pj\CSCGRA_noisy_mu\runs\tb_matrix_2018"
)
$ErrorActionPreference = "Stop"
$caseList = $Cases.Split(',') | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
$algList = $Algs.Split(',') | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
New-Item -ItemType Directory -Force $OutRoot | Out-Null
$rows = @()
foreach($case in $caseList){
  foreach($alg in $algList){
    $name = "case${case}_alg${alg}"
    $out = Join-Path $OutRoot $name
    Write-Host "=== $name ==="
    powershell -ExecutionPolicy Bypass -File "D:\vivado_pj\CSCGRA_noisy_mu\scripts\run_tb_soc_program_k_sweep_select_2018.ps1" -Case $case -Alg $alg -OutDir $out | Tee-Object -FilePath (Join-Path $out "driver.stdout.log")
    $xsim = Join-Path $out "xsim.stdout.log"
    $text = if(Test-Path $xsim){ Get-Content $xsim -Raw } else { "" }
    $summary = [regex]::Match($text, 'tb_soc_program_k_sweep: (\d+) PASS, (\d+) FAIL')
    $pass = if($summary.Success){ [int]$summary.Groups[1].Value } else { -1 }
    $fail = if($summary.Success){ [int]$summary.Groups[2].Value } else { -1 }
    $soc = [regex]::Match($text, 'SOC_RESULT[^\r\n]*')
    $rows += [pscustomobject]@{Case=$case; Alg=$alg; Pass=$pass; Fail=$fail; Result=$soc.Value; Out=$out}
    $rows | Export-Csv (Join-Path $OutRoot "summary.csv") -NoTypeInformation
    if($fail -ne 0){
      Write-Host "FAIL_DETECTED $name"
      $rows | Format-Table -AutoSize
      exit 2
    }
  }
}
$rows | Format-Table -AutoSize