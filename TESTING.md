# 委派規則測試計畫

目前版本驗證保守委派 gate、單一 `plan-light` 角色、實際高風險變更判斷、source boundary 與 sandbox 安裝隔離

## 現行自動化環境

所有測試資料只能建立在 repository 內已忽略的 `.sandbox/`，不得以使用者目錄作為安裝、設定、暫存或測試專案目的地

- `.sandbox/claude-profile`：持久的隔離 Claude 登入與設定
- `.sandbox/runs/<guid>/install-root`：安裝器測試
- `.sandbox/runs/<guid>/project`：從 `tests/fixtures/lane-project` 複製的測試專案
- `.sandbox/runs/<guid>/tmp`：Claude CLI 暫存資料

```powershell
pwsh -NoProfile -File .\tests\Test-All.ps1
pwsh -NoProfile -File .\tests\Initialize-ClaudeSandbox.ps1
pwsh -NoProfile -File .\tests\Invoke-LaneScenariosLive.ps1 -ApprovedTotalBudgetUsd 0.32
pwsh -NoProfile -File .\tests\Invoke-LaneScenariosLive.ps1 -All -ApprovedTotalBudgetUsd 0.96
```

`auth status` 只檢查本機登入紀錄；若 Live 呼叫回傳 401，使用 `Initialize-ClaudeSandbox.ps1 -ForceLogin` 明確重新整理隔離 profile 的 Claude subscription 登入。此流程不先執行 `auth logout`，也不接觸使用者預設 Claude 設定

若任何目的地解析到使用者目錄，測試必須立即停止。即使已發生意外安裝，也不得檢查、異動、復原或刪除該位置

## 現行 lane 預期

| 情境 | lane | 子代理上限 |
|---|---|---:|
| 已知 DTO、CRUD 或文件機械修改 | single-agent / plan-light | 0 |
| 大型陌生呼叫鏈或 CI Log | plan-light | explorer ×1 |
| 顯式獨立驗證 | plan-light | verifier ×1 |
| 唯讀安全或架構分析 | single-agent / plan-light | explorer ×0-1 |
| 單一低風險 cohesive feature | plan-light | implementer ×1 |
| 實際 authentication policy 或正式資料 migration | orchestrate-heavy | planner ×1、implementer ×1、verifier ×1，explorer 選用 ×1 |
| 明確完整流程的兩個獨立交付單元 | orchestrate-heavy | implementer 最多 ×2 |

`orchestrate-heavy` 的固定治理骨架為 planner ×1、writer 前明確核准、verifier ×1；explorer 只在核准後仍有未解答程式路徑問題時選用。兩個 disjoint cohesive units 可以使用 implementer ×2，但不省略 planner、核准或 verifier

Live lane eval 每個 scenario 只執行一次，使用 Sonnet low、`--tools ""`、額外禁止 `Agent`、最多兩個 turns與結構化輸出。`-ApprovedTotalBudgetUsd` 明確限制整批核准額度，單次 CLI 門檻預設 0.50 USD；runner 會把成功及錯誤結果的已觀察成本納入整批累計，並只把剩餘額度交給下一案。第二個 turn 僅供 Claude CLI 完成 structured output 封裝。CLI 在單次 API 呼叫完成後才可能判斷超出門檻，因此參數不是帳單的絕對硬上限

## 現行任務成本基準

`tests/Invoke-CostBenchmark.ps1` 量測 lane 分類成本與三種代表性任務的真實執行成本。它不使用本 repository 作為 Claude 寫入目標，而是為每筆量測從 `tests/fixtures/cost-benchmark` 建立全新的 `.sandbox/runs/<benchmark-id>/projects/<cell>` 副本

量測矩陣：

| 類型 | 任務數 | 策略數 | 重複次數 | 筆數 |
|---|---:|---:|---:|---:|
| Lane 分類 | 3 | 1 | 3 | 9 |
| 任務執行 | 3 | 2 | 3 | 18 |
| 合計 | | | | 27 |

每筆資料記錄 CLI 回報的成本、時間、Token、cache token、turns、lane、Agent 角色、修改範圍與確定性驗收結果。重試前的失敗結果只要 Claude CLI 提供 `total_cost_usd` 仍會以 `record_state=superseded-attempt` 保留在 CSV 並計入作業總成本，但不混入策略均值與曲線

