[CmdletBinding()]
param([switch]$KeepArtifacts)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CostBenchmark.Common.ps1')

function Write-TestJson {
    param($Value, [string]$Path)
    [System.IO.File]::WriteAllText(
        $Path,
        ($Value | ConvertTo-Json -Depth 50) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$definition = Get-CostBenchmarkDefinition
if ($definition.version -ne '1.0' -or $definition.tasks.Count -ne 3 -or $definition.target_repetitions -ne 3) {
    throw 'Cost benchmark definition must contain three tasks and three repetitions'
}
$policyFingerprint = Get-PolicyFingerprint -RepositoryRoot (Get-RepositoryRoot)
$benchmarkInputFingerprint = Get-BenchmarkInputFingerprint
if ($policyFingerprint -notmatch '^[0-9a-f]{64}$' -or $benchmarkInputFingerprint -notmatch '^[0-9a-f]{64}$') {
    throw 'Policy and benchmark input fingerprints must be SHA-256 hex values'
}
$calibrationSchedule = @(Get-CostBenchmarkSchedule -Definition $definition -Phase Calibrate)
$completeSchedule = @(Get-CostBenchmarkSchedule -Definition $definition -Phase Complete)
if ($calibrationSchedule.Count -ne 9 -or $completeSchedule.Count -ne 18) {
    throw "Unexpected benchmark schedule size: calibration=$($calibrationSchedule.Count), complete=$($completeSchedule.Count)"
}
$allRunOrders = @($calibrationSchedule.run_order) + @($completeSchedule.run_order)
if (@($allRunOrders | Sort-Object -Unique).Count -ne 27 -or ($allRunOrders | Measure-Object -Minimum).Minimum -ne 1 -or ($allRunOrders | Measure-Object -Maximum).Maximum -ne 27) {
    throw 'Benchmark run_order must be unique and continuous from 1 through 27'
}
foreach ($task in $definition.tasks) {
    $roundOne = @($calibrationSchedule | Where-Object { $_.task.id -eq $task.id -and $_.kind -eq 'execution' })
    $roundTwo = @($completeSchedule | Where-Object { $_.task.id -eq $task.id -and $_.repetition -eq 2 -and $_.kind -eq 'execution' })
    if ($roundOne[0].strategy -ne $task.current_strategy -or $roundTwo[0].strategy -ne $task.counterfactual_strategy) {
        throw "Benchmark strategy order is not balanced for $($task.id)"
    }
}

$sampleStream = @(
    '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"orchestration_explorer"}},{"type":"text","text":"web/LoginView.vue"}]}}',
    '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.125,"duration_ms":1200,"duration_api_ms":900,"num_turns":2,"result":"src/BenchmarkApp/Web/LoginEndpoint.cs","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40},"modelUsage":{"claude-sonnet-test":{"costUSD":0.125}}}'
)
$parsedStream = ConvertFrom-ClaudeStream -Lines $sampleStream
if ($parsedStream.observed_lane -ne 'plan-light' -or $parsedStream.subagent_count -ne 1 -or $parsedStream.delegated_roles -ne 'explorer:1') {
    throw 'Claude stream parser did not identify the explorer delegation'
}
$errorStream = ConvertFrom-ClaudeStream -Lines @('{"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":0.42,"duration_ms":100,"duration_api_ms":90,"num_turns":2,"usage":{},"modelUsage":{}}')
if ([decimal]$errorStream.result.total_cost_usd -ne [decimal]0.42 -or -not $errorStream.result.is_error) {
    throw 'Claude stream parser lost error cost evidence'
}

$runRoot = New-SandboxRun
try {
    $projectRoot = Assert-TestPath -Path (Join-Path $runRoot 'project')
    $reportRoot = Assert-TestPath -Path (Join-Path $runRoot 'report')
    $installedProfileRoot = Assert-TestPath -Path (Join-Path $runRoot 'installed-profile')
    New-Item -ItemType Directory -Force -Path $projectRoot, $reportRoot, $installedProfileRoot | Out-Null
    Copy-Item -Path (Join-Path (Get-RepositoryRoot) 'src\*') -Destination $installedProfileRoot -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $installedProfileRoot 'hooks\risky-change-trigger.sh') -Force
    [System.IO.File]::WriteAllText((Join-Path $installedProfileRoot 'settings.json'), "{}`n", [System.Text.UTF8Encoding]::new($false))
    $installedFingerprint = Get-InstalledPolicyFingerprint -ProfileRoot $installedProfileRoot
    $installedAgentPath = Join-Path $installedProfileRoot 'agents\explorer.md'
    [System.IO.File]::AppendAllText($installedAgentPath, "`n# fingerprint probe`n", [System.Text.UTF8Encoding]::new($false))
    if ($installedFingerprint -eq (Get-InstalledPolicyFingerprint -ProfileRoot $installedProfileRoot)) {
        throw 'Installed policy fingerprint did not detect an agent configuration change'
    }
    Copy-Item -Path (Join-Path (Get-CostBenchmarkFixtureRoot) '*') -Destination $projectRoot -Recurse -Force
    & dotnet run --project (Join-Path $projectRoot 'tests/BenchmarkChecks/BenchmarkChecks.csproj') -- baseline | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Benchmark fixture baseline failed' }
    & git -C $projectRoot init --quiet
    & git -C $projectRoot add -A
    & git -C $projectRoot -c user.name='Claude Dev Kit Test' -c user.email='test@example.invalid' commit --quiet -m 'baseline'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize benchmark outcome fixture' }

    $dtoPath = Join-Path $projectRoot 'src/BenchmarkApp/Contracts/UserDto.cs'
    $mapperPath = Join-Path $projectRoot 'src/BenchmarkApp/Mapping/UserMapper.cs'
    $dto = (Get-Content -Raw -LiteralPath $dtoPath).Replace('string Id, string Name)', 'string Id, string Name, string DisplayName)')
    $mapper = (Get-Content -Raw -LiteralPath $mapperPath).Replace('new(user.Id, user.Name)', 'new(user.Id, user.Name, user.ProfileName)')
    [System.IO.File]::WriteAllText($dtoPath, $dto, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($mapperPath, $mapper, [System.Text.UTF8Encoding]::new($false))
    $dtoTask = $definition.tasks | Where-Object id -EQ 'known-dto-change' | Select-Object -First 1
    $outcome = Test-CostBenchmarkOutcome -Task $dtoTask -Strategy 'current-policy' -ProjectRoot $projectRoot -StreamResult ([pscustomobject]@{
        assistant_text = 'done'; roles = @(); observed_lane = 'single-agent'
    })
    if (-not $outcome.quality_pass -or -not $outcome.test_pass -or -not $outcome.scope_pass) {
        throw "Deterministic DTO outcome failed: $($outcome | ConvertTo-Json -Depth 10 -Compress)"
    }
    $incompleteHeavyOutcome = Test-CostBenchmarkOutcome -Task $dtoTask -Strategy 'forced-heavy' -ProjectRoot $projectRoot -ApprovalTurns 1 -StreamResult ([pscustomobject]@{
        assistant_text = 'done'; roles = @('planner'); delegated_roles = 'planner:1'; observed_lane = 'orchestrate-heavy'
    })
    $failedHeavyChecks = @($incompleteHeavyOutcome.checks | Where-Object { -not $_.passed } | Select-Object -ExpandProperty id)
    if ($incompleteHeavyOutcome.quality_pass -or 'heavy-single-writer' -notin $failedHeavyChecks -or 'heavy-verifier' -notin $failedHeavyChecks) {
        throw 'Forced-heavy outcome must reject a planner-only workflow'
    }

    $benchmarkId = Split-Path -Leaf $runRoot
    $recordsRoot = Join-Path $runRoot 'records'
    $attemptsRoot = Join-Path $runRoot 'attempts'
    New-Item -ItemType Directory -Force -Path $recordsRoot, $attemptsRoot | Out-Null
    if ((Get-RecordedPhaseSpend -RunRoot $runRoot -Phase Calibrate) -ne 0) {
        throw 'Empty benchmark phase spend must be zero under strict mode'
    }
    $manifest = [ordered]@{
        version = '1.0'
        benchmark_id = $benchmarkId
        created_utc = [DateTime]::UtcNow.ToString('o')
        target_repetitions = 3
        claude_version = '2.1.214 (Claude Code)'
        policy_fingerprint = $policyFingerprint
        installed_policy_fingerprint = $installedFingerprint
        benchmark_input_fingerprint = $benchmarkInputFingerprint
        quality_contract_version = Get-CostBenchmarkQualityContractVersion
        fixture = 'cost-benchmark'
    }
    Write-TestJson -Value $manifest -Path (Join-Path $runRoot 'manifest.json')

    $allSchedule = @($calibrationSchedule + $completeSchedule | Sort-Object repetition, run_order)
    $index = 0
    foreach ($cell in $allSchedule) {
        $index++
        $baseCost = switch ($cell.strategy) {
            'classification' { 0.01 }
            'current-policy' {
                switch ($cell.task.id) {
                    'known-dto-change' { 0.10 }
                    'login-flow-analysis' { 0.20 }
                    default { 0.40 }
                }
            }
            'forced-heavy' { 0.30 }
            default { 0.15 }
        }
        $record = [ordered]@{}
        foreach ($column in (Get-CostBenchmarkColumns)) { $record[$column] = '' }
        $record.benchmark_id = $benchmarkId
        $record.timestamp_utc = [DateTime]::UtcNow.ToString('o')
        $record.claude_version = $manifest.claude_version
        $record.policy_fingerprint = $manifest.policy_fingerprint
        $record.task_id = $cell.task.id
        $record.category = $cell.task.category
        $record.kind = $cell.kind
        $record.strategy = $cell.strategy
        $record.repetition = $cell.repetition
        $record.run_order = $index
        $record.expected_lane = $cell.task.expected_lane
        $record.observed_lane = if ($cell.strategy -eq 'forced-heavy') { 'orchestrate-heavy' } elseif ($cell.kind -eq 'classification' -or $cell.strategy -eq 'current-policy') { $cell.task.expected_lane } else { 'single-agent' }
        $record.delegated_roles = if ($cell.strategy -eq 'forced-heavy' -or ($cell.strategy -eq 'current-policy' -and $cell.task.expected_lane -eq 'orchestrate-heavy')) {
            'implementer:1;planner:1;verifier:1'
        }
        elseif (($cell.kind -eq 'classification' -or $cell.strategy -eq 'current-policy') -and $cell.task.expected_lane -eq 'plan-light') {
            'explorer:1'
        }
        else { '' }
        $record.subagent_count = @($record.delegated_roles -split ';' | Where-Object { $_ }).Count
        $record.approval_turns = if ($cell.task.expected_lane -eq 'orchestrate-heavy' -or $cell.strategy -eq 'forced-heavy') { 1 } else { 0 }
        $record.model = 'sonnet'
        $record.effort = 'low'
        $record.total_cost_usd = [math]::Round($baseCost + ($cell.repetition * 0.001), 4)
        $record.duration_ms = 1000 + $index
        $record.duration_api_ms = 800 + $index
        $record.wall_seconds = 10 + $index
        $record.input_tokens = 10
        $record.output_tokens = 20
        $record.cache_creation_input_tokens = 30
        $record.cache_read_input_tokens = 40
        $record.num_turns = 2
        $record.acceptance_passed = 2
        $record.acceptance_total = 2
        $record.acceptance_rate = 1
        $record.test_pass = $true
        $record.scope_pass = $true
        $record.quality_pass = $true
        $record.status = 'pass'
        $record.error_type = ''
        $record.budget_limit_usd = 1
        $record.model_usage_json = '{}'
        $record.checks = @()
        $record.changed_files = @()
        $record.unexpected_files = @()
        $record.test_output = 'PASS'
        $record = Update-CostBenchmarkRecordQualityContract -Record $record -Task $cell.task
        Write-TestJson -Value $record -Path (Join-Path $recordsRoot "$($cell.key).json")
    }

    $attemptRecord = Get-Content -Raw -LiteralPath (Join-Path $recordsRoot "$($allSchedule[0].key).json") | ConvertFrom-Json -Depth 50
    $attemptRecord.status = 'error'
    $attemptRecord.error_type = 'error_max_budget_usd'
    $attemptRecord.total_cost_usd = 0.42
    Write-TestJson -Value $attemptRecord -Path (Join-Path $attemptsRoot "$($allSchedule[0].key)--attempt.json")
    $expectedCalibrationSpend = [decimal](($allSchedule | Where-Object repetition -EQ 1 | ForEach-Object {
        $recordPath = Join-Path $recordsRoot "$($_.key).json"
        [decimal]((Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json).total_cost_usd)
    } | Measure-Object -Sum).Sum) + [decimal]0.42
    if ((Get-RecordedPhaseSpend -RunRoot $runRoot -Phase Calibrate) -ne $expectedCalibrationSpend) {
        throw 'Recorded calibration spend must include current records and superseded attempts exactly once'
    }

    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-CostReport.ps1') -BenchmarkId $benchmarkId -OutputDirectory $reportRoot
    if ($LASTEXITCODE -ne 0) { throw 'Offline cost report generation failed' }
    $csv = @(Import-Csv -LiteralPath (Join-Path $reportRoot 'task-cost-data.csv'))
    if ($csv.Count -ne 28 -or @($csv | Where-Object record_state -EQ 'current').Count -ne 27 -or @($csv | Where-Object record_state -EQ 'superseded-attempt').Count -ne 1) {
        throw "Cost report CSV did not preserve 27 current records and one superseded attempt: rows=$($csv.Count)"
    }
    $markdown = Get-Content -Raw -LiteralPath (Join-Path $reportRoot 'task-cost-report.md')
    foreach ($expected in @('執行策略比較', '現行策略相對差異', 'Lane 分類成本', '27 / 27', '保留的重試 attempt：1 筆', 'Benchmark 作業總成本', 'Quality contract')) {
        if (-not $markdown.Contains($expected)) { throw "Cost report is missing: $expected" }
    }
    $svgText = Get-Content -Raw -LiteralPath (Join-Path $reportRoot 'task-cost-curves.svg')
    [xml]$svg = $svgText
    if (($svg.SelectNodes('//*[local-name()="polyline"]')).Count -ne 6) { throw 'Cost SVG must contain two curves for each of three tasks' }
    if ($svgText -match '#[0-9a-fA-F]{3,8}') { throw 'Cost SVG must not hardcode light or dark palette colors' }

    Remove-Item -LiteralPath $attemptsRoot -Recurse -Force
    New-Item -ItemType Directory -Path $attemptsRoot | Out-Null
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-CostReport.ps1') -BenchmarkId $benchmarkId -OutputDirectory $reportRoot
    if ($LASTEXITCODE -ne 0) { throw 'Cost report generation failed when no superseded attempts exist' }
    $reportWithoutAttempts = Get-Content -Raw -LiteralPath (Join-Path $reportRoot 'task-cost-report.md')
    if (-not $reportWithoutAttempts.Contains('保留的重試 attempt：0 筆')) {
        throw 'Cost report did not represent an empty superseded-attempt set'
    }

    $outsideOutput = Join-Path (Split-Path (Get-RepositoryRoot) -Parent) ("claude-dev-kit-report-outside-probe-{0}" -f [guid]::NewGuid().ToString('N'))
    $outsideResult = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-CostReport.ps1') -BenchmarkId $benchmarkId -OutputDirectory $outsideOutput 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or -not $outsideResult.Contains('Report output must stay inside')) {
        throw 'Cost report generator did not reject an output path outside the repository sandbox boundary'
    }
    if (Test-Path -LiteralPath $outsideOutput) { throw 'Rejected report path was unexpectedly created' }

    $runnerContent = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'Invoke-CostBenchmark.ps1')
    foreach ($required in @('ApprovedBudgetUsd', 'BENCHMARK_APPROVAL_REQUIRED', '--no-session-persistence', "'--disallowed-tools', 'Agent'", 'projected_remaining_with_25pct_buffer_usd', 'Get-InstalledPolicyFingerprint', 'benchmark_input_fingerprint', 'quality_contract_version', 'Update-StoredQualityContract', 'RECOVER:', 'Get-RecordedPhaseSpend', 'phase_observed_cost_usd')) {
        if (-not $runnerContent.Contains($required)) { throw "Cost benchmark runner is missing safety behavior: $required" }
    }
    if ($runnerContent.Contains("'--safe-mode'")) {
        throw 'Forced-single must retain the installed policy and differ only by explicit no-delegation instructions and Agent denial'
    }
    foreach ($scriptName in @('CostBenchmark.Common.ps1', 'Invoke-CostBenchmark.ps1', 'New-CostReport.ps1', 'Test-CostBenchmark.ps1')) {
        $parseTokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$parseTokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw "PowerShell parse error in $scriptName`: $($parseErrors[0].Message)" }
    }

    Write-Output 'PASS: cost benchmark fixture, schedule, parser, outcome and report'
}
finally {
    if ($KeepArtifacts) {
        Write-Output "ARTIFACT_ROOT: $runRoot"
    }
    else {
        Remove-SandboxRun -RunRoot $runRoot
    }
}
