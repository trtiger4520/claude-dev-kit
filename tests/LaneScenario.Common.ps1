Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LaneEvaluationErrors {
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)]$Result
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $roleCounts = @{}
    $subagentCount = 0
    foreach ($agent in @($Result.delegated_agents)) {
        if ($roleCounts.ContainsKey($agent.role)) {
            $errors.Add("duplicate-role:$($agent.role)")
            continue
        }
        $roleCounts[$agent.role] = [int]$agent.count
        $subagentCount += [int]$agent.count
    }

    if ($Result.lane -notin $Scenario.allowed_lanes) { $errors.Add("lane:$($Result.lane)") }
    if ($Result.approval_required -ne $Scenario.approval_required) { $errors.Add('approval') }
    if ($Result.lane -eq 'single-agent' -and $subagentCount -ne 0) { $errors.Add('single-agent-count') }
    if ($Result.lane -eq 'plan-light' -and $subagentCount -gt 1) { $errors.Add('plan-light-count') }
    if ($subagentCount -gt $Scenario.max_subagents) { $errors.Add('max-subagents') }
    foreach ($role in $Scenario.required_roles) {
        if (-not $roleCounts.ContainsKey($role)) { $errors.Add("required-role:$role") }
    }
    foreach ($role in $roleCounts.Keys) {
        if ($role -notin $Scenario.allowed_roles) {
            $errors.Add("disallowed-role:$role")
            continue
        }
        $limit = $Scenario.max_role_counts.PSObject.Properties | Where-Object Name -EQ $role | Select-Object -First 1
        if ($null -eq $limit -or $roleCounts[$role] -gt [int]$limit.Value) { $errors.Add("role-limit:$role") }
    }
    return $errors
}

function Assert-LaneEvaluation {
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)]$Result
    )

    $errors = @(Get-LaneEvaluationErrors -Scenario $Scenario -Result $Result)
    if ($errors.Count -gt 0) {
        $resultJson = $Result | ConvertTo-Json -Depth 10 -Compress
        throw "Scenario '$($Scenario.id)' failed lane evaluation: $($errors -join ', '); result=$resultJson"
    }
}