`forced-single` 不使用 Claude CLI `--safe-mode`，因為 safe mode 會同時移除全域 CLAUDE.md、Hook、Skill 與 Agent 設定，讓 A/B 比較混入政策缺席的影響。Runner 保留同一套已安裝政策，只以明確 counterfactual prompt 與 `--disallowed-tools Agent` 移除委派能力

預算流程刻意拆成兩階段：

1. 使用 `-Phase Calibrate -ApprovedBudgetUsd <校準預算>` 明確核准第一輪九筆資料
2. runner 依校準資料估算剩餘兩輪，再乘上 25% 緩衝
3. 人員確認投影後，使用同一個 Benchmark ID 與新的 `-ApprovedBudgetUsd` 執行 `-Phase Complete`

完整命令：

```powershell
pwsh -NoProfile -File .\tests\Invoke-CostBenchmark.ps1 -Phase Calibrate -ApprovedBudgetUsd <校準預算>
pwsh -NoProfile -File .\tests\Invoke-CostBenchmark.ps1 -Phase Complete -BenchmarkId <benchmark-id> -ApprovedBudgetUsd <核准的剩餘預算>
```

安全與可比較性條件：

- 兩階段之間 Claude CLI 版本與 policy fingerprint 必須相同
- 兩階段之間隔離 profile 的實際安裝 fingerprint 必須相同，包含 Agent model／effort 與 managed settings
- 兩階段之間任務定義與合成 fixture fingerprint 必須相同
- 每筆執行使用無外部套件相依的合成 fixture，並在變更前建立本地 Git baseline
- 高風險現行策略必須先輸出核准標記，核准前不得有 tracked 或 non-ignored untracked 變更
- 所有 Claude 設定、暫存、raw transcript 與工作專案只能存在 `.sandbox/`
- 校準或完整 runner 都沒有預設可用預算，缺少 `-ApprovedBudgetUsd` 會直接拒絕執行
- 不因單筆失敗自動重跑；只有明確傳入 `-RetryFailed` 才會保留前次 attempt 後重試
- 校準中斷時可用原 Benchmark ID 續跑，已完成 cell 會略過；重試既有錯誤 cell 另須新的明確預算與 `-RetryFailed`

完整執行成功後，`tests/New-CostReport.ps1` 會建立 Markdown、CSV 與 SVG。Markdown 提供策略均值、中位數、範圍、時間、Token、策略驗收通過率與相對差異；SVG 使用共用 Y 軸顯示三個任務各三輪的累積 API 等價成本。策略驗收包含共通交付檢查及該策略承諾的工作流程條件，不等同純產品品質分數。成本是 Claude CLI 的 API 等價估算，不是訂閱帳單

## 2026-07-12 歷史完整行為測試

以下內容保留為舊版策略的歷史證據，其中 `Runtime:`、`tasks/metrics.log`、多 explorer fan-out 與外部 CleanArchitecture 測試位置已不再是現行驗收條件

## 測試任務

### T1 小任務 → 預期 lane: single-agent

> 為 TodoItem 的 Note 加上 500 字元長度上限驗證，並補一個對應的單元測試

（原題為 Title 200 字元上限，但模板 10.8.0 已內建該規則，故改為 Note——目前完全沒有驗證規則）

- **預期 subagent**：無（0 個）— 主 agent 直接改 validator + 測試
- **通過標準**：全程沒有啟動任何 subagent；tokens 明顯低於舊行為（舊規則會因 2-3 檔觸發全套流程）

### T2 中任務低風險 → 預期 lane: plan-light

> 為 TodoList 加上封存（Archive）功能：新增 command、endpoint 與測試

- **預期 subagent**：至多 1 個 planner（或主線內短計畫），至多 1 個 implementer；**不出現** verifier 全套流程
- **通過標準**：沒有觸發完整 planner → implementer(s) → verifier 劇本；驗證用窄範圍指令（filtered tests）

### T3 顯式完整流程 → `/orchestrate`

> /orchestrate 為 TodoItem 加上 DueDate（到期日）欄位與依到期日排序功能，需更新 Domain、Application（command/query）、Web endpoint 與對應測試

（原題為 Priority 欄位，但模板 10.8.0 的 TodoItem 已內建 Priority，故改為 DueDate——觸及層面相同）

- **預期 subagent**：planner ×1 → explorer ×0-2 → implementer ≤2 並行（依檔案衝突分群）→ verifier ×1
- **通過標準**：每個 subagent 報告結尾有 `Runtime:` 行；結束後 `tasks/metrics.log` 新增一行完整記錄；無 model capacity 錯誤（explorer/implementer 已改 inherit）

