# Claude Dev Kit 任務成本基準報告

- Benchmark ID：`e266d10bf5624db1a58dd33492f0f0e9`
- Claude CLI：`2.1.214 (Claude Code)`
- Policy fingerprint：`9198d82339e2709189adce61a0eca559b16c8a98641a964600c81940d0430edf`
- Installed policy fingerprint：`cacc8229d98754de8ebf1c7abde15974a63bf658e4fdb9e1c308a8a8715910af`
- Benchmark input fingerprint：`ee617ac3cdb7a42ed205ffe680bf0d7029a9486b7467dc3fb1439d2f6236387f`
- Quality contract：`2.0`
- 樣本：27 / 27
- 完成樣本成本：$5.6771 USD
- 保留的重試 attempt：0 筆，$0.0000 USD
- Benchmark 作業總成本：$5.6771 USD
- 金額為 Claude CLI 回報的 API 等價估算，不代表訂閱方案實際帳單

![各任務累積成本曲線](task-cost-curves.svg)

## 執行策略比較

| 任務 | 策略 | 輪數 | 平均 USD | Median | 範圍 | 平均秒數 | 平均 Token | 策略驗收 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| known-dto-change | current-policy | 3 | 0.1411 | 0.1413 | 0.1405–0.1415 | 31.8 | 192535 | 3/3 |
| known-dto-change | forced-heavy | 3 | 0.7666 | 0.6131 | 0.3925–1.2940 | 173.1 | 329206 | 1/3 |
| login-flow-analysis | current-policy | 3 | 0.2369 | 0.2348 | 0.2236–0.2521 | 62.9 | 42275 | 3/3 |
| login-flow-analysis | forced-single | 3 | 0.3246 | 0.2849 | 0.2671–0.4218 | 54.3 | 297681 | 3/3 |
| authentication-policy-change | current-policy | 3 | 0.1906 | 0.1911 | 0.1882–0.1925 | 49.1 | 165165 | 0/3 |
| authentication-policy-change | forced-single | 3 | 0.1402 | 0.1337 | 0.1332–0.1537 | 38.3 | 189879 | 3/3 |

策略驗收同時包含共通交付檢查與該策略承諾的工作流程條件，用於判斷策略是否完整落實，不等同純產品品質分數

## 現行策略相對差異

| 任務 | 反事實策略 | 成本差異 | 時間差異 | 策略驗收差異 |
|---|---|---:|---:|---:|
| known-dto-change | forced-heavy | -81.6% | -81.6% | 66.7 pp |
| login-flow-analysis | forced-single | -27.0% | 16.0% | 0.0 pp |
| authentication-policy-change | forced-single | 35.9% | 28.3% | -100.0 pp |

## Lane 分類成本

| 任務 | 輪次 | Lane | 子代理建議 | USD | 秒數 | 狀態 |
|---|---:|---|---|---:|---:|---|
| known-dto-change | 1 | single-agent |  | 0.0286 | 5.0 | pass |
| login-flow-analysis | 1 | plan-light | explorer:1 | 0.0356 | 9.2 | pass |
| authentication-policy-change | 1 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0323 | 7.9 | pass |
| login-flow-analysis | 2 | plan-light | explorer:1 | 0.0291 | 6.3 | pass |
| authentication-policy-change | 2 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0306 | 6.9 | pass |
| known-dto-change | 2 | single-agent |  | 0.0317 | 8.1 | pass |
| authentication-policy-change | 3 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0314 | 5.8 | pass |
| known-dto-change | 3 | single-agent |  | 0.0290 | 6.9 | pass |
| login-flow-analysis | 3 | plan-light | explorer:1 | 0.0291 | 6.7 | pass |

## 每輪明細

