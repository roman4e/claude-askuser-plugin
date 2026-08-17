#!/usr/bin/env bash
# config.sh — read ask-user settings.
#
# Lookup order per key: environment variable → config file → caller's default.
# The config file is grep-parsed rather than sourced, so a stray line in it can
# never execute code inside a permission hook.
#
# File: ~/.claude/ask-user.conf   (override path with $ASK_USER_CONF)
#   ASK_USER_UI=notify        # notify | zenity
#   ASK_USER_TIMEOUT=300      # seconds to wait for an answer; 0 = forever
#   ASK_USER_BTN_PAD=6        # em spaces around a numbered button label
#   ASK_USER_MAX_LABEL=10     # longest option text still shown on a button

cfg_path() {
    printf '%s\n' "${ASK_USER_CONF:-$HOME/.claude/ask-user.conf}"
}

# cfg_is_off VALUE — treat the usual spellings of "off" as false.
cfg_is_off() {
    case "${1:-}" in
        0|false|FALSE|False|no|NO|off|OFF|disabled) return 0 ;;
        *) return 1 ;;
    esac
}

# Exit 0 when the plugin is switched off (see /sysnotif).
cfg_disabled() {
    cfg_is_off "$(cfg_get ASK_USER_ENABLED 1)"
}

# Print the environment variable that says this session is driven from another
# device, or nothing. Local dialogs are useless then — Claude Code delivers the
# question to the remote device through its own flow instead.
#
# CLAUDE_CODE_BRIDGE_SESSION_ID is what Claude Code 2.1 actually sets when a
# session is bridged. The two CLAUDE_CODE_REMOTE* names are kept because older
# builds may still use them; CLAUDE_CODE_REMOTE_SESSION_ID does not appear in
# the 2.1 binary at all. Set ASK_USER_REMOTE_BYPASS=0 if a build turns out to
# set the bridge id for ordinary local sessions too.
cfg_remote_reason() {
    cfg_is_off "$(cfg_get ASK_USER_REMOTE_BYPASS 1)" && return 1
    case "${CLAUDE_CODE_REMOTE:-}" in
        1|true|TRUE|True|yes|YES|on|ON) printf 'CLAUDE_CODE_REMOTE\n'; return 0 ;;
    esac
    if [ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ]; then
        printf 'CLAUDE_CODE_REMOTE_SESSION_ID\n'; return 0
    fi
    if [ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ]; then
        printf 'CLAUDE_CODE_BRIDGE_SESSION_ID\n'; return 0
    fi
    return 1
}

cfg_is_remote() {
    cfg_remote_reason >/dev/null
}

# cfg_get KEY [DEFAULT]
cfg_get() {
    local key="$1" def="${2-}" line val
    local env_val="${!key-}"

    if [ -n "$env_val" ]; then
        printf '%s\n' "$env_val"
        return 0
    fi

    local conf
    conf=$(cfg_path)
    if [ -r "$conf" ]; then
        line=$(grep -m1 -E "^[[:space:]]*${key}[[:space:]]*=" "$conf" 2>/dev/null) || line=""
        if [ -n "$line" ]; then
            val="${line#*=}"
            val="${val%%#*}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            printf '%s\n' "$val"
            return 0
        fi
    fi

    printf '%s\n' "$def"
}