### T4 探索型 → 預期 read fan-out

> 追蹤 CreateTodoItem 從 HTTP endpoint 到資料庫寫入的完整流程，整理驗證、授權、Domain Event 的處理位置與慣例

- **預期 subagent**：explorer ×3 以上**並行**（endpoint 路徑 / 行為管線 / Domain Event 各一）
- **通過標準**：explorer 一次並行啟動而非逐一序列；主 context 沒有出現原始搜尋輸出；invariants 被記錄到 `tasks/notes.md`

### T5 高風險自動觸發 → 預期 lane: orchestrate（不需顯式呼叫）

> 調整 Identity 授權設定：把 TodoLists 相關 endpoint 全部改為需要 Administrator 角色

（原題寫「特定角色」，R1 實測會觸發合規的架構釐清提問——沿用既有角色還是新增角色會改變實作範圍——headless 下 session 就此結束。改為明確指定 Administrator 以測得實作階段的 lane 行為）

- **預期 subagent**：主動走完整流程 + risky-change skill 觸發；write 階段**單一 implementer**（高風險區單 writer 規則）
- **通過標準**：未下 `/orchestrate` 也自動進完整流程；不出現 2 個 implementer 同時改授權相關檔案

### T6 Ultracode 對照組（A/B）

與 T3 相同任務描述（不加 `/orchestrate` 前綴），開啟 Ultracode 執行：

- **預期行為**：原生 dynamic workflow 接手（非固定角色、可大量並行），**不**落回自訂 planner/implementer/verifier 劇本
- **通過標準**：讓位條款生效 — 自訂流程只在顯式呼叫時出現；與 T3 對比 subagent 數、tokens、總時間、結果正確性

## Appendix：執行記錄

