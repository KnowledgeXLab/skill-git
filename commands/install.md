---
name: skill-git:install
description: Install a skill from SkillHub (skills.sh) or ClawHub (clawhub.ai). Triggers on "install skill", "download skill from", or when called from /skill-git:search after the user confirms an install. Usage: /skill-git:install skillhub:<owner/repo@skill> or /skill-git:install clawhub:<slug>.
argument-hint: skillhub:<owner/repo@skill> | clawhub:<slug> [-a <agent>]
allowed-tools: Bash(bash *), AskUserQuestion
---

You are running `/skill-git:install`. Follow these steps exactly.

All output shown to the user must be in English.

## Tool Loading

Before doing any work, load all required tools in a **single** ToolSearch call:
```
select:TaskCreate,TaskUpdate,TaskList,AskUserQuestion
```
Do not issue multiple ToolSearch calls.

## Task Tracking

You MUST create a task for each item below and update each task's status as you progress (pending → in_progress → completed):

1. **Parse arguments** — validate identifier format, derive `install_name`, extract agent flag
2. **Init check** — run prelude, get AGENT / GLOBAL_BASE / SKILLS_JSON
3. **Conflict check** — verify `install_name` not already installed; set `install_path`
4. **Download skill** — fetch files from the registry into `install_path`
5. **Preview and confirm** — display skill name, description, content preview; ask user to confirm
6. **Init skill** — run `sg-init.sh` to create git repo, initial commit, and v1.0.0 tag

---

## Step 0 — Parse Arguments

If `$ARGUMENTS` is empty:
```
Identifier required.
Usage: /skill-git:install skillhub:<owner>/<repo>@<skill>
       /skill-git:install clawhub:<slug>

Use /skill-git:search to find skills first.
```
Stop.

Extract `registry` and `identifier` from the first non-flag token:

- `skillhub:<owner>/<repo>@<skill>` → `registry = "skillhub"`, validate `identifier` contains `/` and `@`
- `clawhub:<slug>` → `registry = "clawhub"`, validate slug is non-empty with no `/` or spaces
- Unknown prefix → `Unknown registry. Use "skillhub:" or "clawhub:" as prefix.` Stop.

On validation failure, extract a best-effort search query from all non-flag tokens (e.g. `vercel/agent-browser` → `agent-browser`) and run a registry search to suggest the correct identifier:

**SkillHub fallback search:**
```bash
npx skills find "<query>" 2>&1
```

**ClawHub fallback search:**
```bash
curl -s "https://clawhub.ai/api/v1/search?q=<query>" 2>&1
```

Parse the results and present matching skills to the user using AskUserQuestion with one option per result plus a "Cancel" option. Each option label should show the full valid identifier (e.g. `skillhub:vercel/agent-browser@agent-browser`). If no results are found, show the expected format and stop:
```
# SkillHub
Invalid SkillHub identifier. Expected: skillhub:<owner>/<repo>@<skill>

# ClawHub
Invalid ClawHub slug. Expected: clawhub:<slug>
```

When the user selects a result, use that as the new `identifier` and `registry` and continue.

Derive `install_name` immediately:
- SkillHub: the `<skill>` part after `@`
- ClawHub: the `<slug>`

Extract optional flags:
- `-a <value>`: target agent (`claude`, `gemini`, `codex`, `openclaw`). Pass through to prelude.

---

## Step 1 — Init Check

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS
```

If STATUS is not `ok`:
- `not_initialized` + INITIALIZED_AGENTS non-empty → suggest `/skill-git:init -a <agent>`
- `not_initialized` + INITIALIZED_AGENTS empty → tell user to run `/skill-git:init` first
- `error` → display REASON and stop

Use AGENT, GLOBAL_BASE, and SKILLS_JSON from prelude output for all subsequent steps.

Map `AGENT` → `npx_agent` for use in Step 3a:

| AGENT | npx_agent |
|-------|-----------|
| `claude` | `claude-code` |
| `gemini` | `gemini` |
| `codex` | `codex` |
| `openclaw` | `openclaw` |

---

## Step 2 — Conflict Check

Look up `install_name` in SKILLS_JSON. If found:
```
Skill "<install_name>" is already installed locally (version <conflict_version>).
Path: <conflict_path>

