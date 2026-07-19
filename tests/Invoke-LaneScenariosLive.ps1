[CmdletBinding()]
param(
    [switch]$All,
    [string[]]$ScenarioId,
    [ValidateRange(0.01, 1000)]
    [decimal]$MaxBudgetUsd = 0.50,
    [Parameter(Mandatory)]
    [ValidateRange(0.01, 1000)]
    [decimal]$ApprovedTotalBudgetUsd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Test-Sandbox.ps1')
. (Join-Path $PSScriptRoot 'LaneScenario.Common.ps1')

$repositoryRoot = Get-RepositoryRoot
$profileRoot = Assert-TestPath -Path (Get-ClaudeProfileRoot) -AllowProfile
$scenarioPath = Join-Path $PSScriptRoot 'references/lane-scenarios.v1.json'
$schemaPath = Join-Path $PSScriptRoot 'references/lane-evaluation-result.schema.json'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures/lane-project'
$installer = Join-Path $repositoryRoot 'install.ps1'
$matrix = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json -Depth 30
$schemaJson = Get-Content -Raw -LiteralPath $schemaPath
$claude = Get-Command claude -ErrorAction Stop
$runRoot = New-SandboxRun

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments,
        [int]$TimeoutMilliseconds = 60000
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $process.StandardInput.Close()
    $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
    $standardErrorTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        $process.Kill($true)
        throw "Process timed out after $TimeoutMilliseconds ms: $FilePath"
    }
    $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
    $standardError = $standardErrorTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $standardOutput
        StandardError = $standardError
    }
}

$environmentNames = @(
    'CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_TMPDIR', 'CLAUDE_CODE_DISABLE_AUTO_MEMORY',
    'CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS', 'MAX_STRUCTURED_OUTPUT_RETRIES'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = if (Test-Path "Env:$name") { (Get-Item "Env:$name").Value } else { $null }
}