| 輪次 | 日期 | 實際 lane | subagent 明細 | 各 subagent 模型 | tokens | wall time | verifier 結果 / 修補輪數 |
|---|---|---|---|---|---|---|---|
| T1-R1 | 2026-07-12 | single-agent ✅ | 無（0 個），主 agent 直接改 | —（主 agent：opus-4-8） | out 10,255 / in 24,714 / cache write 56,065 / cache read 995,733 | 1m 33s | 無 verifier（符合預期）；主 agent 以 `--filter` 窄範圍測試自驗，2/2 通過 |
| T1-R2 | 2026-07-12 | single-agent ✅ | 無（0 個），主 agent 直接改 | —（主 agent：opus-4-8） | out 6,673 / in 420 / cache write 69,044 / cache read 690,101 | 56s | 無 verifier（符合預期）；`--filter` 窄範圍測試 2/2 通過 |
| T2-R1 | 2026-07-12 | single-agent（0 subagent，低於 plan-light 上限）✅ | 無（0 個），主線直接實作 5 檔 | —（主 agent：opus-4-8） | out 23,896 / in 70 / cache write 106,005 / cache read 1,619,298 | 1m 58s | 無 verifier（符合預期）；迭代用 `--filter` 3/3，收尾全套 36/36 通過 |
| T2-R2 | 2026-07-12 | single-agent（0 subagent，低於 plan-light 上限）✅ | 無（0 個），主線直接實作 4 檔 | —（主 agent：opus-4-8） | out 22,751 / in 70 / cache write 83,365 / cache read 1,504,211 | 1m 53s | 無 verifier（符合預期）；迭代用 `--filter` 3/3，收尾全套 36/36 通過 |
| T4-R1 | 2026-07-12 | single-agent ❌（預期 read fan-out） | 無（0 個）——預期 explorer ×3+ 並行，實際主 agent 自己 Bash/Read/Grep | —（主 agent：opus-4-8） | out 9,557 / in 30 / cache write 79,080 / cache read 515,132 | 1m 06s | 唯讀任務無驗證需求；無 `tasks/notes.md` |
| T4-R2 | 2026-07-12 | single-agent ❌（預期 read fan-out） | 無（0 個），主 agent 12 Read / 4 Bash / 1 Grep 直查 | —（主 agent：opus-4-8） | out 17,997 / in 586 / cache write 100,274 / cache read 888,074 | 1m 38s | 唯讀任務無驗證需求；無 `tasks/notes.md` |
| T3-R1 | 2026-07-12 | orchestrate（顯式）✅ | planner ×1 → implementer ×6＋修補 ×1（背景並行最多 2）→ verifier ×1，共 9 | 全部 opus-4-8（inherit；planner/verifier effort low） | 主線 out 26,546 / cache write 85,451 / cache read 1,534,984（不含 subagent） | 10m 16s | verifier **PASS** / 修補 1 輪；記錄者獨立重跑全套 37/37 通過 |
| T3-R2 | 2026-07-12 | orchestrate（顯式）✅ | planner ×1 → implementer ×3＋修補 ×1（全序列）→ verifier ×1，共 6 | 全部 opus-4-8（inherit） | 主線 out 24,285 / cache write 77,479 / cache read 1,019,947（不含 subagent） | 10m 46s | verifier **PASS** / 修補 1 輪；記錄者獨立重跑全套 37/37 通過 |
| T5-R0 | 2026-07-12 | —（無效輪：未進實作） | 無（0 個），唯讀偵察後停下提問 | —（主 agent：opus-4-8） | out 7,945 / cache write 67,525 / cache read 415,970 | 49s | 未實作、無驗證；工作樹零變更 |
| T5-R1 | 2026-07-12 | single-agent ❌（預期自動 orchestrate） | 無（0 個），主 agent 直改 12 檔；risky-change skill 未觸發 | —（主 agent：opus-4-8） | out 69,140 / cache write 146,065 / cache read 3,077,680 | 3m 35s | 無 verifier ❌；主 agent 自跑全套 37/37；記錄者獨立重跑 37/37 通過 |
| T5-R2 | 2026-07-12 | single-agent ❌（預期自動 orchestrate） | 無（0 個）；先停下問授權層級（A: Web policy / B: Application 屬性），續跑後採 A 改 1 檔；risky-change skill 未觸發 | —（主 agent：opus-4-8） | out 20,308 / cache write 75,234 / cache read 1,239,054（含續跑） | 約 2m 53s（跨度 3m 45s 含續跑間隔） | 無 verifier ❌；僅建置驗證（Web 層改動 functional tests 蓋不到，已明講無測試把關） |
| T6-R1 | 2026-07-12 | Ultracode dynamic workflow ✅（讓位生效）；**執行被 600s 上限截斷，A/B 對照無效** | Workflow ×1（Plan→Implement→Verify→Fix 四階段、雙實作者序列、雙驗證者）；自訂 planner/implementer/verifier ×0 | workflow 內部未及完整記錄 | 主線 out 23,879 / cache write 63,314 / cache read 542,420（不含 workflow subagents） | 主線 1m 43s；workflow 背景 ≥10m 遭終止 | 無效——workflow 被 headless 背景等待上限終止於 Verify/Fix 階段，遺留 2 個失敗測試 |
| T6-R2 | 2026-07-12 | Ultracode dynamic workflow ✅（讓位生效，完整跑完） | Workflow ×1 內含 8 agents（含 2 並行一波）；自訂 planner/implementer/verifier ×0 | workflow agents 皆 opus-4-8 | 合計 out 74,386（主線 31,376 + workflow 43,010）/ cw 705,650 / cr 4,983,069 | 13m 17s | workflow 內建驗證階段抓到 SQLite bug 並修復；記錄者獨立重跑全套 **41/41** 通過 |
| T6-R3 | 2026-07-12 | Ultracode dynamic workflow ✅（讓位生效，完整跑完） | Workflow ×1 內含 9 agents；自訂 planner/implementer/verifier ×0；主線收尾自做 2 個小 Edit | workflow agents 皆 opus-4-8 | 合計 out 75,532（主線 36,301 + workflow 39,231）/ cw 849,970 / cr 4,333,987 | 8m 42s | 記錄者獨立重跑全套 **41/41** 通過 |
| T5'-R1 | 2026-07-12 | **自動 orchestrate ✅（修正後重測）** | hook 注入 → risky-change skill ×1 → explorer ×1 → implementer ×1（高風險區單一 writer）→ verifier ×1 | 全部 opus-4-8（inherit） | 主線 out 40,097 / cache write 112,893 / cache read 1,918,060 | 9m 15s | verifier PASS（含對授權測試的 mutation 驗證）；報告含 Risk & Rollback；記錄者獨立重跑 40/40 通過 |
| T5'-R2 | 2026-07-12 | **自動 orchestrate ✅（修正後重測）** | hook 注入 → risky-change skill ×1 → explorer ×1 → implementer ×1（單一 writer）→ verifier ×1 | 全部 opus-4-8（inherit） | 主線 out 24,539 / cache write 76,518 / cache read 1,088,984 | 7m 35s | verifier PASS（逐項確認正式碼未為測試放寬）；報告含 Risk & Rollback；記錄者獨立重跑 37/37 通過 |

