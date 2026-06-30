#!/usr/bin/env bash
# ask.sh — Show native choice dialog or fall back to text output.
# Usage: ask.sh [--delay N] "Question?" "Option A" "Option B" "Option C"
#   --delay N  sleep N seconds BEFORE checking focus (captures tab ID upfront)
# Output: chosen option text (stdout), exit 1 if cancelled.

set -euo pipefail

# ── Parse --delay ─────────────────────────────────────────────────────────────
DELAY=0
if [ "${1:-}" = "--delay" ]; then
    DELAY="${2:?--delay requires a number}"
    shift 2
fi

QUESTION="${1:?Question required}"
shift
OPTIONS=("$@")

# ── Remote Control bypass ─────────────────────────────────────────────────────
# When Claude Code runs in Remote Control mode the question must be delivered to
# the user's remote device (phone/desktop) via the native AskUserQuestion path.
# Do NOT pop a local zenity dialog — the user is not at this machine.
_is_truthy() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}
if _is_truthy "${CLAUDE_CODE_REMOTE:-}" || [ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ]; then
    echo "__USE_ASK_USER_QUESTION__"
    echo "$QUESTION"
    printf '%s\n' "${OPTIONS[@]}"
    exit 0
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

# ── Detect GUI ────────────────────────────────────────────────────────────────
HAS_DISPLAY=0
[ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] && HAS_DISPLAY=1

# ── Find our terminal emulator window via process tree ───────────────────────
# Walking up /proc avoids the "user already in another app at script start"
# bug where xdotool getactivewindow would capture the wrong (non-terminal) window.
_TERM_PID=""
_pid=$$
for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    _ppid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
    [ -z "$_ppid" ] || [ "$_ppid" = "0" ] || [ "$_ppid" = "1" ] && break
    _comm=$(ps -o comm= -p "$_ppid" 2>/dev/null | head -c 40 | tr -d ' ')
    case "${_comm}" in
        gnome-terminal*|xterm|konsole|alacritty|kitty|wezterm|tilix|terminator|foot|rxvt*)
            _TERM_PID="$_ppid"; break ;;
    esac
    _pid="$_ppid"
done

# ── Capture Claude tab identity BEFORE delay ─────────────────────────────────
# CLAUDE_WIN:  the gnome-terminal X window that shows the active tab title.
#              Found via process tree so it's correct even when user is already
#              in another app at the time ask.sh starts.
# GTERM_WINS:  newline-separated list of all terminal X windows (for "in-terminal" check).
# CLAUDE_BARE: window title with first word stripped (removes Claude spinner ⠐/⠂/…).
CLAUDE_WIN=""
CLAUDE_BARE=""
GTERM_WINS=""

if [ "$HAS_DISPLAY" -eq 1 ] && command -v xdotool &>/dev/null; then
    if [ -n "$_TERM_PID" ]; then
        GTERM_WINS=$(xdotool search --pid "$_TERM_PID" 2>/dev/null) || true
    fi

    ACTIVE_NOW=$(xdotool getactivewindow 2>/dev/null) || true

    if [ -n "$GTERM_WINS" ]; then
        if echo "$GTERM_WINS" | grep -qx "${ACTIVE_NOW:-__none__}"; then
            # Terminal IS currently focused — active window IS our terminal window
            CLAUDE_WIN="$ACTIVE_NOW"
        else
            # Terminal is NOT focused right now (user already in another app).
            # Pick the terminal window with the richest title (Claude task title
            # has a Braille spinner prefix; other shells have a plain prompt).
            # We scan all terminal windows and prefer the one whose title differs
            # from a plain "Terminal" or empty string.
            _best=""
            _best_title=""
            while IFS= read -r _wid; do
                [ -z "$_wid" ] && continue
                _t=$(xdotool getwindowname "$_wid" 2>/dev/null) || true
                [ -z "$_t" ] || [ "$_t" = "Terminal" ] && continue
                # Prefer windows with Braille prefix (Claude Code spinner)
                _first_byte=$(printf '%s' "$_t" | head -c 3 | od -An -tx1 | tr -d ' \n')
                case "$_first_byte" in
                    e2a090*|e2a082*|e2a081*|e2a084*|e2a088*|e2a0a0*)
                        CLAUDE_WIN="$_wid"; _best_title="$_t"; break ;;
                esac
                _best="$_wid"; _best_title="$_t"
            done <<< "$GTERM_WINS"
            [ -z "$CLAUDE_WIN" ] && CLAUDE_WIN="${_best:-}"
        fi
    else
        # No terminal PID found — fall back to active window
        CLAUDE_WIN="$ACTIVE_NOW"
    fi

    if [ -n "$CLAUDE_WIN" ]; then
        _raw=$(xdotool getwindowname "$CLAUDE_WIN" 2>/dev/null) || true
        CLAUDE_BARE="${_raw#* }"   # strip first word (Braille spinner)
    fi
fi

# ── Wait ──────────────────────────────────────────────────────────────────────
if [ "$DELAY" -gt 0 ]; then
    sleep "$DELAY"
fi

# ── Check focus after delay ───────────────────────────────────────────────────
TERMINAL_FOCUSED=1  # default: show inline question
if [ "$HAS_DISPLAY" -eq 1 ] && command -v xdotool &>/dev/null && [ -n "$CLAUDE_WIN" ]; then
    ACTIVE=$(xdotool getactivewindow 2>/dev/null) || true

    if [ -n "$GTERM_WINS" ]; then
        if ! echo "$GTERM_WINS" | grep -qx "${ACTIVE:-__none__}"; then
            # Active window is not gnome-terminal at all → user is in another app
            TERMINAL_FOCUSED=0
        elif [ -n "$CLAUDE_BARE" ]; then
            # User is in gnome-terminal but might be in a different tab:
            # the active-window title reflects the currently visible tab.
            _cur_raw=$(xdotool getwindowname "$CLAUDE_WIN" 2>/dev/null) || true
            _cur_bare="${_cur_raw#* }"
            if [ -n "$_cur_bare" ] && [ "$_cur_bare" != "$CLAUDE_BARE" ]; then
                TERMINAL_FOCUSED=0
            fi
        fi
    else
        # Fallback (no GTERM_WINS): compare window IDs
        if [ -n "$ACTIVE" ] && [ "$ACTIVE" != "$CLAUDE_WIN" ]; then
            TERMINAL_FOCUSED=0
        elif [ -n "$CLAUDE_BARE" ]; then
            _cur_raw=$(xdotool getwindowname "$CLAUDE_WIN" 2>/dev/null) || true
            _cur_bare="${_cur_raw#* }"
            if [ -n "$_cur_bare" ] && [ "$_cur_bare" != "$CLAUDE_BARE" ]; then
                TERMINAL_FOCUSED=0
            fi
        fi
    fi
fi

USE_ZENITY=0
[ "$HAS_DISPLAY" -eq 1 ] && [ "$TERMINAL_FOCUSED" -eq 0 ] && USE_ZENITY=1

if [ "$USE_ZENITY" -eq 1 ] && command -v zenity &>/dev/null; then
    _WPATH=$(pwd | rev | cut -d'/' -f1-2 | rev)
    ANSWER=$(zenity --list \
        --title="Claude asks | $_WPATH" \
        --text="$QUESTION" \
        --column="Option" \
        --hide-header \
        --width=420 --height=340 \
        "${OPTIONS[@]}" 2>/dev/null) || exit 1
    echo "$ANSWER"
else
    echo "__USE_ASK_USER_QUESTION__"
    echo "$QUESTION"
    printf '%s\n' "${OPTIONS[@]}"
fi
