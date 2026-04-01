---
name: skill-git:revert
description: Roll back one or more skills to a previous version. Use when the user wants to undo skill changes, discard uncommitted edits, restore an older version, or recover from a bad commit. Triggers on "revert my skill", "roll back skill", "restore skill to v1.0.0", "undo my skill changes", or similar.
argument-hint: [<skill-name>] [-a <agent>]
allowed-tools: Bash(bash *), AskUserQuestion
---

You are running `/skill-git:revert`. Follow these steps exactly.

## Task Tracking

You MUST create a task for each item below and update each task's status as you progress (pending → in_progress → completed):

1. **Select skill(s)** — parse arguments or list registered skills for the user to choose
2. **Determine target version** — detect dirty/clean state, resolve target tag for each skill
3. **Analyze changes** — summarize what will be undone in plain language
4. **Confirm with user** — show warning prompt and wait for explicit confirmation
5. **Execute revert** — backup, reset, delete tags, update config.json
6. **Report result** — display success/failure for each skill

## Prelude

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS`

If STATUS is not `ok`:
- Re-examine RAW_ARGUMENTS — check if the user expressed an agent name or intent that can be semantically resolved (e.g. a typo, a paraphrase, or an implicit default).
- If you can determine intent, note the resolution (e.g. "Treating `-a cluade` as `claude`") and proceed.
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is non-empty, suggest the user run `/skill-git:init -a <agent>`, or mention which agents are already available.
- If STATUS is `error`, display REASON as a plain-language error and stop.
- If intent cannot be resolved, display a clear error and stop.

Use AGENT, GLOBAL_BASE, and SKILLS_JSON from prelude output for all subsequent steps. The `skills` map referred to throughout this document is the parsed content of SKILLS_JSON.

**Agent name in positional position:** If `$ARGUMENTS` contains a known agent name (claude, gemini, codex, openclaw) as a standalone positional token not preceded by `-a`, silently treat it as `-a <agent>`: override AGENT, re-read GLOBAL_BASE and SKILLS_JSON from `~/.skill-git/config.json` for that agent. Do not pass it to any skill-name parsing steps.

## Step 1 — Select Skill(s)

Parse `$ARGUMENTS` for any skill name(s) or version hints expressed in natural language. Accepted forms:
- No argument → list all registered skills and ask the user which one(s) to revert
- One or more skill names → proceed with those skills
- A version tag (e.g. `v1.0.1`) → use as the target version (resolve skill interactively if ambiguous)

If no skill is specified, display the registered skills list, then use the AskUserQuestion tool:
- question: "Which skill(s) do you want to revert?"
- header: "Skills"
- options: build dynamically from registered skills (label: skill name, description: "current: <version>"). Include up to 3 individual skills plus an "All skills" option as the 4th. If there are more than 3 skills, choose the most recently changed 3. The user may also type skill names or numbers in Other.
- multiSelect: true (allow selecting multiple individual skills)

Resolve the selection to one or more skill names and paths. If "All skills" is selected, use all registered skills. Validate each name exists in the `skills` map; if not, tell the user and stop.

## Step 2 — Detect Scenario and Determine Target Version

For each selected skill, run:

```bash
git -C <path> status --porcelain
```

Then determine the scenario and target version:

**Scenario A — Dirty working tree (uncommitted changes exist):**
- If the user did NOT specify a version → target = current tag (discard uncommitted changes only, stay at current version)
- If the user specified an older version → target = that version (discard uncommitted changes AND hard-reset to the specified version)

**Scenario B — Clean working tree (no uncommitted changes):**
- If the user did NOT specify a version → target = the tag immediately before the current one (default back one version)
  - Retrieve the previous tag: `git -C <path> tag -l "v*" --sort=-version:refname | sed -n '2p'`
  - If no previous tag exists, tell the user there is no earlier version to revert to, and stop.
  - Display: `[note] No version specified — defaulting to the previous tag <previous-tag>.`
- If the user specified a version → target = that version

For each skill, check that the target tag exists:

```bash
git -C <path> tag -l "<target-tag>"
```

If not found, tell the user the tag does not exist and stop.

## Step 3 — Analyze Changes

For each skill, collect the information needed to describe what will be undone. Do NOT execute any changes yet.

**For Scenario A (discard uncommitted changes only):**

```bash
git -C <path> diff HEAD
git -C <path> status --short
```

**For Scenario A with older version target OR Scenario B:**

```bash
git -C <path> diff <target-tag> HEAD
git -C <path> log --oneline <target-tag>..HEAD
```

Also list all version tags that will be permanently deleted (tags newer than the target):

```bash
git -C <path> tag -l "v*" --sort=version:refname | awk -v target="<target-tag>" 'found {print} $0==target{found=1}'
```

Read each diff and write a **2–3 sentence natural language summary** of what will be undone — describe the rules removed, behaviors restored, or edits discarded. Do not mention git commands or commit hashes.

## Step 4 — Show Confirmation Prompt

Display a confirmation for all selected skills in a single message. Choose the warning level based on the scenario:

---

**Scenario A — Discard uncommitted changes only:**

Display:
```
⚠️  The following uncommitted changes will be permanently discarded:

  <skill-name>    staying at <current-version>
  <2-3 sentence description of what will be lost>

