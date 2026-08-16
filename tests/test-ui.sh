#!/usr/bin/env bash
# Automated tests for the pure logic in lib/ui.sh and lib/config.sh.
# No GUI required — notification delivery is covered by tests/manual-ui.sh.
#
# Usage: bash tests/test-ui.sh

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")

# shellcheck source=../lib/config.sh
. "$ROOT/lib/config.sh"
# shellcheck source=../lib/ui.sh
. "$ROOT/lib/ui.sh"

PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' \
            "$name" "$expected" "$actual"
    fi
}

EM=$' '

# ── cfg_get ───────────────────────────────────────────────────────────────────
CONF=$(mktemp)
cat > "$CONF" <<'EOF'
# comment line
ASK_USER_UI=zenity
ASK_USER_TIMEOUT = 42
ASK_USER_BTN_PAD=3   # trailing comment
EOF
export ASK_USER_CONF="$CONF"

check "cfg_get reads plain value"        "zenity" "$(cfg_get ASK_USER_UI notify)"
check "cfg_get trims spaces around ="    "42"     "$(cfg_get ASK_USER_TIMEOUT 300)"
check "cfg_get strips inline comment"    "3"      "$(cfg_get ASK_USER_BTN_PAD 6)"
check "cfg_get falls back to default"    "300"    "$(cfg_get ASK_USER_MISSING 300)"
check "cfg_get ignores commented keys"   "on"     "$(cfg_get comment on)"

ASK_USER_UI=notify \
    check "cfg_get env overrides file" "notify" "$(ASK_USER_UI=notify cfg_get ASK_USER_UI zenity)"

rm -f "$CONF"
unset ASK_USER_CONF

# ── ui_escape ─────────────────────────────────────────────────────────────────
check "ui_escape ampersand" "a &amp; b"        "$(ui_escape 'a & b')"
check "ui_escape angles"    "&lt;tag&gt;"      "$(ui_escape '<tag>')"
check "ui_escape order"     "&amp;lt;"         "$(ui_escape '&lt;')"
check "ui_escape plain"     "nothing here"     "$(ui_escape 'nothing here')"

# ── ui_pad ────────────────────────────────────────────────────────────────────
check "ui_pad wraps in em spaces" "${EM}${EM}1${EM}${EM}" "$(ui_pad 1 2)"
check "ui_pad zero is identity"   "1"                     "$(ui_pad 1 0)"

# ── ui_build_choices ──────────────────────────────────────────────────────────
# All labels short → every option becomes a worded button, body stays empty.
ui_build_choices 10 2 "Yes" "No" "Cancel"
check "short: no body lines"   ""                   "$UI_BODY"
check "short: action count"    "6"                  "${#UI_ACTIONS[@]}"
check "short: key 0"           "0"                  "${UI_ACTIONS[0]}"
check "short: label 0 unpadded" "Yes"               "${UI_ACTIONS[1]}"
check "short: key 2"           "2"                  "${UI_ACTIONS[4]}"
check "short: label 2"         "Cancel"             "${UI_ACTIONS[5]}"

# All labels long → numbered buttons, every option listed in the body.
ui_build_choices 10 2 "Migrate incrementally" "Cutover in one night"
check "long: action count"     "4"                  "${#UI_ACTIONS[@]}"
check "long: key 0"            "0"                  "${UI_ACTIONS[0]}"
check "long: label 0 padded"   "${EM}${EM}1${EM}${EM}" "${UI_ACTIONS[1]}"
check "long: label 1 padded"   "${EM}${EM}2${EM}${EM}" "${UI_ACTIONS[3]}"
check "long: body lists both"  "<b>1.</b> Migrate incrementally
<b>2.</b> Cutover in one night" "$UI_BODY"

# Mixed → long ones numbered and listed, short one keeps its word.
ui_build_choices 10 2 "Migrate incrementally" "Cancel" "Cutover in one night"
check "mixed: action count"    "6"                  "${#UI_ACTIONS[@]}"
check "mixed: long is 1"       "${EM}${EM}1${EM}${EM}" "${UI_ACTIONS[1]}"
check "mixed: short is worded" "Cancel"             "${UI_ACTIONS[3]}"
check "mixed: numbering skips short" "${EM}${EM}2${EM}${EM}" "${UI_ACTIONS[5]}"
check "mixed: keys are indices" "0 1 2" \
    "${UI_ACTIONS[0]} ${UI_ACTIONS[2]} ${UI_ACTIONS[4]}"
