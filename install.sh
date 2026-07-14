#!/bin/sh
# install.sh — 安裝/更新 claude-dev-kit 到 ~/.claude（macOS / Linux）
# 重複執行即為更新；settings.json 只合併本 kit 的 hook 註冊，不動其他既有設定
# 執行時逐項回報：[建立]/[新增]/[覆蓋]/[取代]/[合併]/[更新]/[備份]/[未動]，皆附完整路徑
set -eu

SRC=$(cd "$(dirname "$0")/src" && pwd)
DEST="$HOME/.claude"

echo "== claude-dev-kit 安裝/更新 -> $DEST =="

for d in agents commands skills hooks; do
    if [ ! -d "$DEST/$d" ]; then
        mkdir -p "$DEST/$d"
        echo "[建立] $DEST/$d"
    fi
done

install_file() {
    t="$2/$(basename "$1")"
    if [ -e "$t" ]; then a='覆蓋'; else a='新增'; fi
    cp "$1" "$t"
    echo "[$a] $t"
}

# ---- agents：安裝時可為每個 agent 選擇 model 與 effort ----
INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

get_current_field() {
    t="$1"; field="$2"
    if [ -e "$t" ]; then
        grep "^$field:" "$t" 2>/dev/null | head -n1 | sed "s/^$field:[[:space:]]*//"
    fi
}

resolve_model() {
    name="$1"; current="$2"
    envname="CDK_MODEL_$(echo "$name" | tr '[:lower:]' '[:upper:]')"
    eval "envval=\${$envname:-}"
    if [ -n "$envval" ]; then echo "$envval"; return; fi
    if [ "$INTERACTIVE" -ne 1 ]; then echo "$current"; return; fi
    echo "" >&2
    echo "選擇 agent「$name」使用的 model（目前：$current）" >&2
    echo "  1) inherit（跟隨主對話模型）" >&2
    echo "  2) sonnet" >&2
    echo "  3) opus" >&2
    echo "  4) haiku" >&2
    echo "  5) fable" >&2
    printf "輸入數字或直接輸入完整 model ID，Enter 保留目前設定：" >&2
    read -r choice
    case "$choice" in
        '') echo "$current" ;;
        1) echo "inherit" ;;
        2) echo "sonnet" ;;
        3) echo "opus" ;;
        4) echo "haiku" ;;
        5) echo "fable" ;;
        *) echo "$choice" ;;
    esac
}

resolve_effort() {
    name="$1"; current="$2"
    envname="CDK_EFFORT_$(echo "$name" | tr '[:lower:]' '[:upper:]')"
    eval "envval=\${$envname:-}"
    if [ -n "$envval" ]; then
        if [ "$envval" = "inherit" ]; then echo ""; else echo "$envval"; fi
        return
    fi
    if [ "$INTERACTIVE" -ne 1 ]; then echo "$current"; return; fi
    current_display="$current"
    [ -z "$current_display" ] && current_display='inherit'
    echo "" >&2
    echo "選擇 agent「$name」使用的 effort（目前：$current_display）" >&2
    echo "  1) inherit（跟隨主對話，不寫入 effort 欄位）" >&2
    echo "  2) low" >&2
    echo "  3) medium" >&2
    echo "  4) high" >&2
    echo "  5) xhigh" >&2
    echo "  6) max" >&2
    printf "輸入數字，Enter 保留目前設定：" >&2
    read -r choice
    case "$choice" in
        '') echo "$current" ;;
        1) echo "" ;;
        2) echo "low" ;;
        3) echo "medium" ;;
        4) echo "high" ;;
        5) echo "xhigh" ;;
        6) echo "max" ;;
        *) echo "無效輸入，保留目前設定：$current_display" >&2; echo "$current" ;;
    esac
}

install_agent_file() {
    file="$1"; destDir="$2"
    target="$destDir/$(basename "$file")"
    if [ -e "$target" ]; then a='覆蓋'; else a='新增'; fi
    name=$(basename "$file" .md)

    # 既有安裝以目的地設定為準；全新安裝以 src frontmatter 為預設
    current_model=$(get_current_field "$target" model)
    [ -z "$current_model" ] && current_model=$(get_current_field "$file" model)
    [ -z "$current_model" ] && current_model='inherit'
    if [ -e "$target" ]; then
        current_effort=$(get_current_field "$target" effort)
    else
        current_effort=$(get_current_field "$file" effort)
    fi

    chosen_model=$(resolve_model "$name" "$current_model")
    chosen_effort=$(resolve_effort "$name" "$current_effort")

    awk -v model="$chosen_model" -v effort="$chosen_effort" '
        /^model:/  { print "model: " model; if (effort != "") print "effort: " effort; next }
        /^effort:/ { next }
        { print }
    ' "$file" > "$target"

    echo "[$a] $target"
    effort_display="$chosen_effort"
    [ -z "$effort_display" ] && effort_display='inherit'
    echo "       model=$chosen_model, effort=$effort_display"
}

