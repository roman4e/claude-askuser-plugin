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
