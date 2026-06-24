#!/usr/bin/env bash
# install.sh — ask-user plugin full setup
# Installs:
#   1. Plugin files + registration in installed_plugins.json
#   2. PreToolUse hook script → ~/.claude/hooks/pre-tool-notify.sh
#   3. Hook + permission entries in ~/.claude/settings.json

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="ask-user@local"
CLAUDE_DIR="${HOME}/.claude"
PLUGINS_JSON="${CLAUDE_DIR}/plugins/installed_plugins.json"
SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
HOOK_DIR="${CLAUDE_DIR}/hooks"
HOOK_SCRIPT="${HOOK_DIR}/pre-tool-notify.sh"
ASK_SH="${PLUGIN_DIR}/scripts/ask.sh"

echo "→ Installing ask-user plugin..."

# ── 1. Plugin registration ────────────────────────────────────────────────────
mkdir -p "${CLAUDE_DIR}/plugins/cache/local"

if [ ! -f "$PLUGINS_JSON" ]; then
    echo '{"version":2,"plugins":{}}' > "$PLUGINS_JSON"
fi

python3 - <<PYEOF
import json, datetime, sys

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

# ── 3. Hook script ────────────────────────────────────────────────────────────
mkdir -p "$HOOK_DIR"

cat > "$HOOK_SCRIPT" << 'HOOKEOF'
#!/usr/bin/env bash
# PreToolUse hook: zenity confirmation when user is away from terminal.
# Terminal focused → silent pass-through (built-in prompt handles approval).
# User in another app → zenity popup with Allow/Block.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', '?'))
except Exception:
    print('?')
" 2>/dev/null || echo "?")

TOOL_DETAIL=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    if 'command' in inp:
        print(str(inp['command'])[:120])
    elif 'file_path' in inp:
        print(str(inp['file_path']))
    elif 'description' in inp:
        print(str(inp['description'])[:120])
    elif inp:
        first_val = next(iter(inp.values()), '')
        print(str(first_val)[:120])
except Exception:
    pass
" 2>/dev/null || true)

HAS_DISPLAY=0
[ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] && HAS_DISPLAY=1

if [ "$HAS_DISPLAY" -eq 0 ]; then exit 0; fi
if ! command -v xdotool &>/dev/null || ! command -v zenity &>/dev/null; then exit 0; fi

# Walk process tree to find terminal emulator
_TERM_PID=""
_pid=$$
for _i in $(seq 1 12); do
    _ppid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
    [ -z "$_ppid" ] || [ "$_ppid" = "0" ] || [ "$_ppid" = "1" ] && break
    _comm=$(ps -o comm= -p "$_ppid" 2>/dev/null | head -c 40 | tr -d ' ')
    case "${_comm}" in
        gnome-terminal*|xterm|konsole|alacritty|kitty|wezterm|tilix|terminator|foot|rxvt*)
            _TERM_PID="$_ppid"; break ;;
    esac
    _pid="$_ppid"
done

TERMINAL_FOCUSED=1
if [ -n "$_TERM_PID" ]; then
    GTERM_WINS=$(xdotool search --pid "$_TERM_PID" 2>/dev/null) || true
    ACTIVE=$(xdotool getactivewindow 2>/dev/null) || true
    if [ -n "$GTERM_WINS" ] && ! echo "$GTERM_WINS" | grep -qx "${ACTIVE:-__none__}"; then
        TERMINAL_FOCUSED=0
    fi
fi

if [ "$TERMINAL_FOCUSED" -eq 1 ]; then exit 0; fi

_WPATH=$(pwd | rev | cut -d'/' -f1-2 | rev)
_TEXT="${TOOL_NAME}"
[ -n "$TOOL_DETAIL" ] && _TEXT="${TOOL_NAME}: ${TOOL_DETAIL}"

if zenity --question \
    --title="Claude Code | ${_WPATH}" \
    --text="${_TEXT}" \
    --ok-label="Allow" \
    --cancel-label="Block" \
    --width=460 \
    2>/dev/null
then
    printf '{"decision":"approve"}\n'
else
    printf '{"decision":"block","reason":"Blocked by user via zenity (%s)"}\n' "$TOOL_NAME"
fi
HOOKEOF

chmod +x "$HOOK_SCRIPT"
echo "  ✓ Hook script installed: ${HOOK_SCRIPT}"

# ── 4. Merge settings.json ────────────────────────────────────────────────────
python3 - <<PYEOF
import json, sys

path = "${SETTINGS_JSON}"
ask_sh_perm = "Bash(${ASK_SH} *)"
hook_cmd = "bash ${HOOK_SCRIPT}"
hook_entry = {"type": "command", "command": hook_cmd}
hook_matcher_block = {
    "matcher": "Bash|Edit|Write",
    "hooks": [hook_entry]
}

with open(path) as f:
    data = json.load(f)

# permissions.allow — add ask.sh entry if missing
perms = data.setdefault("permissions", {})
allow = perms.setdefault("allow", [])
if ask_sh_perm not in allow:
    allow.insert(0, ask_sh_perm)
    print("  ✓ Added ask.sh to permissions.allow")
else:
    print("  · permissions.allow already has ask.sh entry")

# hooks.PreToolUse — add/merge hook entry
hooks = data.setdefault("hooks", {})
pre = hooks.setdefault("PreToolUse", [])

# Find existing matcher block for Bash|Edit|Write
existing = None
for block in pre:
    if block.get("matcher") == "Bash|Edit|Write":
        existing = block
        break

if existing is None:
    pre.append(hook_matcher_block)
    print("  ✓ Added PreToolUse hook for Bash|Edit|Write")
else:
    # Ensure our hook command is present
    cmds = [h.get("command","") for h in existing.get("hooks",[])]
    if hook_cmd not in cmds:
        existing.setdefault("hooks", []).append(hook_entry)
        print("  ✓ Added hook command to existing PreToolUse block")
    else:
        print("  · PreToolUse hook already configured")

# enabledPlugins
data.setdefault("enabledPlugins", {})["ask-user@local"] = True

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print("  ✓ settings.json updated")
PYEOF

echo ""
echo "Done. Restart Claude Code for hooks to take effect."
echo "Test: switch to browser, give Claude a command requiring approval → zenity should appear."
