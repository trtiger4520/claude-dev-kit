# 委派規則測試計畫

驗證 2026-07 調整後的行為：風險導向 gate、Ultracode 讓位、model inherit、read-many/write-few、Runtime 回報與 metrics.log

## 測試環境

**目標專案**：[jasontaylordev/CleanArchitecture](https://github.com/jasontaylordev/CleanArchitecture)（.NET 10 SDK 10.0.201、C#、多專案分層 + 完整測試，規模適中）

不直接 clone 模板 repo，而是用模板產生乾淨的測試方案（SQLite 免 Docker、無前端框架）：

```powershell
dotnet new install Clean.Architecture.Solution.Template
dotnet new ca-sln --client-framework none --database sqlite --output OrchTest
cd OrchTest
dotnet build   # 先確認基線可建置
```

注意：FunctionalTests / IntegrationTests 可能需要額外基礎設施，驗證以 Domain/Application 的 UnitTests 為主

## 每輪執行後記錄（appendix 表格）

| 欄位 | 來源 |
|---|---|
| task id / 日期 | 手動 |
| 實際 lane（single-agent / plan-light / orchestrate） | 觀察 |
| subagent 明細（角色 × 數量、是否並行） | 觀察 |
| 各 subagent 模型 | 報告結尾 `Runtime:` 行 |
| tokens | `/cost` |
| wall time | 手動 |
| verifier 結果 / 修補輪數 | 報告或 `tasks/metrics.log` |

每個測試至少跑 2 次（模型行為有隨機性，單次不足以下結論）

## 測試任務

### T1 小任務 → 預期 lane: single-agent

> 為 TodoItem 的 Title 加上 200 字元長度上限驗證，並補一個對應的單元測試

- **預期 subagent**：無（0 個）— 主 agent 直接改 validator + 測試
- **通過標準**：全程沒有啟動任何 subagent；tokens 明顯低於舊行為（舊規則會因 2-3 檔觸發全套流程）

### T2 中任務低風險 → 預期 lane: plan-light

> 為 TodoList 加上封存（Archive）功能：新增 command、endpoint 與測試

- **預期 subagent**：至多 1 個 planner（或主線內短計畫），至多 1 個 implementer；**不出現** verifier 全套流程
- **通過標準**：沒有觸發完整 planner → implementer(s) → verifier 劇本；驗證用窄範圍指令（filtered tests）

### T3 顯式完整流程 → `/orchestrate`

> /orchestrate 為 TodoItem 加上 Priority 欄位與排序功能，需更新 Domain、Application（command/query）、Web endpoint 與對應測試

- **預期 subagent**：planner ×1 → explorer ×0-2 → implementer ≤2 並行（依檔案衝突分群）→ verifier ×1
- **通過標準**：每個 subagent 報告結尾有 `Runtime:` 行；結束後 `tasks/metrics.log` 新增一行完整記錄；無 model capacity 錯誤（explorer/implementer 已改 inherit）

### T4 探索型 → 預期 read fan-out

> 追蹤 CreateTodoItem 從 HTTP endpoint 到資料庫寫入的完整流程，整理驗證、授權、Domain Event 的處理位置與慣例

- **預期 subagent**：explorer ×3 以上**並行**（endpoint 路徑 / 行為管線 / Domain Event 各一）
- **通過標準**：explorer 一次並行啟動而非逐一序列；主 context 沒有出現原始搜尋輸出；invariants 被記錄到 `tasks/notes.md`

### T5 高風險自動觸發 → 預期 lane: orchestrate（不需顯式呼叫）

> 調整 Identity 授權設定：把 TodoLists 相關 endpoint 全部改為需要特定角色

- **預期 subagent**：主動走完整流程 + risky-change skill 觸發；write 階段**單一 implementer**（高風險區單 writer 規則）
- **通過標準**：未下 `/orchestrate` 也自動進完整流程；不出現 2 個 implementer 同時改授權相關檔案

### T6 Ultracode 對照組（A/B）

與 T3 相同任務描述（不加 `/orchestrate` 前綴），開啟 Ultracode 執行：

- **預期行為**：原生 dynamic workflow 接手（非固定角色、可大量並行），**不**落回自訂 planner/implementer/verifier 劇本
- **通過標準**：讓位條款生效 — 自訂流程只在顯式呼叫時出現；與 T3 對比 subagent 數、tokens、總時間、結果正確性

## 判讀與後續

- T1/T2 失敗（小任務仍進全套流程）→ 回頭再收緊 CLAUDE.md 的 gate 描述
- T3 的 `Runtime:` 行 effort 欄多半是 unknown（subagent 看不到自身 effort），模型分析以 model 欄為主
- 全部通過後才進中期項目：planner 結構化 JSON 輸出、tasks/notes.md 管理規則
