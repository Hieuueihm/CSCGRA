param(
    [Parameter(Mandatory=$true)][string]$TbName,
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.1\bin",
    [string]$OutRoot = "D:\vivado_pj\CSCGRA_opt\runs\tb_basic_2018"
)
$ErrorActionPreference = "Stop"
$Root = "D:\vivado_pj\CSCGRA_opt"
$RtlDir = Join-Path $Root "CSCGRA.srcs\sources_1\new"
$Tb = Join-Path $Root "tests\$TbName.v"
if (!(Test-Path $Tb)) { throw "TB not found: $Tb" }
$OutDir = Join-Path $OutRoot $TbName
New-Item -ItemType Directory -Force $OutDir | Out-Null
Set-Location $OutDir
Remove-Item -Recurse -Force .\xsim.dir,.\*.log,.\*.jou,.\*.pb,.\*.wdb -ErrorAction SilentlyContinue
$srcs = Get-ChildItem $RtlDir -Filter *.v | Sort-Object Name | ForEach-Object { $_.FullName }
& (Join-Path $VivadoBin "xvlog.bat") -sv -i (Join-Path $Root "tests") @srcs $Tb *> "xvlog.stdout.log"
if ($LASTEXITCODE -ne 0) { Get-Content "xvlog.stdout.log" -Tail 120; exit $LASTEXITCODE }
& (Join-Path $VivadoBin "xelab.bat") --timescale 1ns/1ps --override_timeunit --override_timeprecision $TbName -s $TbName *> "xelab.stdout.log"
if ($LASTEXITCODE -ne 0) { Get-Content "xelab.stdout.log" -Tail 120; exit $LASTEXITCODE }
& (Join-Path $VivadoBin "xsim.bat") $TbName -runall *> "xsim.stdout.log"
Get-Content "xsim.stdout.log" -Tail 120
exit $LASTEXITCODE
