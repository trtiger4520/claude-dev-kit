[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Calibrate', 'Complete')]
    [string]$Phase,

    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$BenchmarkId,

    [Parameter(Mandatory)]
    [ValidateRange(0.01, 1000)]
    [decimal]$ApprovedBudgetUsd,

    [decimal]$ClassificationBudgetUsd = 0.50,
    [decimal]$StandardRunBudgetUsd = 0.75,
    [decimal]$HeavyRunBudgetUsd = 2.00,
    [switch]$RetryFailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CostBenchmark.Common.ps1')
. (Join-Path $PSScriptRoot 'LaneScenario.Common.ps1')

function Write-Utf8Json {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $json = $Value | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Update-StoredQualityContract {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$Definition
    )

    $targetVersion = Get-CostBenchmarkQualityContractVersion
    $manifestVersion = [string](Get-PropertyValue $Manifest 'quality_contract_version' '')
    if (-not [string]::IsNullOrWhiteSpace($manifestVersion) -and $manifestVersion -ne $targetVersion) {
        throw "Unsupported benchmark quality contract version: $manifestVersion"
    }

    $updatedCount = 0
    $recordsRoot = Join-Path $RunRoot 'records'
    if (Test-Path -LiteralPath $recordsRoot -PathType Container) {
        foreach ($recordFile in Get-ChildItem -LiteralPath $recordsRoot -Filter '*.json') {
            $record = Get-Content -Raw -LiteralPath $recordFile.FullName | ConvertFrom-Json -Depth 50
            if ([string](Get-PropertyValue $record 'quality_contract_version' '') -eq $targetVersion) { continue }
            $task = $Definition.tasks | Where-Object { $_.id -eq $record.task_id } | Select-Object -First 1
            if ($null -eq $task) { throw "Unknown task in stored benchmark record: $($record.task_id)" }
            $record = Update-CostBenchmarkRecordQualityContract -Record $record -Task $task
            Write-Utf8Json -Value $record -Path $recordFile.FullName
            $updatedCount++
        }
    }
    if ($manifestVersion -ne $targetVersion) {
        Set-PropertyValue -Object $Manifest -Name 'quality_contract_version' -Value $targetVersion
        Write-Utf8Json -Value $Manifest -Path (Join-Path $RunRoot 'manifest.json')
    }
    return $updatedCount
}

function Invoke-ExternalJsonProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [int]$TimeoutMilliseconds = 120000
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$process.Start()
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw "Process timed out after $TimeoutMilliseconds ms: $FilePath"
    }
    $watch.Stop()
    return [pscustomobject]@{
        exit_code = $process.ExitCode
        stdout = $stdoutTask.GetAwaiter().GetResult()
        stderr = $stderrTask.GetAwaiter().GetResult()
        wall_seconds = $watch.Elapsed.TotalSeconds
    }
}

function New-UserStreamMessage {
    param([Parameter(Mandatory)][string]$Text)
    return ([ordered]@{
        type = 'user'
        message = [ordered]@{
            role = 'user'
            content = @([ordered]@{ type = 'text'; text = $Text })
        }
    } | ConvertTo-Json -Depth 10 -Compress)
}

