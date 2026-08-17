---
description: Turn ask-user desktop notification dialogs on or off
argument-hint: "[enable|disable|status]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sysnotif.sh:*)
---

Run the toggle and report its output verbatim:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sysnotif.sh" $ARGUMENTS
```

With no argument it prints the current state.

The setting lands in `~/.claude/ask-user.conf` as `ASK_USER_ENABLED`, which the
PreToolUse hook and `ask.sh` read on every call — it takes effect immediately in
sessions that are already running, no restart needed.

When disabled, permission prompts fall back to Claude Code's built-in terminal
prompt and choice questions go through `AskUserQuestion`. Nothing is lost; the
dialogs simply stop appearing on the desktop.
