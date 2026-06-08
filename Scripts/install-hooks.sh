#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK="$(pwd)/build/island.app/Contents/MacOS/vibe-hook"
if [[ ! -x "$HOOK" ]]; then
  echo "vibe-hook not found at $HOOK — run ./Scripts/bundle.sh first" >&2
  exit 1
fi

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, sys, os, shutil

settings_path, hook = sys.argv[1], sys.argv[2]
events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]

data = {}
if os.path.exists(settings_path):
    shutil.copy(settings_path, settings_path + ".island.bak")
    with open(settings_path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
for ev in events:
    groups = hooks.setdefault(ev, [])
    # find/create a group whose hooks we own; idempotent on the command string
    target = None
    for g in groups:
        if isinstance(g, dict) and "hooks" in g:
            target = g; break
    if target is None:
        target = {"hooks": []}
        groups.append(target)
    cmds = [h.get("command") for h in target["hooks"] if isinstance(h, dict)]
    if hook not in cmds:
        target["hooks"].append({"type": "command", "command": hook})

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
print("Updated", settings_path)
print("Backup at", settings_path + ".island.bak")
PY
