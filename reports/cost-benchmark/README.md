# Cost Benchmark Reports

此目錄由 `tests/New-CostReport.ps1` 產生版本化的成本基準報告，每種 model 設定一個子目錄，名稱取自校準時的 `-ReportLabel`（例如 `sonnet-5-5/`）。新模型或新的 agent 設定請開新 label，不覆寫既有報告

每個子目錄包含：

- `task-cost-report.md`：摘要表格、比較與限制
- `task-cost-data.csv`：每輪正規化資料
- `task-cost-curves.svg`：三個代表任務的累積 API 等價成本曲線

Live 原始 stream JSON 只保留在已忽略的 `.sandbox/runs/<benchmark-id>/`，不會寫入此目錄

已知限制：

- Claude CLI 2.1.292 回報的 `claude-haiku-5-5` 成本與官方定價不符（例：82k cache read＋21k cache write＋4.9k output 回報 $0.218，依官方定價約 $0.006），`explorer-probe_explorer-haiku-5-5/` 的 USD 欄位會高估；比較時請用 CSV 的 `model_usage_json` token 數重算
- Agent 的 model 別名 `haiku` 在此 CLI 版本對應 `claude-haiku-4-5-20251001`；要測 Haiku 5.5 必須設定完整 ID，例如 `CDK_MODEL_EXPLORER=claude-haiku-5-5`
