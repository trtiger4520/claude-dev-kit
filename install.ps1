# install.ps1 — 安裝/更新 claude-dev-kit 到 %USERPROFILE%\.claude（Windows）
# 重複執行即為更新；settings.json 只合併本 kit 的 hook 註冊，不動其他既有設定
# 執行時逐項回報：[建立]/[新增]/[覆蓋]/[取代]/[合併]/[更新]/[備份]/[未動]，皆附完整路徑
# -DryRun：只印出將會做的動作，不寫入任何檔案
param(
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$src  = Join-Path $PSScriptRoot 'src'
$dest = Join-Path $env:USERPROFILE '.claude'

if ($DryRun) {
    Write-Host "== claude-dev-kit 安裝/更新 -> $dest（-DryRun，僅預覽不寫入）=="
} else {
    Write-Host "== claude-dev-kit 安裝/更新 -> $dest =="
}

foreach ($dir in 'agents', 'commands', 'skills', 'hooks') {
    $d = Join-Path $dest $dir
    if (-not (Test-Path $d)) {
        if ($DryRun) {
            Write-Host "[建立] $d（dry-run，未建立）"
        } else {
            New-Item -ItemType Directory -Force $d | Out-Null
            Write-Host "[建立] $d"
        }
    }
}

function Install-File([string]$file, [string]$destDir) {
    $target = Join-Path $destDir (Split-Path -Leaf $file)
    $action = if (Test-Path $target) { '覆蓋' } else { '新增' }
    if ($DryRun) {
        Write-Host "[$action] $target（dry-run，未寫入）"
    } else {
        Copy-Item $file $target -Force
        Write-Host "[$action] $target"
    }
}

# ---- agents：安裝時可為每個 agent 選擇 model 與 effort ----
$modelAliases  = @{ '1' = 'inherit'; '2' = 'sonnet'; '3' = 'opus'; '4' = 'haiku'; '5' = 'fable' }
$effortAliases = @{ '1' = '';        '2' = 'low';    '3' = 'medium'; '4' = 'high'; '5' = 'xhigh'; '6' = 'max' }
$interactive   = -not [Console]::IsInputRedirected

function Get-CurrentField([string]$targetPath, [string]$fieldName) {
    if (Test-Path $targetPath) {
        $line = Get-Content $targetPath | Where-Object { $_ -match "^${fieldName}:\s*(.+)$" } | Select-Object -First 1
        if ($line -and ($line -match "^${fieldName}:\s*(.+)$")) { return $Matches[1].Trim() }
    }
    return ''
}

function Resolve-Model([string]$agentName, [string]$currentModel) {
    $envVar = "CDK_MODEL_$($agentName.ToUpper())"
    if (Test-Path "Env:$envVar") {
        $envVal = (Get-Item "Env:$envVar").Value
        if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal.Trim() }
    }
    if (-not $interactive) { return $currentModel }
    Write-Host ""
    Write-Host "選擇 agent「$agentName」使用的 model（目前：$currentModel）"
    Write-Host "  1) inherit（跟隨主對話模型）"
    Write-Host "  2) sonnet"
    Write-Host "  3) opus"
    Write-Host "  4) haiku"
    Write-Host "  5) fable"
    $choice = Read-Host "輸入數字或直接輸入完整 model ID，Enter 保留目前設定"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $currentModel }
    if ($modelAliases.ContainsKey($choice)) { return $modelAliases[$choice] }
    return $choice.Trim()
}

function Resolve-Effort([string]$agentName, [string]$currentEffort) {
    $envVar = "CDK_EFFORT_$($agentName.ToUpper())"
    if (Test-Path "Env:$envVar") {
        $envVal = (Get-Item "Env:$envVar").Value
        if (-not [string]::IsNullOrWhiteSpace($envVal)) {
            if ($envVal.Trim() -eq 'inherit') { return '' }
            return $envVal.Trim()
        }
    }
    if (-not $interactive) { return $currentEffort }
    $currentDisplay = if ($currentEffort) { $currentEffort } else { 'inherit' }
    Write-Host ""
    Write-Host "選擇 agent「$agentName」使用的 effort（目前：$currentDisplay）"
    Write-Host "  1) inherit（跟隨主對話，不寫入 effort 欄位）"
    Write-Host "  2) low"
    Write-Host "  3) medium"
    Write-Host "  4) high"
    Write-Host "  5) xhigh"
    Write-Host "  6) max"
    $choice = Read-Host "輸入數字，Enter 保留目前設定"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $currentEffort }
    if ($effortAliases.ContainsKey($choice)) { return $effortAliases[$choice] }
    Write-Warning "無效輸入，保留目前設定：$currentDisplay"
    return $currentEffort
}

