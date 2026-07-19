Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Test-Sandbox.ps1')

$script:CostBenchmarkTaskPath = Join-Path $PSScriptRoot 'references/cost-benchmark-tasks.v1.json'
$script:CostBenchmarkFixtureRoot = Join-Path $PSScriptRoot 'fixtures/cost-benchmark'
$script:CostBenchmarkQualityContractVersion = '2.0'
$script:CostBenchmarkColumns = @(
    'record_state', 'benchmark_id', 'timestamp_utc', 'claude_version', 'policy_fingerprint', 'quality_contract_version', 'task_id', 'category',
    'kind', 'strategy', 'repetition', 'run_order', 'expected_lane', 'observed_lane',
    'delegated_roles', 'subagent_count', 'approval_turns', 'model', 'effort', 'total_cost_usd',
    'duration_ms', 'duration_api_ms', 'wall_seconds', 'input_tokens', 'output_tokens',
    'cache_creation_input_tokens', 'cache_read_input_tokens', 'num_turns', 'acceptance_passed',
    'acceptance_total', 'acceptance_rate', 'test_pass', 'scope_pass', 'quality_pass', 'status',
    'error_type', 'budget_limit_usd', 'model_usage_json'
)

function Get-CostBenchmarkDefinition {
    return Get-Content -Raw -Encoding utf8 -LiteralPath $script:CostBenchmarkTaskPath | ConvertFrom-Json -Depth 30
}

function Get-CostBenchmarkFixtureRoot { return [System.IO.Path]::GetFullPath($script:CostBenchmarkFixtureRoot) }
function Get-CostBenchmarkColumns { return @($script:CostBenchmarkColumns) }
function Get-CostBenchmarkQualityContractVersion { return $script:CostBenchmarkQualityContractVersion }

function Get-CostBenchmarkRunRoot {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$BenchmarkId,
        [switch]$RequireExisting
    )

    $runRoot = Assert-TestPath -Path (Join-Path (Join-Path (Get-SandboxRoot) 'runs') $BenchmarkId)
    if ($RequireExisting -and -not (Test-Path -LiteralPath $runRoot -PathType Container)) {
        throw "Benchmark run not found: $BenchmarkId"
    }
    return $runRoot
}

