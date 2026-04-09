---
name: skill-git:list
description: List all registered skills with their versions and descriptions. Triggers on "list my skills", "show skills", "what skills do I have", "skill list", or "list skill-git skills".
argument-hint: [-a <agent>] [-v] [<filter>]
allowed-tools: Bash(bash *)
---

You are running `/skill-git:list`. Follow these steps exactly.

All output shown to the user must be in English.

## Prelude

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS`

If STATUS is not `ok`:
- Re-examine RAW_ARGUMENTS — check if the user expressed an agent name or intent that can be semantically resolved (e.g. a typo or implicit default).
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is non-empty, suggest `/skill-git:init -a <agent>`.
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is empty, tell the user to run `/skill-git:init` first.
- If STATUS is `error`, display REASON as a plain-language error and stop.

Use AGENT, GLOBAL_BASE, and SKILLS_JSON from prelude output.

**Agent name in positional position:** If `$ARGUMENTS` contains a known agent name (claude, gemini, codex, openclaw) as a standalone positional token not preceded by `-a`, silently treat it as `-a <agent>`.

## Step 1 — List Skills

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-list.sh" "<global_base>" '<skills_json>' $ARGUMENTS
```

Display the script output to the user.
