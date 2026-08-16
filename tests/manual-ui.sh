#!/usr/bin/env bash
# Interactive checks for the notification backend. Needs a desktop session.
#
# Usage: bash tests/manual-ui.sh [confirm|choose|long|timeout|all]
#        ASK_USER_UI=zenity bash tests/manual-ui.sh all   # same run via zenity

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=../lib/config.sh
. "$ROOT/lib/config.sh"
# shellcheck source=../lib/ui.sh
. "$ROOT/lib/ui.sh"

WHAT="${1:-all}"

echo "backend: $(ui_backend)"
echo

t_confirm() {
    echo "→ confirm: click Allow or Block"
    if ui_confirm "Claude Code | manual test" "Bash: git push --force origin main"; then
        echo "   result: ALLOW"
    else
        echo "   result: BLOCK (or dismissed/timed out)"
    fi
    echo
}

t_choose() {
    echo "→ choose, short labels: expect words on the buttons"
    if ui_choose "Claude asks | manual test" "Ship it?" "Yes" "No" "Later"; then
        echo "   result: [$UI_ANSWER]"
    else
        echo "   result: <no answer>"
    fi
    echo
}

t_long() {
    echo "→ choose, long labels: expect numbered buttons + list in the body"
    if ui_choose "Claude asks | manual test" "Which migration strategy?" \
        "Migrate incrementally with backward compatibility" \
        "Single cutover during the night window" \
        "Dual-write for two weeks" \
        "Cancel"; then
        echo "   result: [$UI_ANSWER]"
    else
        echo "   result: <no answer>"
    fi
    echo
}

t_timeout() {
    echo "→ timeout: do NOT touch the dialog; it must disappear on its own"
    if ASK_USER_TIMEOUT=10 ui_choose "Claude asks | timeout test" \
        "Leave this alone for 10s" "Yes" "No"; then
        echo "   result: [$UI_ANSWER] (expected no answer)"
    else
        echo "   result: <no answer> OK"
    fi
    echo
}

case "$WHAT" in
    confirm) t_confirm ;;
    choose)  t_choose ;;
    long)    t_long ;;
    timeout) t_timeout ;;
    all)     t_confirm; t_choose; t_long; t_timeout ;;
    *)       echo "unknown: $WHAT"; exit 2 ;;
esac
