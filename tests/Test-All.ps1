[CmdletBinding()]
param(
    [switch]$Live,
    [switch]$AllLive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Test-Sandbox.ps1')
Assert-SandboxIgnored

foreach ($test in @('Test-Policy.ps1', 'Test-Hooks.ps1', 'Test-LaneScenarios.ps1', 'Test-LiveRunner.ps1', 'Test-Installer.ps1', 'Test-SourceBoundary.ps1')) {
    $path = Join-Path $PSScriptRoot $test
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $test" }
}

$gitBash = 'C:\Program Files\Git\usr\bin\bash.exe'
if (Test-Path -LiteralPath $gitBash -PathType Leaf) {
    & $gitBash (Join-Path $PSScriptRoot 'Test-Shell.sh')
    if ($LASTEXITCODE -ne 0) { throw 'Git Bash smoke test failed' }
}
else {
    Write-Warning 'Git Bash not found; shell smoke test was skipped'
}

if ($Live -or $AllLive) {
    $liveArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-LaneScenariosLive.ps1'))
    if ($AllLive) { $liveArguments += '-All' }
    & pwsh @liveArguments
    if ($LASTEXITCODE -ne 0) { throw 'Claude live lane evaluation failed' }
}

Write-Output 'PASS: Claude Dev Kit test suite'
