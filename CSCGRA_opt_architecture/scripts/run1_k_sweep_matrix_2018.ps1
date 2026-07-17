param(
  [string]$Cases = "0,1,2,3,4,5,6,7",
  [string]$Algs = "0,1,2,3,4,5,6,7",
  [string]$OutDir = "runs/run1_k_sweep_matrix"
)
$ErrorActionPreference = "Stop"
$vivado = "C:\Xilinx\Vivado\2018.1\bin"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$caseList = $Cases.Split(',') | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
$algList = $Algs.Split(',') | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
$rows = @()
foreach($case in $caseList){
  foreach($alg in $algList){
    if($case -eq 0 -and ($alg -eq 1 -or $alg -eq 4)){
      $rows += [pscustomobject]@{Case=$case; Alg=$alg; Result='SKIP_2K'; Log=''}
      continue
    }
    $name = "case${case}_alg${alg}"
    $log = Join-Path $OutDir "$name.log"
    & "$vivado\xvlog.bat" -sv -d "TB_CASE_$case" -d "TB_ALG_$alg" -f tests\run1\tb_run1_k_sweep_files.f | Out-File $log -Encoding ascii
    & "$vivado\xelab.bat" tb_run1_k_sweep_1k -debug typical -s "tb_run1_${name}_sim" | Tee-Object -FilePath $log -Append | Out-Null
    & "$vivado\xsim.bat" "tb_run1_${name}_sim" -tclbatch run1_ksweep.tcl | Tee-Object -FilePath $log -Append | Out-Null
    $txt = Get-Content $log -Raw
    if($txt -match 'FAIL|X_MISM') { $res='FAIL' }
    elseif($txt -match 'tb_run1_k_sweep_1k: .* 0 FAIL') { $res='PASS' }
    else { $res='UNKNOWN' }
    $rows += [pscustomobject]@{Case=$case; Alg=$alg; Result=$res; Log=$log}
    Write-Host "$name $res"
  }
}
$rows | Export-Csv (Join-Path $OutDir 'summary.csv') -NoTypeInformation
$rows | Format-Table -AutoSize | Out-String | Set-Content (Join-Path $OutDir 'summary.txt')
$fail = @($rows | Where-Object { $_.Result -notin @('PASS','SKIP_2K') })
if($fail.Count -gt 0){ exit 1 }