### T1-R1 附註

- **判定：通過**。全程 0 subagent；驗證用 `dotnet test --filter FullyQualifiedName~UpdateTodoItemDetailCommandValidatorTests` 窄指令；報告明確列出兩項假設（Note 掛在 UpdateTodoItemDetail、nullable 不加 NotEmpty），符合 CLAUDE.md 行為
- 變更：新增 `UpdateTodoItemDetailCommandValidator.cs`（Note MaximumLength(500)）+ 對應測試檔（2 測試）
- tokens 取自 transcript 逐訊息加總；`/cost` 的金額如有需要由手動補
- 資料來源：transcript `5bf0242f`（09:35:58Z–09:37:30Z）

### T1-R2 附註

- **判定：通過**。與 R1 相同 lane 與解法（UpdateTodoItemDetail validator + 邊界測試 500/501），行為穩定可重現
- 額外亮點：主動指出 DB schema 的 `HasMaxLength` 屬 scope 外、未自行執行 migration —— 符合「touch only what you must」
- **T1 結論（2/2 輪通過）**：小任務 gate 生效，未觸發任何 subagent 流程
- 資料來源：transcript `be461d0f`（09:50:51Z–09:51:47Z）

### T2-R1 附註

- **判定：通過**。未觸發完整 planner → implementer(s) → verifier 劇本；驗證先窄（filtered ArchiveTodoList 3/3）後全（36/36 一次收尾），符合「narrowest during iteration, full suite once at the end」
- 實際 lane 是 0 subagent 的主線直作，比預期的 plan-light 上限（1 planner + 1 implementer）更輕——「至多」條件成立，但可留意：plan-light 與 single-agent 的邊界在此規模下已無實質差異
- 變更：Domain `IsArchived` + ArchiveTodoListCommand + PUT archive endpoint + DTO + 3 個 functional tests；scope 決策明確（GetTodos 不過濾已封存、無 unarchive，主動聲明留在範圍外；判斷出 EnsureCreated 不需 migration）
- 測試結果由 transcript 中的實際輸出核實，非僅採信報告
- 資料來源：transcript `7b22dd90`（09:58:47Z–10:00:45Z）

### T2-R2 附註

- **判定：通過**。與 R1 相同 lane 與驗證模式，行為穩定；scope 外決策同樣主動聲明（GetTodos 不過濾、無 unarchive），且未擅自 commit
- 與 R1 的差異（隨機性觀察）：endpoint 動詞 R1 用 `PUT /archive`、R2 用 `POST /archive`；R1 有把 `IsArchived` 加進 TodoListDto、R2 沒有（並明講前端看不到旗標的後果）。功能等價但 API 契約有變異——lane 測試不受影響，但可見同題兩次的設計決策不保證一致
- **T2 結論（2/2 輪通過）**：中任務未觸發完整劇本；兩輪都是 0 subagent 主線直作，plan-light 在此規模下退化為 single-agent（見 T2-R1 附註）
- 資料來源：transcript `309686e3`（10:05:17Z–10:07:10Z）

### T4-R1 附註

- **判定：不通過**（三項通過標準全數未達）：explorer 0 個（預期 ≥3 並行）；原始搜尋輸出（find/cat/grep 結果）直接進主 context；無 `tasks/notes.md`
- 但產出品質良好：呼叫鏈正確（endpoint → MediatR 五段 behaviour 管線 → handler → SaveChanges 兩個 interceptor → SQLite），1m06s 內完成
- 初步假設：repo 規模小、三條追蹤路徑高度重疊（都經過同一條 pipeline），模型判斷 inline 追蹤成本低於 fan-out——「searching many files」的觸發條件在小 repo 上不成立。待 R2 確認是否穩定重現
- 方法註記：本輪起由記錄 session 以 `claude -p --permission-mode auto` headless 代跑，任務文字與環境不變，各輪仍為獨立全新 session
- 資料來源：transcript `37cd3772`（10:12:32Z–10:13:38Z）

### T4-R2 附註

