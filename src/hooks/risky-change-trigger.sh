#!/bin/sh
# UserPromptSubmit hook：高風險關鍵字候選標記（deterministic，不直接決定 lane）
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
    ctx = ('POTENTIAL HIGH-RISK DOMAIN (deterministic keyword screening, not a lane decision): '
           'first determine whether the request actually WRITES or changes security-sensitive '
           'behavior or controls, payments, persisted data or schema, secrets or cryptography, '
           'tenant boundaries, or production deployment state. Read-only analysis, '
           'documentation-only work, and incidental mentions stay in single-agent or plan-light. '
           'Only an actual high-risk change requires the risky-change skill, explicit plan '
           'approval, orchestrate-heavy, one writer, independent verification, and a Risk & '
           'Rollback report.')
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                             "additionalContext": ctx}}))
PYEOF