function Get-PolicyFingerprint {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $sourceRoot = Join-Path $RepositoryRoot 'src'
    $relativeFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
        [System.IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName).Replace('\', '/')
    } | Sort-Object)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($relativePath in $relativeFiles) {
        $path = Join-Path $RepositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Policy file missing: $relativePath" }
        [void]$builder.Append($relativePath.Replace('\', '/')).Append("`n")
        [void]$builder.Append((Get-Content -Raw -Encoding utf8 -LiteralPath $path)).Append("`n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-BenchmarkInputFingerprint {
    $repositoryRoot = Get-RepositoryRoot
    $paths = @($script:CostBenchmarkTaskPath) + @(Get-ChildItem -LiteralPath $script:CostBenchmarkFixtureRoot -Recurse -File | Select-Object -ExpandProperty FullName)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($path in ($paths | Sort-Object)) {
        $relativePath = [System.IO.Path]::GetRelativePath($repositoryRoot, $path).Replace('\', '/')
        [void]$builder.Append($relativePath).Append("`n")
        [void]$builder.Append((Get-Content -Raw -Encoding utf8 -LiteralPath $path)).Append("`n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-InstalledPolicyFingerprint {
    param([Parameter(Mandatory)][string]$ProfileRoot)

    $resolvedProfile = Assert-TestPath -Path $ProfileRoot -AllowProfile
    $sourceRoot = Join-Path (Get-RepositoryRoot) 'src'
    $relativeFiles = @('CLAUDE.md')
    foreach ($directory in @('agents', 'commands', 'skills')) {
        $sourceDirectory = Join-Path $sourceRoot $directory
        $relativeFiles += @(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File | ForEach-Object {
            [System.IO.Path]::GetRelativePath($sourceRoot, $_.FullName).Replace('\', '/')
        })
    }
    $relativeFiles += @('hooks/risky-change-trigger.ps1', 'settings.json')

    $builder = [System.Text.StringBuilder]::new()
    foreach ($relativePath in ($relativeFiles | Sort-Object -Unique)) {
        $path = Join-Path $resolvedProfile $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installed policy file missing: $relativePath" }
        [void]$builder.Append($relativePath).Append("`n")
        [void]$builder.Append((Get-Content -Raw -Encoding utf8 -LiteralPath $path)).Append("`n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-CostBenchmarkSchedule {
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][ValidateSet('Calibrate', 'Complete')][string]$Phase
    )

    $targetRepetitions = [int]$Definition.target_repetitions
    $repetitions = if ($Phase -eq 'Calibrate') { @(1) } else { @(2..$targetRepetitions) }
    $schedule = [System.Collections.Generic.List[object]]::new()
    $order = if ($Phase -eq 'Complete') { [int]$Definition.tasks.Count * 3 } else { 0 }
    foreach ($repetition in $repetitions) {
        $tasks = @($Definition.tasks)
        $offset = ($repetition - 1) % $tasks.Count
        $orderedTasks = @($tasks[$offset..($tasks.Count - 1)])
        if ($offset -gt 0) { $orderedTasks += @($tasks[0..($offset - 1)]) }
        foreach ($task in $orderedTasks) {
            $order++
            $schedule.Add([pscustomobject]@{
                key = "$($task.id)--classification--r$repetition"
                task = $task
                kind = 'classification'
                strategy = 'classification'
                repetition = $repetition
                run_order = $order
            })
            $strategies = if ($repetition % 2 -eq 0) {
                @($task.counterfactual_strategy, $task.current_strategy)
            }
            else {
                @($task.current_strategy, $task.counterfactual_strategy)
            }
            foreach ($strategy in $strategies) {
                $order++
                $schedule.Add([pscustomobject]@{
                    key = "$($task.id)--$strategy--r$repetition"
                    task = $task
                    kind = 'execution'
                    strategy = $strategy
                    repetition = $repetition
                    run_order = $order
                })
            }
        }
    }
    return @($schedule)
}

function Get-RecordedPhaseSpend {
    param([Parameter(Mandatory)][string]$RunRoot, [Parameter(Mandatory)][ValidateSet('Calibrate', 'Complete')][string]$Phase)

    $records = @()
    foreach ($directory in @('records', 'attempts')) {
        $path = Join-Path $RunRoot $directory
        if (Test-Path -LiteralPath $path -PathType Container) {
            $records += @(Get-ChildItem -LiteralPath $path -Filter *.json | ForEach-Object {
                Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json -Depth 50
            })
        }
    }
    $phaseRecords = @(if ($Phase -eq 'Calibrate') {
        $records | Where-Object { [int]$_.repetition -eq 1 }
    }
    else {
        $records | Where-Object { [int]$_.repetition -ge 2 }
    })
    if ($phaseRecords.Count -eq 0) { return [decimal]0 }
    return [decimal](($phaseRecords | Measure-Object -Property total_cost_usd -Sum).Sum)
}

function Get-PropertyValue {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Set-PropertyValue {
    param($Object, [Parameter(Mandatory)][string]$Name, $Value)
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    else { $property.Value = $Value }
}

function Get-CostBenchmarkRoleCount {
    param(
        [AllowEmptyString()][string]$DelegatedRoles,
        [Parameter(Mandatory)][ValidateSet('planner', 'explorer', 'implementer', 'verifier')][string]$Role
    )

    if ([string]::IsNullOrWhiteSpace($DelegatedRoles)) { return 0 }
    foreach ($entry in $DelegatedRoles.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        if ($entry -match '^(?<role>[a-z-]+):(?<count>\d+)$' -and $Matches.role -eq $Role) {
            return [int]$Matches.count
        }
    }
    return 0
}

function Get-CostBenchmarkHeavyGovernanceChecks {
    param(
        [Parameter(Mandatory)]$Task,
        [Parameter(Mandatory)][string]$Strategy,
        [Parameter(Mandatory)][string]$ObservedLane,
        [AllowEmptyString()][string]$DelegatedRoles,
        [int]$ApprovalTurns = 0
    )

    $requiresHeavy = $Strategy -eq 'forced-heavy' -or (
        $Strategy -eq 'current-policy' -and [string]$Task.expected_lane -eq 'orchestrate-heavy'
    )
    if (-not $requiresHeavy) { return }

    $plannerCount = Get-CostBenchmarkRoleCount -DelegatedRoles $DelegatedRoles -Role planner
    $explorerCount = Get-CostBenchmarkRoleCount -DelegatedRoles $DelegatedRoles -Role explorer
    $writerCount = Get-CostBenchmarkRoleCount -DelegatedRoles $DelegatedRoles -Role implementer
    $verifierCount = Get-CostBenchmarkRoleCount -DelegatedRoles $DelegatedRoles -Role verifier
    return @(
        [pscustomobject]@{ id = 'heavy-lane'; passed = $ObservedLane -eq 'orchestrate-heavy'; evidence = $ObservedLane }
        [pscustomobject]@{ id = 'heavy-planner'; passed = $plannerCount -eq 1; evidence = "planners=$plannerCount" }
        [pscustomobject]@{ id = 'heavy-approval'; passed = $ApprovalTurns -eq 1; evidence = "approval_turns=$ApprovalTurns" }
        [pscustomobject]@{ id = 'heavy-single-writer'; passed = $writerCount -eq 1; evidence = "implementers=$writerCount" }
        [pscustomobject]@{ id = 'heavy-verifier'; passed = $verifierCount -eq 1; evidence = "verifiers=$verifierCount" }
        [pscustomobject]@{ id = 'heavy-explorer-limit'; passed = $explorerCount -le 1; evidence = "explorers=$explorerCount" }
    )
}

function Get-AgentRoleFromInput {
    param($InputObject)

    foreach ($name in @('subagent_type', 'agent', 'name', 'description')) {
        $value = [string](Get-PropertyValue -Object $InputObject -Name $name -Default '')
        foreach ($role in @('planner', 'explorer', 'implementer', 'verifier')) {
            if ($value -match $role) { return $role }
        }
    }
    return 'unknown'
}

function ConvertFrom-ClaudeStream {
    param([Parameter(Mandatory)][string[]]$Lines)

    $roles = [System.Collections.Generic.List[string]]::new()
    $result = $null
    $assistantText = [System.Text.StringBuilder]::new()
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json -Depth 50 }
        catch { continue }
        if ($event.type -eq 'assistant') {
            foreach ($block in @($event.message.content)) {
                if ($block.type -eq 'text') { [void]$assistantText.AppendLine([string]$block.text) }
                if ($block.type -eq 'tool_use' -and $block.name -eq 'Agent') {
                    $roles.Add((Get-AgentRoleFromInput -InputObject $block.input))
                }
            }
        }
        if ($event.type -eq 'result') { $result = $event }
    }
    if ($null -eq $result) { throw 'Claude stream did not contain a result event' }
    $roleCounts = @($roles | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Count)" })
    $observedLane = if ($roles.Count -eq 0) {
        'single-agent'
    }
    elseif ($roles -contains 'planner' -or $roles -contains 'verifier' -or @($roles | Where-Object { $_ -eq 'implementer' }).Count -gt 1) {
        'orchestrate-heavy'
    }
    else {
        'plan-light'
    }
    return [pscustomobject]@{
        result = $result
        assistant_text = (($assistantText.ToString() + [string](Get-PropertyValue $result 'result' '')).Trim())
        roles = @($roles)
        delegated_roles = ($roleCounts -join ';')
        subagent_count = $roles.Count
        observed_lane = $observedLane
    }
}

function Get-ChangedRepositoryFiles {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $status = @(& git -C $ProjectRoot -c core.quotepath=false status --porcelain=v1 --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect benchmark project status: $ProjectRoot" }
    return @($status | ForEach-Object {
        if ($_.Length -lt 4) { return }
        $_.Substring(3).Replace('\', '/')
    } | Where-Object { $_ } | Sort-Object -Unique)
}

function Test-CostBenchmarkOutcome {
    param(
        [Parameter(Mandatory)]$Task,
        [Parameter(Mandatory)][string]$Strategy,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)]$StreamResult,
        [int]$ApprovalTurns = 0
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    $changedFiles = @(Get-ChangedRepositoryFiles -ProjectRoot $ProjectRoot)
    $allowedFiles = @($Task.allowed_changed_files)
    $unexpectedFiles = @($changedFiles | Where-Object { $_ -notin $allowedFiles })
    $missingExpectedChange = $allowedFiles.Count -gt 0 -and @($allowedFiles | Where-Object { $_ -in $changedFiles }).Count -eq 0
    $scopePass = $unexpectedFiles.Count -eq 0 -and -not $missingExpectedChange
    $checks.Add([pscustomobject]@{ id = 'scope'; passed = $scopePass; evidence = ($changedFiles -join ',') })

    $testPass = $true
    $testOutput = ''
    if ($Task.verifier_mode -ne 'none') {
        $testOutput = & dotnet run --project (Join-Path $ProjectRoot 'tests/BenchmarkChecks/BenchmarkChecks.csproj') -- $Task.verifier_mode 2>&1 | Out-String
        $testPass = $LASTEXITCODE -eq 0
        $checks.Add([pscustomobject]@{ id = 'deterministic-test'; passed = $testPass; evidence = $testOutput.Trim() })
    }

    foreach ($anchor in @($Task.anchors)) {
        $checks.Add([pscustomobject]@{
            id = "anchor:$anchor"
            passed = $StreamResult.assistant_text.Contains([string]$anchor, [System.StringComparison]::OrdinalIgnoreCase)
            evidence = $anchor
        })
    }

    if ($Task.id -eq 'authentication-policy-change') {
        $riskPass = $StreamResult.assistant_text -match '(?i)Risk\s*&\s*Rollback|Risk and Rollback|風險.*回復|風險.*回滾'
        $checks.Add([pscustomobject]@{ id = 'risk-and-rollback'; passed = $riskPass; evidence = 'final response' })
    }

    if ($Strategy -eq 'current-policy') {
        $checks.Add([pscustomobject]@{
            id = 'expected-lane'
            passed = $StreamResult.observed_lane -eq $Task.expected_lane
            evidence = $StreamResult.observed_lane
        })
    }

    $delegatedRoles = [string](Get-PropertyValue $StreamResult 'delegated_roles' '')
    foreach ($governanceCheck in @(Get-CostBenchmarkHeavyGovernanceChecks -Task $Task -Strategy $Strategy -ObservedLane $StreamResult.observed_lane -DelegatedRoles $delegatedRoles -ApprovalTurns $ApprovalTurns)) {
        $checks.Add($governanceCheck)
    }

    $passed = @($checks | Where-Object passed).Count
    $total = $checks.Count
    return [pscustomobject]@{
        checks = @($checks)
        acceptance_passed = $passed
        acceptance_total = $total
        acceptance_rate = if ($total -eq 0) { 1 } else { [math]::Round($passed / $total, 4) }
        test_pass = $testPass
        scope_pass = $scopePass
        quality_pass = $passed -eq $total
        changed_files = @($changedFiles)
        unexpected_files = @($unexpectedFiles)
        test_output = $testOutput.Trim()
    }
}

function ConvertTo-CostBenchmarkRecord {
    param(
        [Parameter(Mandatory)][string]$BenchmarkId,
        [Parameter(Mandatory)]$Cell,
        [Parameter(Mandatory)]$StreamResult,
        [Parameter(Mandatory)]$Outcome,
        [Parameter(Mandatory)][string]$ClaudeVersion,
        [Parameter(Mandatory)][string]$PolicyFingerprint,
        [Parameter(Mandatory)][decimal]$BudgetLimitUsd,
        [Parameter(Mandatory)][double]$WallSeconds,
        [int]$ApprovalTurns = 0
    )

    $result = $StreamResult.result
    $usage = Get-PropertyValue $result 'usage' ([pscustomobject]@{})
    $modelUsage = Get-PropertyValue $result 'modelUsage' ([pscustomobject]@{})
    return [ordered]@{
        record_state = 'current'
        benchmark_id = $BenchmarkId
        timestamp_utc = [DateTime]::UtcNow.ToString('o')
        claude_version = $ClaudeVersion
        policy_fingerprint = $PolicyFingerprint
        quality_contract_version = Get-CostBenchmarkQualityContractVersion
        task_id = $Cell.task.id
        category = $Cell.task.category
        kind = $Cell.kind
        strategy = $Cell.strategy
        repetition = $Cell.repetition
        run_order = $Cell.run_order
        expected_lane = $Cell.task.expected_lane
        observed_lane = $StreamResult.observed_lane
        delegated_roles = $StreamResult.delegated_roles
        subagent_count = $StreamResult.subagent_count
        approval_turns = $ApprovalTurns
        model = 'sonnet'
        effort = 'low'
        total_cost_usd = [decimal](Get-PropertyValue $result 'total_cost_usd' 0)
        duration_ms = [long](Get-PropertyValue $result 'duration_ms' 0)
        duration_api_ms = [long](Get-PropertyValue $result 'duration_api_ms' 0)
        wall_seconds = [math]::Round($WallSeconds, 3)
        input_tokens = [long](Get-PropertyValue $usage 'input_tokens' 0)
        output_tokens = [long](Get-PropertyValue $usage 'output_tokens' 0)
        cache_creation_input_tokens = [long](Get-PropertyValue $usage 'cache_creation_input_tokens' 0)
        cache_read_input_tokens = [long](Get-PropertyValue $usage 'cache_read_input_tokens' 0)
        num_turns = [int](Get-PropertyValue $result 'num_turns' 0)
        acceptance_passed = $Outcome.acceptance_passed
        acceptance_total = $Outcome.acceptance_total
        acceptance_rate = $Outcome.acceptance_rate
        test_pass = $Outcome.test_pass
        scope_pass = $Outcome.scope_pass
        quality_pass = $Outcome.quality_pass
        status = if ([bool](Get-PropertyValue $result 'is_error' $false)) { 'error' } elseif ($Outcome.quality_pass) { 'pass' } else { 'quality-fail' }
        error_type = if ([bool](Get-PropertyValue $result 'is_error' $false)) { [string](Get-PropertyValue $result 'subtype' 'error') } else { '' }
        budget_limit_usd = $BudgetLimitUsd
        model_usage_json = ($modelUsage | ConvertTo-Json -Depth 20 -Compress)
        checks = @($Outcome.checks)
        changed_files = @($Outcome.changed_files)
        unexpected_files = @($Outcome.unexpected_files)
        test_output = $Outcome.test_output
    }
}

function Update-CostBenchmarkRecordQualityContract {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)]$Task
    )

    Set-PropertyValue -Object $Record -Name 'quality_contract_version' -Value (Get-CostBenchmarkQualityContractVersion)
    if ([string](Get-PropertyValue $Record 'kind' '') -ne 'execution') { return $Record }

    $legacyIds = @('single-writer', 'independent-verifier')
    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($check in @(Get-PropertyValue $Record 'checks' @())) {
        $id = [string](Get-PropertyValue $check 'id' '')
        if ($id -in $legacyIds -or $id.StartsWith('heavy-', [System.StringComparison]::Ordinal)) { continue }
        $checks.Add($check)
    }
    foreach ($check in @(Get-CostBenchmarkHeavyGovernanceChecks -Task $Task -Strategy ([string]$Record.strategy) -ObservedLane ([string]$Record.observed_lane) -DelegatedRoles ([string]$Record.delegated_roles) -ApprovalTurns ([int]$Record.approval_turns))) {
        $checks.Add($check)
    }

    $passed = @($checks | Where-Object { [bool]$_.passed }).Count
    $total = $checks.Count
    $qualityPass = $passed -eq $total
    Set-PropertyValue -Object $Record -Name 'checks' -Value @($checks)
    Set-PropertyValue -Object $Record -Name 'acceptance_passed' -Value $passed
    Set-PropertyValue -Object $Record -Name 'acceptance_total' -Value $total
    Set-PropertyValue -Object $Record -Name 'acceptance_rate' -Value $(if ($total -eq 0) { 1 } else { [math]::Round($passed / $total, 4) })
    Set-PropertyValue -Object $Record -Name 'quality_pass' -Value $qualityPass
    if ([string](Get-PropertyValue $Record 'status' '') -ne 'error') {
        Set-PropertyValue -Object $Record -Name 'status' -Value $(if ($qualityPass) { 'pass' } else { 'quality-fail' })
    }
    return $Record
}

function Export-CostBenchmarkCsv {
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][string]$Path
    )

    $columns = Get-CostBenchmarkColumns
    $rows = foreach ($record in $Records) {
        $row = [ordered]@{}
        foreach ($column in $columns) { $row[$column] = Get-PropertyValue $record $column '' }
        [pscustomobject]$row
    }
    $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8NoBOM
}
