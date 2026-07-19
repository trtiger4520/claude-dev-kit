[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ForceLogin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Test-Sandbox.ps1')

Assert-SandboxIgnored
if ($CheckOnly -and $ForceLogin) { throw 'Use either -CheckOnly or -ForceLogin, not both' }
$profileRoot = Assert-TestPath -Path (Get-ClaudeProfileRoot) -AllowProfile
$temporaryRoot = Assert-TestPath -Path (Join-Path $profileRoot 'tmp') -AllowProfile
$claude = Get-Command claude -ErrorAction Stop

New-Item -ItemType Directory -Force -Path $profileRoot, $temporaryRoot | Out-Null
$env:CLAUDE_CONFIG_DIR = $profileRoot
$env:CLAUDE_CODE_TMPDIR = $temporaryRoot
$env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = '1'

& $claude.Source auth status *> $null
if ($LASTEXITCODE -eq 0 -and -not $ForceLogin) {
    Write-Output "PASS: isolated Claude profile is authenticated at $profileRoot"
    exit 0
}

if ($CheckOnly) {
    throw "Isolated Claude profile is not authenticated. Run: pwsh -NoProfile -File `"$PSCommandPath`""
}

if ($ForceLogin) {
    Write-Host "Refreshing Claude login for isolated profile after a live API authentication failure: $profileRoot"
}
else {
    Write-Host "Starting one-time Claude login for isolated profile: $profileRoot"
}
& $claude.Source auth login --claudeai
if ($LASTEXITCODE -ne 0) { throw 'Isolated Claude login failed' }

& $claude.Source auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'Claude login completed but isolated auth status still fails' }

Write-Output "PASS: isolated Claude profile authenticated at $profileRoot"
