Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Test-Sandbox.ps1')

$repositoryRoot = Get-RepositoryRoot
$boundaryScript = Join-Path $repositoryRoot 'src/skills/source-boundary/scripts/Test-SourceBoundary.ps1'
$runRoot = New-SandboxRun

function Invoke-Boundary {
    param(
        [Parameter(Mandatory)][ValidateSet('Capture', 'Verify')][string]$Mode,
        [Parameter(Mandatory)][string]$Snapshot,
        [Parameter(Mandatory)][string]$Repository,
        [string[]]$AllowedWrite = @()
    )

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $boundaryScript, '-Mode', $Mode, '-SnapshotFile', $Snapshot, '-Repository', $Repository)
    foreach ($pattern in $AllowedWrite) { $arguments += @('-AllowedWrite', $pattern) }
    $output = & pwsh @arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

try {
    $projectRoot = Assert-TestPath -Path (Join-Path $runRoot 'project')
    $snapshotPath = Assert-TestPath -Path (Join-Path $runRoot 'snapshot.json')
    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'src') | Out-Null
    Set-Content -LiteralPath (Join-Path $projectRoot 'src/app.txt') -Value 'baseline' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $projectRoot '.gitignore') -Value 'ignored/' -Encoding utf8NoBOM
    & git -C $projectRoot init --quiet
    & git -C $projectRoot add -A
    & git -C $projectRoot -c user.name='Claude Dev Kit Test' -c user.email='test@example.invalid' commit --quiet -m 'baseline'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create source-boundary fixture repository' }

    $capture = Invoke-Boundary -Mode Capture -Snapshot $snapshotPath -Repository $projectRoot
    if ($capture.ExitCode -ne 0) { throw "Boundary capture failed: $($capture.Output)" }
    $unchanged = Invoke-Boundary -Mode Verify -Snapshot $snapshotPath -Repository $projectRoot
    if ($unchanged.ExitCode -ne 0 -or -not $unchanged.Output.Contains('PASS: source boundary preserved')) {
        throw "Unchanged boundary verification failed: $($unchanged.Output)"
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'generated') | Out-Null
    Set-Content -LiteralPath (Join-Path $projectRoot 'generated/result.txt') -Value 'allowed' -Encoding utf8NoBOM
    $allowed = Invoke-Boundary -Mode Verify -Snapshot $snapshotPath -Repository $projectRoot -AllowedWrite 'generated/**'
    if ($allowed.ExitCode -ne 0) { throw "Allowed generated write was rejected: $($allowed.Output)" }

    Set-Content -LiteralPath (Join-Path $projectRoot 'src/app.txt') -Value 'unexpected verifier edit' -Encoding utf8NoBOM
    $violation = Invoke-Boundary -Mode Verify -Snapshot $snapshotPath -Repository $projectRoot -AllowedWrite 'generated/**'
    if ($violation.ExitCode -eq 0 -or -not $violation.Output.Contains('Source boundary violation: src/app.txt')) {
        throw "Unexpected source write was not rejected: $($violation.Output)"
    }

    Write-Output 'PASS: source-boundary capture and verification'
}
finally {
    Remove-SandboxRun -RunRoot $runRoot
}
