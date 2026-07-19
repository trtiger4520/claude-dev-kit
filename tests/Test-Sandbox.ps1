Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:SandboxRoot = [System.IO.Path]::GetFullPath((Join-Path $script:RepositoryRoot '.sandbox'))
$script:RunsRoot = Join-Path $script:SandboxRoot 'runs'
$script:ClaudeProfileRoot = Join-Path $script:SandboxRoot 'claude-profile'

function Get-RepositoryRoot { return $script:RepositoryRoot }
function Get-SandboxRoot { return $script:SandboxRoot }
function Get-ClaudeProfileRoot { return $script:ClaudeProfileRoot }

function Test-PathPrefix {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $resolvedPath.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedPath.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-SandboxIgnored {
    $probe = '.sandbox/ignore-probe'
    & git -C $script:RepositoryRoot check-ignore --quiet -- $probe
    if ($LASTEXITCODE -ne 0) {
        throw '.sandbox must be ignored before any test files are created'
    }
}

function Assert-TestPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowProfile
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathPrefix -Path $resolvedPath -Root $script:SandboxRoot)) {
        throw "Test path is outside repository sandbox: $resolvedPath"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE) -and (Test-PathPrefix -Path $resolvedPath -Root $env:USERPROFILE)) {
        throw "Test path resolves inside the protected user profile: $resolvedPath"
    }
    if (-not $AllowProfile -and (Test-PathPrefix -Path $resolvedPath -Root $script:ClaudeProfileRoot)) {
        throw "Run cleanup must not target the persistent Claude test profile: $resolvedPath"
    }
    return $resolvedPath
}

function New-SandboxRun {
    Assert-SandboxIgnored
    $leaf = [guid]::NewGuid().ToString('N')
    $runRoot = Join-Path $script:RunsRoot $leaf
    $resolved = Assert-TestPath -Path $runRoot
    New-Item -ItemType Directory -Force -Path $resolved | Out-Null
    return $resolved
}

function Remove-SandboxRun {
    param([Parameter(Mandatory)][string]$RunRoot)

    $resolved = Assert-TestPath -Path $RunRoot
    if (-not (Test-PathPrefix -Path $resolved -Root $script:RunsRoot)) {
        throw "Cleanup target is not a sandbox run: $resolved"
    }
    $leaf = Split-Path -Leaf $resolved
    if ($leaf -notmatch '^[0-9a-f]{32}$') {
        throw "Cleanup target does not have a run identifier: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Assert-InstallerDestinationOutput {
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$ExpectedDestination
    )

    $expected = [System.IO.Path]::GetFullPath($ExpectedDestination)
    if (-not $Output.Contains("-> $expected")) {
        throw "Installer did not report the expected destination: $expected"
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $protectedProfile = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\', '/')
        if (-not (Test-PathPrefix -Path $expected -Root $protectedProfile) -and $Output.Contains("-> $protectedProfile")) {
            throw "STOP: installer output resolved inside the protected user profile $protectedProfile. Do not inspect, modify, restore, or delete that location"
        }
    }
}
