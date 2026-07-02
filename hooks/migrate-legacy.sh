#!/usr/bin/env bash
# SessionStart migration hook.
# In older plugin versions the PreToolUse hook was written to
# ~/.claude/hooks/pre-tool-notify.sh and registered in ~/.claude/settings.json.
# The hook now lives inside the plugin, so those legacy artifacts must be
# removed on upgrade — otherwise the popup fires twice or keeps firing
# after the plugin is disabled.
#
# Cheap fast-path: if there's nothing to clean, exit immediately.

set -euo pipefail

LEGACY_HOOK="${HOME}/.claude/hooks/pre-tool-notify.sh"
SETTINGS_JSON="${HOME}/.claude/settings.json"
LEGACY_MARK="pre-tool-notify.sh"

# Fast exit: neither the file nor a matching settings entry exists.
if [ ! -e "$LEGACY_HOOK" ] && \
   { [ ! -f "$SETTINGS_JSON" ] || ! grep -q "$LEGACY_MARK" "$SETTINGS_JSON" 2>/dev/null; }; then
    exit 0
fi

# Remove legacy hook script.
if [ -e "$LEGACY_HOOK" ]; then
    rm -f "$LEGACY_HOOK" 2>/dev/null || true
fi

# Strip legacy PreToolUse entry from settings.json.
if [ -f "$SETTINGS_JSON" ] && grep -q "$LEGACY_MARK" "$SETTINGS_JSON" 2>/dev/null; then
    python3 - "$SETTINGS_JSON" "$LEGACY_MARK" <<'PYEOF' 2>/dev/null || true
import json, sys
path, mark = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
hooks = data.get("hooks", {})
pre = hooks.get("PreToolUse", [])
new_pre = []
for block in pre:
    kept = [h for h in block.get("hooks", []) if mark not in h.get("command", "")]
    if kept:
        block["hooks"] = kept
        new_pre.append(block)
    elif block.get("matcher") != "Bash|Edit|Write":
        new_pre.append(block)
if new_pre:
    hooks["PreToolUse"] = new_pre
elif "PreToolUse" in hooks:
    del hooks["PreToolUse"]
if hooks:
    data["hooks"] = hooks
elif "hooks" in data:
    del data["hooks"]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
fi

exit 0