function Invoke-ClaudeStreamProcess {
    param(
        [Parameter(Mandatory)][string]$ClaudePath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][decimal]$BudgetUsd,
        [Parameter(Mandatory)][string]$Strategy,
        [Parameter(Mandatory)][string]$RawOutputPath,
        [switch]$RequiresApproval,
        [int]$TimeoutMilliseconds = 1800000
    )

    $allowedTools = 'Read,Glob,Grep,Edit,Write,Bash(dotnet *),Bash(git status *),Bash(git diff *),Agent'
    $arguments = @(
        '-p',
        '--input-format', 'stream-json',
        '--output-format', 'stream-json',
        '--verbose',
        '--include-hook-events',
        '--no-session-persistence',
        '--model', 'sonnet',
        '--effort', 'low',
        '--permission-mode', 'acceptEdits',
        '--allowed-tools', $allowedTools,
        '--max-turns', '30',
        '--max-budget-usd', $BudgetUsd.ToString([System.Globalization.CultureInfo]::InvariantCulture),
        '--setting-sources', 'user'
    )
    if ($Strategy -eq 'forced-single') { $arguments += @('--disallowed-tools', 'Agent') }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ClaudePath
    $startInfo.WorkingDirectory = $ProjectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $lines = [System.Collections.Generic.List[string]]::new()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $approvalSent = $false
    [void]$process.Start()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine((New-UserStreamMessage -Text $Prompt))
    $process.StandardInput.Flush()
    if (-not $RequiresApproval) { $process.StandardInput.Close() }

    $readTask = $process.StandardOutput.ReadLineAsync()
    while ($true) {
        if ($readTask.Wait(250)) {
            $line = $readTask.GetAwaiter().GetResult()
            if ($null -eq $line) { break }
            $lines.Add($line)
            if ($RequiresApproval -and -not $approvalSent -and $line.Contains('BENCHMARK_APPROVAL_REQUIRED', [System.StringComparison]::Ordinal)) {
                $changesBeforeApproval = @(Get-ChangedRepositoryFiles -ProjectRoot $ProjectRoot)
                if ($changesBeforeApproval.Count -gt 0) {
                    $process.Kill($true)
                    throw "Heavy benchmark changed files before approval: $($changesBeforeApproval -join ', ')"
                }
                $approvalText = 'Approved. Execute the presented plan exactly within the original scope, run the requested deterministic verification, and complete the final report.'
                $process.StandardInput.WriteLine((New-UserStreamMessage -Text $approvalText))
                $process.StandardInput.Flush()
                $process.StandardInput.Close()
                $approvalSent = $true
            }
            $readTask = $process.StandardOutput.ReadLineAsync()
        }
        if ($watch.ElapsedMilliseconds -gt $TimeoutMilliseconds) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Claude benchmark timed out after $TimeoutMilliseconds ms"
        }
        if ($process.HasExited -and $readTask.IsCompleted) { continue }
    }
    if (-not $process.HasExited) { $process.WaitForExit() }
    $watch.Stop()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [System.IO.File]::WriteAllLines($RawOutputPath, $lines, [System.Text.UTF8Encoding]::new($false))
    if ($stderr) {
        [System.IO.File]::WriteAllText("$RawOutputPath.stderr.txt", $stderr, [System.Text.UTF8Encoding]::new($false))
    }
    return [pscustomobject]@{
        exit_code = $process.ExitCode
        lines = @($lines)
        wall_seconds = $watch.Elapsed.TotalSeconds
        approval_turns = if ($approvalSent) { 1 } else { 0 }
        stderr = $stderr
    }
}

function Initialize-BenchmarkProject {
    param([Parameter(Mandatory)][string]$RunRoot, [Parameter(Mandatory)][string]$CellKey)

    if ($CellKey -notmatch '^[a-z0-9-]+$') { throw "Unsafe benchmark cell key: $CellKey" }
    $projectsRoot = Assert-TestPath -Path (Join-Path $RunRoot 'projects')
    $projectRoot = Assert-TestPath -Path (Join-Path $projectsRoot $CellKey)
    New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null
    Copy-Item -Path (Join-Path (Get-CostBenchmarkFixtureRoot) '*') -Destination $projectRoot -Recurse -Force
    $baseline = & dotnet run --project (Join-Path $projectRoot 'tests/BenchmarkChecks/BenchmarkChecks.csproj') -- baseline 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Benchmark fixture baseline failed: $baseline" }
    & git -C $projectRoot init --quiet
    & git -C $projectRoot add -A
    & git -C $projectRoot -c user.name='Claude Dev Kit Benchmark' -c user.email='benchmark@example.invalid' commit --quiet -m 'baseline'
    if ($LASTEXITCODE -ne 0) { throw "Unable to initialize benchmark project: $CellKey" }
    return $projectRoot
}

