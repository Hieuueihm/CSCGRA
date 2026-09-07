Set-StrictMode -Version Latest

function Resolve-PythonCommand {
    param([string[]]$RequiredModules = @())

    $candidates = @()
    if ($env:CSCGRA_PYTHON) {
        $candidates += [pscustomobject]@{
            Executable = $env:CSCGRA_PYTHON
            PrefixArguments = @()
        }
    }
    if ($env:VIRTUAL_ENV) {
        $candidates += [pscustomobject]@{
            Executable = Join-Path $env:VIRTUAL_ENV "Scripts\python.exe"
            PrefixArguments = @()
        }
    }

    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $candidates += [pscustomobject]@{
        Executable = Join-Path $repoRoot ".venv\Scripts\python.exe"
        PrefixArguments = @()
    }
    $candidates += [pscustomobject]@{
        Executable = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
        PrefixArguments = @()
    }

    foreach ($commandName in @("python.exe", "python3.exe")) {
        foreach ($command in @(Get-Command $commandName -All -ErrorAction SilentlyContinue)) {
            $candidates += [pscustomobject]@{
                Executable = $command.Source
                PrefixArguments = @()
            }
        }
    }
    foreach ($command in @(Get-Command "py.exe" -All -ErrorAction SilentlyContinue)) {
        $candidates += [pscustomobject]@{
            Executable = $command.Source
            PrefixArguments = @("-3")
        }
    }

    $probe = "import importlib.util,sys; missing=[m for m in sys.argv[1:] if importlib.util.find_spec(m) is None]; raise SystemExit(1 if missing else 0)"
    $visited = @{}
    foreach ($candidate in $candidates) {
        $key = "$($candidate.Executable)|$($candidate.PrefixArguments -join ' ')"
        if ($visited.ContainsKey($key) -or
            -not (Test-Path -LiteralPath $candidate.Executable)) {
            continue
        }
        $visited[$key] = $true
        & $candidate.Executable @($candidate.PrefixArguments) -c $probe @RequiredModules 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $candidate
        }
    }

    $requirements = if ($RequiredModules.Count) {
        " with modules: $($RequiredModules -join ', ')"
    } else {
        ""
    }
    throw "No usable Python 3 interpreter found$requirements. Set CSCGRA_PYTHON."
}

function Invoke-PythonScript {
    param(
        [Parameter(Mandatory = $true)]$Python,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $Python.Executable @($Python.PrefixArguments) $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}
