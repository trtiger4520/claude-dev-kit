# Claude Dev Kit

適用於 Claude Code 全域設定（~/.claude/）

## 結構與機制分層

| 層        | 內容                                                   | 載入時機   | 設計原因                       |
| --------- | ------------------------------------------------------ | ---------- | ------------------------------ |
| CLAUDE.md | 每次都適用的行為規則                                   | 每個對話   | 控制在 50 行內，省 context     |
| agents/   | planner、explorer、implementer、verifier               | 被委派時   | 職責分離、獨立 context         |
| commands/ | /orchestrate、/verify                                  | 手動觸發   | 強制走完整流程                 |
| skills/   | repo-discovery、bugfix-protocol、risky-change、lessons | 情境符合時 | 冗長的檢查清單不該常駐 context |
| hooks/    | risky-change-trigger（UserPromptSubmit 關鍵字硬觸發）  | 每次送出 prompt | 高風險偵測不能交給模型主觀判斷 |

skills 的命名刻意避開常見的 plugin skill 名稱（debug、code-review、testing-strategy 等），
不會與 engineering 系列 plugin 衝突

## 安裝方式

全新安裝與更新都是同一支腳本，重複執行即可

### Windows（PowerShell）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### macOS / Linux

```bash
sh install.sh
```

加上 `-DryRun`（PowerShell）或 `--dry-run`（sh）只會印出將會做的動作，不寫入任何檔案，方便測試

兩支腳本做的事相同：

- 複製 agents/、commands/、skills/、hooks/ 到 `~/.claude/` 對應目錄
- 安裝 agents 時，逐一詢問每個 agent 要用的 model 與 effort（僅互動環境會問；直接 Enter 保留目前設定）：
  - model：`inherit`（跟隨主對話模型）/`sonnet`/`opus`/`haiku`/`fable`，也可直接輸入完整 model ID
  - effort：`inherit`（不寫入 effort 欄位）/`low`/`medium`/`high`/`xhigh`/`max`
  - 各 agent 的建議預設值（全新安裝時直接 Enter 即採用；更新時保留既有設定，不會被預設值覆蓋）：

    | agent | model | effort |
    | --- | --- | --- |
    | planner | inherit | inherit |
    | verifier | inherit | high |
    | implementer | sonnet | medium |
    | explorer | sonnet | low |

    分配邏輯：品質關鍵角色（planner 規劃、verifier 驗收把關）跟隨主對話模型，verifier 加高 effort；implementer 執行已定義明確的子任務，用 sonnet+medium 平衡成本；explorer 需要正確追蹤呼叫鏈（探索錯誤會污染下游），用 sonnet+low 兼顧品質與 fan-out 成本（註：haiku 不支援 effort 參數）。預設值定義在 `src/agents/*.md` 的 frontmatter，改那裡即可調整預設
  - 也可用環境變數在安裝前直接指定、跳過該欄位的提示：`CDK_MODEL_EXPLORER`、`CDK_MODEL_IMPLEMENTER`、`CDK_MODEL_PLANNER`、`CDK_MODEL_VERIFIER`（值同上）；`CDK_EFFORT_EXPLORER`、`CDK_EFFORT_IMPLEMENTER`、`CDK_EFFORT_PLANNER`、`CDK_EFFORT_VERIFIER`（值為 `inherit`/空字串 或 low/medium/high/xhigh/max）
  - 非互動環境（stdin 非 tty，例如 CI、curl pipe）且未設定對應環境變數時，直接沿用該 agent 目前已安裝的設定，不會被重置回預設值
- CLAUDE.md「整份取代」`~/.claude/CLAUDE.md`（不是附加）
- 自動把 UserPromptSubmit hook 合併進 `~/.claude/settings.json`——只新增或更新本 kit 自己的項目，不動其他既有設定；寫入前先備份為 settings.json.bak

執行時會逐項回報動了什麼、沒動什麼，皆附完整路徑：

| 標記   | 意義                                                         |
| ------ | ------------------------------------------------------------ |
| [建立] | 目錄原本不存在，新建                                          |
| [新增] | 目標檔案原本不存在，複製進去                                  |
| [覆蓋] | 目標檔案已存在，以 kit 版本覆蓋                               |
| [取代] | 僅 CLAUDE.md——整份覆蓋而非附加，取代前先備份；內容相同時不覆蓋也不備份 |
| [合併] | settings.json 附加本 kit 的 hook 項目，其餘內容原樣保留       |
| [更新] | settings.json 已有本 kit 的 hook 項目，只改該筆 command（列出新舊值） |
| [備份] | 寫入前先備份：settings.json → settings.json.bak、CLAUDE.md → CLAUDE.md.bak（各只保留一層，每次覆蓋） |
| [未動] | 未變動的部分：settings.json 其他設定鍵、hooks 其他事件；hook 已註冊且相同、或 CLAUDE.md 內容相同時，該檔完全不寫入也不備份 |

未列出的既有檔案與設定一律不會被變動

注意：

- skills 目錄若是首次建立需重啟 Claude Code
- macOS/Linux 的 hook 與 settings 合併需要 python3（macOS 裝了 Xcode Command Line Tools 即有）
- 若 settings.json 無法解析，腳本會跳過合併並提示手動處理

手動合併 settings.json（僅腳本無法解析時需要）：

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command", "command": "<見下方對應平台指令>", "timeout": 15 } ] }
  ]
}
```

- Windows：`pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\\Users\\<你>\\.claude\\hooks\\risky-change-trigger.ps1"`
- macOS/Linux：`"/Users/<你>/.claude/hooks/risky-change-trigger.sh"`
