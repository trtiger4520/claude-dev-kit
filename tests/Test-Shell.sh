#!/usr/bin/env bash

set -euo pipefail
export PATH="/usr/bin:/bin:$PATH"

repo_root=$(cd "$(dirname "$0")/.." && pwd)
sandbox_root="$repo_root/.sandbox"
runs_root="$sandbox_root/runs"
run_id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
run_root="$runs_root/$run_id"
install_root="$run_root/install-root"
environment_root="$run_root/environment-root"
explicit_root="$run_root/explicit-wins"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ "$run_id" =~ ^[0-9a-f]{32}$ && "$run_root" == "$runs_root/$run_id" ]]; then
        rm -rf -- "$run_root"
    else
        printf 'Refusing unsafe shell-test cleanup: %s\n' "$run_root" >&2
    fi
}
trap cleanup EXIT

git -C "$repo_root" check-ignore --quiet -- .sandbox/ignore-probe || fail '.sandbox must be ignored before shell tests create files'
[[ "$run_id" =~ ^[0-9a-f]{32}$ ]] || fail "Shell test run id is not a GUID: $run_id"
[ "$run_root" = "$sandbox_root/runs/$run_id" ] || fail "Shell test path escaped the repository sandbox: $run_root"
case "$run_root" in
    /c/Users/trtig/*|C:/Users/trtig/*) fail "Shell test path resolves inside the protected user profile: $run_root" ;;
esac

mkdir -p "$run_root"
bash_bin=${BASH:-/usr/bin/bash}
"$bash_bin" -n "$repo_root/install.sh"
"$bash_bin" -n "$repo_root/src/hooks/risky-change-trigger.sh"
"$bash_bin" -n "$repo_root/src/skills/source-boundary/scripts/Test-SourceBoundary.sh"

export CDK_MODEL_EXPLORER=sonnet
export CDK_MODEL_IMPLEMENTER=sonnet
export CDK_MODEL_PLANNER=inherit
export CDK_MODEL_VERIFIER=inherit
export CDK_EFFORT_EXPLORER=low
export CDK_EFFORT_IMPLEMENTER=medium
export CDK_EFFORT_PLANNER=inherit
export CDK_EFFORT_VERIFIER=high

dry_output=$("$bash_bin" "$repo_root/install.sh" --dry-run --destination "$install_root" 2>&1)
printf '%s\n' "$dry_output" | grep -F -- "-> $install_root" >/dev/null || fail 'Shell installer dry-run did not report the sandbox destination'
[ ! -e "$install_root" ] || fail 'Shell installer dry-run created the destination'

"$bash_bin" "$repo_root/install.sh" --destination "$install_root" >/dev/null
[ -f "$install_root/CLAUDE.md" ] || fail 'Shell installer did not install CLAUDE.md'
[ -f "$install_root/agents/explorer.md" ] || fail 'Shell installer did not install agents'
[ -f "$install_root/skills/source-boundary/scripts/Test-SourceBoundary.sh" ] || fail 'Shell installer did not install the source-boundary script'
grep -F 'POTENTIAL HIGH-RISK DOMAIN' "$install_root/hooks/risky-change-trigger.sh" >/dev/null || fail 'Shell installer copied the wrong risk hook'

env_output=$(CLAUDE_CONFIG_DIR="$environment_root" "$bash_bin" "$repo_root/install.sh" --dry-run 2>&1)
printf '%s\n' "$env_output" | grep -F -- "-> $environment_root" >/dev/null || fail 'Shell installer did not honor CLAUDE_CONFIG_DIR'

explicit_output=$(CLAUDE_CONFIG_DIR="$environment_root" "$bash_bin" "$repo_root/install.sh" --dry-run --destination "$explicit_root" 2>&1)
printf '%s\n' "$explicit_output" | grep -F -- "-> $explicit_root" >/dev/null || fail 'Shell installer explicit destination did not take precedence over CLAUDE_CONFIG_DIR'

if command -v python3 >/dev/null 2>&1; then
    grep -F "$install_root/hooks/risky-change-trigger.sh" "$install_root/settings.json" >/dev/null || fail 'Shell hook command did not use the sandbox destination'
    unrelated=$(printf '%s' '{"prompt":"Update a button label"}' | "$bash_bin" "$repo_root/src/hooks/risky-change-trigger.sh")
    [ -z "$unrelated" ] || fail 'Shell risk hook matched an unrelated prompt'
    risk=$(printf '%s' '{"prompt":"Analyze authentication without changing files"}' | "$bash_bin" "$repo_root/src/hooks/risky-change-trigger.sh")
    printf '%s' "$risk" | grep -F 'POTENTIAL HIGH-RISK DOMAIN' >/dev/null || fail 'Shell risk hook did not mark a candidate domain'
    printf '%s' "$risk" | grep -F 'Read-only analysis' >/dev/null || fail 'Shell risk hook omitted the read-only exception'
fi

printf '%s\n' 'PASS: sandboxed shell installer and hook syntax'