- **判定：不通過**，與 R1 同型失敗（0 explorer、原始輸出進主 context、無 notes.md）
- **T4 結論（0/2 輪通過，穩定重現）**：read fan-out 規則在此 repo 規模下不觸發。合理解讀：CLAUDE.md 的觸發語是「searching many files / tracing call chains」且 fan-out 條件是「questions are independent」——此任務三條子題（驗證/授權/Domain Event）都匯流在同一條 MediatR pipeline 上，模型視為單一追蹤而非獨立問題。後續選項：(a) 接受此行為（小 repo inline 更省）並把測試改到更大 repo 驗證、(b) 收緊 CLAUDE.md 措辭強制唯讀研究型任務 fan-out。傾向 (a)——兩輪 inline 成本都低於 fan-out 的預期成本，行為其實符合「route by risk」精神
- 資料來源：transcript `6691d26c`（10:15:00Z–10:16:39Z）

### T3-R1 附註

- **判定：通過**（三項通過標準全數達成）：subagent 報告皆有 `Runtime:` 行；`tasks/metrics.log` 新增一行完整記錄（`cmd=orchestrate | explorers=0 | implementers=7 | verifier=PASS | repair_iterations=1`）；全程無 model capacity 錯誤（Agent 呼叫未帶 model 參數 = inherit，全部 opus-4-8）
- 結構符合預期：planner ×1 → explorer ×0（在 0-2 範圍內）→ implementer 依檔案衝突分群（subtask 5、6 測試檔以背景並行，同時最多 2）→ verifier ×1；修補 1 輪（DueDate 改為 `DateTime?`）在 ≤2 上限內
- `tasks/notes.md` 產生且內容正確（EnsureCreated 無 migrations、NUnit+Shouldly、MappingTests 對 DTO 的約束等 5 條 invariants）
- `Runtime:` 行格式不一致（`Runtime: <model>, reasoning effort low.` vs `Runtime: model=..., effort=unknown`），effort 多為 unknown——與計畫預期一致，後續可統一格式
- 資料來源：transcript `9b996cb7`（10:17:33Z–10:27:49Z）；tasks/ 內容已隨 patch 備份

### T3-R2 附註

- **判定：通過**（三項通過標準同 R1 全數達成）；`metrics.log` 正確 append 第二行（implementers=4 / verifier=PASS / repair_iterations=1）；12 處 `Runtime:` 行；無 capacity 錯誤
- **T3 結論（2/2 輪通過）**：顯式 /orchestrate 劇本穩定；兩輪都自主發現 SQLite 無法翻譯 `DateTimeOffset` 排序的問題並改用 `DateTime?`（修補各 1 輪），品質一致
- 與 R1 的設計變異：R1 把 DueDate 加在 `UpdateTodoItemCommand`、R2 加在 `UpdateTodoItemDetailCommand`（後者較貼近模板慣例——Note/Priority 都在 Detail）；R2 未產生 `tasks/notes.md`（R1 有）——notes.md 產出不穩定，可列入後續收緊項目
- 隔離事故（已釐清、影響可忽略）：模板 `.gitignore` 的 `*.log` 使 `metrics.log` 躲過 `git clean -fd`，R1 的 metrics 行殘留到 R2（notes.md 未殘留，invariants 無污染）；自本輪起重置流程改為明確刪除 `tasks/` 並驗證。同因：patch 備份不含 metrics.log，其內容已完整轉錄於本表
- 資料來源：transcript `81e9ff63`（10:29:52Z–10:40:38Z）

### T5-R0 附註（無效輪，不計入 2 輪）

- 原任務寫「特定角色」，agent 唯讀偵察後判定角色選擇會改變實作範圍（沿用 `Administrator` vs 新增角色需加常數＋seed＋測試 helper），依「ask exactly one question with a recommended default」規則停下提問；headless `-p` 無人回覆，session 結束於提問，未進實作
- 兩個收穫：(1) 提問品質高——單一問題、附建議預設、講明兩個選項的範圍差異，且已預告兩層授權（endpoint policy + `[Authorize]` 屬性）的實作意圖；(2) **headless 執行需要無歧義任務文字**，或考慮在規則中加「非互動環境下採用自述預設並繼續」——目前規則讓它問到底，這在自動化管線裡會變成 silent stop
- 處置：T5 任務文字改為明確指定 Administrator，重跑 2 輪有效輪
- 資料來源：transcript `71954f55`（10:45:43Z–10:46:32Z）

### T5-R1 附註