To update it, use /skill-git:merge after installing under a different name,
or run /skill-git:revert to manage existing versions.
```
Stop.

Set `install_path` = `<GLOBAL_BASE>/skills/<install_name>`.

---

## Step 3 — Download Skill

### 3a. SkillHub

From `identifier` (`<owner>/<repo>@<skill>`), derive:
- `github_url` = `https://github.com/<owner>/<repo>`
- `skill_folder` = `<skill>` (the part after `@`)

```bash
npx skills add "<github_url>" --skill "<skill_folder>" -a "<npx_agent>" 2>&1
```

If the command succeeds and `<install_path>/SKILL.md` exists:
- Set `skill_source_dir` = `<install_path>` (files already in place)
- Read `<install_path>/SKILL.md` as `downloaded_content`

If the command fails or `SKILL.md` is not found:
```
Could not download skill from SkillHub.
  Command: npx skills add <github_url> --skill <skill_folder>

  The skill may not exist or the registry may be unavailable.
  Browse manually: https://skills.sh/<owner>/<repo>/<skill_folder>
```
Stop.

### 3b. ClawHub

Fetch metadata and SKILL.md in parallel:

```bash
HTTP_META=$(curl -s -o /tmp/sg_install_meta.json -w "%{http_code}" "https://clawhub.ai/api/v1/skills/<slug>")
HTTP_SKILL=$(curl -s -o /tmp/sg_install_skill.md -w "%{http_code}" "https://clawhub.ai/api/v1/packages/<slug>/file?path=SKILL.md")
echo "META=$HTTP_META SKILL=$HTTP_SKILL"
```

Check status codes:
- `META=404` → `Skill "<slug>" not found on ClawHub.` Stop.
- `META` not `200` → `ClawHub metadata request failed (HTTP <N>). Try again or browse: https://clawhub.ai/skills/<slug>` Stop.
- `SKILL=404` → `SKILL.md not found for "<slug>" on ClawHub.` Stop.
- `SKILL` not `200` → `ClawHub file request failed (HTTP <N>). Try again or browse: https://clawhub.ai/skills/<slug>` Stop.

Extract `skill_downloads` from metadata:
```bash
jq -r '.skill.stats.downloads // 0' /tmp/sg_install_meta.json
```

Write skill to disk:
```bash
mkdir -p "<install_path>"
cp /tmp/sg_install_skill.md "<install_path>/SKILL.md"
rm -f /tmp/sg_install_meta.json /tmp/sg_install_skill.md
```

Read `<install_path>/SKILL.md` as `downloaded_content`. If the file is missing or empty after writing:
```
Could not write SKILL.md to <install_path>.
  Browse manually: https://clawhub.ai/skills/<slug>
```
Stop.

### 3c. Validate

Verify `downloaded_content` is non-empty and starts with `---`. If not:
```
Downloaded content does not appear to be a valid SKILL.md.

Content preview:
  <first 200 chars, or "(empty)">

Aborting. The skill source may be corrupt or unavailable.
```
Stop.

Parse frontmatter to extract `description` as `skill_description`.

---

## Step 4 — Preview and Confirm

Display the skill preview:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Install preview

  Source   : <SkillHub — owner/repo@skill | ClawHub — slug>
  Name     : <install_name>
  Install  : <install_path>/
  Desc     : <skill_description or "(no description)">
  <Downloads: <N>  ← ClawHub only, when available>

  Content preview:
  ─────────────────────────────────────────
  <first 10 lines of downloaded_content>
  ─────────────────────────────────────────
  <if skill_source_dir = null and registry = "clawhub":>
  Note: ClawHub provides SKILL.md content only — scripts and examples not included.
```

Use the AskUserQuestion tool:
- question: "Install '<install_name>' to <install_path>/?"
- header: "Confirm install"
- options:
  - label: "Yes, install", description: "Write files and create version tag v1.0.0"
  - label: "Cancel", description: "Abort — no files will be written"
- multiSelect: false

If "Cancel": `Install cancelled.` Stop.

---

## Step 5 — Init Skill

Use the Skill tool to invoke `skill-git:init`, passing `-a <AGENT>` if a non-default agent was specified in Step 0.

If the skill reports any error, display it and stop.

---

## Output Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Installed ✅

  <install_name>  v1.0.0
  Path : <install_path>/SKILL.md
  From : <SkillHub — owner/repo@skill | ClawHub — slug>
  Desc : <skill_description or "(no description)">

  Next steps:
    /skill-git:check <install_name>   — validate for conflicts
    /skill-git:list                   — view all installed skills
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