This cannot be undone.
```

Then use the AskUserQuestion tool:
- question: "Permanently discard these uncommitted changes in <skill-name>?"
- header: "Confirm"
- options:
  - label: "Yes, discard changes", description: "Restore <skill-name> to <current-version> (cannot be undone)"
  - label: "No, cancel", description: "Exit without making any changes"
- multiSelect: false

---

**Scenario A with older version target — Discard uncommitted AND hard-reset:**

Display:
```
🚨  WARNING: Two destructive operations will be performed on <skill-name>:

  1. All uncommitted changes will be permanently discarded.
  2. The following committed versions will be permanently deleted:
       <version-1>, <version-2>, ...

  Reverting to: <target-version>

  What will be removed:
  <2-3 sentence description of what will be undone>

This cannot be undone. These versions will be gone forever.
```

Then use the AskUserQuestion tool:
- question: "Perform both destructive operations on <skill-name>? This cannot be undone."
- header: "Confirm"
- options:
  - label: "Yes, revert to <target-version>", description: "Discard uncommitted changes AND permanently delete the listed versions"
  - label: "No, cancel", description: "Exit without making any changes"
- multiSelect: false

---

**Scenario B — Single version back (default):**

Display:
```
The following changes will be permanently removed from <skill-name>:

  <current-version> → <target-version>
  Deleting tag: <current-version>

  What will be removed:
  <2-3 sentence description of what will be undone>

This cannot be undone.
```

Then use the AskUserQuestion tool:
- question: "Permanently remove these changes from <skill-name>?"
- header: "Confirm"
- options:
  - label: "Yes, revert to <target-version>", description: "Delete tag <current-version> and reset to <target-version> (cannot be undone)"
  - label: "No, cancel", description: "Exit without making any changes"
- multiSelect: false

---

**Scenario B — Multi-version jump:**

Display:
```
🚨  WARNING: Multiple committed versions of <skill-name> will be permanently deleted:

  Reverting: <current-version> → <target-version>
  Versions to be deleted: <v-1>, <v-2>, <v-3>, ...

  What will be removed:
  <2-3 sentence description of what will be undone across all deleted versions>

This cannot be undone. All listed versions will be gone forever.
```

Then use the AskUserQuestion tool:
- question: "Permanently delete these versions of <skill-name>? This cannot be undone."
- header: "Confirm"
- options:
  - label: "Yes, delete versions", description: "Revert from <current-version> to <target-version>, permanently deleting all listed tags"
  - label: "No, cancel", description: "Exit without making any changes"
- multiSelect: false

---

If the user does not confirm, tell them nothing was changed and stop.

## Step 5 — Execute

Process each confirmed skill in order.

**5a. Backup**

Before touching anything, create a timestamped backup:

```bash
cp -r <path> /tmp/skill-git-backup-<skill-name>-$(date +%s)
```

**5b. Reset**

**Scenario A — Discard uncommitted changes only:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<path>" reset --hard HEAD
```

**All other cases (hard-reset to target tag):**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<path>" reset --hard <target-tag>
```

If the reset command fails, print the error message in plain language (no raw git output), restore from the backup, and stop. Do not proceed to tag deletion.

**5c. Delete Newer Tags**

For every version tag newer than the target (collected in Step 3), delete it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<path>" tag -d <tag>
```

If any tag deletion fails, note it in the final report but continue with the remaining deletions.

**5d. Update config.json**

Update the version for each successfully reverted skill:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-config-set.sh" "<agent>" "<skill_name>" "<target-version>"
```

Skip this update if the reset failed for that skill.

## Step 6 — Report

```
✅ <skill-name>    reverted to <target-version>
✅ <skill-name>    reverted to <target-version>
❌ <skill-name>    failed — <plain-language reason>

[skill-git] Done. Run /skill-git:commit to record new changes going forward.
```
