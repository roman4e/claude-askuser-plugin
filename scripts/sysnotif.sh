#!/usr/bin/env bash
# sysnotif.sh — turn the ask-user desktop dialogs on or off.
#
# Usage: sysnotif.sh [enable|disable|status|toggle]
#
# Writes ASK_USER_ENABLED to the config file, which both the PreToolUse hook and
# ask.sh read on every invocation — the change applies to sessions that are
# already running, no restart involved.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=../lib/config.sh
. "$ROOT/lib/config.sh"
# shellcheck source=../lib/ui.sh
. "$ROOT/lib/ui.sh"

CONF=$(cfg_path)

cfg_set() {
    local key="$1" value="$2" tmp
    mkdir -p "$(dirname "$CONF")"
    if [ -f "$CONF" ] && grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONF"; then
        tmp=$(mktemp)
        sed -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$CONF" > "$tmp"
        cat "$tmp" > "$CONF"
        rm -f "$tmp"
    else
        [ -f "$CONF" ] || printf '# ask-user configuration\n' > "$CONF"
        printf '%s=%s\n' "$key" "$value" >> "$CONF"
    fi
}

status() {
    local enabled reason
    enabled=$(cfg_get ASK_USER_ENABLED 1)

    if cfg_is_off "$enabled"; then
        printf 'Desktop dialogs: OFF\n'
    else
        printf 'Desktop dialogs: ON\n'
    fi
    printf 'Config: %s\n' "$CONF"

    # Everything below explains why a dialog might not appear even when ON.
    reason=$(cfg_remote_reason || true)
    if [ -n "$reason" ]; then
        printf 'Suppressed: session is bridged to another device (%s)\n' "$reason"
    fi
    if ! focus_display_present; then
        printf 'Suppressed: no graphical session ($DISPLAY and $WAYLAND_DISPLAY are unset)\n'
    fi
    printf 'Backend: %s (ASK_USER_UI=%s)\n' "$(ui_backend)" "$(cfg_get ASK_USER_UI notify)"
    printf 'Timeout: %ss\n' "$(cfg_get ASK_USER_TIMEOUT 300)"
    command -v gdbus  >/dev/null 2>&1 || printf 'Missing: gdbus (notify backend unavailable)\n'
    command -v zenity >/dev/null 2>&1 || printf 'Missing: zenity (no fallback backend)\n'
    command -v xdotool >/dev/null 2>&1 || printf 'Missing: xdotool (focus detection disabled)\n'
}

# Kept local so lib/focus.sh does not have to be sourced just for one test.
focus_display_present() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

case "${1:-status}" in
    enable|on)
        cfg_set ASK_USER_ENABLED 1
        printf 'Desktop dialogs enabled.\n\n'
        status
        ;;
    disable|off)
        cfg_set ASK_USER_ENABLED 0
        printf 'Desktop dialogs disabled. Permission prompts stay in the terminal.\n\n'
        status
        ;;
    toggle)
        if cfg_disabled; then cfg_set ASK_USER_ENABLED 1; else cfg_set ASK_USER_ENABLED 0; fi
        status
        ;;
    status|'')
        status
        ;;
    *)
        printf 'Usage: sysnotif.sh [enable|disable|status|toggle]\n' >&2
        exit 2
        ;;
esac
