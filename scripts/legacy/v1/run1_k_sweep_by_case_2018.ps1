param(
  [string]$Cases = "0,1,2,3,4,5,6,7",
  [string]$OutDir = "runs/run1_k_sweep_by_case"
)
$ErrorActionPreference = "Stop"
$vivado = "C:\Xilinx\Vivado\2018.1\bin"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$rows = @()
foreach($case in ($Cases.Split(',') | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })){
  $name = "case${case}_all"
  $log = Join-Path $OutDir "$name.log"
  & "$vivado\xvlog.bat" -sv -d "TB_CASE_$case" -f tests\run1\tb_run1_k_sweep_files.f | Out-File $log -Encoding ascii
  & "$vivado\xelab.bat" tb_run1_k_sweep -debug typical -s "tb_run1_${name}_sim" | Out-File $log -Append -Encoding ascii
  & "$vivado\xsim.bat" "tb_run1_${name}_sim" -tclbatch run1_ksweep.tcl | Out-File $log -Append -Encoding ascii
  $txt = Get-Content $log -Raw
  if($txt -match 'X_MISM|FAIL irq|FAIL golden|FAIL pc|FAIL nonzero|FAIL ctx|FAIL cf_loop|FAIL done') { $res='FAIL' }
  elseif($txt -match 'tb_run1_k_sweep: .* 0 FAIL') { $res='PASS' }
  else { $res='UNKNOWN' }
  $rows += [pscustomobject]@{Case=$case; Result=$res; Log=$log}
  Write-Host "$name $res"
}
$rows | Export-Csv (Join-Path $OutDir 'summary.csv') -NoTypeInformation
$rows | Format-Table -AutoSize | Out-String | Set-Content (Join-Path $OutDir 'summary.txt')
$fail = @($rows | Where-Object { $_.Result -ne 'PASS' })
if($fail.Count -gt 0){ exit 1 }




