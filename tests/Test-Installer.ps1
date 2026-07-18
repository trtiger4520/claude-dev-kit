Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Test-Sandbox.ps1')

$repositoryRoot = Get-RepositoryRoot
$installer = Join-Path $repositoryRoot 'install.ps1'
$runRoot = New-SandboxRun

function Get-TreeSnapshot {
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) { return '' }
    $items = foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        "$relative=$((Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash)"
    }
    return ($items -join "`n")
}

function Invoke-Installer {
    param(
        [string]$Destination,
        [switch]$DryRun
    )

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer)
    if ($Destination) { $arguments += @('-Destination', $Destination) }
    if ($DryRun) { $arguments += '-DryRun' }
    $output = '' | & pwsh @arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Assert-Success {
    param([Parameter(Mandatory)]$Result, [string]$Operation)
    if ($Result.ExitCode -ne 0) { throw "$Operation failed: $($Result.Output)" }
}

$environmentNames = @(
    'CDK_MODEL_EXPLORER', 'CDK_MODEL_IMPLEMENTER', 'CDK_MODEL_PLANNER', 'CDK_MODEL_VERIFIER',
    'CDK_EFFORT_EXPLORER', 'CDK_EFFORT_IMPLEMENTER', 'CDK_EFFORT_PLANNER', 'CDK_EFFORT_VERIFIER',
    'CLAUDE_CONFIG_DIR'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = if (Test-Path "Env:$name") { (Get-Item "Env:$name").Value } else { $null }
}

