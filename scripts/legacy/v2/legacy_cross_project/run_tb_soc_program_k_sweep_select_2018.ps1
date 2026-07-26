param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin",
    [string]$OutDir = "D:\vivado_pj\CSCGRA_noisy_mu\runs\tb_soc_program_k_sweep_select_2018",
    [int]$Case = -1,
    [int]$Alg = -1,
    [int]$StartCase = -1,
    [int]$EndCase = -1,
    [int]$StartAlg = -1,
    [int]$EndAlg = -1
)

$ErrorActionPreference = "Stop"
$Root = "D:\vivado_pj\CSCGRA_noisy_mu"
$RtlDir = Join-Path $Root "CSCGRA.srcs\sources_1\new"
$Tb = Join-Path $Root "tests\tb_soc_program_k_sweep.v"
$TbName = "tb_soc_program_k_sweep"

New-Item -ItemType Directory -Force $OutDir | Out-Null
Set-Location $OutDir
Remove-Item -Recurse -Force .\xsim.dir,.\*.log,.\*.jou,.\*.pb,.\*.wdb,.\run.tcl -ErrorAction SilentlyContinue
$srcs = Get-ChildItem $RtlDir -Filter *.v | Sort-Object Name | ForEach-Object { $_.FullName }

$defs = @()
if ($Case -ge 0) { $defs += @("-d", "TB_CASE_$Case") }
if ($Alg -ge 0) { $defs += @("-d", "TB_ALG_$Alg") }
if ($StartCase -ge 0) { $defs += @("-d", "TB_START_CASE_$StartCase") }
if ($EndCase -ge 0) { $defs += @("-d", "TB_END_CASE_$EndCase") }
if ($StartAlg -ge 0) { $defs += @("-d", "TB_START_ALG_$StartAlg") }
if ($EndAlg -ge 0) { $defs += @("-d", "TB_END_ALG_$EndAlg") }

& (Join-Path $VivadoBin "xvlog.bat") -sv @defs -i (Join-Path $Root "tests") @srcs $Tb *> "xvlog.stdout.log"
if ($LASTEXITCODE -ne 0) { Get-Content "xvlog.stdout.log" -Tail 120; exit $LASTEXITCODE }

& (Join-Path $VivadoBin "xelab.bat") --timescale 1ns/1ps --override_timeunit --override_timeprecision $TbName -s $TbName *> "xelab.stdout.log"
if ($LASTEXITCODE -ne 0) { Get-Content "xelab.stdout.log" -Tail 120; exit $LASTEXITCODE }

Set-Content -Path "run.tcl" -Value "run all`nquit`n" -NoNewline
& (Join-Path $VivadoBin "xsim.bat") $TbName -tclbatch run.tcl *> "xsim.stdout.log"
Get-Content "xsim.stdout.log" -Tail 160
exit $LASTEXITCODE