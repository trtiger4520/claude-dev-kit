# Claude Dev Kit 任務成本基準報告

- Benchmark ID：`773d89bfb2304667935f78454d88478a`
- Claude CLI：`2.1.289 (Claude Code)`
- Policy fingerprint：`1b81e1da1b1ebda473e945688226bf6afd86a46ac191da471bcaa951fb5079aa`
- Installed policy fingerprint：`10e257235ad14ffd7a9c0b3ea5c8d2b625506dbd69f5428dabd6263d0d5ae2d2`
- Benchmark input fingerprint：`ee617ac3cdb7a42ed205ffe680bf0d7029a9486b7467dc3fb1439d2f6236387f`
- Quality contract：`2.1`
- 樣本：27 / 27
- 完成樣本成本：$4.5251 USD
- 保留的重試 attempt：0 筆，$0.0000 USD
- Benchmark 作業總成本：$4.5251 USD
- 金額為 Claude CLI 回報的 API 等價估算，不代表訂閱方案實際帳單

![各任務累積成本曲線](task-cost-curves.svg)

## 執行策略比較

| 任務 | 策略 | 輪數 | 平均 USD | Median | 範圍 | 平均秒數 | 平均 Token | 策略驗收 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| known-dto-change | current-policy | 3 | 0.1381 | 0.1377 | 0.1365–0.1401 | 17.2 | 186950 | 3/3 |
| known-dto-change | forced-heavy | 3 | 0.4007 | 0.4059 | 0.3667–0.4296 | 67.2 | 291547 | 0/3 |
| login-flow-analysis | current-policy | 3 | 0.1549 | 0.1595 | 0.1277–0.1777 | 25.9 | 110870 | 3/3 |
| login-flow-analysis | forced-single | 3 | 0.1509 | 0.1432 | 0.1416–0.1678 | 20.0 | 181459 | 2/3 |
| authentication-policy-change | current-policy | 3 | 0.4181 | 0.4159 | 0.4019–0.4364 | 86.8 | 49285 | 3/3 |
| authentication-policy-change | forced-single | 3 | 0.1179 | 0.1177 | 0.1164–0.1197 | 16.6 | 103671 | 3/3 |

策略驗收同時包含共通交付檢查與該策略承諾的工作流程條件，用於判斷策略是否完整落實，不等同純產品品質分數

## 現行策略相對差異

| 任務 | 反事實策略 | 成本差異 | 時間差異 | 策略驗收差異 |
|---|---|---:|---:|---:|
| known-dto-change | forced-heavy | -65.5% | -74.4% | 100.0 pp |
| login-flow-analysis | forced-single | 2.7% | 29.6% | 33.3 pp |
| authentication-policy-change | forced-single | 254.5% | 422.2% | 0.0 pp |

## Lane 分類成本

| 任務 | 輪次 | Lane | 子代理建議 | USD | 秒數 | 狀態 |
|---|---:|---|---|---:|---:|---|
| known-dto-change | 1 | single-agent |  | 0.0423 | 10.4 | pass |
| login-flow-analysis | 1 | plan-light | explorer:1 | 0.0421 | 8.5 | pass |
| authentication-policy-change | 1 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0434 | 10.0 | pass |
| login-flow-analysis | 2 | plan-light | explorer:1 | 0.0424 | 9.6 | pass |
| authentication-policy-change | 2 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0434 | 6.5 | pass |
| known-dto-change | 2 | single-agent |  | 0.0415 | 11.8 | pass |
| authentication-policy-change | 3 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0435 | 9.4 | pass |
| known-dto-change | 3 | single-agent |  | 0.0421 | 6.8 | pass |
| login-flow-analysis | 3 | plan-light | explorer:1 | 0.0422 | 6.6 | pass |

## 每輪明細

