# Claude Dev Kit 任務成本基準報告

- Benchmark ID：`838684df35cb4036a191fcc34de98a01`
- Claude CLI：`2.1.292 (Claude Code)`
- 主對話 model／effort：`sonnet`／`low`
- 任務組：`explorer-probe`
- Policy fingerprint：`1a994c2ee17137ac6d6162b2ab469d347d4400018e4ede9c58d78f47ca269efb`
- Installed policy fingerprint：`70a5aac51397417519870f782f5550bd0e0006c70325b52a5ba3b0a425a6fcb7`
- Benchmark input fingerprint：`ee98dfa272865d15630368b678a02430d0f33769f26777473b673b9e8ee67fb1`
- Quality contract：`2.1`
- 樣本：9 / 9
- 完成樣本成本：$1.8220 USD
- 保留的重試 attempt：0 筆，$0.0000 USD
- Benchmark 作業總成本：$1.8220 USD
- 金額為 Claude CLI 回報的 API 等價估算，不代表訂閱方案實際帳單

![各任務累積成本曲線](task-cost-curves.svg)

## 執行策略比較

| 任務 | 策略 | 輪數 | 平均 USD | Median | 範圍 | 平均秒數 | 平均 Token | 策略驗收 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| login-flow-analysis | forced-explorer | 3 | 0.2524 | 0.2214 | 0.2041–0.3318 | 41.5 | 53675 | 2/3 |
| login-flow-analysis | forced-single | 3 | 0.1983 | 0.1718 | 0.1372–0.2858 | 27.4 | 179314 | 3/3 |

策略驗收同時包含共通交付檢查與該策略承諾的工作流程條件，用於判斷策略是否完整落實，不等同純產品品質分數

## 現行策略相對差異

| 任務 | 反事實策略 | 成本差異 | 時間差異 | 策略驗收差異 |
|---|---|---:|---:|---:|
| login-flow-analysis | forced-single | 27.3% | 51.4% | -33.3 pp |

## Lane 分類成本

| 任務 | 輪次 | Lane | 子代理建議 | USD | 秒數 | 狀態 |
|---|---:|---|---|---:|---:|---|
| login-flow-analysis | 1 | plan-light | explorer:1 | 0.0263 | 6.2 | pass |
| login-flow-analysis | 2 | plan-light | explorer:1 | 0.3971 | 9.1 | pass |
| login-flow-analysis | 3 | plan-light | explorer:1 | 0.0464 | 9.1 | pass |

## 每輪明細

| 順序 | 任務 | 類型 | 策略 | R | Lane | Agents | USD | 秒數 | 驗收 | 狀態 |
|---:|---|---|---|---:|---|---:|---:|---:|---:|---|
| 1 | login-flow-analysis | classification | classification | 1 | plan-light | 1 | 0.0263 | 6.2 | 1/1 | pass |
| 2 | login-flow-analysis | execution | forced-explorer | 1 | plan-light | 1 | 0.3318 | 43.5 | 11/12 | quality-fail |
| 3 | login-flow-analysis | execution | forced-single | 1 | single-agent | 0 | 0.2858 | 33.0 | 11/11 | pass |
| 4 | login-flow-analysis | classification | classification | 2 | plan-light | 1 | 0.3971 | 9.1 | 1/1 | pass |
| 5 | login-flow-analysis | execution | forced-single | 2 | single-agent | 0 | 0.1718 | 29.9 | 11/11 | pass |
| 6 | login-flow-analysis | execution | forced-explorer | 2 | plan-light | 1 | 0.2041 | 37.0 | 12/12 | pass |
| 7 | login-flow-analysis | classification | classification | 3 | plan-light | 1 | 0.0464 | 9.1 | 1/1 | pass |
| 8 | login-flow-analysis | execution | forced-explorer | 3 | plan-light | 1 | 0.2214 | 44.0 | 12/12 | pass |
| 9 | login-flow-analysis | execution | forced-single | 3 | single-agent | 0 | 0.1372 | 19.3 | 11/11 | pass |

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
