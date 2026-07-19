[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$BenchmarkId,

    [string]$OutputDirectory,
    [switch]$AllowIncomplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'CostBenchmark.Common.ps1')

function Get-Median {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return 0 }
    $sorted = @($Values | Sort-Object)
    $middle = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2
}

function Format-Number {
    param([double]$Value, [string]$Pattern = '0.0000')
    return $Value.ToString($Pattern, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Escape-MarkdownCell {
    param($Value)
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Get-GroupSummary {
    param([Parameter(Mandatory)][object[]]$Rows)
    $costs = @($Rows | ForEach-Object { [double]$_.total_cost_usd })
    $walls = @($Rows | ForEach-Object { [double]$_.wall_seconds })
    $tokens = @($Rows | ForEach-Object {
        [double]$_.input_tokens + [double]$_.output_tokens + [double]$_.cache_creation_input_tokens + [double]$_.cache_read_input_tokens
    })
    return [pscustomobject]@{
        count = $Rows.Count
        mean_cost = ($costs | Measure-Object -Average).Average
        median_cost = Get-Median -Values $costs
        min_cost = ($costs | Measure-Object -Minimum).Minimum
        max_cost = ($costs | Measure-Object -Maximum).Maximum
        mean_wall = ($walls | Measure-Object -Average).Average
        mean_tokens = ($tokens | Measure-Object -Average).Average
        quality_passes = @($Rows | Where-Object { [string]$_.quality_pass -eq 'True' }).Count
    }
}

function New-CostCurveSvg {
    param(
        [Parameter(Mandatory)][object[]]$ExecutionRows,
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$Path
    )

    $width = 1080
    $height = 440
    $left = 64
    $top = 72
    $facetWidth = 320
    $plotWidth = 240
    $plotHeight = 260
    $taskSeries = @()
    $globalMax = 0.0
    foreach ($task in $Definition.tasks) {
        $series = @()
        foreach ($strategy in @($task.current_strategy, $task.counterfactual_strategy)) {
            $cumulative = 0.0
            $points = @()
            foreach ($repetition in 1..[int]$Definition.target_repetitions) {
                $row = $ExecutionRows | Where-Object { $_.task_id -eq $task.id -and $_.strategy -eq $strategy -and [int]$_.repetition -eq $repetition } | Select-Object -First 1
                if ($null -eq $row) { continue }
                $cumulative += [double]$row.total_cost_usd
                $globalMax = [math]::Max($globalMax, $cumulative)
                $points += [pscustomobject]@{ repetition = $repetition; cumulative = $cumulative }
            }
            $series += [pscustomobject]@{ strategy = $strategy; points = @($points) }
        }
        $taskSeries += [pscustomobject]@{ task = $task; series = @($series) }
    }
    if ($globalMax -le 0) { $globalMax = 1 }

    $xml = [System.Text.StringBuilder]::new()
    [void]$xml.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" role=`"img`" aria-labelledby=`"title desc`">")
    [void]$xml.AppendLine('  <title id="title">各任務三輪累積 API 等價成本</title>')
    [void]$xml.AppendLine('  <desc id="desc">三個任務的現行策略與反事實策略累積美元成本折線圖，使用實線與虛線區分策略</desc>')
    [void]$xml.AppendLine('  <style>svg{color-scheme:light dark;color:CanvasText;background:transparent;font-family:system-ui,sans-serif}.axis,.grid{stroke:currentColor;stroke-opacity:.32;fill:none}.grid{stroke-opacity:.12}.series{stroke:currentColor;stroke-width:2;fill:none}.counter{stroke-dasharray:7 5}.point{fill:Canvas;stroke:currentColor;stroke-width:2}.label,.tick,.facet-title{fill:currentColor}.tick{font-size:11px}.label{font-size:12px}.facet-title{font-size:14px;font-weight:500}</style>')
    [void]$xml.AppendLine('  <line x1="64" y1="32" x2="94" y2="32" class="series"/><text x="100" y="36" class="label">現行策略</text>')
    [void]$xml.AppendLine('  <line x1="190" y1="32" x2="220" y2="32" class="series counter"/><text x="226" y="36" class="label">反事實策略</text>')

    for ($taskIndex = 0; $taskIndex -lt $taskSeries.Count; $taskIndex++) {
        $facet = $taskSeries[$taskIndex]
        $x0 = $left + ($taskIndex * $facetWidth)
        $y0 = $top
        $title = [System.Security.SecurityElement]::Escape([string]$facet.task.id)
        [void]$xml.AppendLine("  <text x=`"$x0`" y=`"$($y0 - 18)`" class=`"facet-title`">$title</text>")
        foreach ($fraction in @(0, 0.5, 1)) {
            $y = $y0 + $plotHeight - ($plotHeight * $fraction)
            $value = $globalMax * $fraction
            [void]$xml.AppendLine("  <line x1=`"$x0`" y1=`"$y`" x2=`"$($x0 + $plotWidth)`" y2=`"$y`" class=`"grid`"/>")
            [void]$xml.AppendLine("  <text x=`"$($x0 - 8)`" y=`"$($y + 4)`" text-anchor=`"end`" class=`"tick`">`$$((Format-Number $value '0.000'))</text>")
        }
        [void]$xml.AppendLine("  <line x1=`"$x0`" y1=`"$y0`" x2=`"$x0`" y2=`"$($y0 + $plotHeight)`" class=`"axis`"/>")
        [void]$xml.AppendLine("  <line x1=`"$x0`" y1=`"$($y0 + $plotHeight)`" x2=`"$($x0 + $plotWidth)`" y2=`"$($y0 + $plotHeight)`" class=`"axis`"/>")
        foreach ($repetition in 1..[int]$Definition.target_repetitions) {
            $x = $x0 + (($repetition - 1) * ($plotWidth / ([int]$Definition.target_repetitions - 1)))
            [void]$xml.AppendLine("  <text x=`"$x`" y=`"$($y0 + $plotHeight + 22)`" text-anchor=`"middle`" class=`"tick`">R$repetition</text>")
        }
        for ($seriesIndex = 0; $seriesIndex -lt $facet.series.Count; $seriesIndex++) {
            $series = $facet.series[$seriesIndex]
            if ($series.points.Count -eq 0) { continue }
            $coordinates = foreach ($point in $series.points) {
                $x = $x0 + (($point.repetition - 1) * ($plotWidth / ([int]$Definition.target_repetitions - 1)))
                $y = $y0 + $plotHeight - (($point.cumulative / $globalMax) * $plotHeight)
                "$([math]::Round($x,2)),$([math]::Round($y,2))"
            }
            $class = if ($seriesIndex -eq 0) { 'series' } else { 'series counter' }
            [void]$xml.AppendLine("  <polyline points=`"$($coordinates -join ' ')`" class=`"$class`"/>")
            foreach ($point in $series.points) {
                $x = $x0 + (($point.repetition - 1) * ($plotWidth / ([int]$Definition.target_repetitions - 1)))
                $y = $y0 + $plotHeight - (($point.cumulative / $globalMax) * $plotHeight)
                [void]$xml.AppendLine("  <circle cx=`"$([math]::Round($x,2))`" cy=`"$([math]::Round($y,2))`" r=`"3.5`" class=`"point`"/>")
            }
            $last = $series.points[-1]
            $lastX = $x0 + $plotWidth
            $lastY = $y0 + $plotHeight - (($last.cumulative / $globalMax) * $plotHeight)
            $strategyLabel = if ($seriesIndex -eq 0) { '現行' } else { '反事實' }
            [void]$xml.AppendLine("  <text x=`"$($lastX + 6)`" y=`"$($lastY + 4)`" class=`"tick`">$strategyLabel `$$((Format-Number $last.cumulative '0.000'))</text>")
        }
    }
    [void]$xml.AppendLine('  <text x="540" y="424" text-anchor="middle" class="label">重複輪次；Y 軸為累積 API 等價成本（USD），三圖共用尺度</text>')
    [void]$xml.AppendLine('</svg>')
    [System.IO.File]::WriteAllText($Path, $xml.ToString(), [System.Text.UTF8Encoding]::new($false))
}

$runRoot = Get-CostBenchmarkRunRoot -BenchmarkId $BenchmarkId -RequireExisting
$definition = Get-CostBenchmarkDefinition
$manifest = Get-Content -Raw -LiteralPath (Join-Path $runRoot 'manifest.json') | ConvertFrom-Json -Depth 20
$records = @(Get-ChildItem -LiteralPath (Join-Path $runRoot 'records') -Filter *.json | ForEach-Object {
    Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json -Depth 50
} | Sort-Object run_order)
$qualityContractVersion = Get-CostBenchmarkQualityContractVersion
if ([string](Get-PropertyValue $manifest 'quality_contract_version' '') -ne $qualityContractVersion) {
    throw 'Benchmark manifest uses an unsupported quality contract; resume the benchmark runner to migrate stored records'
}
$incompatibleRecords = @($records | Where-Object { [string](Get-PropertyValue $_ 'quality_contract_version' '') -ne $qualityContractVersion })
if ($incompatibleRecords.Count -gt 0) {
    throw "Benchmark contains $($incompatibleRecords.Count) record(s) from an unsupported quality contract"
}
$attemptRecords = @()
$attemptsRoot = Join-Path $runRoot 'attempts'
if (Test-Path -LiteralPath $attemptsRoot -PathType Container) {
    $attemptRecords = @(Get-ChildItem -LiteralPath $attemptsRoot -Filter *.json | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json -Depth 50
    } | Sort-Object timestamp_utc)
}

$expectedRecordCount = [int]$definition.tasks.Count * [int]$definition.target_repetitions * 3
if (-not $AllowIncomplete -and $records.Count -ne $expectedRecordCount) {
    throw "Benchmark is incomplete: records=$($records.Count), expected=$expectedRecordCount"
}
if ($records.Count -eq 0) { throw 'Benchmark contains no records' }

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-RepositoryRoot) 'reports/cost-benchmark'
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$repositoryRoot = Get-RepositoryRoot
$sandboxRoot = Get-SandboxRoot
$versionedReportRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'reports/cost-benchmark'))
if (-not (Test-PathPrefix -Path $resolvedOutput -Root $versionedReportRoot) -and -not (Test-PathPrefix -Path $resolvedOutput -Root $sandboxRoot)) {
    throw "Report output must stay inside the repository report root or its sandbox: $resolvedOutput"
}
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
$csvPath = Join-Path $resolvedOutput 'task-cost-data.csv'
$reportPath = Join-Path $resolvedOutput 'task-cost-report.md'
$svgPath = Join-Path $resolvedOutput 'task-cost-curves.svg'
$csvRecords = @()
foreach ($record in $records) {
    if ($null -eq $record.PSObject.Properties['record_state']) { $record | Add-Member -NotePropertyName record_state -NotePropertyValue 'current' }
    else { $record.record_state = 'current' }
    $csvRecords += $record
}
foreach ($attempt in $attemptRecords) {
    if ($null -eq $attempt.PSObject.Properties['record_state']) { $attempt | Add-Member -NotePropertyName record_state -NotePropertyValue 'superseded-attempt' }
    else { $attempt.record_state = 'superseded-attempt' }
    $csvRecords += $attempt
}
Export-CostBenchmarkCsv -Records $csvRecords -Path $csvPath

$executionRows = @($records | Where-Object kind -EQ 'execution')
$classificationRows = @($records | Where-Object kind -EQ 'classification')
New-CostCurveSvg -ExecutionRows $executionRows -Definition $definition -Path $svgPath

$markdown = [System.Text.StringBuilder]::new()
[void]$markdown.AppendLine('# Claude Dev Kit 任務成本基準報告')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine(('- Benchmark ID：`{0}`' -f $BenchmarkId))
[void]$markdown.AppendLine(('- Claude CLI：`{0}`' -f $manifest.claude_version))
[void]$markdown.AppendLine(('- Policy fingerprint：`{0}`' -f $manifest.policy_fingerprint))
[void]$markdown.AppendLine(('- Installed policy fingerprint：`{0}`' -f (Get-PropertyValue $manifest 'installed_policy_fingerprint' 'unknown')))
[void]$markdown.AppendLine(('- Benchmark input fingerprint：`{0}`' -f (Get-PropertyValue $manifest 'benchmark_input_fingerprint' 'unknown')))
[void]$markdown.AppendLine(('- Quality contract：`{0}`' -f (Get-PropertyValue $manifest 'quality_contract_version' 'unknown')))
[void]$markdown.AppendLine("- 樣本：$($records.Count) / $expectedRecordCount")
$completedCost = [double](($records | Measure-Object -Property total_cost_usd -Sum).Sum)
$attemptCost = [double](($attemptRecords | Measure-Object -Property total_cost_usd -Sum).Sum)
[void]$markdown.AppendLine("- 完成樣本成本：`$$((Format-Number $completedCost))` USD")
[void]$markdown.AppendLine("- 保留的重試 attempt：$($attemptRecords.Count) 筆，`$$((Format-Number $attemptCost))` USD")
[void]$markdown.AppendLine("- Benchmark 作業總成本：`$$((Format-Number ($completedCost + $attemptCost)))` USD")
[void]$markdown.AppendLine('- 金額為 Claude CLI 回報的 API 等價估算，不代表訂閱方案實際帳單')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('![各任務累積成本曲線](task-cost-curves.svg)')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## 執行策略比較')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| 任務 | 策略 | 輪數 | 平均 USD | Median | 範圍 | 平均秒數 | 平均 Token | 品質通過 |')
[void]$markdown.AppendLine('|---|---|---:|---:|---:|---:|---:|---:|---:|')
foreach ($task in $definition.tasks) {
    foreach ($strategy in @($task.current_strategy, $task.counterfactual_strategy)) {
        $rows = @($executionRows | Where-Object { $_.task_id -eq $task.id -and $_.strategy -eq $strategy })
        if ($rows.Count -eq 0) { continue }
        $summary = Get-GroupSummary -Rows $rows
        [void]$markdown.AppendLine("| $($task.id) | $strategy | $($summary.count) | $((Format-Number $summary.mean_cost)) | $((Format-Number $summary.median_cost)) | $((Format-Number $summary.min_cost))–$((Format-Number $summary.max_cost)) | $((Format-Number $summary.mean_wall '0.0')) | $((Format-Number $summary.mean_tokens '0')) | $($summary.quality_passes)/$($summary.count) |")
    }
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## 現行策略相對差異')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| 任務 | 反事實策略 | 成本差異 | 時間差異 | 品質通過差異 |')
[void]$markdown.AppendLine('|---|---|---:|---:|---:|')
foreach ($task in $definition.tasks) {
    $currentRows = @($executionRows | Where-Object { $_.task_id -eq $task.id -and $_.strategy -eq $task.current_strategy })
    $counterRows = @($executionRows | Where-Object { $_.task_id -eq $task.id -and $_.strategy -eq $task.counterfactual_strategy })
    if ($currentRows.Count -eq 0 -or $counterRows.Count -eq 0) { continue }
    $current = Get-GroupSummary -Rows $currentRows
    $counter = Get-GroupSummary -Rows $counterRows
    $costDelta = if ($counter.mean_cost -eq 0) { 0 } else { (($current.mean_cost - $counter.mean_cost) / $counter.mean_cost) * 100 }
    $timeDelta = if ($counter.mean_wall -eq 0) { 0 } else { (($current.mean_wall - $counter.mean_wall) / $counter.mean_wall) * 100 }
    $qualityDelta = ($current.quality_passes / $current.count - $counter.quality_passes / $counter.count) * 100
    [void]$markdown.AppendLine("| $($task.id) | $($task.counterfactual_strategy) | $((Format-Number $costDelta '0.0'))% | $((Format-Number $timeDelta '0.0'))% | $((Format-Number $qualityDelta '0.0')) pp |")
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Lane 分類成本')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| 任務 | 輪次 | Lane | 子代理建議 | USD | 秒數 | 狀態 |')
[void]$markdown.AppendLine('|---|---:|---|---|---:|---:|---|')
foreach ($row in $classificationRows) {
    [void]$markdown.AppendLine("| $($row.task_id) | $($row.repetition) | $($row.observed_lane) | $(Escape-MarkdownCell $row.delegated_roles) | $((Format-Number ([double]$row.total_cost_usd))) | $((Format-Number ([double]$row.wall_seconds) '0.0')) | $($row.status) |")
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## 每輪明細')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| 順序 | 任務 | 類型 | 策略 | R | Lane | Agents | USD | 秒數 | 驗收 | 狀態 |')
[void]$markdown.AppendLine('|---:|---|---|---|---:|---|---:|---:|---:|---:|---|')
foreach ($row in $records) {
    [void]$markdown.AppendLine("| $($row.run_order) | $($row.task_id) | $($row.kind) | $($row.strategy) | $($row.repetition) | $($row.observed_lane) | $($row.subagent_count) | $((Format-Number ([double]$row.total_cost_usd))) | $((Format-Number ([double]$row.wall_seconds) '0.0')) | $($row.acceptance_passed)/$($row.acceptance_total) | $($row.status) |")
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## 判讀方式')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('- 小修改比較保守策略避免不必要完整 orchestration 的成本')
[void]$markdown.AppendLine('- 探索任務比較 context 隔離增加的成本與呼叫鏈完整度')
[void]$markdown.AppendLine('- 高風險任務比較單一 writer、核准與 verifier 所形成的安全溢價')
[void]$markdown.AppendLine('- 結論只依確定性驗收與實際量測，不另外呼叫模型產生主觀品質分數')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## 限制')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('- 合成 fixture 與每組三輪只能建立可重現的內部基準，不代表所有真實專案')
[void]$markdown.AppendLine('- Prompt cache、模型版本、CLI 版本與服務狀態會影響 Token、時間及成本')
[void]$markdown.AppendLine('- `total_cost_usd` 是 CLI 估算；訂閱使用者應以方案使用量或 Console 為準')
[void]$markdown.AppendLine('- 重試前的失敗 attempt 保留在 CSV 並計入作業總成本，但不納入策略均值與曲線')
[void]$markdown.AppendLine('- `TESTING.md` 的舊版數據使用不同模型與策略，只能作歷史背景，不納入本報告統計')

[System.IO.File]::WriteAllText($reportPath, $markdown.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Output "REPORT: $reportPath"
Write-Output "DATA: $csvPath"
Write-Output "CURVE: $svgPath"
