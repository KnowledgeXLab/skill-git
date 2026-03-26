---
name: skill-git:check
description: Check a skill for internal rule conflicts, agent config conflicts, and security issues. Usage: /skill-git:check <skill-name> [-a <agent>]
argument-hint: <skill-name> [-a <agent>]
allowed-tools: Bash(bash *)
---

You are executing `/skill-git:check`. Follow the steps below precisely.

## Prelude

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS --agent-only`

If STATUS is `ok`: use AGENT and GLOBAL_BASE from prelude output in Step 2.
If STATUS is `not_detected` (unknown agent): proceed to Step 2's custom agent lookup path.
If STATUS is `error`: display REASON and stop.

## Step 1: Parse Arguments

The user's input after the command name is: $ARGUMENTS

Extract:
- `skill_name`: the first positional argument (required). Two supported formats:
  - `<skill-name>` — search across all known skill paths
  - `<plugin-name>:<skill-name>` — search only within the specified plugin's skills directory
- `agent`: the value after `-a` flag (optional). Defaults to auto-detect if not provided.

**Agent name as skill_name:** If the first positional token exactly matches a known agent name (claude, gemini, codex, openclaw) and no `-a` flag was given, the user likely meant `-a <agent>` rather than a skill named after the agent. Silently treat it as the agent specifier: re-run the prelude result with that agent (read `~/.skill-git/config.json`), set `skill_name` to empty, and continue to the missing-skill_name error below which will show the usage message.

If `skill_name` is missing, respond:
```
Usage: /skill-git:check <skill-name> [-a <agent>]
Examples:
  /skill-git:check code-review
  /skill-git:check my-plugin:code-review
  /skill-git:check code-review -a gemini
```
Then stop.

If the format is `<plugin-name>:<skill-name>`, set:
- `plugin_filter` = `<plugin-name>`
- `skill_name` = `<skill-name>`

Otherwise set `plugin_filter` = null.

## Step 2: Resolve Agent Configuration

**If STATUS was `ok` from the Prelude:** use `AGENT` and `GLOBAL_BASE` directly. Set `base_dir = GLOBAL_BASE`. Skip the custom agent lookup below.

**If STATUS was `not_detected` (unknown agent from Prelude):** the user specified a custom agent via `-a`. Read `~/.skill-git/config.local.md` for custom agent definitions:

```yaml
---
agents:
  my-custom-agent:
    project_config: "MY-AGENT.md"
    global_config: "~/.my-agent/MY-AGENT.md"
    project_skill_paths:
      - ".my-agent/skills/"
      - ".my-agent/plugins/*/skills/"
    global_skill_paths:
      - "~/.my-agent/skills/"
      - "~/.my-agent/plugins/*/skills/"
---
```

The user can also override `base_dir` in `~/.skill-git/config.local.md`:
```yaml
---
default_agent: claude
base_dir: /custom/path/to/cli/data
---
```
If `base_dir` is set in config, it takes precedence.

If the agent from RAW_ARGUMENTS is still not found after checking config.local.md, respond:
```
Unknown agent: "<agent>"
Define it in ~/.skill-git/config.local.md or use a built-in agent: claude, gemini, codex, openclaw
```
Then stop.

**Built-in agent config file names** (for use in Step 4 — reading config files):

| agent | project config | global config |
|-------|---------------|---------------|
| `claude` | `CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `gemini` | `GEMINI.md` | `~/.gemini/GEMINI.md` |
| `codex` | `AGENTS.md` | `~/.codex/AGENTS.md` |
| `openclaw` | `CLAW.md` | `~/.openclaw/CLAW.md` |

If the detected agent's config files do not exist on disk, that is fine — those checks will be skipped in Step 5.

## Step 3: Find the Skill File

Skills always live as `<skill-name>/SKILL.md` inside a skill directory — never as a flat `.md` file.

**Build the candidate list:**

1. Read `<base_dir>/plugins/installed_plugins.json`. Extract the `installPath` from **every** entry — regardless of whether the plugin name matches the skill name. A skill can live inside any plugin.

2. Collect all candidate paths to check (two file formats exist):

   **Format A — subdirectory skill** (`skills/<skill-name>/SKILL.md`):
   - `<base_dir>/skills/<skill-name>/SKILL.md` — global user skills
   - `{project}/.<agent>/skills/<skill-name>/SKILL.md` — project user skills
   - For **each** plugin in `installed_plugins.json`: `<installPath>/skills/<skill-name>/SKILL.md`

   **Format B — flat command file** (`commands/<skill-name>.md`):
   - For **each** plugin in `installed_plugins.json`: `<installPath>/commands/<skill-name>.md`

   Do not skip any plugin based on its name — the skill name and the plugin name are independent. For example, the `skill-creator` skill can exist inside the `document-skills` plugin.

3. Check all candidate paths in parallel. Collect every path where the file actually exists.

---

**If `plugin_filter` is set** (format was `<plugin-name>:<skill-name>`):

