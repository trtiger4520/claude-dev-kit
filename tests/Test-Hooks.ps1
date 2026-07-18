Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$powerShellHook = Join-Path $repositoryRoot 'src/hooks/risky-change-trigger.ps1'
$shellHook = Join-Path $repositoryRoot 'src/hooks/risky-change-trigger.sh'

function Invoke-RiskHook {
    param([Parameter(Mandatory)][string]$Prompt)

    $inputJson = @{ prompt = $Prompt } | ConvertTo-Json -Compress
    $output = $inputJson | & pwsh -NoProfile -ExecutionPolicy Bypass -File $powerShellHook 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "PowerShell risk hook failed: $output" }
    return $output.Trim()
}

$unrelated = Invoke-RiskHook -Prompt 'Update the button label on the profile page'
if ($unrelated) { throw "Unrelated prompt unexpectedly produced hook output: $unrelated" }

foreach ($prompt in @(
    'Analyze the current authentication policy without changing files',
    'Change the production authorization policy for administrators',
    '更新部署文件中的說明文字'
)) {
    $output = Invoke-RiskHook -Prompt $prompt
    if (-not $output) { throw "High-risk keyword prompt produced no output: $prompt" }
    $parsed = $output | ConvertFrom-Json
    $context = $parsed.hookSpecificOutput.additionalContext
    if (-not $context.Contains('POTENTIAL HIGH-RISK DOMAIN')) { throw 'Hook did not mark a potential domain' }
    if (-not $context.Contains('Read-only analysis')) { throw 'Hook did not preserve the read-only lane exception' }
    if ($context.Contains('HIGH RISK by definition') -or $context.Contains('NO discretion')) {
        throw 'Hook still forces a keyword-only heavy lane'
    }
}

$shellContent = Get-Content -Raw -Encoding utf8 -LiteralPath $shellHook
$powerShellContent = Get-Content -Raw -Encoding utf8 -LiteralPath $powerShellHook
foreach ($required in @('POTENTIAL HIGH-RISK DOMAIN', 'Read-only analysis', 'Only an actual high-risk change requires')) {
    if (-not $shellContent.Contains($required) -or -not $powerShellContent.Contains($required)) {
        throw "Hook implementations are missing shared policy text: $required"
    }
}

Write-Output 'PASS: advisory risk hooks'