| 順序 | 任務 | 類型 | 策略 | R | Lane | Agents | USD | 秒數 | 驗收 | 狀態 |
|---:|---|---|---|---:|---|---:|---:|---:|---:|---|
| 1 | known-dto-change | classification | classification | 1 | single-agent | 0 | 0.0423 | 10.4 | 1/1 | pass |
| 2 | known-dto-change | execution | current-policy | 1 | single-agent | 0 | 0.1365 | 17.4 | 3/3 | pass |
| 3 | known-dto-change | execution | forced-heavy | 1 | orchestrate-heavy | 2 | 0.4059 | 74.6 | 7/8 | quality-fail |
| 4 | login-flow-analysis | classification | classification | 1 | plan-light | 1 | 0.0421 | 8.5 | 1/1 | pass |
| 5 | login-flow-analysis | execution | current-policy | 1 | single-agent | 0 | 0.1595 | 26.1 | 12/12 | pass |
| 6 | login-flow-analysis | execution | forced-single | 1 | single-agent | 0 | 0.1416 | 17.0 | 11/11 | pass |
| 7 | authentication-policy-change | classification | classification | 1 | orchestrate-heavy | 3 | 0.0434 | 10.0 | 1/1 | pass |
| 8 | authentication-policy-change | execution | current-policy | 1 | orchestrate-heavy | 3 | 0.4364 | 94.1 | 10/10 | pass |
| 9 | authentication-policy-change | execution | forced-single | 1 | single-agent | 0 | 0.1177 | 14.5 | 3/3 | pass |
| 10 | login-flow-analysis | classification | classification | 2 | plan-light | 1 | 0.0424 | 9.6 | 1/1 | pass |
| 11 | login-flow-analysis | execution | forced-single | 2 | single-agent | 0 | 0.1432 | 17.5 | 6/11 | quality-fail |
| 12 | login-flow-analysis | execution | current-policy | 2 | plan-light | 1 | 0.1777 | 37.9 | 12/12 | pass |
| 13 | authentication-policy-change | classification | classification | 2 | orchestrate-heavy | 3 | 0.0434 | 6.5 | 1/1 | pass |
| 14 | authentication-policy-change | execution | forced-single | 2 | single-agent | 0 | 0.1164 | 18.5 | 3/3 | pass |
| 15 | authentication-policy-change | execution | current-policy | 2 | orchestrate-heavy | 3 | 0.4159 | 88.1 | 10/10 | pass |
| 16 | known-dto-change | classification | classification | 2 | single-agent | 0 | 0.0415 | 11.8 | 1/1 | pass |
| 17 | known-dto-change | execution | forced-heavy | 2 | orchestrate-heavy | 2 | 0.3667 | 61.3 | 7/8 | quality-fail |
| 18 | known-dto-change | execution | current-policy | 2 | single-agent | 0 | 0.1377 | 19.6 | 3/3 | pass |
| 19 | authentication-policy-change | classification | classification | 3 | orchestrate-heavy | 3 | 0.0435 | 9.4 | 1/1 | pass |
| 20 | authentication-policy-change | execution | current-policy | 3 | orchestrate-heavy | 3 | 0.4019 | 78.1 | 10/10 | pass |
| 21 | authentication-policy-change | execution | forced-single | 3 | single-agent | 0 | 0.1197 | 16.9 | 3/3 | pass |
| 22 | known-dto-change | classification | classification | 3 | single-agent | 0 | 0.0421 | 6.8 | 1/1 | pass |
| 23 | known-dto-change | execution | current-policy | 3 | single-agent | 0 | 0.1401 | 14.6 | 3/3 | pass |
| 24 | known-dto-change | execution | forced-heavy | 3 | orchestrate-heavy | 2 | 0.4296 | 65.8 | 7/8 | quality-fail |
| 25 | login-flow-analysis | classification | classification | 3 | plan-light | 1 | 0.0422 | 6.6 | 1/1 | pass |
| 26 | login-flow-analysis | execution | current-policy | 3 | single-agent | 0 | 0.1277 | 13.8 | 12/12 | pass |
| 27 | login-flow-analysis | execution | forced-single | 3 | single-agent | 0 | 0.1678 | 25.6 | 11/11 | pass |

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