Filter `installed_plugins.json` to entries whose key starts with `<plugin-name>@`.
Search both formats for those entries:
- `<installPath>/skills/<skill-name>/SKILL.md`
- `<installPath>/commands/<skill-name>.md`

If not found, respond:
```
Skill "<skill_name>" not found in plugin "<plugin_filter>".

Installed plugins matching "<plugin_filter>":
  <list matching installPaths, or "none" if no match>
```
Then stop.

---

**If `plugin_filter` is null** (plain skill name):

**If exactly 1 match**: use it directly, derive `skill_dir` (see below), proceed to Step 4.

**If multiple matches**: present a numbered list and ask the user to choose:
```
Found N skills named "<skill_name>":
  [1] global skill         ~/.claude/skills/<skill_name>/SKILL.md
  [2] superpowers (skill)  ~/.claude/plugins/cache/.../superpowers/5.0.5/skills/<skill_name>/SKILL.md
  [3] hookify (command)    ~/.claude/plugins/cache/.../hookify/d53f/commands/<skill_name>.md
  [4] project command      .claude/commands/<skill_name>.md

Which one to check? (enter a number):
  Tip: use /skill-git:check <plugin-name>:<skill-name> to target a plugin directly
```
Wait for the user's response, then proceed with the selected file.

**After a file is selected, derive `skill_dir` and `skill_format`:**

- **Format A** (`…/skills/<skill-name>/SKILL.md`):
  - `skill_dir` = parent directory of the selected file (e.g. `~/.claude/skills/humanizer/`)
  - `skill_format` = `"directory"`
- **Format B** (`…/commands/<skill-name>.md`):
  - `skill_dir` = null (flat file, no associated directory)
  - `skill_format` = `"flat"`

**If no match**: respond:
```
Skill "<skill_name>" not found.

Available skills:
  <list all skills found across all locations, grouped by source>
```
Then stop.

## Step 4: Read Files

**Skill files:**

- If `skill_format` = `"directory"`: read all `*.md` files at the top level of `skill_dir` (non-recursive). Read `SKILL.md` first, then remaining `*.md` files in alphabetical order. Do not descend into subdirectories.
- If `skill_format` = `"flat"`: read only the single command file found in Step 3.

**Config files (some may not exist — that is fine):**
- The project-level agent config (search from current working directory upward for the filename from Step 2)
- The global agent config at `<base_dir>/<global_config_filename>` from Step 2

## Step 5: Extract Rules (with caching)

Extract rules for each source below. Use the cache when available; write to cache after fresh extraction.

---

### 5a — Skill rules

**Determine `skill_name`:**
- Skill file is `…/skills/<skill_name>/SKILL.md` → `skill_name` = directory basename
- Skill file is `…/commands/<skill_name>.md` → `skill_name` = filename without extension

**Cache path:** `~/.skill-git/cache/<agent>/rules/<skill_name>.json`

**Staleness check:**
```bash
git -C <skill_dir> rev-parse --short HEAD 2>/dev/null
```
- If cache exists and `commit_sha` matches current SHA → use `rules` from cache as `skill_rules`; note `(skill rules from cache)`
- No git repo: compare `extracted_at` in cache against the mtime of all `*.md` files at the top level of the skill directory — if none are newer, use cache
- Otherwise → extract rules from all top-level `*.md` files in the skill directory (per the Rule Extraction skill), then write to cache:

```bash
mkdir -p ~/.skill-git/cache/<agent>/rules
```

Cache file format (`~/.skill-git/cache/<agent>/rules/<skill_name>.json`):
```json
{
  "skill": "<skill_name>",
  "path": "<skill_dir_path>",
  "version": "<git describe --tags --abbrev=0, or 'untracked'>",
  "commit_sha": "<sha or null>",
  "extracted_at": "<ISO 8601 UTC>",
  "rules": [ ... ]
}
```

Set `skill_rules` to the resulting rules list.

---

### 5b — Config rules

For each config file found (project-level and global), check and update its own cache entry.

**Cache paths:**
- Project config → `~/.skill-git/cache/<agent>/configs/project-<basename>.json`
- Global config  → `~/.skill-git/cache/<agent>/configs/global-<basename>.json`

**Staleness check** (mtime, since config files have no git repo):
```bash
stat -c "%Y" <config_file> 2>/dev/null || stat -f "%m" <config_file>
```
- If cache exists and stored `mtime` matches current mtime → use cached rules; note `(config rules from cache)`
- Otherwise → extract rules from the config file, then write to cache:

```bash
mkdir -p ~/.skill-git/cache/<agent>/configs
```

Cache file format:
```json
{
  "path": "<absolute_path>",
  "mtime": <integer>,
  "extracted_at": "<ISO 8601 UTC>",
  "rules": [ ... ]
}
```

Set `project_rules` / `global_rules` from the resulting rules lists.

---

Then apply conflict detection directly (see Conflict Patterns skill for the full detection process) for the following checks in parallel:

