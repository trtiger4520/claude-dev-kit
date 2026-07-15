# install.ps1 — 安裝/更新 claude-dev-kit 到 %USERPROFILE%\.claude（Windows）
# 重複執行即為更新；settings.json 只合併本 kit 的 hook 註冊，不動其他既有設定
# 執行時逐項回報：[建立]/[新增]/[覆蓋]/[取代]/[合併]/[更新]/[備份]/[未動]，皆附完整路徑
$ErrorActionPreference = 'Stop'

$src  = $PSScriptRoot
$dest = Join-Path $env:USERPROFILE '.claude'

Write-Host "== claude-dev-kit 安裝/更新 -> $dest =="

foreach ($dir in 'agents', 'commands', 'skills', 'hooks', 'workflows') {
    $d = Join-Path $dest $dir
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force $d | Out-Null
        Write-Host "[建立] $d"
    }
}

function Install-File([string]$file, [string]$destDir) {
    $target = Join-Path $destDir (Split-Path -Leaf $file)
    $action = if (Test-Path $target) { '覆蓋' } else { '新增' }
    Copy-Item $file $target -Force
    Write-Host "[$action] $target"
}

foreach ($f in Get-ChildItem (Join-Path $src 'agents')   -Filter *.md) { Install-File $f.FullName (Join-Path $dest 'agents') }
foreach ($f in Get-ChildItem (Join-Path $src 'commands') -Filter *.md) { Install-File $f.FullName (Join-Path $dest 'commands') }
foreach ($f in Get-ChildItem (Join-Path $src 'workflows') -Filter *.js) { Install-File $f.FullName (Join-Path $dest 'workflows') }

foreach ($d in Get-ChildItem (Join-Path $src 'skills') -Directory) {
    $target = Join-Path $dest "skills\$($d.Name)"
    $action = if (Test-Path $target) { '覆蓋' } else { '新增' }
    Copy-Item $d.FullName (Join-Path $dest 'skills') -Recurse -Force
    Write-Host "[$action] $target"
}

# CLAUDE.md 整份取代，不是附加；取代前備份一層（.bak 每次覆蓋），內容相同則不處理
$claudeSrc    = Join-Path $src 'CLAUDE.md'
$claudeTarget = Join-Path $dest 'CLAUDE.md'
if (Test-Path $claudeTarget) {
    if ((Get-FileHash $claudeSrc).Hash -eq (Get-FileHash $claudeTarget).Hash) {
        Write-Host "[未動] $claudeTarget — 內容相同，未覆蓋、未備份"
    }
    else {
        Copy-Item $claudeTarget "$claudeTarget.bak" -Force
        Write-Host "[備份] $claudeTarget -> $claudeTarget.bak（只保留一層）"
        Copy-Item $claudeSrc $claudeTarget -Force
        Write-Host "[取代] $claudeTarget（整份覆蓋，非附加）"
    }
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
    if ($settingsExisted) {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        Write-Host "[備份] $settingsPath -> $settingsPath.bak"
    }
    else {
        Write-Host "[新增] $settingsPath"
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
    $json = $settings | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding $false))
}

if ($otherKeys.Count)       { Write-Host "[未動] settings.json 其他設定鍵：$($otherKeys -join '、')" }
if ($otherHookEvents.Count) { Write-Host "[未動] settings.json hooks 其他事件：$($otherHookEvents -join '、')" }

Write-Host "== 完成 =="
Write-Host "未列出的既有檔案與設定一律未變動"
Write-Host "skills 目錄若是首次建立，需重啟 Claude Code"
