# Claude Dev Kit

適用於 Claude Code 全域設定（~/.claude/）

## 結構與機制分層

| 層        | 內容                                                   | 載入時機   | 設計原因                       |
| --------- | ------------------------------------------------------ | ---------- | ------------------------------ |
| CLAUDE.md | 每次都適用的行為規則                                   | 每個對話   | 控制在 50 行內，省 context     |
| agents/   | planner、explorer、implementer、verifier               | 被委派時   | 職責分離、獨立 context         |
| commands/ | /orchestrate、/verify                                  | 手動觸發   | 強制走完整流程                 |
| skills/   | repo-discovery、bugfix-protocol、risky-change、lessons | 情境符合時 | 冗長的檢查清單不該常駐 context |

skills 的命名刻意避開常見的 plugin skill 名稱（debug、code-review、testing-strategy 等），
不會與 engineering 系列 plugin 衝突

## 安裝方式

```powershell
# Windows PowerShell，全新安裝或覆蓋舊版 claude-orchestration
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\agents","$env:USERPROFILE\.claude\commands","$env:USERPROFILE\.claude\skills"
Copy-Item agents\*.md "$env:USERPROFILE\.claude\agents\"
Copy-Item commands\*.md "$env:USERPROFILE\.claude\commands\"
Copy-Item -Recurse -Force skills\* "$env:USERPROFILE\.claude\skills\"
# CLAUDE.md 這次請「整份取代」而不是附加，原因見下方衝突整理
Copy-Item -Force CLAUDE.md "$env:USERPROFILE\.claude\CLAUDE.md"
```

macOS/Linux 對應：cp agents/\*.md ~/.claude/agents/ 依此類推

注意：skills 目錄若是首次建立需重啟 Claude Code
