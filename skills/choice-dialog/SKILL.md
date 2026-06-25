---
name: choice-dialog
description: This skill should be used when Claude needs to present the user with a choice between 2-4 options during task execution — choosing an approach, implementation strategy, configuration option, or any decision point where user preference is required before proceeding. Also use when the user asks Claude to "ask me", "let me choose", or "give me options".
version: 3.0.0
---

# Choice Dialog — Native Linux Dialog with Fallback

Use `${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh` to present choices. Never ask in plain text.

## Usage

```bash
RESULT=$("${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh" "Question?" "Option A" "Option B" "Option C")

# If the user might be away (e.g. after a long operation), add --delay N
# to capture the Claude Code tab ID first, then wait N seconds before checking:
RESULT=$("${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh" --delay 5 "Question?" "Option A" "Option B" "Option C")
```

## Behavior

The script auto-selects the best method:

| Condition | Method |
|-----------|--------|
| **Remote Control active** (`CLAUDE_CODE_REMOTE` truthy or `CLAUDE_CODE_REMOTE_SESSION_ID` set) | Returns `__USE_ASK_USER_QUESTION__` → use `AskUserQuestion` so the question is delivered to the user's remote device |
| No display (`$DISPLAY` unset) | Returns `__USE_ASK_USER_QUESTION__` → use `AskUserQuestion` |
| Display available + terminal **focused** | Returns `__USE_ASK_USER_QUESTION__` → use `AskUserQuestion` |
| Display available + terminal **not focused** | Shows native `zenity` popup |

Script auto-installs `xdotool` via apt/dnf/pacman if missing.

## Handling the result

```bash
RESULT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh" "Which approach?" \
    "SQLite (Recommended)" "PostgreSQL" "Redis")

if [ "${RESULT}" = "__USE_ASK_USER_QUESTION__" ]; then
    # use AskUserQuestion tool with the same options
    : # <-- call AskUserQuestion here
else
    echo "User chose: $RESULT"
fi
```

## Rules

- Always use this script — never ask inline in text
- 2-4 options per call
- First option = recommended (append `(Recommended)` to label)
- If script exits with code 1 → user cancelled → ask again or use default
- Do NOT add "Other" option — AskUserQuestion provides it automatically
