# Claude Dev Kit 任務成本基準報告

- Benchmark ID：`d42e9ed0f3f149518b3fd011b34b993c`
- Claude CLI：`2.1.289 (Claude Code)`
- Policy fingerprint：`2cb0c69fe91888b141586ddca5335e47e256387f547f23b155dd8a474d95e4a5`
- Installed policy fingerprint：`1976c8393dce13b0185369de77ef0699cb6f76645f6fdb5cb2163876d6004fef`
- Benchmark input fingerprint：`ee617ac3cdb7a42ed205ffe680bf0d7029a9486b7467dc3fb1439d2f6236387f`
- Quality contract：`2.1`
- 樣本：27 / 27
- 完成樣本成本：$4.4159 USD
- 保留的重試 attempt：0 筆，$0.0000 USD
- Benchmark 作業總成本：$4.4159 USD
- 金額為 Claude CLI 回報的 API 等價估算，不代表訂閱方案實際帳單

![各任務累積成本曲線](task-cost-curves.svg)

## 執行策略比較

| 任務 | 策略 | 輪數 | 平均 USD | Median | 範圍 | 平均秒數 | 平均 Token | 策略驗收 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| known-dto-change | current-policy | 3 | 0.1664 | 0.1504 | 0.1370–0.2119 | 19.8 | 214092 | 3/3 |
| known-dto-change | forced-heavy | 3 | 0.4493 | 0.4510 | 0.4327–0.4642 | 78.8 | 374280 | 0/3 |
| login-flow-analysis | current-policy | 3 | 0.1563 | 0.1616 | 0.1437–0.1636 | 22.7 | 176584 | 2/3 |
| login-flow-analysis | forced-single | 3 | 0.1599 | 0.1427 | 0.1342–0.2027 | 18.4 | 166913 | 3/3 |
| authentication-policy-change | current-policy | 3 | 0.1780 | 0.1779 | 0.1716–0.1846 | 36.3 | 205855 | 0/3 |
| authentication-policy-change | forced-single | 3 | 0.1180 | 0.1185 | 0.1150–0.1207 | 17.2 | 104591 | 3/3 |

策略驗收同時包含共通交付檢查與該策略承諾的工作流程條件，用於判斷策略是否完整落實，不等同純產品品質分數

## 現行策略相對差異

| 任務 | 反事實策略 | 成本差異 | 時間差異 | 策略驗收差異 |
|---|---|---:|---:|---:|
| known-dto-change | forced-heavy | -63.0% | -74.9% | 100.0 pp |
| login-flow-analysis | forced-single | -2.2% | 23.7% | -33.3 pp |
| authentication-policy-change | forced-single | 50.8% | 111.7% | -100.0 pp |

## Lane 分類成本

| 任務 | 輪次 | Lane | 子代理建議 | USD | 秒數 | 狀態 |
|---|---:|---|---|---:|---:|---|
| known-dto-change | 1 | single-agent |  | 0.3911 | 7.8 | pass |
| login-flow-analysis | 1 | plan-light | explorer:1 | 0.0418 | 6.7 | pass |
| authentication-policy-change | 1 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0432 | 7.5 | pass |
| login-flow-analysis | 2 | plan-light | explorer:1 | 0.0419 | 7.4 | pass |
| authentication-policy-change | 2 | orchestrate-heavy | implementer:1;planner:1;verifier:1 | 0.0435 | 6.6 | pass |
| known-dto-change | 2 | single-agent |  | 0.0420 | 8.1 | pass |
| authentication-policy-change | 3 | orchestrate-heavy | planner:1;verifier:1 | 0.0432 | 7.6 | pass |
| known-dto-change | 3 | single-agent |  | 0.0419 | 6.4 | pass |
| login-flow-analysis | 3 | plan-light | explorer:1 | 0.0433 | 8.8 | pass |

## 每輪明細

