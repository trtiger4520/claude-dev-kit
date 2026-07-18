Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LaneScenario.Common.ps1')

$scenarioPath = Join-Path $PSScriptRoot 'references/lane-scenarios.v1.json'
$schemaPath = Join-Path $PSScriptRoot 'references/lane-evaluation-result.schema.json'
$matrix = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json -Depth 30
$schema = Get-Content -Raw -LiteralPath $schemaPath

if (-not (Test-Json -Json $schema -ErrorAction SilentlyContinue)) { throw 'Lane result schema is invalid JSON' }
if ($matrix.version -ne '1.0' -or $matrix.scenarios.Count -ne 12) { throw 'Lane matrix must be version 1.0 with twelve scenarios' }

$validLanes = @('single-agent', 'plan-light', 'orchestrate-heavy')
$validRoles = @('planner', 'explorer', 'implementer', 'verifier')
$ids = [System.Collections.Generic.HashSet[string]]::new()
foreach ($scenario in $matrix.scenarios) {
    if (-not $ids.Add($scenario.id)) { throw "Duplicate scenario id: $($scenario.id)" }
    if (-not $scenario.prompt -or $scenario.allowed_lanes.Count -eq 0) { throw "Incomplete scenario: $($scenario.id)" }
    foreach ($lane in $scenario.allowed_lanes) {
        if ($lane -notin $validLanes) { throw "Invalid lane in $($scenario.id): $lane" }
    }
    foreach ($role in @($scenario.required_roles) + @($scenario.allowed_roles)) {
        if ($role -notin $validRoles) { throw "Invalid role in $($scenario.id): $role" }
    }
    if (@($scenario.required_roles | Where-Object { $_ -notin $scenario.allowed_roles }).Count -gt 0) {
        throw "Scenario requires a role it does not allow: $($scenario.id)"
    }
    $roleLimits = @{}
    foreach ($property in $scenario.max_role_counts.PSObject.Properties) {
        if ($property.Name -notin $scenario.allowed_roles) { throw "Unexpected role limit in $($scenario.id): $($property.Name)" }
        if ([int]$property.Value -lt 1) { throw "Invalid role limit in $($scenario.id): $($property.Name)" }
        if ($property.Name -eq 'implementer' -and [int]$property.Value -gt 2) { throw "Too many implementers in $($scenario.id)" }
        if ($property.Name -ne 'implementer' -and [int]$property.Value -ne 1) { throw "Non-writer role limit must be one in $($scenario.id)" }
        $roleLimits[$property.Name] = [int]$property.Value
    }
    foreach ($role in $scenario.allowed_roles) {
        if (-not $roleLimits.ContainsKey($role)) { throw "Missing role limit in $($scenario.id): $role" }
    }
    if ('plan-light' -in $scenario.allowed_lanes -and $scenario.max_subagents -gt 1) { throw "Plan-light limit exceeded in $($scenario.id)" }
}

foreach ($smokeId in $matrix.smoke_scenarios) {
    if (-not $ids.Contains($smokeId)) { throw "Unknown smoke scenario: $smokeId" }
}
if ($matrix.smoke_scenarios.Count -ne 4) { throw 'Exactly four smoke scenarios are required' }

$knownDto = $matrix.scenarios | Where-Object id -EQ 'known-dto-field' | Select-Object -First 1
$validResultJson = '{"lane":"single-agent","delegated_agents":[],"approval_required":false,"rationale":"Known local change"}'
if (-not (Test-Json -Json $validResultJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) { throw 'Valid sample result failed its schema' }
Assert-LaneEvaluation -Scenario $knownDto -Result ($validResultJson | ConvertFrom-Json)

$invalidResult = '{"lane":"plan-light","delegated_agents":[{"role":"explorer","count":1}],"approval_required":false,"rationale":"Unnecessary delegation"}' | ConvertFrom-Json
$invalidErrors = @(Get-LaneEvaluationErrors -Scenario $knownDto -Result $invalidResult)
if ('lane:plan-light' -notin $invalidErrors -or 'max-subagents' -notin $invalidErrors) {
    throw "Invalid sample did not report expected errors: $($invalidErrors -join ', ')"
}

Write-Output 'PASS: 12 lane scenarios and result schema'
