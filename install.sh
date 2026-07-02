#!/usr/bin/env bash
# install.sh — ask-user plugin setup
# Registers the plugin, whitelists ask.sh, and cleans up legacy
# system-level hook entries from earlier plugin versions.
# The PreToolUse hook now lives inside the plugin (hooks/hooks.json) and
# activates/deactivates together with the plugin itself.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="ask-user@local"
CLAUDE_DIR="${HOME}/.claude"
PLUGINS_JSON="${CLAUDE_DIR}/plugins/installed_plugins.json"
SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
LEGACY_HOOK="${CLAUDE_DIR}/hooks/pre-tool-notify.sh"
ASK_SH="${PLUGIN_DIR}/scripts/ask.sh"

echo "→ Installing ask-user plugin..."

# ── 1. Plugin registration ────────────────────────────────────────────────────
mkdir -p "${CLAUDE_DIR}/plugins/cache/local"

if [ ! -f "$PLUGINS_JSON" ]; then
    echo '{"version":2,"plugins":{}}' > "$PLUGINS_JSON"
fi

python3 - <<PYEOF
import json, datetime

path = "${PLUGINS_JSON}"
plugin_dir = "${PLUGIN_DIR}"
plugin_name = "${PLUGIN_NAME}"

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

with open(path) as f:
    data = json.load(f)

data.setdefault("plugins", {})
data["plugins"][plugin_name] = [{
    "scope": "user",
    "installPath": plugin_dir,
    "version": "1.0.0",
    "installedAt": now,
    "lastUpdated": now,
}]

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print("  ✓ Plugin registered in installed_plugins.json")
PYEOF

# ── 2. Ensure settings.json exists ───────────────────────────────────────────
if [ ! -f "$SETTINGS_JSON" ]; then
    echo '{}' > "$SETTINGS_JSON"
fi

# ── 3. Remove legacy system-level hook script ────────────────────────────────
if [ -f "$LEGACY_HOOK" ]; then
    rm -f "$LEGACY_HOOK"
    echo "  ✓ Removed legacy hook script: ${LEGACY_HOOK}"
fi

# ── 4. Merge settings.json: perm + enable, clean legacy hook entry ───────────
python3 - <<PYEOF
import json

path = "${SETTINGS_JSON}"
ask_sh_perm = "Bash(${ASK_SH} *)"
legacy_hook_cmd_substr = "hooks/pre-tool-notify.sh"

with open(path) as f:
    data = json.load(f)

# permissions.allow — add ask.sh entry if missing
perms = data.setdefault("permissions", {})
allow = perms.setdefault("allow", [])
# Drop stale ask.sh entries pointing to different install paths
allow[:] = [p for p in allow if not (
    isinstance(p, str) and p.startswith("Bash(") and "ask-user" in p and "/scripts/ask.sh " in p and p != ask_sh_perm
)]
if ask_sh_perm not in allow:
    allow.insert(0, ask_sh_perm)
    print("  ✓ Added ask.sh to permissions.allow")
else:
    print("  · permissions.allow already has ask.sh entry")

# hooks.PreToolUse — strip any legacy pre-tool-notify.sh command inherited
# from earlier plugin versions (the hook now lives inside the plugin).
hooks = data.get("hooks", {})
pre = hooks.get("PreToolUse", [])
new_pre = []
removed = 0
for block in pre:
    kept = []
    for h in block.get("hooks", []):
        cmd = h.get("command", "")
        if legacy_hook_cmd_substr in cmd:
            removed += 1
            continue
        kept.append(h)
    if kept:
        block["hooks"] = kept
        new_pre.append(block)
    elif block.get("matcher") != "Bash|Edit|Write":
        # keep unrelated empty blocks untouched
        new_pre.append(block)
if new_pre:
    hooks["PreToolUse"] = new_pre
elif "PreToolUse" in hooks:
    del hooks["PreToolUse"]
if not hooks and "hooks" in data:
    del data["hooks"]
elif hooks:
    data["hooks"] = hooks
if removed:
    print(f"  ✓ Removed {removed} legacy PreToolUse hook entry/entries from settings.json")

# enabledPlugins
data.setdefault("enabledPlugins", {})["ask-user@local"] = True

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print("  ✓ settings.json updated")
PYEOF

echo ""
echo "Done. Restart Claude Code so the plugin's built-in hook loads."
echo "The PreToolUse hook is now part of the plugin — disabling ask-user"
echo "in /plugin also disables the hook automatically."