function Remove-BenchmarkProject {
    param([Parameter(Mandatory)][string]$RunRoot, [Parameter(Mandatory)][string]$ProjectRoot)
    $projectsRoot = Assert-TestPath -Path (Join-Path $RunRoot 'projects')
    $resolvedProject = Assert-TestPath -Path $ProjectRoot
    if (-not (Test-PathPrefix -Path $resolvedProject -Root $projectsRoot)) {
        throw "Refusing benchmark project cleanup outside projects root: $resolvedProject"
    }
    Remove-Item -LiteralPath $resolvedProject -Recurse -Force
}

function ConvertFrom-ClassificationWrapper {
    param(
        [Parameter(Mandatory)]$Cell,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$Wrapper,
        [Parameter(Mandatory)][double]$WallSeconds
    )

    $changedFiles = @(Get-ChangedRepositoryFiles -ProjectRoot $ProjectRoot)
    $scopePass = $changedFiles.Count -eq 0
    if ($null -eq $Wrapper.structured_output) {
        $streamResult = [pscustomobject]@{
            result = $Wrapper
            assistant_text = [string](Get-PropertyValue $Wrapper 'result' '')
            roles = @()
            delegated_roles = ''
            subagent_count = 0
            observed_lane = 'unknown'
        }
        $outcome = [pscustomobject]@{
            checks = @([pscustomobject]@{ id = 'structured-output'; passed = $false; evidence = [string](Get-PropertyValue $Wrapper 'subtype' 'missing') })
            acceptance_passed = 0
            acceptance_total = 1
            acceptance_rate = 0
            test_pass = $true
            scope_pass = $scopePass
            quality_pass = $false
            changed_files = @($changedFiles)
            unexpected_files = @($changedFiles)
            test_output = ''
        }
        return [pscustomobject]@{ stream_result = $streamResult; outcome = $outcome; wall_seconds = $WallSeconds; approval_turns = 0 }
    }
    $declaredRoles = [System.Collections.Generic.List[string]]::new()
    foreach ($agent in @($Wrapper.structured_output.delegated_agents)) {
        for ($index = 0; $index -lt [int]$agent.count; $index++) { $declaredRoles.Add([string]$agent.role) }
    }
    $roleCounts = @($declaredRoles | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Count)" })
    $streamResult = [pscustomobject]@{
        result = $Wrapper
        assistant_text = [string]$Wrapper.structured_output.rationale
        roles = @($declaredRoles)
        delegated_roles = ($roleCounts -join ';')
        subagent_count = $declaredRoles.Count
        observed_lane = [string]$Wrapper.structured_output.lane
    }
    $lanePass = $streamResult.observed_lane -eq $Cell.task.expected_lane
    $outcome = [pscustomobject]@{
        checks = @([pscustomobject]@{ id = 'expected-lane'; passed = $lanePass; evidence = $streamResult.observed_lane })
        acceptance_passed = if ($lanePass) { 1 } else { 0 }
        acceptance_total = 1
        acceptance_rate = if ($lanePass) { 1 } else { 0 }
        test_pass = $true
        scope_pass = $scopePass
        quality_pass = $lanePass -and $scopePass
        changed_files = @($changedFiles)
        unexpected_files = @($changedFiles)
        test_output = ''
    }
    return [pscustomobject]@{ stream_result = $streamResult; outcome = $outcome; wall_seconds = $WallSeconds; approval_turns = 0 }
}

function Invoke-ClassificationCell {
    param(
        [Parameter(Mandatory)]$Cell,
        [Parameter(Mandatory)][string]$ClaudePath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][decimal]$BudgetUsd,
        [Parameter(Mandatory)][string]$SchemaJson,
        [Parameter(Mandatory)][string]$RawOutputPath
    )

    $prompt = @"
