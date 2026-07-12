#!/bin/sh
# install.sh — 安裝/更新 claude-dev-kit 到 ~/.claude（macOS / Linux）
# 重複執行即為更新；settings.json 只合併本 kit 的 hook 註冊，不動其他既有設定
# 執行時逐項回報：[建立]/[新增]/[覆蓋]/[取代]/[合併]/[更新]/[備份]/[未動]，皆附完整路徑
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
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

for f in "$SRC"/agents/*.md;   do install_file "$f" "$DEST/agents"; done
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