**Check A — Internal consistency**
Compare `skill_rules` against itself (intra-list conflict detection).

**Check B — Project config conflicts**
Compare `skill_rules` against `project_rules`.
Skip if project config file was not found.

**Check C — Global config conflicts**
Compare `skill_rules` against `global_rules`.
Skip if global config file was not found.

**Check D — Security scan**
Apply security pattern detection to `skill_rules` alone (prompt injection, data exfiltration, privilege escalation).

## Step 6: Format and Output Report

Print the report in this format:

```
Checking <skill_file_path> (agent: <agent_display_name>)

─────────────────────────────────────────
  <section A>

  <section B>

  <section C>

  <section D>
─────────────────────────────────────────
  Summary: <summary line>
```

For each section, use the following format:

**No issues:**
```
  ✅ Internal consistency: no conflicts
```

**Has issues (⚠️ for medium/high conflicts, 🔴 for high severity or security):**
```
  ⚠️  Project config conflicts × 2 (CLAUDE.md)

     skill:<line>   "<rule_a text>"
     ↕ conflicts with CLAUDE.md:<line>: "<rule_b text>"
     Reason: <explanation>

     skill:<line>   "<rule_a text>"
     ↕ conflicts with CLAUDE.md:<line>: "<rule_b text>"
     Reason: <explanation>
```

**Config file not found:**
```
  ➖ Project config: CLAUDE.md not found, skipped
```

**Security issues use 🔴:**
```
  🔴 Security risks × 1

     skill:<line>   "<rule text>"
     Risk: <explanation>
```

**Summary line examples:**
- `Summary: No issues found ✅`
- `Summary: 2 conflicts and 1 security risk found — resolve before use`

After the summary line, if there are any `high` or `medium` severity conflicts, or any security issues, ask:

```
Fix these conflicts now? (y/n)
```

If `n`, stop. If `y`, proceed to Step 7.

If there are no fixable issues (only `low` overlaps, or no issues at all), stop after the report.

## Step 7: Interactive Conflict Resolution

Work through each fixable issue one at a time, in order of severity: 🔴 security issues first, then `high` conflicts, then `medium` conflicts. Do not display the next issue until the user has responded to the current one.

**Format for internal consistency conflicts** (two rules within the skill itself contradict each other):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Conflict <N>/<total>: Internal consistency

  [1] skill:<line>  "<rule_a text>"
  [2] skill:<line>  "<rule_b text>"
  [3] Write a custom rule (replaces both)
  [4] Skip

Which to keep?
```

**Format for config conflicts** (skill rule vs CLAUDE.md or global config):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Conflict <N>/<total>: <check label, e.g. "Project config conflict">

  [1] Keep skill rule  (remove conflicting line from <config file>)
       skill:<line>  "<rule_a text>"

  [2] Keep config rule  (remove conflicting line from skill)
       <config file>:<line>  "<rule_b text>"

  [3] Write a custom rule  (update both files)
  [4] Skip

Your choice:
```

**Format for security issues** (single rule, no opposing rule):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 Security issue <N>/<total>: <risk type>

  skill:<line>  "<rule text>"
  Risk: <explanation>

  [1] Delete this rule
  [2] Edit this rule (tell me what to change it to)
  [3] Skip

Your choice:
```

**Handling each choice:**

- `[1]` / `[2]` — record which file to modify and which line to remove
- `[3]` Write custom:
  - Prompt: `Enter the new rule:`
  - Record the custom text; both files will be updated
- `[4]` Skip — record as skipped, move to next
- `[2]` Edit (security) — prompt: `Enter the corrected rule:`, record the replacement text

Do not write any files yet. Collect all decisions first.

## Step 8: Confirm and Write

After all issues have been presented, display a summary of pending changes and ask for confirmation:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Pending changes:

  <skill_file_path>
    - Remove line <N>: "<text>"
    - Replace line <N>: "<old>" → "<new>"   (if custom rule)

  <config_file_path>
    - Remove line <N>: "<text>"

  (<N> skipped — not modified)

Write these changes? (y/n)
```

If `n`, discard all changes and stop. No files are written.

If `y`, apply the changes to each file. Then output:

```
Done ✅

  Modified: <skill_file_path>
  Modified: <config_file_path>   (if applicable)
  Skipped:  <N> conflicts

```

After writing, if the skill file was modified, suggest:
```
Run /skill-git:commit to save the new version of this skill.
```

If any conflicts were skipped, suggest:
```
Run /skill-git:check <skill-name> again to handle the remaining conflicts.
```

## Notes

- Be thorough but avoid false positives. If two rules address different topics, do not report them as conflicting.
- Scope overlaps (compatible but related rules) should appear at the end of the relevant section as low-priority notes, not as conflicts. They are not offered for interactive resolution.
- If the skill file is empty, respond: `Skill file is empty, nothing to check.`
- When removing a line from a config file, delete only that line. Do not alter surrounding content.