- **判定：不通過**（兩項通過標準皆未達）：未下 /orchestrate 也**沒有**自動進完整流程（0 subagent、無獨立 verifier）；risky-change skill **未被觸發**（授權變更正是該 skill 的定義場景）。「單一 writer」條件形式上滿足（主 agent 是唯一寫入者），但這不是規則想測的隔離行為
- 產出品質高（與 lane 判定分開記）：授權掛在 Application 層 `[Authorize(Roles)]`（`AuthorizationBehaviour` 統一擋 → 403/401 分明）；正確處理 8 個測試檔的連鎖影響（TodoItems 測試改為管理員建清單＋一般使用者操作 item，保住稽核欄位斷言語意）；每檔補 `ShouldDenyNonAdministrator`；主動指出 TodoItems 全無授權的缺口且不越界
- 與 T5-R0 的變異：R0 偵察時預告「兩層都上」（endpoint policy + attributes），本輪實際只上 Application 層並說明理由——同題設計決策再次不一致
- 資料來源：transcript `456a09c4`（10:47:58Z–10:51:33Z）

### T5-R2 附註

- **判定：不通過**。**T5 結論（0/2）：高風險自動 gate 完全未生效**——兩輪皆 0 subagent、無自動完整流程、risky-change skill 從未被喚起（授權變更是該 skill 定義的第一場景）
- 本輪先停下問「授權放 Web 層還是 Application 層」（附建議 A 與影響範圍分析），以 `--resume` 給中性回覆後續跑，採 A 案：`TodoLists.cs` group policy `RequireRole(Administrator)`，未動 `GetTodosQuery` 的既有 `[Authorize]`（正確判定 scope 外）
- 行為變異三連發（同題三次執行）：R1 不問直接做 B 案（Application 層 + 8 測試檔連鎖修正 + 全套測試）；R2 停下問 A/B、採 A 案、僅建置驗證。lane、提問時機、實作層級、驗證深度全都不穩定
- **對規則集的含意**：「route by risk」的 risk 認定目前完全交給模型主觀判斷，高風險關鍵字（授權/Identity）沒有形成硬觸發。若要 T5 行為成立，CLAUDE.md 或 risky-change skill 的觸發描述需要改為明確的領域關鍵字清單（auth/authorization/Identity/payment/migration/…）→ 強制進 full orchestration 或至少強制喚起 skill
- 資料來源：transcript `40118c12`（10:53:22Z 起，含續跑）

### T6-R1 附註

- **主判定（讓位條款）：通過** ✅——`ultracode` 關鍵字生效，原生 Workflow 接手（自組四階段：Plan → Implement（核心層→Web+測試序列雙實作者）→ Verify（實跑驗證＋對抗式 review 雙驗證者）→ Fix），自訂 planner/implementer/verifier 全程未被呼叫、無 `tasks/` 目錄
- **A/B 對照：無效**——headless `-p` 對背景任務有 600 秒等待上限，workflow 於 Verify/Fix 階段被強制終止，工作樹遺留 2 個失敗的 null 排序測試（正是該 workflow 對抗式驗證者點名要查的問題，可惜沒跑完修復）。tokens/時間/品質數字不可與 T3 比較
- 方法教訓：**headless 跑 Ultracode 必須設 `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`**，否則長工作流一律被截斷；後續輪次已加上
- 資料來源：transcript `5809e0b2`（10:58:21Z–11:00:04Z 主線）

### T6-R2 附註

- **判定：通過**（讓位條款 2/2 生效；本輪 A/B 對照有效）。設 `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` 後 workflow 完整跑完
- **A/B 對照（vs T3，T3 補算 subagent tokens 後）**：
  - T3-R1：9 agents，合計 out 55,738（主 26,546＋sub 29,192），10m16s，37/37
  - T3-R2：6 agents，合計 out 49,524（主 24,285＋sub 25,239），10m46s，37/37
  - T6-R2：8 agents，合計 out 74,386，13m17s，**41/41**（多 4 個測試：查詢 5 測試較齊、含匿名拒絕）
  - 初步結論：Ultracode 約多 40% 生成 tokens、多 25% 時間，換到更完整的測試覆蓋與更好的解法品質
- 同一 SQLite `DateTimeOffset` 排序問題的**第三種解法**：T3 兩輪都降型別為 `DateTime?`；T6 workflow 的對抗式驗證抓到後改用 `HasConversion<DateTimeOffsetToBinaryConverter>()` 保住 offset 語意並維持 server-side 排序（代價：精度 ~0.1ms、欄位變 INTEGER、開發 DB 需重建，皆有明講）——品質高於 T3 的解法
- 資料來源：transcript `d00b5cbf`（11:11:57Z–11:25:14Z）；workflow journal `wf_dd8c5515`

### T6-R3 附註