check "mixed: body only long" "<b>1.</b> Migrate incrementally
<b>2.</b> Cutover in one night" "$UI_BODY"

# Markup in an option must be escaped in the body.
ui_build_choices 5 2 "Use <b>bold</b> & co"
check "escape: body escaped" "<b>1.</b> Use &lt;b&gt;bold&lt;/b&gt; &amp; co" "$UI_BODY"

# A short label is NOT escaped for the body but must still be safe on a button;
# button labels are plain text (no markup), so they stay verbatim.
ui_build_choices 10 0 "a & b"
check "escape: short label verbatim" "a & b" "${UI_ACTIONS[1]}"

# ── ui_pick_body ──────────────────────────────────────────────────────────────
check "ui_pick_body joins question and list" "Which one?
<b>1.</b> Migrate incrementally" "$(ui_pick_body "Which one?" "<b>1.</b> Migrate incrementally")"
check "ui_pick_body escapes question" "a &amp; b" "$(ui_pick_body "a & b" "")"

# ── ui_parse_signal ───────────────────────────────────────────────────────────
LOG=$(mktemp)
cat > "$LOG" <<'EOF'
/org/freedesktop/Notifications: org.freedesktop.Notifications.NotificationClosed (uint32 11, uint32 2)
/org/freedesktop/Notifications: org.freedesktop.Notifications.ActionInvoked (uint32 11, '1')
EOF
check "action wins over close in same log" "1" "$(ui_parse_action "$LOG" 11)"
check "action ignores other ids"           ""  "$(ui_parse_action "$LOG" 12)"
check "close detected"                     "2" "$(ui_parse_closed "$LOG" 11)"
rm -f "$LOG"

# ── ui_parse_id ───────────────────────────────────────────────────────────────
check "ui_parse_id skips the uint32 literal" "6" "$(ui_parse_id '(uint32 6,)')"
check "ui_parse_id multi digit"            "326" "$(ui_parse_id '(uint32 326,)')"
check "ui_parse_id on garbage"               "" "$(ui_parse_id 'error: no such service')"

# ── ui_choose / ui_confirm plumbing ───────────────────────────────────────────
# Stub the dialog so the answer path is exercised without a desktop session.
ui_backend() { printf 'notify\n'; }
STUB_KEY=""
ui_dbus_ask() {
    UI_ANSWER=""
    [ -n "$STUB_KEY" ] || return 1
    UI_ANSWER="$STUB_KEY"
}

OPTS_LONG=("Migrate incrementally with backward compatibility" "Cancel")

STUB_KEY=0
ui_choose "t" "q" "${OPTS_LONG[@]}"
check "choose maps key to full option text" \
    "Migrate incrementally with backward compatibility" "$UI_ANSWER"

STUB_KEY=1
ui_choose "t" "q" "${OPTS_LONG[@]}"
check "choose maps second key" "Cancel" "$UI_ANSWER"

STUB_KEY=7
if ui_choose "t" "q" "${OPTS_LONG[@]}"; then rc=0; else rc=1; fi
check "choose rejects out-of-range key" "1 " "$rc $UI_ANSWER"

STUB_KEY="bogus"
if ui_choose "t" "q" "${OPTS_LONG[@]}"; then rc=0; else rc=1; fi
check "choose rejects non-numeric key" "1 " "$rc $UI_ANSWER"

STUB_KEY=""
if ui_choose "t" "q" "${OPTS_LONG[@]}"; then rc=0; else rc=1; fi
check "choose reports no answer" "1 " "$rc $UI_ANSWER"

STUB_KEY="allow"
if ui_confirm "t" "Bash: ls"; then rc=0; else rc=1; fi
check "confirm allow" "0" "$rc"

STUB_KEY="block"
if ui_confirm "t" "Bash: ls"; then rc=0; else rc=1; fi
check "confirm block" "1" "$rc"

STUB_KEY=""
if ui_confirm "t" "Bash: ls"; then rc=0; else rc=1; fi
check "confirm dismissed blocks" "1" "$rc"

# ── summary ───────────────────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
