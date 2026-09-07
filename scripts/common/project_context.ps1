Set-StrictMode -Version Latest

function Get-FileSetSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][System.IO.FileInfo[]]$Files
    )

    $repoFull = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $lines = foreach ($file in @($Files | Sort-Object FullName -Unique)) {
        $full = [IO.Path]::GetFullPath($file.FullName)
        if (-not $full.StartsWith($repoFull + [IO.Path]::DirectorySeparatorChar,
                                 [StringComparison]::OrdinalIgnoreCase)) {
            throw "Cannot fingerprint a file outside the repository: $full"
        }
        $relative = $full.Substring($repoFull.Length + 1).Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        "${relative}:$hash"
    }

    $payload = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-ProjectSourceIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RtlVersion,
        [switch]$IncludeVerification
    )

    $rtlRoot = Join-Path $RepoRoot "rtl\$RtlVersion"
    if (-not (Test-Path -LiteralPath $rtlRoot)) {
        throw "RTL root does not exist: $rtlRoot"
    }
    $rtlFiles = @(Get-ChildItem -LiteralPath $rtlRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".v", ".vh", ".sv", ".f") })
    $trackedRoots = @($rtlRoot)

    $identity = [ordered]@{
        git_head = (& git -C $RepoRoot rev-parse HEAD).Trim()
        git_branch = (& git -C $RepoRoot branch --show-current).Trim()
        rtl_sha256 = Get-FileSetSha256 -RepoRoot $RepoRoot -Files $rtlFiles
        rtl_file_count = $rtlFiles.Count
    }

    if ($IncludeVerification) {
        $verificationRoot = Join-Path $RepoRoot "verification\$RtlVersion"
        $verificationFiles = @(Get-ChildItem -LiteralPath $verificationRoot -Recurse -File |
            Where-Object { $_.Extension -in @(".v", ".vh", ".sv", ".f") })
        $trackedRoots += $verificationRoot
        $identity.verification_sha256 = Get-FileSetSha256 -RepoRoot $RepoRoot -Files $verificationFiles
        $identity.verification_file_count = $verificationFiles.Count
    }

    $repoFull = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $statusArgs = @("-C", $RepoRoot, "status", "--porcelain", "--untracked-files=all", "--")
    foreach ($root in $trackedRoots) {
        $rootFull = [IO.Path]::GetFullPath($root)
        if (-not $rootFull.StartsWith($repoFull + [IO.Path]::DirectorySeparatorChar,
                                     [StringComparison]::OrdinalIgnoreCase)) {
            throw "Source root is outside the repository: $rootFull"
        }
        $statusArgs += $rootFull.Substring($repoFull.Length + 1).Replace("\", "/")
    }
    $identity.source_dirty = @(& git @statusArgs).Count -ne 0
    return [pscustomobject]$identity
}