| 順序 | 任務 | 類型 | 策略 | R | Lane | Agents | USD | 秒數 | 驗收 | 狀態 |
|---:|---|---|---|---:|---|---:|---:|---:|---:|---|
| 1 | known-dto-change | classification | classification | 1 | single-agent | 0 | 0.0286 | 5.0 | 1/1 | pass |
| 2 | known-dto-change | execution | current-policy | 1 | single-agent | 0 | 0.1405 | 33.2 | 3/3 | pass |
| 3 | known-dto-change | execution | forced-heavy | 1 | orchestrate-heavy | 1 | 0.3925 | 90.9 | 6/8 | quality-fail |
| 4 | login-flow-analysis | classification | classification | 1 | plan-light | 1 | 0.0356 | 9.2 | 1/1 | pass |
| 5 | login-flow-analysis | execution | current-policy | 1 | plan-light | 1 | 0.2348 | 78.5 | 12/12 | pass |
| 6 | login-flow-analysis | execution | forced-single | 1 | single-agent | 0 | 0.4218 | 62.0 | 11/11 | pass |
| 7 | authentication-policy-change | classification | classification | 1 | orchestrate-heavy | 3 | 0.0323 | 7.9 | 1/1 | pass |
| 8 | authentication-policy-change | execution | current-policy | 1 | single-agent | 0 | 0.1911 | 51.6 | 5/10 | quality-fail |
| 9 | authentication-policy-change | execution | forced-single | 1 | single-agent | 0 | 0.1537 | 48.3 | 3/3 | pass |
| 10 | login-flow-analysis | classification | classification | 2 | plan-light | 1 | 0.0291 | 6.3 | 1/1 | pass |
| 11 | login-flow-analysis | execution | forced-single | 2 | single-agent | 0 | 0.2671 | 33.7 | 11/11 | pass |
| 12 | login-flow-analysis | execution | current-policy | 2 | plan-light | 1 | 0.2521 | 60.5 | 12/12 | pass |
| 13 | authentication-policy-change | classification | classification | 2 | orchestrate-heavy | 3 | 0.0306 | 6.9 | 1/1 | pass |
| 14 | authentication-policy-change | execution | forced-single | 2 | single-agent | 0 | 0.1337 | 32.0 | 3/3 | pass |
| 15 | authentication-policy-change | execution | current-policy | 2 | single-agent | 0 | 0.1882 | 44.8 | 5/10 | quality-fail |
| 16 | known-dto-change | classification | classification | 2 | single-agent | 0 | 0.0317 | 8.1 | 1/1 | pass |
| 17 | known-dto-change | execution | forced-heavy | 2 | orchestrate-heavy | 2 | 0.6131 | 144.0 | 6/8 | quality-fail |
| 18 | known-dto-change | execution | current-policy | 2 | single-agent | 0 | 0.1413 | 33.1 | 3/3 | pass |
| 19 | authentication-policy-change | classification | classification | 3 | orchestrate-heavy | 3 | 0.0314 | 5.8 | 1/1 | pass |
| 20 | authentication-policy-change | execution | current-policy | 3 | single-agent | 0 | 0.1925 | 50.9 | 5/10 | quality-fail |
| 21 | authentication-policy-change | execution | forced-single | 3 | single-agent | 0 | 0.1332 | 34.5 | 3/3 | pass |
| 22 | known-dto-change | classification | classification | 3 | single-agent | 0 | 0.0290 | 6.9 | 1/1 | pass |
| 23 | known-dto-change | execution | current-policy | 3 | single-agent | 0 | 0.1415 | 29.0 | 3/3 | pass |
| 24 | known-dto-change | execution | forced-heavy | 3 | orchestrate-heavy | 3 | 1.2940 | 284.3 | 8/8 | pass |
| 25 | login-flow-analysis | classification | classification | 3 | plan-light | 1 | 0.0291 | 6.7 | 1/1 | pass |
| 26 | login-flow-analysis | execution | current-policy | 3 | plan-light | 1 | 0.2236 | 49.7 | 12/12 | pass |
| 27 | login-flow-analysis | execution | forced-single | 3 | single-agent | 0 | 0.2849 | 67.1 | 11/11 | pass |

## 判讀方式

- 小修改比較保守策略避免不必要完整 orchestration 的成本
- 探索任務比較 context 隔離增加的成本與呼叫鏈完整度
- 高風險任務比較單一 writer、核准與 verifier 所形成的安全溢價
- 結論只依確定性驗收與實際量測，不另外呼叫模型產生主觀品質分數

## 限制

- 合成 fixture 與每組三輪只能建立可重現的內部基準，不代表所有真實專案
- Prompt cache、模型版本、CLI 版本與服務狀態會影響 Token、時間及成本
- `total_cost_usd` 是 CLI 估算；訂閱使用者應以方案使用量或 Console 為準
- 重試前的失敗 attempt 保留在 CSV 並計入作業總成本，但不納入策略均值與曲線
- `TESTING.md` 的舊版數據使用不同模型與策略，只能作歷史背景，不納入本報告統計