Classify this hypothetical task using the installed global CLAUDE.md policy
Do not execute the task, modify files, invoke skills, or dispatch agents
Return only the structured lane evaluation

Task: $($Cell.task.task_prompt)
"@
    $arguments = @(
        '-p', $prompt,
        '--tools', '',
        '--disallowed-tools', 'Agent',
        '--disable-slash-commands',
        '--no-session-persistence',
        '--output-format', 'json',
        '--json-schema', $SchemaJson,
        '--max-turns', '2',
        '--model', 'sonnet',
        '--effort', 'low',
        '--max-budget-usd', $BudgetUsd.ToString([System.Globalization.CultureInfo]::InvariantCulture),
        '--setting-sources', 'user'
    )
    $call = Invoke-ExternalJsonProcess -FilePath $ClaudePath -Arguments $arguments -WorkingDirectory $ProjectRoot
    [System.IO.File]::WriteAllText($RawOutputPath, $call.stdout, [System.Text.UTF8Encoding]::new($false))
    if ($call.stderr) { [System.IO.File]::WriteAllText("$RawOutputPath.stderr.txt", $call.stderr, [System.Text.UTF8Encoding]::new($false)) }
    $wrapper = $call.stdout | ConvertFrom-Json -Depth 50
    return ConvertFrom-ClassificationWrapper -Cell $Cell -ProjectRoot $ProjectRoot -Wrapper $wrapper -WallSeconds $call.wall_seconds
}

Assert-SandboxIgnored
$definition = Get-CostBenchmarkDefinition
$repositoryRoot = Get-RepositoryRoot
$policyFingerprint = Get-PolicyFingerprint -RepositoryRoot $repositoryRoot
$benchmarkInputFingerprint = Get-BenchmarkInputFingerprint
$claude = Get-Command claude -ErrorAction Stop
$claudeVersion = (& $claude.Source --version | Select-Object -First 1).Trim()
$profileRoot = Assert-TestPath -Path (Get-ClaudeProfileRoot) -AllowProfile

if ($Phase -eq 'Calibrate' -and -not $BenchmarkId) {
    $runRoot = New-SandboxRun
    $BenchmarkId = Split-Path -Leaf $runRoot
    $manifest = [ordered]@{
        version = '1.0'
        benchmark_id = $BenchmarkId
        created_utc = [DateTime]::UtcNow.ToString('o')
        target_repetitions = [int]$definition.target_repetitions
        claude_version = $claudeVersion
        policy_fingerprint = $policyFingerprint
        benchmark_input_fingerprint = $benchmarkInputFingerprint
        quality_contract_version = Get-CostBenchmarkQualityContractVersion
        fixture = 'cost-benchmark'
    }
    foreach ($directory in @('raw', 'records', 'attempts', 'projects', 'tmp')) {
        New-Item -ItemType Directory -Force -Path (Assert-TestPath -Path (Join-Path $runRoot $directory)) | Out-Null
    }
    Write-Utf8Json -Value $manifest -Path (Join-Path $runRoot 'manifest.json')
}
else {
    if (-not $BenchmarkId) { throw '-BenchmarkId is required when continuing an existing benchmark' }
    $runRoot = Get-CostBenchmarkRunRoot -BenchmarkId $BenchmarkId -RequireExisting
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $runRoot 'manifest.json') | ConvertFrom-Json -Depth 20
    if ($manifest.policy_fingerprint -ne $policyFingerprint) {
        throw 'Policy fingerprint changed after calibration; start a new benchmark to keep comparisons valid'
    }
    if ([string](Get-PropertyValue $manifest 'benchmark_input_fingerprint' '') -ne $benchmarkInputFingerprint) {
        throw 'Benchmark task definition or fixture changed after calibration; start a new benchmark to keep comparisons valid'
    }
    if ($manifest.claude_version -ne $claudeVersion) {
        throw 'Claude CLI version changed after calibration; start a new benchmark to keep comparisons valid'
    }
}
$qualityMigrationCount = Update-StoredQualityContract -RunRoot $runRoot -Manifest $manifest -Definition $definition
if ($qualityMigrationCount -gt 0) {
    Write-Output "QUALITY CONTRACT: migrated_records=$qualityMigrationCount version=$(Get-CostBenchmarkQualityContractVersion)"
}
Write-Output "BENCHMARK: phase=$Phase benchmark_id=$BenchmarkId approved_budget_usd=$ApprovedBudgetUsd"
$budgetManifestField = if ($Phase -eq 'Calibrate') { 'calibration_approved_budget_usd' } else { 'complete_approved_budget_usd' }
Set-PropertyValue -Object $manifest -Name $budgetManifestField -Value $ApprovedBudgetUsd
Write-Utf8Json -Value $manifest -Path (Join-Path $runRoot 'manifest.json')

