#!/usr/bin/env bash
# ui.sh — ask the user a question through desktop notification buttons,
# falling back to zenity.
#
# Public API:
#   ui_backend                        → "notify" | "zenity"
#   ui_confirm TITLE TEXT             → exit 0 allow, 1 block
#   ui_choose  TITLE QUESTION OPT...  → prints chosen option, exit 1 if none
#
# Requires lib/config.sh to be sourced first.
#
# Why raw D-Bus instead of notify-send: with --action, notify-send buffers its
# stdout until an action arrives, so --print-id never reaches us. If the wait
# then times out, the notification is left hanging on screen with no id to
# close it. Talking to org.freedesktop.Notifications directly gives us the id
# up front, and also drops the libnotify >= 0.8 requirement.

UI_ANSWER=""
UI_BUS="org.freedesktop.Notifications"
UI_OBJ="/org/freedesktop/Notifications"
UI_EM_SPACE=$' '

# ── pure helpers (covered by tests/test-ui.sh) ────────────────────────────────

# Escape text for a notification body (the daemon renders body-markup).
ui_escape() {
    local s="${1-}"
    # Backslash the ampersands: since bash 5.2 a bare & in the replacement
    # stands for the matched text, which would turn "&lt;" into "<lt;".
    s="${s//&/\&amp;}"
    s="${s//</\&lt;}"
    s="${s//>/\&gt;}"
    printf '%s\n' "$s"
}

# ui_pad TEXT COUNT — widen a button label with em spaces. A lone digit
# renders as a button too narrow to hit comfortably.
ui_pad() {
    local text="${1-}" n="${2:-0}" pad="" i
    for ((i = 0; i < n; i++)); do pad="${pad}${UI_EM_SPACE}"; done
    printf '%s%s%s\n' "$pad" "$text" "$pad"
}

# ui_build_choices MAXLEN PAD OPT... — decide how each option is presented.
# Short option  → its own text on the button.
# Long option   → a padded number on the button, full text listed in the body,
#                 because notification daemons truncate button labels hard
#                 (~10 chars in cinnamon, often to a single word).
# Sets UI_ACTIONS (key label key label ...) and UI_BODY (newline-joined list).
# The action key is always the option's index, so the caller maps the answer
# back to the untruncated option text.
ui_build_choices() {
    local maxlen="$1" pad="$2"; shift 2
    UI_ACTIONS=()
    UI_BODY=""
    local i=0 n=1 o
    for o in "$@"; do
        if [ "${#o}" -le "$maxlen" ]; then
            UI_ACTIONS+=("$i" "$o")
        else
            [ -n "$UI_BODY" ] && UI_BODY="${UI_BODY}"$'\n'
            UI_BODY="${UI_BODY}<b>${n}.</b> $(ui_escape "$o")"
            UI_ACTIONS+=("$i" "$(ui_pad "$n" "$pad")")
            n=$((n + 1))
        fi
        i=$((i + 1))
    done
}

# ui_pick_body QUESTION LIST — assemble the notification body.
ui_pick_body() {
    local q="${1-}" list="${2-}"
    if [ -n "$list" ]; then
        printf '%s\n%s\n' "$(ui_escape "$q")" "$list"
    else
        ui_escape "$q"
    fi
}

# ui_parse_id RAW — pull the notification id out of a gdbus reply.
# Must not simply strip non-digits: "uint32" carries a 32 of its own.
ui_parse_id() {
    printf '%s' "${1-}" | sed -nE 's/.*uint32 ([0-9]+).*/\1/p' | head -1
}

# ui_parse_action LOG ID — the action key the user clicked, empty if none.
ui_parse_action() {
    local log="$1" id="$2"
    sed -nE "s/.*ActionInvoked \(uint32 ${id}, '(.*)'\).*/\1/p" "$log" 2>/dev/null | head -1
}

# ui_parse_closed LOG ID — the close reason, empty if still open.
ui_parse_closed() {
    local log="$1" id="$2"
    sed -nE "s/.*NotificationClosed \(uint32 ${id}, uint32 ([0-9]+)\).*/\1/p" "$log" 2>/dev/null | head -1
}

