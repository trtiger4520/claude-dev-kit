Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Read-RepoFile {
    param([Parameter(Mandatory)][string]$RelativePath)
    return Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot $RelativePath)
}

function Assert-Contains {
    param([string]$Content, [string]$Expected, [string]$File)
    if (-not $Content.Contains($Expected)) { throw "$File is missing required policy text: $Expected" }
}

function Assert-NotContains {
    param([string]$Content, [string]$Forbidden, [string]$File)
    if ($Content.Contains($Forbidden)) { throw "$File contains forbidden policy text: $Forbidden" }
}

$claude = Read-RepoFile 'src/CLAUDE.md'
foreach ($required in @(
    '`single-agent`',
    '`plan-light`',
    '`orchestrate-heavy`',
    'default to zero subagents and select at most one of explorer, implementer, or verifier',
    'Keep read-only security, migration, deployment, and architecture analysis in `single-agent` or `plan-light`',
    'Delegate only when at least two signals are present',
    'File count, step count, cross-module scope, cross-platform scope, or unfamiliar paths',
    'availability alone does not bypass this gate'
)) { Assert-Contains -Content $claude -Expected $required -File 'src/CLAUDE.md' }
foreach ($forbidden in @('3-6 explorers', 'Use proactively', 'Keyword match decides', 'high risk BY DEFINITION')) {
    Assert-NotContains -Content $claude -Forbidden $forbidden -File 'src/CLAUDE.md'
}

$planner = Read-RepoFile 'src/agents/planner.md'
$explorer = Read-RepoFile 'src/agents/explorer.md'
$implementer = Read-RepoFile 'src/agents/implementer.md'
$verifier = Read-RepoFile 'src/agents/verifier.md'
$allAgents = $planner + $explorer + $implementer + $verifier
Assert-NotContains -Content $allAgents -Forbidden 'Use proactively' -File 'src/agents/*.md'
Assert-NotContains -Content $allAgents -Forbidden 'Runtime:' -File 'src/agents/*.md'
Assert-Contains -Content $planner -Expected 'cohesive delivery units' -File 'src/agents/planner.md'
Assert-Contains -Content $explorer -Expected 'limited parent exploration has not converged' -File 'src/agents/explorer.md'
Assert-Contains -Content $implementer -Expected 'one cohesive delivery unit' -File 'src/agents/implementer.md'
Assert-Contains -Content $implementer -Expected 'disallowedTools: Agent' -File 'src/agents/implementer.md'
Assert-Contains -Content $verifier -Expected 'You never modify files' -File 'src/agents/verifier.md'

$orchestrate = Read-RepoFile 'src/commands/orchestrate.md'
$verify = Read-RepoFile 'src/commands/verify.md'
Assert-Contains -Content $orchestrate -Expected 'Use one writer by default' -File 'src/commands/orchestrate.md'
Assert-Contains -Content $orchestrate -Expected 'at most one explorer' -File 'src/commands/orchestrate.md'
Assert-Contains -Content $orchestrate -Expected 'source-boundary skill' -File 'src/commands/orchestrate.md'
Assert-NotContains -Content $orchestrate -Forbidden 'tasks/metrics.log' -File 'src/commands/orchestrate.md'
Assert-NotContains -Content $orchestrate -Forbidden 'tasks/notes.md' -File 'src/commands/orchestrate.md'
Assert-Contains -Content $verify -Expected 'Do not revert, delete, or repair verifier changes' -File 'src/commands/verify.md'

$riskySkill = Read-RepoFile 'src/skills/risky-change/SKILL.md'
$repoDiscovery = Read-RepoFile 'src/skills/repo-discovery/SKILL.md'
Assert-Contains -Content $riskySkill -Expected 'Keyword mentions and read-only analysis do not trigger this protocol' -File 'src/skills/risky-change/SKILL.md'
Assert-NotContains -Content $repoDiscovery -Forbidden 'tasks/notes.md' -File 'src/skills/repo-discovery/SKILL.md'

Write-Output 'PASS: conservative delegation policy'
