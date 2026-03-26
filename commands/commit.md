---
name: skill-git:commit
description: Use when the user wants to snapshot, save, or version their skills. Triggers on "commit my skills", "save skill changes", "new version of my skill", or after editing any SKILL.md file.
argument-hint: [-a <agent>]
allowed-tools: Bash(bash *)
---

You are running `/skill-git:commit`. Follow these steps exactly.

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

## Step 1a — Filesystem Scan

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-warn-unregistered.sh" "<global_base>" '<skills_json>'
```

Display the output if any (do not stop, do not prompt).

Then continue to Step 1b.

## Step 1b — Parallel Scan

Spawn one subagent per skill in parallel. Each subagent receives a single skill's `name` and `path` and runs:

Instructions for each subagent:
1. **First**, run `git -C <path> status --porcelain` and check its exit code.
   - If the exit code is **128** (directory missing or not a git repo) → return `{ "missing": true, "name": "<skill-name>", "path": "<path>" }`. Do not run git diff.
2. If `status --porcelain` is empty → return `{ "changed": false }`.
3. If status is non-empty → run `git -C <path> diff HEAD` and return:
   - `changed: true`
   - `files`: list of changed file paths (from status output)
   - `diff`: full output of `git diff HEAD`
   - `untracked`: list of files with `??` prefix from status (these are new, untracked files)
   - For untracked files, also read their content and include it in the result.

Wait for all subagents to complete.

Collect all results where `missing: true`. If any, automatically remove each from config.json:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-handle-missing.sh" "<agent>" "<skill_name>" "<path>"
```

Display the script output.

Then proceed to Step 2 with only non-missing skills.

## Step 2 — Display Change Summary

If all skills returned `changed: false`:

```
✅ Nothing to commit. All skills are up to date.
```

Stop here.

Otherwise, for each skill with `changed: true`, read the diff/content returned by its subagent and write **2-3 sentences in English** describing what actually changed (new rules added, behaviors modified, files restructured — not just file names).

A skill is a **new skill** if its name does not appear in the `skills` map in config.json.

Display the summary and prompt the user:

```
📋 Detected changes in N skill(s):

  1. <skill-name>    ~ <N> file(s) changed
     <2-3 sentence English description of what changed>

  2. <skill-name>    + new skill
     <2-3 sentence English description of the new skill>

  ...

How to proceed?
  a) Commit all
  b) Commit selected (enter numbers or names, e.g. "1,3" or "humanizer code-review")
  c) Cancel
  d) Other (describe what you want)
```

Wait for the user's response. Parse it to determine which skills to commit:
- `a` → all changed skills
- `b` + input → match by number (1-based index in the list) or by skill name; both are accepted
- `c` → stop, tell the user nothing was committed
- `d` or free text → interpret the user's intent and clarify if needed

## Step 3 — Version & Message Suggestions

For each skill selected in Step 2:

1. **Pre-flight tag check**: run `git -C <path> tag --list "v*"` to see existing tags. If the tag you are about to suggest already exists, pick the next logical version.

2. Analyze the diff and apply SemVer rules:

   | Bump        | When to apply                                                         |
   |-------------|-----------------------------------------------------------------------|
   | PATCH x.x.+1 | Wording fixes, minor rule tweaks, typo corrections                   |
   | MINOR x.+1.0 | New rules or behaviors, new supporting files (scripts, examples)      |
   | MAJOR +1.0.0 | Core behavior rewrite, major rule deletions, fundamental purpose change |

3. Generate a short, lowercase imperative commit message (e.g. `"add em-dash detection rule"`).

Output **all suggestions in a single message** — do not prompt skill by skill:

```
Here are the suggested versions and messages for all selected skills:

  1. <skill-name>    <current> → <suggested>
     "<commit message>"

  2. <skill-name>    <current> → <suggested>
     "<commit message>"

  ...

How to proceed?
  a) Accept all
  b) Edit specific ones (enter numbers or names + your changes)
  c) Cancel
  d) Other
```

Wait for the user's response. Collect all final versions and messages before moving to execution. Do not execute anything yet.

## Step 4 — Execute

After all versions and messages are confirmed, execute for each skill in order:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<path>" add -A
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<path>" commit -m "<message>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<path>" tag <version>
```

If any command fails, print the git error, skip the config.json update for that skill, and continue with the remaining skills.

After each successful commit+tag, update config.json:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-config-set.sh" "<agent>" "<skill_name>" "<version>"
```

When all done, show the final result:

```
✅ <skill-name>    → <version>  committed
✅ <skill-name>    → <version>  committed
⏭️  <skill-name>   skipped

[skill-git] Done. Run /skill-git:revert to roll back any skill to a previous version.
```