# ── backend selection ─────────────────────────────────────────────────────────

ui_notify_capable() {
    command -v gdbus >/dev/null 2>&1 || return 1
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ] || return 1
    local caps
    caps=$(timeout 3 gdbus call --session --dest "$UI_BUS" --object-path "$UI_OBJ" \
        --method "$UI_BUS.GetCapabilities" 2>/dev/null) || return 1
    case "$caps" in
        *"'actions'"*) return 0 ;;
        *) return 1 ;;
    esac
}

ui_backend() {
    local want
    want=$(cfg_get ASK_USER_UI notify)
    if [ "$want" = "notify" ] && ui_notify_capable; then
        printf 'notify\n'
    else
        printf 'zenity\n'
    fi
}

# ── D-Bus dialog ──────────────────────────────────────────────────────────────

UI_ACTIVE_ID=""
UI_MON_PID=""
UI_LOG=""

# Close whatever is still on screen and stop the monitor. Runs on normal exit
# and on a kill: a PreToolUse hook that overruns its Claude Code timeout is
# terminated outright, and without this the notification would be orphaned with
# nobody left holding its id.
ui_teardown() {
    if [ -n "$UI_MON_PID" ]; then
        kill "$UI_MON_PID" 2>/dev/null || true
        wait "$UI_MON_PID" 2>/dev/null || true
        UI_MON_PID=""
    fi
    if [ -n "$UI_ACTIVE_ID" ]; then
        timeout 3 gdbus call --session --dest "$UI_BUS" --object-path "$UI_OBJ" \
            --method "$UI_BUS.CloseNotification" "$UI_ACTIVE_ID" >/dev/null 2>&1 || true
        UI_ACTIVE_ID=""
    fi
    if [ -n "$UI_LOG" ]; then
        rm -f "$UI_LOG"
        UI_LOG=""
    fi
}
# A signal trap alone is not enough: bash runs the handler and then resumes the
# loop, so the script would keep waiting on a notification it just closed. The
# signal handler has to end the process itself.
ui_on_signal() {
    ui_teardown
    trap - EXIT
    exit 143
}
trap ui_teardown EXIT
trap ui_on_signal INT TERM HUP

# ui_dbus_ask SUMMARY BODY KEY LABEL [KEY LABEL ...]
# Sets UI_ANSWER to the chosen action key; exit 1 when the user dismissed the
# dialog or the wait timed out. Always leaves the screen clean.
#
# The answer travels through a global rather than stdout on purpose. Running
# this inside $(...) would put the polling loop in a subshell, where the
# notification id is invisible to the parent's trap and a TERM aimed at the
# parent never reaches the loop — the exact case of Claude Code killing a hook
# that overran its timeout.
ui_dbus_ask() {
    UI_ANSWER=""
    local summary="$1" body="$2"; shift 2

    local acts="" key label
    while [ "$#" -ge 2 ]; do
        key=$1; label=$2; shift 2
        [ -n "$acts" ] && acts="$acts, "
        acts="$acts$(ui_gvariant_str "$key"), $(ui_gvariant_str "$label")"
    done

    local timeout_s
    timeout_s=$(cfg_get ASK_USER_TIMEOUT 300)
    [ "$timeout_s" -gt 0 ] 2>/dev/null || timeout_s=86400

    UI_LOG=$(mktemp) || return 1

    gdbus monitor --session --dest "$UI_BUS" > "$UI_LOG" 2>/dev/null &
    UI_MON_PID=$!
    # gdbus monitor needs to be attached before Notify fires, or the reply can
    # beat the subscription and the click is never seen.
    sleep 0.4

    local raw id
    raw=$(timeout 5 gdbus call --session --dest "$UI_BUS" --object-path "$UI_OBJ" \
        --method "$UI_BUS.Notify" \
        "Claude Code" 0 "dialog-question" "$summary" "$body" \
        "[$acts]" "{'urgency': <byte 2>}" 0 2>/dev/null) || raw=""
    id=$(ui_parse_id "$raw")

    if [ -z "$id" ]; then
        ui_teardown
        return 1
    fi
    UI_ACTIVE_ID="$id"

    local answer="" closed="" waited=0
    while [ "$waited" -lt "$((timeout_s * 5))" ]; do
        answer=$(ui_parse_action "$UI_LOG" "$id")
        [ -n "$answer" ] && break
        closed=$(ui_parse_closed "$UI_LOG" "$id")
        if [ -n "$closed" ]; then
            # ActionInvoked and NotificationClosed arrive back to back and can
            # land in the log out of order. Give the action a moment to show up
            # before treating the close as a dismissal.
            sleep 0.3
            answer=$(ui_parse_action "$UI_LOG" "$id")
            break
        fi
        sleep 0.2
        waited=$((waited + 1))
    done

    # Teardown closes the notification; a dialog the user already answered or
    # dismissed is gone, so this only matters on timeout.
    ui_teardown

    [ -n "$answer" ] || return 1
    UI_ANSWER="$answer"
}

