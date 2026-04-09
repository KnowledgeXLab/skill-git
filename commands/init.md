---
name: skill-git:init
description: Initialize version tracking for your skills. Creates an independent git repo inside each skill folder and tags it v1.0.0. Run once before using any other skill-git commands. Supports -a <agent> (claude/gemini/codex/openclaw) and --project flags.
argument-hint: [-a <agent>] [--project]
allowed-tools: Bash(bash *), AskUserQuestion
---

You are running `/skill-git:init`. Follow these steps in order.
\

## Task Tracking

You MUST create a task for each item below and update each task's status as you progress (pending → in_progress → completed):

1. **Resolve agent** — detect or prompt for the target agent (claude, gemini, codex, openclaw)
2. **Explain what will happen** — summarize the init steps to the user before executing
3. **Verify git is installed** — check `git --version`
4. **Run initialization** — execute `sg-init.sh` and display the full output


## Step 1 — Resolve agent

Parse `$ARGUMENTS` for a `-a <value>` flag.

**If `-a` was provided:** use that value as `agent`. Validate it against the known agents:

| value | base_dir |
|-------|----------|
| `claude` | `~/.claude` |
| `gemini` | `~/.gemini` |
| `codex` | `~/.codex` |
| `openclaw` | `~/.openclaw/skills`, `~/.openclaw/workspace/skills/` |

If the value is not in the table, respond:
```
Unknown agent: "<value>"
Supported agents: claude, gemini, codex, openclaw
```
Then stop.

**If `-a` was not provided:** auto-detect using the following steps in order:

**Step A — Check parent process:**
Run `ps -p $PPID -o comm=` and match the output:
- contains `claude` → `claude`
- contains `gemini` → `gemini`
- contains `codex` → `codex`
- contains `openclaw` or `claw` → `openclaw`

If matched, set `agent` and note: `(agent auto-detected from process: <agent>)`

**Step B — Check user config (if Step A fails):**
Read `~/.skill-git/config.local.md` and look for a `default_agent` field:
```yaml
---
default_agent: gemini
---
```
If found, set `agent` from that value. Note: `(agent from config: <agent>)`

**Step C — Prompt user (if Step B also fails):**

Tell the user that the CLI tool could not be detected automatically, then use the AskUserQuestion tool:
- question: "Which agent are you initializing skills for?"
- header: "Agent"
- options:
  - label: "claude", description: "~/.claude/skills/"
  - label: "gemini", description: "~/.gemini/skills/"
  - label: "codex", description: "~/.codex/skills/"
  - label: "openclaw", description: "~/.openclaw/skills/ + ~/.openclaw/workspace/skills/"
- multiSelect: false

Set `agent` from the user's response.

## Step 2 — Explain what will happen

Tell the user:

> `skill-git init` will set up local version tracking for your **<agent>** skills:
> 1. Scan the agent's skill directories for subfolders, including symlinked directories (openclaw scans both `~/.openclaw/skills/` and `~/.openclaw/workspace/skills/`)
> 2. For each subfolder, run `git init` + initial commit + tag `v1.0.0`
> 3. Write `~/.skill-git/config.json` to record the agent, base path, and skill versions
> 4. Create `~/.skill-git/config.local.md` (template) if it does not already exist
>
> All git repos stay on your local machine. Nothing is uploaded anywhere.

## Step 3 — Check git is installed

Run: `git --version`

If the command fails or git is not found, tell the user to install git first (`brew install git` on macOS) and stop.

## Step 4 — Run initialization

Construct the argument string:
- Always include `-a <agent>` (using the resolved agent from Step 1)
- Pass through `--project` if the user included it in `$ARGUMENTS`

Run: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-init.sh" -a <agent> [--project]`

Display the full output to the user exactly as printed. If there are errors, explain what went wrong based on the output.

You should output all the plugins and skills detected in the formatted and pretty  output to the user. 
Also, if there's any [info] or [warn] or [error] in the output, you should explain it to the  user.

###  `sg-init.sh`  Supported Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `-a <agent>` | auto-detected | Agent to initialize. Supported values: `claude`, `gemini`, `codex`, `openclaw`. Determines the base directory (e.g. `~/.claude/` for claude). `openclaw` scans both `~/.openclaw/skills/` and `~/.openclaw/workspace/skills/`. |
| `--project` | off | Also scan the project-level skills directory. For most agents: `./<agent>/skills/` under the current working directory. For `openclaw`: `./skills/` under the current working directory. |

Examples:
- `/skill-git:init` — auto-detect agent, initialize its skills
- `/skill-git:init -a gemini` — initialize gemini skills at `~/.gemini/skills/`
- `/skill-git:init --project` — auto-detect agent, initialize both global and project-level skills

 DO NOT passes unrecognized flags, the script will print an error and exit. 
 if user passes unrecognized flags, you should correct it and  run the command again. 