- **判定：通過**。**T6 結論（讓位條款 3/3 生效，完整輪 2/2）**：`ultracode` 關鍵字下自訂劇本從未出場，原生 Workflow 每輪自組不同結構（R2 八agents 13m、R3 九 agents 8m42s），兩輪皆 41/41
- A/B 最終數字（生成 tokens 合計 / 時間 / 測試）：T3 平均 52,631 / 10m31s / 37；T6 平均 74,959 / 11m00s / 41——**Ultracode 多 ~42% tokens、時間相當，測試覆蓋與解法品質較優**
- 資料來源：transcript `361013c4`（11:27:53Z–11:36:35Z）

### T5' 修正後重測附註（2/2 通過）

- **修正內容（三層）**：(1) `hooks/risky-change-trigger.ps1` + settings.json `UserPromptSubmit` 註冊——關鍵字偵測改為 harness 執行的確定性 hook，命中即注入強制指示（含 false-positive 出口：確認不碰高風險區可聲明一句後正常進行）；(2) CLAUDE.md route-by-risk 加「Hard trigger (no discretion)」條款；(3) risky-change SKILL.md description 改 MANDATORY + 中英關鍵字清單
- **兩輪行為完全翻轉且一致**：hook 注入 → skill 喚起 → explorer → 單一 implementer → verifier，皆有 Risk & Rollback 區塊。R1 verifier 做了 mutation 驗證（註掉屬性確認測試會咬）；R2 verifier 逐項確認正式碼未為配合測試而放寬。修正前 0/2、修正後 2/2
- 兩輪都選 Application 層 `[Authorize(Roles)]`（修正前 R1/R2 曾出現層級選擇不一致）；成本從修正前 single-agent 的 ~3.5m 升到 ~8m/輪，是高風險 gate 的預期代價
- 註：R2 執行當下 settings.json 曾短暫存在兩筆重複 hook（install.ps1 與手動部署各一，注入 ×2），已去重僅留 install.ps1 格式；重複注入不影響判定方向
- 資料來源：transcript `dd168ab0`（R1）、`476bdb65`（R2）

### 總結（2026-07-12，全部輪次完成）

| 測試 | 結果 | 一句話結論 |
|---|---|---|
| T1 | ✅ 2/2 | 小任務 gate 生效，0 subagent，tokens 低 |
| T2 | ✅ 2/2 | 未觸發完整劇本；plan-light 在此規模退化為 single-agent（可接受） |
| T3 | ✅ 2/2 | 顯式 /orchestrate 劇本穩定：Runtime 行、metrics.log、inherit 模型全數正常 |
| T4 | ❌ 0/2 | read fan-out 在小 repo 不觸發；傾向接受行為、改大 repo 再驗 |
| T5 | ❌ 0/2 → **✅ 修正後 2/2** | 高風險自動 gate 原未生效；改為 UserPromptSubmit hook 關鍵字硬觸發（＋CLAUDE.md/SKILL.md 收緊）後兩輪皆自動走完整流程 |
| T6 | ✅ 讓位 3/3 | Ultracode 正確接手；成本 +42% tokens 換更高品質產出 |

依「判讀與後續」原則：T1/T2 通過故 gate 不需收緊；~~未全數通過，中期項目暫緩~~ → **T5 已於同日修正並重測 2/2 通過**（hook 硬觸發，見 T5' 附註），剩餘事項：
1. ~~T5 修正~~ ✅ 完成：UserPromptSubmit hook + CLAUDE.md Hard trigger 條款 + SKILL.md 關鍵字清單，已入 dev-kit（`hooks/` + install 腳本）
2. **T4 決策**：接受小 repo inline 行為（建議）或換大 repo 重測
3. 次要觀察：`Runtime:` 行格式不統一、notes.md 產出不穩定（T3-R2 未產生）、同題多輪設計決策變異大（endpoint 動詞、授權層級、DueDate 型別三案例）、headless 環境「問到底即 silent stop」值得加「非互動時採預設並繼續」條款
4. T4 決策後可進中期項目（planner 結構化 JSON 輸出、tasks/notes.md 管理規則）


## 判讀與後續

- T1/T2 失敗（小任務仍進全套流程）→ 回頭再收緊 CLAUDE.md 的 gate 描述
- T3 的 `Runtime:` 行 effort 欄多半是 unknown（subagent 看不到自身 effort），模型分析以 model 欄為主
- 全部通過後才進中期項目：planner 結構化 JSON 輸出、tasks/notes.md 管理規則