try {
    $env:CDK_MODEL_EXPLORER = 'sonnet'
    $env:CDK_MODEL_IMPLEMENTER = 'sonnet'
    $env:CDK_MODEL_PLANNER = 'inherit'
    $env:CDK_MODEL_VERIFIER = 'inherit'
    $env:CDK_EFFORT_EXPLORER = 'low'
    $env:CDK_EFFORT_IMPLEMENTER = 'medium'
    $env:CDK_EFFORT_PLANNER = 'inherit'
    $env:CDK_EFFORT_VERIFIER = 'high'
    Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

    $installRoot = Assert-TestPath -Path (Join-Path $runRoot 'install-root')
    New-Item -ItemType Directory -Path $installRoot | Out-Null
    $initialSettings = [ordered]@{
        permissions = [ordered]@{ deny = @('Read(./.env)') }
        hooks = [ordered]@{ Stop = @([ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'existing-stop-hook' }) }) }
    }
    $initialSettings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $installRoot 'settings.json') -Encoding utf8NoBOM

    $beforeDryRun = Get-TreeSnapshot -Root $installRoot
    $dryRun = Invoke-Installer -Destination $installRoot -DryRun
    Assert-Success -Result $dryRun -Operation 'Explicit destination dry-run'
    Assert-InstallerDestinationOutput -Output $dryRun.Output -ExpectedDestination $installRoot
    if ($beforeDryRun -ne (Get-TreeSnapshot -Root $installRoot)) { throw 'Dry-run changed the destination tree' }

    $install = Invoke-Installer -Destination $installRoot
    Assert-Success -Result $install -Operation 'Explicit destination install'
    Assert-InstallerDestinationOutput -Output $install.Output -ExpectedDestination $installRoot
    foreach ($relativePath in @(
        'CLAUDE.md', 'settings.json', 'agents/explorer.md', 'agents/implementer.md',
        'agents/planner.md', 'agents/verifier.md', 'commands/orchestrate.md', 'commands/verify.md',
        'hooks/risky-change-trigger.ps1', 'skills/source-boundary/SKILL.md',
        'skills/source-boundary/scripts/Test-SourceBoundary.ps1'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $installRoot $relativePath) -PathType Leaf)) {
            throw "Installed file is missing: $relativePath"
        }
    }

    $settings = Get-Content -Raw -LiteralPath (Join-Path $installRoot 'settings.json') | ConvertFrom-Json -Depth 30
    if ($settings.permissions.deny[0] -ne 'Read(./.env)') { throw 'Installer changed an unrelated settings key' }
    if (-not $settings.hooks.Stop) { throw 'Installer removed an unrelated hook event' }
    $riskCommands = @($settings.hooks.UserPromptSubmit | ForEach-Object { $_.hooks } | Where-Object { $_.command -match 'risky-change-trigger' })
    if ($riskCommands.Count -ne 1) { throw 'Installer did not merge exactly one risk hook' }
    $expectedHookPath = Join-Path $installRoot 'hooks/risky-change-trigger.ps1'
    if (-not $riskCommands[0].command.Contains($expectedHookPath)) { throw 'Risk hook command does not use the explicit destination' }

    $firstInstallSnapshot = Get-TreeSnapshot -Root $installRoot
    $repeat = Invoke-Installer -Destination $installRoot
    Assert-Success -Result $repeat -Operation 'Idempotent reinstall'
    if ($firstInstallSnapshot -ne (Get-TreeSnapshot -Root $installRoot)) { throw 'Idempotent reinstall changed installed files' }

    $explorerPath = Join-Path $installRoot 'agents/explorer.md'
    $explorerContent = Get-Content -Raw -LiteralPath $explorerPath
    $explorerContent = $explorerContent.Replace('model: sonnet', 'model: haiku').Replace('effort: low', 'effort: high')
    Set-Content -LiteralPath $explorerPath -Value $explorerContent -Encoding utf8NoBOM -NoNewline
    Remove-Item Env:CDK_MODEL_EXPLORER
    Remove-Item Env:CDK_EFFORT_EXPLORER
    $preserve = Invoke-Installer -Destination $installRoot
    Assert-Success -Result $preserve -Operation 'Model preservation reinstall'
    $preservedExplorer = Get-Content -Raw -LiteralPath $explorerPath
    if (-not $preservedExplorer.Contains('model: haiku') -or -not $preservedExplorer.Contains('effort: high')) {
        throw 'Installer did not preserve existing model and effort settings'
    }
    $env:CDK_MODEL_EXPLORER = 'sonnet'
    $env:CDK_EFFORT_EXPLORER = 'low'

    $claudePath = Join-Path $installRoot 'CLAUDE.md'
    Set-Content -LiteralPath $claudePath -Value 'sandbox previous CLAUDE content' -Encoding utf8NoBOM
    $backupInstall = Invoke-Installer -Destination $installRoot
    Assert-Success -Result $backupInstall -Operation 'CLAUDE backup install'
    $backupPath = "$claudePath.bak"
    if ((Get-Content -Raw -LiteralPath $backupPath).Trim() -ne 'sandbox previous CLAUDE content') {
        throw 'CLAUDE.md backup did not preserve the previous content'
    }
    $backupHash = (Get-FileHash -LiteralPath $backupPath).Hash
    $unchangedInstall = Invoke-Installer -Destination $installRoot
    Assert-Success -Result $unchangedInstall -Operation 'Unchanged CLAUDE reinstall'
    if ($backupHash -ne (Get-FileHash -LiteralPath $backupPath).Hash) { throw 'Unchanged CLAUDE reinstall rewrote the backup' }

    $invalidRoot = Assert-TestPath -Path (Join-Path $runRoot 'invalid-settings')
    New-Item -ItemType Directory -Path $invalidRoot | Out-Null
    $invalidSettingsPath = Join-Path $invalidRoot 'settings.json'
    Set-Content -LiteralPath $invalidSettingsPath -Value '{ invalid json' -Encoding utf8NoBOM -NoNewline
    $invalidBefore = Get-TreeSnapshot -Root $invalidRoot
    $invalidDryRun = Invoke-Installer -Destination $invalidRoot -DryRun
    Assert-InstallerDestinationOutput -Output $invalidDryRun.Output -ExpectedDestination $invalidRoot
    if ($invalidDryRun.ExitCode -eq 0) { throw 'Invalid settings dry-run unexpectedly succeeded' }
    if ($invalidBefore -ne (Get-TreeSnapshot -Root $invalidRoot)) { throw 'Invalid settings dry-run changed files' }
    if ((Get-Content -Raw -LiteralPath $invalidSettingsPath) -ne '{ invalid json') { throw 'Invalid settings file was overwritten' }
    $invalidInstall = Invoke-Installer -Destination $invalidRoot
    if ($invalidInstall.ExitCode -eq 0) { throw 'Invalid settings install unexpectedly succeeded' }
    if ((Get-Content -Raw -LiteralPath $invalidSettingsPath) -ne '{ invalid json') { throw 'Invalid settings install overwrote settings.json' }
    if (Test-Path -LiteralPath "$invalidSettingsPath.bak") { throw 'Invalid settings install created a misleading backup' }

    $environmentRoot = Assert-TestPath -Path (Join-Path $runRoot 'environment-root')
    $env:CLAUDE_CONFIG_DIR = $environmentRoot
    $environmentDryRun = Invoke-Installer -DryRun
    Assert-Success -Result $environmentDryRun -Operation 'CLAUDE_CONFIG_DIR dry-run'
    Assert-InstallerDestinationOutput -Output $environmentDryRun.Output -ExpectedDestination $environmentRoot
    $environmentInstall = Invoke-Installer
    Assert-Success -Result $environmentInstall -Operation 'CLAUDE_CONFIG_DIR install'
    if (-not (Test-Path -LiteralPath (Join-Path $environmentRoot 'CLAUDE.md'))) { throw 'CLAUDE_CONFIG_DIR was not honored' }

    $explicitRoot = Assert-TestPath -Path (Join-Path $runRoot 'explicit-wins')
    $explicitDryRun = Invoke-Installer -Destination $explicitRoot -DryRun
    Assert-Success -Result $explicitDryRun -Operation 'Explicit precedence dry-run'
    Assert-InstallerDestinationOutput -Output $explicitDryRun.Output -ExpectedDestination $explicitRoot
    $explicitInstall = Invoke-Installer -Destination $explicitRoot
    Assert-Success -Result $explicitInstall -Operation 'Explicit precedence install'
    if (-not (Test-Path -LiteralPath (Join-Path $explicitRoot 'CLAUDE.md'))) { throw 'Explicit destination was not honored' }

    Write-Output 'PASS: sandboxed PowerShell installer'
}
finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $savedEnvironment[$name]) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item "Env:$name" $savedEnvironment[$name]
        }
    }
    Remove-SandboxRun -RunRoot $runRoot
}
