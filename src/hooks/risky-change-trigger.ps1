# UserPromptSubmit hook：高風險關鍵字硬觸發（deterministic，不經模型判斷）
# 命中時注入 additionalContext，強制走 risky-change skill + full orchestration
# stdin 以 raw bytes 讀取再以 UTF-8 解碼，避免中文關鍵字被主控台編碼弄壞

$stdin = [Console]::OpenStandardInput()
$ms = New-Object System.IO.MemoryStream
$stdin.CopyTo($ms)
$raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())

try { $prompt = ($raw | ConvertFrom-Json).prompt } catch { exit 0 }
if (-not $prompt) { exit 0 }

$pattern = '(?i)\bauth(n|z|entication|orization|orize[sd]?)?\b|\bpermissions?\b|\broles?\b|\bidentity\b|\boauth\b|\bjwt\b|\bsso\b|\bpayments?\b|\bbilling\b|\bmigrations?\b|\bschema\b|\bsecrets?\b|\bcredentials?\b|\bcrypto(graphy)?\b|\btenant\b|\bpipelines?\b|\bdeploy(ment|s)?\b|授權|認證|身分|身份|角色|權限|登入|金流|付款|帳務|計費|遷移|密鑰|金鑰|憑證|機密|多租戶|部署'

if ($prompt -match $pattern) {
    $ctx = 'HIGH-RISK KEYWORD TRIGGER (deterministic hook, not model judgment): this prompt matches high-risk domain keywords (auth/authorization/roles/permissions/identity, payments/billing, migration/schema, secrets/credentials/crypto, multi-tenant, deploy/pipeline). Per global engineering rules this task is HIGH RISK by definition and you have NO discretion here: (1) invoke the risky-change skill BEFORE any implementation; (2) route to full orchestration (planner -> implementer(s) -> verifier) with a single writer in the high-risk area; (3) the final report must include the Risk & Rollback block. Exception: if after reading the code you confirm the change does not actually touch a high-risk domain (the keyword was incidental), state that conclusion explicitly in one sentence and proceed normally.'
    @{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $ctx } } | ConvertTo-Json -Depth 3 -Compress
}
exit 0
