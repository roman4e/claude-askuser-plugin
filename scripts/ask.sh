#!/usr/bin/env bash
# ask.sh — Show a native choice dialog or fall back to text output.
# Usage: ask.sh [--delay N] "Question?" "Option A" "Option B" "Option C"
#   --delay N  sleep N seconds BEFORE checking focus (captures tab ID upfront)
# Output: chosen option text (stdout), or __USE_ASK_USER_QUESTION__ when the
#         question belongs in the terminal instead.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=../lib/config.sh
. "$ROOT/lib/config.sh"
# shellcheck source=../lib/ui.sh
. "$ROOT/lib/ui.sh"
# shellcheck source=../lib/focus.sh
. "$ROOT/lib/focus.sh"

# ── Parse --delay ─────────────────────────────────────────────────────────────
DELAY=0
if [ "${1:-}" = "--delay" ]; then
    DELAY="${2:?--delay requires a number}"
    shift 2
fi

QUESTION="${1:?Question required}"
shift
OPTIONS=("$@")

fallback_inline() {
    echo "__USE_ASK_USER_QUESTION__"
    echo "$QUESTION"
    printf '%s\n' "${OPTIONS[@]}"
    exit 0
}

# ── Remote Control bypass ─────────────────────────────────────────────────────
# When Claude Code runs in Remote Control mode the question must be delivered to
# the user's remote device (phone/desktop) via the native AskUserQuestion path.
# Do NOT pop a local dialog — the user is not at this machine.
_is_truthy() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}
if _is_truthy "${CLAUDE_CODE_REMOTE:-}" || [ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ]; then
    fallback_inline
fi

# ── Ensure xdotool ────────────────────────────────────────────────────────────
if ! command -v xdotool &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y xdotool >/dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y xdotool >/dev/null 2>&1
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm xdotool >/dev/null 2>&1
    fi
fi

focus_has_display || fallback_inline

# ── Capture the Claude tab identity BEFORE the delay ─────────────────────────
focus_capture || true

if [ "$DELAY" -gt 0 ]; then
    sleep "$DELAY"
fi

# Terminal still in front → the built-in AskUserQuestion is the better prompt.
if focus_terminal_focused; then
    fallback_inline
fi

WPATH=$(pwd | rev | cut -d'/' -f1-2 | rev)

# No answer (dismissed notification, timeout, or no usable backend) falls back
# to the inline prompt rather than failing — the user still gets asked.
# ui_choose answers through $UI_ANSWER; wrapping it in $(...) would strand its
# wait loop in a subshell where cleanup on timeout cannot reach it.
ui_choose "Claude asks | $WPATH" "$QUESTION" "${OPTIONS[@]}" || fallback_inline
[ -n "$UI_ANSWER" ] || fallback_inline
echo "$UI_ANSWER"