for f in "$SRC"/agents/*.md;   do install_agent_file "$f" "$DEST/agents"; done
for f in "$SRC"/commands/*.md; do install_file "$f" "$DEST/commands"; done

for d in "$SRC"/skills/*/; do
    name=$(basename "$d")
    t="$DEST/skills/$name"
    if [ -e "$t" ]; then a='覆蓋'; else a='新增'; fi
    cp -R "${d%/}" "$DEST/skills/"
    echo "[$a] $t"
done

# CLAUDE.md 整份取代，不是附加；取代前備份一層（.bak 每次覆蓋），內容相同則不處理
if [ -e "$DEST/CLAUDE.md" ]; then
    if cmp -s "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"; then
        echo "[未動] $DEST/CLAUDE.md — 內容相同，未覆蓋、未備份"
    else
        cp "$DEST/CLAUDE.md" "$DEST/CLAUDE.md.bak"
        echo "[備份] $DEST/CLAUDE.md -> $DEST/CLAUDE.md.bak（只保留一層）"
        cp "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"
        echo "[取代] $DEST/CLAUDE.md（整份覆蓋，非附加）"
    fi
else
    cp "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"
    echo "[新增] $DEST/CLAUDE.md"
fi

install_file "$SRC/hooks/risky-change-trigger.sh" "$DEST/hooks"
chmod +x "$DEST/hooks/risky-change-trigger.sh"

# ---- settings.json：合併 UserPromptSubmit hook 註冊 ----
SETTINGS_PATH="$DEST/settings.json"
HOOK_CMD="\"$DEST/hooks/risky-change-trigger.sh\""

if command -v python3 >/dev/null 2>&1; then
    SETTINGS_PATH="$SETTINGS_PATH" HOOK_CMD="$HOOK_CMD" PYTHONIOENCODING=utf-8 python3 <<'PYEOF'
import json, os, shutil, sys

path = os.environ["SETTINGS_PATH"]
cmd = os.environ["HOOK_CMD"]

existed = os.path.exists(path)
settings = {}
if existed:
    with open(path, encoding="utf-8") as f:
        text = f.read().strip()
    if text:
        try:
            settings = json.loads(text)
        except ValueError:
            print("settings.json 解析失敗，未自動合併 hook（檔案未被修改），"
                  "請手動加入 hooks.UserPromptSubmit（格式見 README）", file=sys.stderr)
            sys.exit(1)

# 先記下既有設定鍵，最後回報哪些沒動
other_keys = [k for k in settings if k != "hooks"]
other_events = [k for k in settings.get("hooks", {}) if k != "UserPromptSubmit"]

ups = settings.setdefault("hooks", {}).setdefault("UserPromptSubmit", [])

# 已註冊過：內容相同就不動檔案，不同則只更新那筆 command；沒註冊過則附加新項目
found = False
old = None
for matcher in ups:
    for h in matcher.get("hooks", []):
        if "risky-change-trigger" in h.get("command", ""):
            found = True
            if h["command"] != cmd:
                old = h["command"]
                h["command"] = cmd

if found and old is None:
    print(f"[未動] {path} — hook 已註冊且內容相同，未寫入、未備份")
else:
    if existed:
        shutil.copyfile(path, path + ".bak")
        print(f"[備份] {path} -> {path}.bak")
    else:
        print(f"[新增] {path}")
    if found:
        print(f"[更新] {path} hooks.UserPromptSubmit 既有項目 command：")
        print(f"       舊：{old}")
        print(f"       新：{cmd}")
    else:
        ups.append({"hooks": [{"type": "command", "command": cmd, "timeout": 15}]})
        print(f"[合併] {path} 新增 hooks.UserPromptSubmit 項目：")
        print(f"       command = {cmd}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(settings, f, ensure_ascii=False, indent=2)
        f.write("\n")

if other_keys:
    print("[未動] settings.json 其他設定鍵：" + "、".join(other_keys))
if other_events:
    print("[未動] settings.json hooks 其他事件：" + "、".join(other_events))
PYEOF
else
    echo "找不到 python3，未自動合併 settings.json（檔案未被修改），請手動加入 hooks.UserPromptSubmit（格式見 README）" >&2
fi

echo "== 完成 =="
echo "未列出的既有檔案與設定一律未變動"
echo "skills 目錄若是首次建立，需重啟 Claude Code"
