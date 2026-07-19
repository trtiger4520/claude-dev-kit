# Claude Dev Kit

適用於 Claude Code 全域設定（~/.claude/）

## 結構與機制分層

| 層        | 內容                                                   | 載入時機   | 設計原因                       |
| --------- | ------------------------------------------------------ | ---------- | ------------------------------ |
| CLAUDE.md | 每次都適用的行為規則                                   | 每個對話   | 保留精簡且可直接執行的政策     |
| agents/   | planner、explorer、implementer、verifier               | 被委派時   | 職責分離、獨立 context         |
| commands/ | /orchestrate、/verify                                  | 手動觸發   | 強制走完整流程                 |
| skills/   | repo-discovery、bugfix-protocol、risky-change、source-boundary、lessons | 情境符合時 | 冗長的檢查清單不該常駐 context |
| hooks/    | risky-change-trigger（UserPromptSubmit 關鍵字候選標記） | 每次送出 prompt | 便宜篩選潛在風險，再依實際變更決定 lane |

skills 的命名刻意避開常見的 plugin skill 名稱（debug、code-review、testing-strategy 等），
不會與 engineering 系列 plugin 衝突

## 子代理策略

預設由主 Agent 直接執行，子代理只用於值得隔離且能獨立完成的工作：

- `single-agent`：已知路徑、局部低風險修改、可由 build、lint 或 test 驗證
- `plan-light`：預設零子代理，需要隔離時最多使用一個 explorer、implementer 或 verifier
- `orchestrate-heavy`：使用者明確要求完整流程，或實際修改安全控制、持久化資料、正式環境狀態、核心架構或破壞公開契約

檔案數、跨模組、跨平台、陌生路徑與高風險關鍵字都不能單獨觸發完整流程。唯讀安全或架構分析維持 `single-agent` 或 `plan-light`

所有 `orchestrate-heavy` 都使用一個 planner、writer 前明確取得使用者核准，以及一個獨立 verifier；只有核准後仍存在未解答程式路徑問題時才選用最多一個 explorer

## 安裝方式

全新安裝與更新都是同一支腳本，重複執行即可

### Windows（PowerShell）

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### macOS / Linux

```bash
sh install.sh
```

加上 `-DryRun`（PowerShell）或 `--dry-run`（sh）只會印出將會做的動作，不寫入任何檔案，方便測試

可明確指定 Claude 設定目錄：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Destination C:\path\to\claude-config
```

```bash
bash install.sh --destination /path/to/claude-config
```

目的地優先序為：明確參數、`CLAUDE_CONFIG_DIR`、預設的 `~/.claude`

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

## 安全測試

所有自動測試只使用 repository 內已忽略的 `.sandbox/`：

```text
.sandbox/
  claude-profile/
  runs/<guid>/install-root/
  runs/<guid>/project/
  runs/<guid>/tmp/
