# Cost Benchmark Reports

此目錄由 `tests/New-CostReport.ps1` 產生版本化的成本基準報告：

- `task-cost-report.md`：摘要表格、比較與限制
- `task-cost-data.csv`：每輪正規化資料
- `task-cost-curves.svg`：三個代表任務的累積 API 等價成本曲線

Live 原始 stream JSON 只保留在已忽略的 `.sandbox/runs/<benchmark-id>/`，不會寫入此目錄