try {
    Assert-SandboxIgnored
    if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
        throw "Isolated Claude profile is missing. Run tests/Initialize-ClaudeSandbox.ps1 first: $profileRoot"
    }

    $temporaryRoot = Assert-TestPath -Path (Join-Path $runRoot 'tmp')
    $projectRoot = Assert-TestPath -Path (Join-Path $runRoot 'project')
    New-Item -ItemType Directory -Force -Path $temporaryRoot, $projectRoot | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot '*') -Destination $projectRoot -Recurse -Force
    & git -C $projectRoot init --quiet
    & git -C $projectRoot add -A
    & git -C $projectRoot -c user.name='Claude Dev Kit Test' -c user.email='test@example.invalid' commit --quiet -m 'baseline'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize live lane fixture repository' }

    $env:CLAUDE_CONFIG_DIR = $profileRoot
    $env:CLAUDE_CODE_TMPDIR = $temporaryRoot
    $env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = '1'
    $env:CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS = '1'
    $env:MAX_STRUCTURED_OUTPUT_RETRIES = '2'

    $dryRun = Invoke-ExternalProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Destination', $profileRoot, '-DryRun')
    if ($dryRun.ExitCode -ne 0) { throw "Sandbox profile installer dry-run failed: $($dryRun.StandardError)$($dryRun.StandardOutput)" }
    Assert-InstallerDestinationOutput -Output ($dryRun.StandardOutput + $dryRun.StandardError) -ExpectedDestination $profileRoot
    $install = Invoke-ExternalProcess -FilePath (Get-Command pwsh).Source -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Destination', $profileRoot)
    if ($install.ExitCode -ne 0) { throw "Sandbox profile install failed: $($install.StandardError)$($install.StandardOutput)" }
    Assert-InstallerDestinationOutput -Output ($install.StandardOutput + $install.StandardError) -ExpectedDestination $profileRoot

    $auth = Invoke-ExternalProcess -FilePath $claude.Source -Arguments @('auth', 'status')
    if ($auth.ExitCode -ne 0) {
        throw 'Isolated Claude profile is not authenticated. Run tests/Initialize-ClaudeSandbox.ps1; live evaluation will not fall back to the user profile'
    }

    if ($All -and $ScenarioId) { throw 'Use either -All or -ScenarioId, not both' }
    if ($All) {
        $selectedScenarios = @($matrix.scenarios)
    }
    elseif ($ScenarioId) {
        $selectedScenarios = @($matrix.scenarios | Where-Object { $_.id -in $ScenarioId })
        $missing = @($ScenarioId | Where-Object { $_ -notin $selectedScenarios.id })
        if ($missing.Count -gt 0) { throw "Unknown scenario ids: $($missing -join ', ')" }
    }
    else {
        $selectedScenarios = @($matrix.scenarios | Where-Object { $_.id -in $matrix.smoke_scenarios })
    }

    $totalObservedCost = [decimal]0
    Write-Output "LIVE BUDGET: scenarios=$($selectedScenarios.Count) approved_total_usd=$ApprovedTotalBudgetUsd per_scenario_cap_usd=$MaxBudgetUsd"
    foreach ($scenario in $selectedScenarios) {
        $remainingBudget = $ApprovedTotalBudgetUsd - $totalObservedCost
        if ($remainingBudget -lt 0.01) {
            throw "Approved live budget exhausted before '$($scenario.id)': approved=$ApprovedTotalBudgetUsd observed=$totalObservedCost"
        }
        $scenarioBudget = [decimal][math]::Min([double]$MaxBudgetUsd, [double]$remainingBudget)
        $budget = $scenarioBudget.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $prompt = @"
Classify this hypothetical task using the installed global CLAUDE.md policy
Do not execute the task, modify files, invoke skills, or dispatch agents
Return only the structured lane evaluation

Task: $($scenario.prompt)
"@
        $arguments = @(
            '-p', $prompt,
            '--tools', '',
            '--disallowed-tools', 'Agent',
            '--disable-slash-commands',
            '--no-session-persistence',
            '--output-format', 'json',
            '--json-schema', $schemaJson,
            '--max-turns', '2',
            '--model', 'sonnet',
            '--effort', 'low',
            '--max-budget-usd', $budget,
            '--setting-sources', 'user'
        )
        $evaluation = Invoke-ExternalProcess -FilePath $claude.Source -Arguments $arguments
        if ($evaluation.ExitCode -ne 0) {
            $budgetFailure = $null
            try {
                $failureResult = $evaluation.StandardOutput | ConvertFrom-Json -Depth 30
                $observedCost = if ($null -ne $failureResult.total_cost_usd) { [decimal]$failureResult.total_cost_usd } else { [decimal]0 }
                $totalObservedCost += $observedCost
                if ($failureResult.subtype -eq 'error_max_budget_usd') {
                    $budgetFailure = "Claude live evaluation exceeded the per-scenario budget for '$($scenario.id)': limit=$budget USD, scenario_observed=$observedCost USD, approved_total=$ApprovedTotalBudgetUsd USD, aggregate_observed=$totalObservedCost USD"
                }
            }
            catch {
                $budgetFailure = $null
            }
            if ($budgetFailure) { throw $budgetFailure }
            throw "Claude live evaluation failed for '$($scenario.id)': $($evaluation.StandardError)$($evaluation.StandardOutput)"
        }
        $wrapper = $evaluation.StandardOutput | ConvertFrom-Json -Depth 30
        $scenarioCost = if ($null -ne $wrapper.total_cost_usd) { [decimal]$wrapper.total_cost_usd } else { [decimal]0 }
        $totalObservedCost += $scenarioCost
        if ($totalObservedCost -gt $ApprovedTotalBudgetUsd) {
            throw "Observed live cost exceeded the approved total after '$($scenario.id)': approved=$ApprovedTotalBudgetUsd observed=$totalObservedCost"
        }
        if ($null -eq $wrapper.structured_output) {
            throw "Scenario '$($scenario.id)' returned no structured_output: scenario_cost=$scenarioCost aggregate_observed=$totalObservedCost"
        }
        $resultJson = $wrapper.structured_output | ConvertTo-Json -Depth 20 -Compress
        if (-not (Test-Json -Json $resultJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
            throw "Scenario '$($scenario.id)' returned an invalid structured result: scenario_cost=$scenarioCost aggregate_observed=$totalObservedCost result=$resultJson"
        }
        try { Assert-LaneEvaluation -Scenario $scenario -Result $wrapper.structured_output }
        catch { throw "$($_.Exception.Message); scenario_cost=$scenarioCost aggregate_observed=$totalObservedCost" }
        $scenarioCostText = $scenarioCost.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
        Write-Output "PASS: $($scenario.id) (observed_cost_usd=$scenarioCostText aggregate_observed_usd=$totalObservedCost)"
    }

    $totalCostText = $totalObservedCost.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
    Write-Output "Live lane scenarios passed: $($selectedScenarios.Count) (observed_cost_usd=$totalCostText)"
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
