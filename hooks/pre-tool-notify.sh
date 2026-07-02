#!/usr/bin/env bash
# PreToolUse hook: zenity confirmation when user is away from terminal.
# Terminal focused → silent pass-through (built-in prompt handles approval).
# User in another app → zenity popup with Allow/Block.

set -euo pipefail

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
