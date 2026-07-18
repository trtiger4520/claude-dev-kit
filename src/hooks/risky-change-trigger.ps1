# UserPromptSubmit hook：高風險關鍵字候選標記（deterministic，不直接決定 lane）
# 命中時注入 additionalContext，要求先判斷是否真的修改高風險行為或狀態
# stdin 以 raw bytes 讀取再以 UTF-8 解碼，避免中文關鍵字被主控台編碼弄壞

$stdin = [Console]::OpenStandardInput()
$ms = New-Object System.IO.MemoryStream
$stdin.CopyTo($ms)
$raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())

try { $prompt = ($raw | ConvertFrom-Json).prompt } catch { exit 0 }
if (-not $prompt) { exit 0 }

$pattern = '(?i)\bauth(n|z|entication|orization|orize[sd]?)?\b|\bpermissions?\b|\broles?\b|\bidentity\b|\boauth\b|\bjwt\b|\bsso\b|\bpayments?\b|\bbilling\b|\bmigrations?\b|\bschema\b|\bsecrets?\b|\bcredentials?\b|\bcrypto(graphy)?\b|\btenant\b|\bpipelines?\b|\bdeploy(ment|s)?\b|授權|認證|身分|身份|角色|權限|登入|金流|付款|帳務|計費|遷移|密鑰|金鑰|憑證|機密|多租戶|部署'

if ($prompt -match $pattern) {
    $ctx = 'POTENTIAL HIGH-RISK DOMAIN (deterministic keyword screening, not a lane decision): first determine whether the request actually WRITES or changes security-sensitive behavior or controls, payments, persisted data or schema, secrets or cryptography, tenant boundaries, or production deployment state. Read-only analysis, documentation-only work, and incidental mentions stay in single-agent or plan-light. Only an actual high-risk change requires the risky-change skill, explicit plan approval, orchestrate-heavy, one writer, independent verification, and a Risk & Rollback report.'
    @{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $ctx } } | ConvertTo-Json -Depth 3 -Compress
}
exit 0
