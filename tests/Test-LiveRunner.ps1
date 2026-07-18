Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runnerPath = Join-Path $PSScriptRoot 'Invoke-LaneScenariosLive.ps1'
$runnerContent = Get-Content -Raw -Encoding utf8 -LiteralPath $runnerPath

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Live runner has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}

$expectedDeclaration = '[Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments'
if (-not $runnerContent.Contains($expectedDeclaration)) {
    throw 'Live runner process arguments must explicitly allow the empty value used by --tools ""'
}
if (-not $runnerContent.Contains("'--tools', ''")) {
    throw 'Live runner no longer disables Claude tools with an explicit empty argument'
}
if (-not $runnerContent.Contains("'--disallowed-tools', 'Agent'")) {
    throw 'Live runner must explicitly deny Agent dispatch in addition to the empty tool set'
}
if (-not $runnerContent.Contains("'--max-turns', '2'")) {
    throw 'Live runner must allow the structured-output completion turn while Agent remains denied'
}
if (-not $runnerContent.Contains('[decimal]$MaxBudgetUsd = 0.08')) {
    throw 'Live runner default budget must cover the observed Sonnet structured-output context cost'
}
if (-not $runnerContent.Contains('observed_cost_usd=')) {
    throw 'Live runner must report observed scenario and aggregate cost'
}

function Test-EmptyArgumentBinding {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments)
    return @($Arguments)
}

$boundArguments = @(Test-EmptyArgumentBinding -Arguments @('alpha', '', 'omega'))
if ($boundArguments.Count -ne 3 -or $boundArguments[1] -ne '') {
    throw 'PowerShell did not preserve the empty process argument'
}

Write-Output 'PASS: live runner empty argument binding'