```

PowerShell 靜態與安裝器測試：

```powershell
pwsh -NoProfile -File .\tests\Test-All.ps1
```

第一次執行 Claude live lane eval 前，在隔離設定檔完成一次登入：

```powershell
pwsh -NoProfile -File .\tests\Initialize-ClaudeSandbox.ps1
```

若 `claude auth status` 顯示已登入，但 Live API 回傳 401，使用 `-ForceLogin` 重新整理的仍是 `.sandbox/claude-profile`，不會登出、讀取或退回使用者預設設定：

```powershell
pwsh -NoProfile -File .\tests\Initialize-ClaudeSandbox.ps1 -ForceLogin
```

執行四個 smoke scenarios 或完整十二個 scenarios：

```powershell
pwsh -NoProfile -File .\tests\Invoke-LaneScenariosLive.ps1 -ApprovedTotalBudgetUsd 0.32
pwsh -NoProfile -File .\tests\Invoke-LaneScenariosLive.ps1 -All -ApprovedTotalBudgetUsd 0.96
```

測試 runner 會同時設定 `CLAUDE_CONFIG_DIR` 與 `CLAUDE_CODE_TMPDIR`，不會退回使用者 Claude 設定。`-ApprovedTotalBudgetUsd` 是每次 runner 的明確整批核准預算；單次 CLI 門檻預設 0.50 USD，可用 `-MaxBudgetUsd` 調低。Runner 會把每案成功或失敗的已觀察成本累加，下一案只取得剩餘核准額度。CLI 在單次 API 呼叫完成後才檢查門檻，因此兩者都不是帳單的絕對硬上限。若安裝目的地解析到使用者目錄，測試會停止且不會清理或修改該位置

## 任務成本基準報告

成本基準使用合成的 .NET 10 與 Vue fixture，比較現行保守委派策略和反事實策略：

| 任務 | 現行策略 | 比較策略 | 討論重點 |
|---|---|---|---|
| 已知 DTO 小修改 | single-agent | forced-heavy | 避免不必要完整 orchestration 的節省 |
| 大型陌生登入呼叫鏈 | explorer ×1 | forced-single | context 隔離成本與追蹤完整度 |
| authentication policy 修改 | heavy | forced-single | 核准、單一 writer 與 verifier 的安全溢價 |

每個任務先做三次 lane 分類，再對兩種執行策略各做三次實作或分析，共 27 筆量測。每一筆使用獨立的 fixture 副本，並以固定驗收條件檢查品質、修改範圍與測試結果

反事實 `forced-single` 仍載入完全相同的已安裝政策與工程規則，只透過 benchmark prompt 和 `Agent` 工具禁用來強制主 Agent 執行，避免把「有無子代理」和「有無 CLAUDE.md／Hook／Skill」混成同一個變因

Live benchmark 分成兩個需要明確預算的階段。先執行九筆校準量測：

```powershell
pwsh -NoProfile -File .\tests\Invoke-CostBenchmark.ps1 -Phase Calibrate -ApprovedBudgetUsd <校準預算>
```

校準完成後，runner 會顯示 Benchmark ID、已觀察成本，以及含 25% 緩衝的剩餘成本投影。確認投影後，再以同一個 Benchmark ID 核准完整階段：

```powershell
pwsh -NoProfile -File .\tests\Invoke-CostBenchmark.ps1 -Phase Complete -BenchmarkId <benchmark-id> -ApprovedBudgetUsd <核准的剩餘預算>
```

校準 manifest 同時鎖定 repository 政策、隔離 profile 實際安裝內容、Agent model／effort、任務定義、fixture 與 Claude CLI 版本。完整階段發現任一 fingerprint 漂移就會停止，避免把不同條件的資料合併成同一份 A/B 報告

完整 27 筆量測成功後會產出：

- `reports/cost-benchmark/task-cost-report.md`：討論用摘要、策略差異與每輪明細表
- `reports/cost-benchmark/task-cost-data.csv`：可供 Excel、Power BI 或其他分析工具使用的原始正規化資料
- `reports/cost-benchmark/task-cost-curves.svg`：三個任務的現行與反事實策略三輪累積成本曲線

CSV 以 `record_state` 區分目前採用的 27 筆樣本與重試前保留的 `superseded-attempt`。失敗 attempt 會計入 Benchmark 作業總成本，但不會混入策略均值與曲線

若校準中斷，可使用輸出中的 Benchmark ID 和新的明確預算續跑；只有要重試已留下錯誤紀錄的 cell 時才加上 `-RetryFailed`：

```powershell
pwsh -NoProfile -File .\tests\Invoke-CostBenchmark.ps1 -Phase Calibrate -BenchmarkId <benchmark-id> -ApprovedBudgetUsd <新核准預算> -RetryFailed
```

`total_cost_usd` 是 Claude CLI 回報的 API 等價成本估算，不代表 Claude 訂閱方案的實際帳單。Raw transcript、暫存專案與 manifest 只保留在 `.sandbox/runs/<benchmark-id>/`，不會讀取或退回使用者 Claude 設定檔
