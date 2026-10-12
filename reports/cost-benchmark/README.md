# Cost Benchmark Reports

此目錄由 `tests/New-CostReport.ps1` 產生版本化的成本基準報告，每種 model 設定一個子目錄，名稱取自校準時的 `-ReportLabel`（例如 `sonnet-5-5/`）。新模型或新的 agent 設定請開新 label，不覆寫既有報告

每個子目錄包含：

- `task-cost-report.md`：摘要表格、比較與限制
- `task-cost-data.csv`：每輪正規化資料
- `task-cost-curves.svg`：三個代表任務的累積 API 等價成本曲線

Live 原始 stream JSON 只保留在已忽略的 `.sandbox/runs/<benchmark-id>/`，不會寫入此目錄
