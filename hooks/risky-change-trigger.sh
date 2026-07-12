#!/bin/sh
# UserPromptSubmit hook：高風險關鍵字硬觸發（deterministic，不經模型判斷）
# 與 risky-change-trigger.ps1 邏輯一致；JSON 解析與 regex 交給 python3
# （macOS 裝了 Xcode Command Line Tools 即有，Linux 幾乎皆內建）
command -v python3 >/dev/null 2>&1 || exit 0

HOOK_INPUT=$(cat)
export HOOK_INPUT

exec python3 <<'PYEOF'
import json, os, re, sys

try:
    prompt = json.loads(os.environ.get("HOOK_INPUT", "")).get("prompt") or ""
except ValueError:
    sys.exit(0)

pattern = (
    r'(?i)\bauth(n|z|entication|orization|orize[sd]?)?\b|\bpermissions?\b|\broles?\b'
    r'|\bidentity\b|\boauth\b|\bjwt\b|\bsso\b|\bpayments?\b|\bbilling\b|\bmigrations?\b'
    r'|\bschema\b|\bsecrets?\b|\bcredentials?\b|\bcrypto(graphy)?\b|\btenant\b'
    r'|\bpipelines?\b|\bdeploy(ment|s)?\b'
    r'|授權|認證|身分|身份|角色|權限|登入|金流|付款|帳務|計費|遷移|密鑰|金鑰|憑證|機密|多租戶|部署'
)

if re.search(pattern, prompt):
    ctx = ('HIGH-RISK KEYWORD TRIGGER (deterministic hook, not model judgment): this prompt '
           'matches high-risk domain keywords (auth/authorization/roles/permissions/identity, '
           'payments/billing, migration/schema, secrets/credentials/crypto, multi-tenant, '
           'deploy/pipeline). Per global engineering rules this task is HIGH RISK by definition '
           'and you have NO discretion here: (1) invoke the risky-change skill BEFORE any '
           'implementation; (2) route to full orchestration (planner -> implementer(s) -> '
           'verifier) with a single writer in the high-risk area; (3) the final report must '
           'include the Risk & Rollback block. Exception: if after reading the code you confirm '
           'the change does not actually touch a high-risk domain (the keyword was incidental), '
           'state that conclusion explicitly in one sentence and proceed normally.')
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                             "additionalContext": ctx}}))
PYEOF
