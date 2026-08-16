#!/usr/bin/env bash
# PreToolUse hook: confirmation prompt when the user is away from the terminal.
# Terminal focused → silent pass-through (built-in prompt handles approval).
# User in another app → notification (or zenity) with Allow/Block.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=../lib/config.sh
. "$ROOT/lib/config.sh"
# shellcheck source=../lib/ui.sh
. "$ROOT/lib/ui.sh"
# shellcheck source=../lib/focus.sh
. "$ROOT/lib/focus.sh"

# Remote Control bypass: when Claude Code runs in remote-control mode, the
# permission prompt is delivered to the user's remote device natively. Do
# nothing here and let the built-in flow handle it.
case "${CLAUDE_CODE_REMOTE:-}" in
    1|true|TRUE|True|yes|YES|on|ON) exit 0 ;;
esac
[ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ] && exit 0

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

focus_has_display || exit 0
command -v xdotool &>/dev/null || exit 0

focus_capture || exit 0
if focus_terminal_focused; then
    exit 0
fi

WPATH=$(pwd | rev | cut -d'/' -f1-2 | rev)
TEXT="${TOOL_NAME}"
[ -n "$TOOL_DETAIL" ] && TEXT="${TOOL_NAME}: ${TOOL_DETAIL}"

if ui_confirm "Claude Code | ${WPATH}" "$TEXT"; then
    printf '{"decision":"approve"}\n'
else
    printf '{"decision":"block","reason":"Blocked by user via ask-user dialog (%s)"}\n' "$TOOL_NAME"
fi