| 順序 | 任務 | 類型 | 策略 | R | Lane | Agents | USD | 秒數 | 驗收 | 狀態 |
|---:|---|---|---|---:|---|---:|---:|---:|---:|---|
| 1 | known-dto-change | classification | classification | 1 | single-agent | 0 | 0.3911 | 7.8 | 1/1 | pass |
| 2 | known-dto-change | execution | current-policy | 1 | single-agent | 0 | 0.2119 | 20.2 | 3/3 | pass |
| 3 | known-dto-change | execution | forced-heavy | 1 | orchestrate-heavy | 2 | 0.4642 | 75.5 | 7/8 | quality-fail |
| 4 | login-flow-analysis | classification | classification | 1 | plan-light | 1 | 0.0418 | 6.7 | 1/1 | pass |
| 5 | login-flow-analysis | execution | current-policy | 1 | single-agent | 0 | 0.1437 | 20.7 | 12/12 | pass |
| 6 | login-flow-analysis | execution | forced-single | 1 | single-agent | 0 | 0.2027 | 22.0 | 11/11 | pass |
| 7 | authentication-policy-change | classification | classification | 1 | orchestrate-heavy | 3 | 0.0432 | 7.5 | 1/1 | pass |
| 8 | authentication-policy-change | execution | current-policy | 1 | single-agent | 0 | 0.1846 | 40.4 | 5/10 | quality-fail |
| 9 | authentication-policy-change | execution | forced-single | 1 | single-agent | 0 | 0.1185 | 17.3 | 3/3 | pass |
| 10 | login-flow-analysis | classification | classification | 2 | plan-light | 1 | 0.0419 | 7.4 | 1/1 | pass |
| 11 | login-flow-analysis | execution | forced-single | 2 | single-agent | 0 | 0.1427 | 15.3 | 11/11 | pass |
| 12 | login-flow-analysis | execution | current-policy | 2 | single-agent | 0 | 0.1636 | 19.9 | 12/12 | pass |
| 13 | authentication-policy-change | classification | classification | 2 | orchestrate-heavy | 3 | 0.0435 | 6.6 | 1/1 | pass |
| 14 | authentication-policy-change | execution | forced-single | 2 | single-agent | 0 | 0.1207 | 16.7 | 3/3 | pass |
| 15 | authentication-policy-change | execution | current-policy | 2 | single-agent | 0 | 0.1779 | 37.3 | 5/10 | quality-fail |
| 16 | known-dto-change | classification | classification | 2 | single-agent | 0 | 0.0420 | 8.1 | 1/1 | pass |
| 17 | known-dto-change | execution | forced-heavy | 2 | orchestrate-heavy | 2 | 0.4327 | 83.9 | 7/8 | quality-fail |
| 18 | known-dto-change | execution | current-policy | 2 | single-agent | 0 | 0.1370 | 19.2 | 3/3 | pass |
| 19 | authentication-policy-change | classification | classification | 3 | orchestrate-heavy | 2 | 0.0432 | 7.6 | 1/1 | pass |
| 20 | authentication-policy-change | execution | current-policy | 3 | single-agent | 0 | 0.1716 | 31.3 | 5/10 | quality-fail |
| 21 | authentication-policy-change | execution | forced-single | 3 | single-agent | 0 | 0.1150 | 17.4 | 3/3 | pass |
| 22 | known-dto-change | classification | classification | 3 | single-agent | 0 | 0.0419 | 6.4 | 1/1 | pass |
| 23 | known-dto-change | execution | current-policy | 3 | single-agent | 0 | 0.1504 | 19.8 | 3/3 | pass |
| 24 | known-dto-change | execution | forced-heavy | 3 | orchestrate-heavy | 2 | 0.4510 | 76.9 | 7/8 | quality-fail |
| 25 | login-flow-analysis | classification | classification | 3 | plan-light | 1 | 0.0433 | 8.8 | 1/1 | pass |
| 26 | login-flow-analysis | execution | current-policy | 3 | single-agent | 0 | 0.1616 | 27.6 | 7/12 | quality-fail |
| 27 | login-flow-analysis | execution | forced-single | 3 | single-agent | 0 | 0.1342 | 17.8 | 11/11 | pass |

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
