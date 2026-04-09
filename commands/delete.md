---
name: skill-git:delete
description: Permanently delete a registered skill from disk and remove it from config.json. Triggers on "delete skill", "remove skill", "uninstall skill", or "delete my <skill-name> skill".
argument-hint: [<skill-name>] [-a <agent>]
allowed-tools: Bash(bash *), AskUserQuestion
---

You are running `/skill-git:delete`. Follow these steps exactly.

## Tool Loading

Before doing any work, load all required tools in a **single** ToolSearch call:
```
select:TaskCreate,TaskUpdate,TaskList,AskUserQuestion
```
Do not issue multiple ToolSearch calls.

## Task Tracking

You MUST create a task for each item below and update each task's status as you progress (pending → in_progress → completed):

1. **Select skill** — parse arguments or present interactive list
2. **Confirm deletion** — show warning and wait for explicit user confirmation
3. **Execute deletion** — call sg-delete.sh --execute
4. **Report result** — display outcome to user

## Prelude

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS`

If STATUS is not `ok`:
- Re-examine RAW_ARGUMENTS — check if the user expressed an agent name or intent that can be semantically resolved (e.g. a typo or implicit default).
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is non-empty, suggest `/skill-git:init -a <agent>`.
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is empty, tell the user to run `/skill-git:init` first.
- If STATUS is `error`, display REASON as a plain-language error and stop.

Use AGENT, GLOBAL_BASE, and SKILLS_JSON from prelude output for all subsequent steps.

**Agent name in positional position:** If `$ARGUMENTS` contains a known agent name (claude, gemini, codex, openclaw) as a standalone positional token not preceded by `-a`, silently treat it as `-a <agent>`.

## Step 1 — Select Skill

**If a skill name is provided in `$ARGUMENTS`:**

Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-delete.sh" --info "<skill_name>" "<global_base>" '<skills_json>'
```

If `STATUS=not_found`, tell the user:
```
Skill "<skill_name>" is not registered.
Run /skill-git:list to see all registered skills.
```
Then stop.

Use the returned SKILL_PATH, SKILL_VERSION, IS_SYMLINK, IS_DIRTY, DIRTY_SUMMARY for the next step.

**If no skill name is provided:**

Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-delete.sh" --list "<global_base>" '<skills_json>'
```

Parse the output (SKILL_COUNT, SKILL_N_NAME, SKILL_N_VERSION, SKILL_N_PATH, SKILL_N_DIRTY).

If SKILL_COUNT=0, tell the user there are no registered skills and stop.

Use the AskUserQuestion tool:
- question: "Which skill do you want to delete?"
- header: "Registered Skills"
- options: one entry per skill (label: skill name, description: `<version> · <path>` — append ` · ⚠️ has uncommitted changes` if `SKILL_N_DIRTY=true`)
- multiSelect: false

After the user selects a skill, run `--info` for the selected skill name to get SKILL_PATH, SKILL_VERSION, IS_SYMLINK, IS_DIRTY, DIRTY_SUMMARY.

## Step 2 — Confirm Deletion

**If `IS_SYMLINK=true`**, display this note before the confirmation prompt:

```
🔗  <skill-name> is a symlink.
    Only the symlink will be removed. Source files will not be affected.
```

**If `IS_DIRTY=true`** (and not a symlink), display this warning before the confirmation prompt:

```
⚠️  <skill-name> has uncommitted changes:
    <DIRTY_SUMMARY>

These changes will be permanently lost.
```

Use the AskUserQuestion tool:
- question: "Permanently delete <skill-name>? This cannot be undone."
- header: "Confirm Delete"
- options:
  - label: `"Yes, delete permanently"` (if IS_SYMLINK=true: `"Yes, unlink"`), description: `"Remove symlink at <SKILL_PATH> and remove from config.json"` (if IS_SYMLINK=true) or `"Delete <SKILL_PATH> and remove from config.json · cannot be undone"` (if IS_DIRTY=true) or `"Delete <SKILL_PATH> and remove from config.json"` (otherwise)
  - label: "No, cancel", description: "Exit without making any changes"
- multiSelect: false

If the user selects "No, cancel", output:
```
Cancelled. No changes were made.
```
Then stop.

## Step 3 — Execute Deletion

Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-delete.sh" --execute "<skill_name>" "<agent>" "<global_base>" '<skills_json>'
```

## Step 4 — Report Result

**If `STATUS=ok` and `WAS_SYMLINK=true`:**
```
✅ <skill-name> unlinked.
   Symlink removed: <DELETED_PATH>
   Source files were not affected.
   Removed from config.json.
```

**If `STATUS=ok` and `PATH_EXISTED=true` and `WAS_SYMLINK=false`:**
```
✅ <skill-name> deleted.
   Path: <DELETED_PATH>
   Removed from config.json.
```

**If `STATUS=ok` and `PATH_EXISTED=false`:**
```
✅ <skill-name> removed from config.json.
   (Skill folder was already missing from disk.)
```

**If `STATUS=error`:**
```
❌ Failed to delete <skill-name>: <plain-language description of REASON>.
   No changes were made to config.json.
```