# Quote a string for a GVariant literal.
ui_gvariant_str() {
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\'/\\\'}"
    printf "'%s'" "$s"
}

# ── public API ────────────────────────────────────────────────────────────────

# ui_confirm TITLE TEXT — permission prompt.
#   0  the user pressed Allow
#   1  the user pressed Block
#   2  no answer: dismissed, timed out, or no backend could show the dialog
#
# Callers must treat 2 as "could not ask" and step aside, never as a denial.
# Collapsing 2 into 1 is what let a suppressed notification — a locked screen or
# do-not-disturb closes it instantly — block every single tool call.
ui_confirm() {
    local title="$1" text="$2"

    if [ "$(ui_backend)" = "notify" ]; then
        ui_dbus_ask "$title" "$(ui_escape "$text")" allow "Allow" block "Block" || return 2
        case "$UI_ANSWER" in
            allow) return 0 ;;
            block) return 1 ;;
            *) return 2 ;;
        esac
    fi

    command -v zenity >/dev/null 2>&1 || return 2
    local rc=0
    zenity --question \
        --title="$title" \
        --text="$text" \
        --ok-label="Allow" \
        --cancel-label="Block" \
        --width=460 \
        2>/dev/null || rc=$?
    case "$rc" in
        0) return 0 ;;
        1) return 1 ;;   # Cancel button, i.e. Block
        *) return 2 ;;   # zenity could not start, was killed, or timed out
    esac
}

# ui_choose TITLE QUESTION OPT... — sets UI_ANSWER to the chosen option,
# verbatim and untruncated. Exit 1 when the user gave no answer.
# Call it directly, never as $(ui_choose ...) — see ui_dbus_ask.
ui_choose() {
    local title="$1" question="$2"; shift 2
    local options=("$@")
    UI_ANSWER=""

    if [ "$(ui_backend)" = "notify" ]; then
        local pad maxlen
        pad=$(cfg_get ASK_USER_BTN_PAD 6)
        maxlen=$(cfg_get ASK_USER_MAX_LABEL 10)

        ui_build_choices "$maxlen" "$pad" "${options[@]}"
        local body
        body=$(ui_pick_body "$question" "$UI_BODY")

        ui_dbus_ask "$title" "$body" "${UI_ACTIONS[@]}" || return 1
        case "$UI_ANSWER" in
            ''|*[!0-9]*) UI_ANSWER=""; return 1 ;;
        esac
        if [ "$UI_ANSWER" -ge "${#options[@]}" ]; then
            UI_ANSWER=""
            return 1
        fi
        UI_ANSWER="${options[$UI_ANSWER]}"
        return 0
    fi

    command -v zenity >/dev/null 2>&1 || return 1
    UI_ANSWER=$(zenity --list \
        --title="$title" \
        --text="$question" \
        --column="Option" \
        --hide-header \
        --width=420 --height=340 \
        "${options[@]}" 2>/dev/null) || { UI_ANSWER=""; return 1; }
    [ -n "$UI_ANSWER" ]
}
