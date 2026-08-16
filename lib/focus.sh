#!/usr/bin/env bash
# focus.sh — work out whether the user is still looking at the Claude Code tab.
#
# Public API:
#   focus_has_display                  → exit 0 when a GUI session is present
#   focus_capture                      → record the Claude terminal window now
#   focus_terminal_focused             → exit 0 when that tab is still on screen
#
# focus_capture must run before any delay: it walks up /proc to find the
# terminal emulator rather than trusting xdotool getactivewindow, which returns
# the wrong window whenever the user was already in another app at start.

FOCUS_TERM_PID=""
FOCUS_WINS=""
FOCUS_WIN=""
FOCUS_BARE=""

focus_has_display() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

_focus_find_term_pid() {
    local pid=$$ ppid comm i
    for i in $(seq 1 12); do
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$ppid" ] || [ "$ppid" = "0" ] || [ "$ppid" = "1" ] && break
        comm=$(ps -o comm= -p "$ppid" 2>/dev/null | head -c 40 | tr -d ' ')
        case "$comm" in
            gnome-terminal*|xterm|konsole|alacritty|kitty|wezterm|tilix|terminator|foot|rxvt*)
                printf '%s\n' "$ppid"; return 0 ;;
        esac
        pid="$ppid"
    done
    return 1
}

focus_capture() {
    focus_has_display || return 1
    command -v xdotool >/dev/null 2>&1 || return 1

    FOCUS_TERM_PID=$(_focus_find_term_pid) || FOCUS_TERM_PID=""

    if [ -n "$FOCUS_TERM_PID" ]; then
        FOCUS_WINS=$(xdotool search --pid "$FOCUS_TERM_PID" 2>/dev/null) || FOCUS_WINS=""
    fi

    local active
    active=$(xdotool getactivewindow 2>/dev/null) || active=""

    if [ -n "$FOCUS_WINS" ]; then
        if printf '%s\n' "$FOCUS_WINS" | grep -qx "${active:-__none__}"; then
            FOCUS_WIN="$active"
        else
            # Terminal is not focused right now. Pick the window whose title
            # looks like Claude Code: its task title carries a Braille spinner
            # prefix, while a plain shell shows an ordinary prompt.
            local best="" wid title first
            while IFS= read -r wid; do
                [ -z "$wid" ] && continue
                title=$(xdotool getwindowname "$wid" 2>/dev/null) || title=""
                [ -z "$title" ] || [ "$title" = "Terminal" ] && continue
                first=$(printf '%s' "$title" | head -c 3 | od -An -tx1 | tr -d ' \n')
                case "$first" in
                    e2a090*|e2a082*|e2a081*|e2a084*|e2a088*|e2a0a0*)
                        FOCUS_WIN="$wid"; break ;;
                esac
                best="$wid"
            done <<< "$FOCUS_WINS"
            [ -z "$FOCUS_WIN" ] && FOCUS_WIN="${best:-}"
        fi
    else
        FOCUS_WIN="$active"
    fi

    if [ -n "$FOCUS_WIN" ]; then
        local raw
        raw=$(xdotool getwindowname "$FOCUS_WIN" 2>/dev/null) || raw=""
        FOCUS_BARE="${raw#* }"   # drop the leading Braille spinner glyph
    fi
    return 0
}

# Exit 0 when the captured Claude tab is still the one on screen.
# Errs towards "focused" so an undetectable setup keeps the inline flow.
focus_terminal_focused() {
    focus_has_display || return 0
    command -v xdotool >/dev/null 2>&1 || return 0
    [ -n "$FOCUS_WIN" ] || return 0

    local active cur
    active=$(xdotool getactivewindow 2>/dev/null) || active=""

    if [ -n "$FOCUS_WINS" ]; then
        if ! printf '%s\n' "$FOCUS_WINS" | grep -qx "${active:-__none__}"; then
            return 1   # active window is not our terminal at all
        fi
    elif [ -n "$active" ] && [ "$active" != "$FOCUS_WIN" ]; then
        return 1
    fi

    # Still inside the terminal, but possibly on a different tab — the window
    # title tracks whichever tab is visible.
    if [ -n "$FOCUS_BARE" ]; then
        cur=$(xdotool getwindowname "$FOCUS_WIN" 2>/dev/null) || cur=""
        cur="${cur#* }"
        [ -n "$cur" ] && [ "$cur" != "$FOCUS_BARE" ] && return 1
    fi
    return 0
}