function Install-AgentFile([string]$file, [string]$destDir) {
    $target = Join-Path $destDir (Split-Path -Leaf $file)
    $action = if (Test-Path $target) { '覆蓋' } else { '新增' }
    $agentName = [IO.Path]::GetFileNameWithoutExtension($file)

    # 既有安裝以目的地設定為準；全新安裝以 src frontmatter 為預設
    $currentModel = Get-CurrentField $target 'model'
    if (-not $currentModel) { $currentModel = Get-CurrentField $file 'model' }
    if (-not $currentModel) { $currentModel = 'inherit' }
    $currentEffort = if (Test-Path $target) { Get-CurrentField $target 'effort' } else { Get-CurrentField $file 'effort' }

    $chosenModel  = Resolve-Model  $agentName $currentModel
    $chosenEffort = Resolve-Effort $agentName $currentEffort

    $content = Get-Content $file -Raw -Encoding UTF8
    $content = $content -replace '(?m)^effort:\s*.*\r?\n', ''
    $modelLine = "model: $chosenModel"
    if ($chosenEffort) { $modelLine = "$modelLine`neffort: $chosenEffort" }
    $content = $content -replace '(?m)^model:\s*.+$', $modelLine

    if ($DryRun) {
        Write-Host "[$action] $target（dry-run，未寫入）"
    } else {
        [System.IO.File]::WriteAllText($target, $content, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "[$action] $target"
    }
    $effortDisplay = if ($chosenEffort) { $chosenEffort } else { 'inherit' }
    Write-Host "       model=$chosenModel, effort=$effortDisplay"
}

foreach ($f in Get-ChildItem (Join-Path $src 'agents')   -Filter *.md) { Install-AgentFile $f.FullName (Join-Path $dest 'agents') }
foreach ($f in Get-ChildItem (Join-Path $src 'commands') -Filter *.md) { Install-File $f.FullName (Join-Path $dest 'commands') }

foreach ($d in Get-ChildItem (Join-Path $src 'skills') -Directory) {
    $target = Join-Path $dest "skills\$($d.Name)"
    $action = if (Test-Path $target) { '覆蓋' } else { '新增' }
    if ($DryRun) {
        Write-Host "[$action] $target（dry-run，未寫入）"
    } else {
        Copy-Item $d.FullName (Join-Path $dest 'skills') -Recurse -Force
        Write-Host "[$action] $target"
    }
}

# CLAUDE.md 整份取代，不是附加；取代前備份一層（.bak 每次覆蓋），內容相同則不處理
$claudeSrc    = Join-Path $src 'CLAUDE.md'
$claudeTarget = Join-Path $dest 'CLAUDE.md'
if (Test-Path $claudeTarget) {
    if ((Get-FileHash $claudeSrc).Hash -eq (Get-FileHash $claudeTarget).Hash) {
        Write-Host "[未動] $claudeTarget — 內容相同，未覆蓋、未備份"
    }
    elseif ($DryRun) {
        Write-Host "[備份] $claudeTarget -> $claudeTarget.bak（dry-run，未寫入）"
        Write-Host "[取代] $claudeTarget（dry-run，未寫入）"
    }
    else {
        Copy-Item $claudeTarget "$claudeTarget.bak" -Force
        Write-Host "[備份] $claudeTarget -> $claudeTarget.bak（只保留一層）"
        Copy-Item $claudeSrc $claudeTarget -Force
        Write-Host "[取代] $claudeTarget（整份覆蓋，非附加）"
    }
}
elseif ($DryRun) {
    Write-Host "[新增] $claudeTarget（dry-run，未寫入）"
}
else {
    Copy-Item $claudeSrc $claudeTarget -Force
    Write-Host "[新增] $claudeTarget"
}

Install-File (Join-Path $src 'hooks\risky-change-trigger.ps1') (Join-Path $dest 'hooks')

# ---- settings.json：合併 UserPromptSubmit hook 註冊 ----
$settingsPath = Join-Path $dest 'settings.json'
$hookScript   = Join-Path $dest 'hooks\risky-change-trigger.ps1'
$shell        = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$hookCommand  = "$shell -NoProfile -ExecutionPolicy Bypass -File `"$hookScript`""

$settings = [pscustomobject]@{}
$settingsExisted = Test-Path $settingsPath
if ($settingsExisted) {
    $rawText = Get-Content -Raw -Encoding UTF8 $settingsPath
    if (-not [string]::IsNullOrWhiteSpace($rawText)) {
        try { $settings = $rawText | ConvertFrom-Json }
        catch {
            Write-Warning "settings.json 解析失敗，未自動合併 hook（檔案未被修改）。其餘檔案已安裝完成"
            Write-Warning "請手動將以下 command 加入 hooks.UserPromptSubmit（格式見 README）："
            Write-Host $hookCommand
            exit 1
        }
    }
}

# 先記下既有設定鍵，最後回報哪些沒動
$otherKeys = @($settings.PSObject.Properties.Name | Where-Object { $_ -ne 'hooks' })
$otherHookEvents = @()
if ($settings.PSObject.Properties['hooks']) {
    $otherHookEvents = @($settings.hooks.PSObject.Properties.Name | Where-Object { $_ -ne 'UserPromptSubmit' })
}

if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}
if (-not $settings.hooks.PSObject.Properties['UserPromptSubmit']) {
    $settings.hooks | Add-Member -NotePropertyName UserPromptSubmit -NotePropertyValue @()
}

# 已註冊過：內容相同就不動檔案，不同則只更新那筆 command；沒註冊過則附加新項目
$found = $false; $oldCommand = $null
foreach ($matcher in @($settings.hooks.UserPromptSubmit)) {
    foreach ($h in @($matcher.hooks)) {
        if ($h -and $h.command -match 'risky-change-trigger') {
            $found = $true
            if ($h.command -ne $hookCommand) {
                $oldCommand = $h.command
                $h.command = $hookCommand
            }
        }
    }
}

if ($found -and -not $oldCommand) {
    Write-Host "[未動] $settingsPath — hook 已註冊且內容相同，未寫入、未備份"
}
else {
    $suffix = if ($DryRun) { "（dry-run，未寫入）" } else { "" }
    if ($settingsExisted) {
        if (-not $DryRun) {
            Copy-Item $settingsPath "$settingsPath.bak" -Force
        }
        Write-Host "[備份] $settingsPath -> $settingsPath.bak$suffix"
    }
    else {
        Write-Host "[新增] $settingsPath$suffix"
    }
    if ($found) {
        Write-Host "[更新] $settingsPath hooks.UserPromptSubmit 既有項目 command："
        Write-Host "       舊：$oldCommand"
        Write-Host "       新：$hookCommand"
    }
    else {
        $entry = [pscustomobject]@{
            hooks = @([pscustomobject]@{ type = 'command'; command = $hookCommand; timeout = 15 })
        }
        $settings.hooks.UserPromptSubmit = @($settings.hooks.UserPromptSubmit) + $entry
        Write-Host "[合併] $settingsPath 新增 hooks.UserPromptSubmit 項目："
        Write-Host "       command = $hookCommand"
    }
    if (-not $DryRun) {
        $json = $settings | ConvertTo-Json -Depth 32
        [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding $false))
    }
}

if ($otherKeys.Count)       { Write-Host "[未動] settings.json 其他設定鍵：$($otherKeys -join '、')" }
if ($otherHookEvents.Count) { Write-Host "[未動] settings.json hooks 其他事件：$($otherHookEvents -join '、')" }

Write-Host "== 完成 =="
if ($DryRun) { Write-Host "（-DryRun 模式，未寫入任何檔案）" }
Write-Host "未列出的既有檔案與設定一律未變動"
Write-Host "skills 目錄若是首次建立，需重啟 Claude Code"