$environmentNames = @(
    'CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_TMPDIR', 'CLAUDE_CODE_DISABLE_AUTO_MEMORY',
    'CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS', 'CLAUDE_CODE_SKIP_PROMPT_HISTORY',
    'MAX_STRUCTURED_OUTPUT_RETRIES'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = if (Test-Path "Env:$name") { (Get-Item "Env:$name").Value } else { $null }
}

$invocationSpend = [decimal]0
$phaseSpend = Get-RecordedPhaseSpend -RunRoot $runRoot -Phase $Phase
if ($phaseSpend -gt $ApprovedBudgetUsd) {
    throw "Recorded phase cost already exceeds the approved budget: approved=$ApprovedBudgetUsd recorded=$phaseSpend"
}
try {
    $env:CLAUDE_CONFIG_DIR = $profileRoot
    $env:CLAUDE_CODE_TMPDIR = Assert-TestPath -Path (Join-Path $runRoot 'tmp')
    $env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = '1'
    $env:CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS = '1'
    $env:CLAUDE_CODE_SKIP_PROMPT_HISTORY = '1'
    $env:MAX_STRUCTURED_OUTPUT_RETRIES = '2'

    $auth = Invoke-ExternalJsonProcess -FilePath $claude.Source -Arguments @('auth', 'status') -WorkingDirectory $repositoryRoot -TimeoutMilliseconds 30000
    if ($auth.exit_code -ne 0) { throw 'Isolated Claude profile is not authenticated; benchmark will not fall back to the user profile' }

    $installer = Join-Path $repositoryRoot 'install.ps1'
    $pwsh = (Get-Command pwsh).Source
    $dryRun = Invoke-ExternalJsonProcess -FilePath $pwsh -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Destination', $profileRoot, '-DryRun') -WorkingDirectory $repositoryRoot
    if ($dryRun.exit_code -ne 0) { throw "Sandbox profile installer dry-run failed: $($dryRun.stderr)$($dryRun.stdout)" }
    Assert-InstallerDestinationOutput -Output ($dryRun.stdout + $dryRun.stderr) -ExpectedDestination $profileRoot
    $install = Invoke-ExternalJsonProcess -FilePath $pwsh -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-Destination', $profileRoot) -WorkingDirectory $repositoryRoot
    if ($install.exit_code -ne 0) { throw "Sandbox profile install failed: $($install.stderr)$($install.stdout)" }
    Assert-InstallerDestinationOutput -Output ($install.stdout + $install.stderr) -ExpectedDestination $profileRoot
    $installedPolicyFingerprint = Get-InstalledPolicyFingerprint -ProfileRoot $profileRoot
    $manifestInstalledFingerprint = [string](Get-PropertyValue $manifest 'installed_policy_fingerprint' '')
    if ([string]::IsNullOrWhiteSpace($manifestInstalledFingerprint)) {
        if ($Phase -ne 'Calibrate') { throw 'Calibration manifest has no installed policy fingerprint; start a new benchmark' }
        Set-PropertyValue -Object $manifest -Name 'installed_policy_fingerprint' -Value $installedPolicyFingerprint
        Write-Utf8Json -Value $manifest -Path (Join-Path $runRoot 'manifest.json')
    }
    elseif ($manifestInstalledFingerprint -ne $installedPolicyFingerprint) {
        throw 'Installed sandbox policy, agent model, or effort configuration changed after calibration; restore it or start a new benchmark'
    }

    $schemaJson = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'references/lane-evaluation-result.schema.json')
    $schedule = @(Get-CostBenchmarkSchedule -Definition $definition -Phase $Phase)
    foreach ($cell in $schedule) {
        $recordPath = Join-Path $runRoot "records/$($cell.key).json"
        if (Test-Path -LiteralPath $recordPath) {
            $existing = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 50
            if ($existing.status -ne 'error' -or -not $RetryFailed) {
                Write-Output "SKIP: $($cell.key)"
                continue
            }
            $attemptPath = Join-Path $runRoot "attempts/$($cell.key)--$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).json"
            Move-Item -LiteralPath $recordPath -Destination $attemptPath
        }

        $remainingBudget = $ApprovedBudgetUsd - $phaseSpend
        if ($remainingBudget -lt 0.01) { throw "Approved phase budget exhausted before $($cell.key)" }
        $cellCap = if ($cell.kind -eq 'classification') {
            $ClassificationBudgetUsd
        }
        elseif ($cell.strategy -eq 'forced-heavy' -or ($cell.strategy -eq 'current-policy' -and $cell.task.expected_lane -eq 'orchestrate-heavy')) {
            $HeavyRunBudgetUsd
        }
        else {
            $StandardRunBudgetUsd
        }
        $runBudget = [decimal][math]::Min([double]$cellCap, [double]$remainingBudget)
        $projectRoot = Initialize-BenchmarkProject -RunRoot $runRoot -CellKey $cell.key
        $rawPath = Join-Path $runRoot "raw/$($cell.key).jsonl"
        try {
            Write-Output "RUN: $($cell.key) budget=$runBudget USD"
            $recoveredFromRaw = $false
            if ($cell.kind -eq 'classification') {
                if ((Test-Path -LiteralPath $rawPath -PathType Leaf) -and -not $RetryFailed) {
                    $wrapper = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json -Depth 50
                    $recoveredWallSeconds = [double](Get-PropertyValue $wrapper 'duration_ms' 0) / 1000
                    $execution = ConvertFrom-ClassificationWrapper -Cell $cell -ProjectRoot $projectRoot -Wrapper $wrapper -WallSeconds $recoveredWallSeconds
                    $recoveredFromRaw = $true
                    Write-Output "RECOVER: $($cell.key) from existing raw result"
                }
                else {
                    $execution = Invoke-ClassificationCell -Cell $cell -ClaudePath $claude.Source -ProjectRoot $projectRoot -BudgetUsd $runBudget -SchemaJson $schemaJson -RawOutputPath $rawPath
                }
            }
            else {
                $requiresApproval = $cell.strategy -eq 'forced-heavy' -or ($cell.strategy -eq 'current-policy' -and $cell.task.expected_lane -eq 'orchestrate-heavy')
                $promptPrefix = if ($cell.strategy -eq 'forced-heavy') {
                    '/orchestrate '
                }
                elseif ($cell.strategy -eq 'forced-single') {
                    'This is a sandbox counterfactual benchmark. Complete the task directly in the main agent without delegation. '
                }
                else { '' }
                $approvalInstruction = if ($requiresApproval) {
                    "`nBefore any file write, present the plan and end that planning turn with BENCHMARK_APPROVAL_REQUIRED on its own line. Wait for the next user message before implementation."
                }
                else { '' }
                $call = Invoke-ClaudeStreamProcess -ClaudePath $claude.Source -ProjectRoot $projectRoot -Prompt ($promptPrefix + $cell.task.task_prompt + $approvalInstruction) -BudgetUsd $runBudget -Strategy $cell.strategy -RawOutputPath $rawPath -RequiresApproval:$requiresApproval
                $streamResult = ConvertFrom-ClaudeStream -Lines $call.lines
                $outcome = Test-CostBenchmarkOutcome -Task $cell.task -Strategy $cell.strategy -ProjectRoot $projectRoot -StreamResult $streamResult -ApprovalTurns $call.approval_turns
                $execution = [pscustomobject]@{ stream_result = $streamResult; outcome = $outcome; wall_seconds = $call.wall_seconds; approval_turns = $call.approval_turns }
            }
            $record = ConvertTo-CostBenchmarkRecord -BenchmarkId $BenchmarkId -Cell $cell -StreamResult $execution.stream_result -Outcome $execution.outcome -ClaudeVersion $claudeVersion -PolicyFingerprint $policyFingerprint -BudgetLimitUsd $runBudget -WallSeconds $execution.wall_seconds -ApprovalTurns $execution.approval_turns
            $record = Update-CostBenchmarkRecordQualityContract -Record $record -Task $cell.task
            Write-Utf8Json -Value $record -Path $recordPath
            $phaseSpend += [decimal]$record.total_cost_usd
            if (-not $recoveredFromRaw) { $invocationSpend += [decimal]$record.total_cost_usd }
            Write-Output "RESULT: $($cell.key) status=$($record.status) cost=$($record.total_cost_usd) USD"
            if ($phaseSpend -gt $ApprovedBudgetUsd) {
                throw "Actual phase cost exceeded the approved budget after $($cell.key): approved=$ApprovedBudgetUsd phase_actual=$phaseSpend"
            }
            if ($record.status -eq 'error') { throw "Claude returned an error for $($cell.key): $($record.error_type)" }
        }
        finally {
            Remove-BenchmarkProject -RunRoot $runRoot -ProjectRoot $projectRoot
        }
    }

    $allRecords = @(Get-ChildItem -LiteralPath (Join-Path $runRoot 'records') -Filter *.json | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json -Depth 50
    })
    if ($Phase -eq 'Calibrate') {
        $calibrationErrors = @($allRecords | Where-Object status -EQ 'error')
        if ($calibrationErrors.Count -gt 0) {
            throw "Calibration contains $($calibrationErrors.Count) failed record(s); resume with -Phase Calibrate -BenchmarkId $BenchmarkId -RetryFailed and a new explicitly approved budget"
        }
        $calibrationCost = [decimal](($allRecords | Where-Object { [int]$_.repetition -eq 1 } | Measure-Object -Property total_cost_usd -Sum).Sum)
        $projectedRemaining = [math]::Round([double]$calibrationCost * 2 * 1.25, 4)
        Write-Output "CALIBRATION COMPLETE: benchmark_id=$BenchmarkId sample_cost_usd=$calibrationCost phase_observed_cost_usd=$phaseSpend projected_remaining_with_25pct_buffer_usd=$projectedRemaining"
        Write-Output "Approval command: pwsh -NoProfile -File .\tests\Invoke-CostBenchmark.ps1 -Phase Complete -BenchmarkId $BenchmarkId -ApprovedBudgetUsd <amount>"
    }
    else {
        $expectedRecordCount = [int]$definition.tasks.Count * [int]$definition.target_repetitions * 3
        if ($allRecords.Count -eq $expectedRecordCount) {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-CostReport.ps1') -BenchmarkId $BenchmarkId
            if ($LASTEXITCODE -ne 0) { throw 'Cost report generation failed' }
            Write-Output "BENCHMARK COMPLETE: benchmark_id=$BenchmarkId records=$($allRecords.Count) phase_cost_usd=$phaseSpend invocation_cost_usd=$invocationSpend"
        }
        else {
            Write-Output "BENCHMARK INCOMPLETE: benchmark_id=$BenchmarkId records=$($allRecords.Count)/$expectedRecordCount"
        }
    }
}
finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $savedEnvironment[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:$name" $savedEnvironment[$name] }
    }
}
