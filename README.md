#  skill-git | Agent Skills Management Plugin

![License](https://img.shields.io/badge/license-MIT-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)
[![ClawhHub](https://img.shields.io/badge/ClawhHub-skill--git-orange)](https://clawhub.ai/zijinoier/skill-git)
![Platforms](https://img.shields.io/badge/platforms-Claude%20%7C%20Gemini%20%7C%20Codex%20%7C%20OpenClaw-brightgreen)

**[中文版](README.zh.md)**

> **Git, but for your AI agent skills.** 🧠

![alt text](teaser.png)

Tired of agent skills that conflict, overlap, or drift out of control? **skill-git** brings the power of version control directly to your AI workflows. 

Track changes, seamlessly roll back bad edits, and—most importantly—**merge overlapping local skills into stronger, unified tools.** Works out-of-the-box across any AI Agent platform, including **Claude**, **OpenClaw**, **Gemini**, and **Codex**.

### 🌟 Key Features

* 🔀 **Combine & Conquer:** Stop adding duplicate micro-skills. Automatically scan for local similarities and merge them to make your agent smarter and more robust.
* 🔍 **Discover & Install:** Search SkillHub and ClawHub registries by keyword, or find online equivalents of your local skills — then install in one command.
* 📦 **Self-Contained & Portable:** Each skill folder gets its own independent `.git` repository.
* 🏷️ **Semantic Versioning:** Every commit is auto-tagged, keeping your skill history perfectly organized.

---

## 📅 Changelog

We ship updates weekly. Here's what's new:

| Date | Release | What's new |
|------|---------|-----------|
| 2026-04-09 | v1.1 | `search` — discover skills from SkillHub & ClawHub; `install` — one-command install with conflict detection; `list` — view your skill library |
| 2026-03-30 | v1.0 | `init`, `commit`, `revert`, `check`, `scan`, `merge` — full version control and merge workflow |


---


## ⚡ Quick Start

One line install the plugin to Claude code:
```bash
claude plugin marketplace add KnowledgeXLab/skill-git
claude plugin install skill-git@knowledgexlab
```

Then run:

```bash
/skill-git:init
```

---

## Features

| Command | What it does |
|---------|-------------|
| 🚀 `init` | Initialize version tracking for all your skills |
| 🔖 `commit` | Snapshot changes with an auto-bumped semver tag |
| ⏪ `revert` | Roll back a skill to any previous version |
| 🛡️ `check` | Audit a skill for rule conflicts and security issues |
| 🔎 `scan` | Find semantically overlapping skills and rate merge candidates |
| 🔀 `merge` | Combine two similar skills into one stronger skill |
| 🔍 `search` | Discover skills from SkillHub and ClawHub by keyword or similarity |
| 📥 `install` | Install a skill from SkillHub or ClawHub with one command |
| 📋 `list` | List all installed skills with their current versions |
| 🗑️ `delete` | Permanently remove a skill from disk and config |


---


## 🗂️ Best Practices

### 1. 🔍 Find, install, and version-control a new skill in one session
You want to add a code-review skill but aren't sure what's out there.
```
/skill-git:search I want to do code review
```
→ Returns the top 5 results from SkillHub and ClawHub, ranked by relevance and download count. Pick one — it installs, previews the content, and asks you to confirm.
```
/skill-git:install clawhub:code-review   # or whichever result you picked
```
→ Files land in `~/.claude/skills/code-review/` and are tagged `v1.0.0` automatically. You're version-controlled from day one.

---

### 2. ⏪ Edit a skill, keep what's good, undo what isn't
You tweak your `planner` skill. Some changes work; one update breaks your workflow a week later.
```
/skill-git:commit             # after a good edit — tags v1.0.1
/skill-git:commit             # after another — tags v1.0.2
/skill-git:revert planner     # something broke → rolls back to v1.0.1 instantly
```
→ Each commit captures the full diff and bumps the version. Revert is atomic — a backup is taken first and restored automatically if anything fails. No edit is ever truly gone.

---

### 3. 🔀 Shrink your library by merging what overlaps
Over time you accumulated `code-review`, `critic`, and `pr-feedback`. They've started contradicting each other.
```
/skill-git:scan                        # finds all overlapping pairs, rated ★★★ / ★★☆ / ★☆☆
/skill-git:merge code-review critic    # combines the top pair interactively
/skill-git:commit                      # snapshots the merged result as v1.1.0
/skill-git:delete critic               # remove the now-redundant original
```
→ `scan` shows you the overlap score before you commit to anything. `merge` resolves conflicts interactively — nothing is written until you confirm. `delete` asks for explicit confirmation and warns you if the skill has uncommitted changes. The result is a leaner library where every skill pulls its weight.

---

## Installation

**Claude** (Recommended)
```bash
claude plugin marketplace add KnowledgeXLab/skill-git
claude plugin install skill-git@knowledgexlab
```

**OpenClaw**
```bash
clawhub install skill-git
```

**Gemini**
```bash
gemini extensions install https://github.com/KnowledgeXLab/skill-git
```

**Codex**
```bash
npx skills add KnowledgeXLab/skill-git -a codex
```

Then initialize:

```
/skill-git:init
```

Supports multiple agents via `-a <agent>`:

```
/skill-git:init -a claude
/skill-git:init -a gemini
/skill-git:init -a codex
/skill-git:init -a openclaw
```

---

## How it works

```
~/.claude/skills/
├── humanizer/
│   ├── SKILL.md
│   └── .git/          ← per-skill repo, tagged v1.0.0, v1.0.1 …
├── mcp-builder/
│   ├── SKILL.md
│   └── .git/
└── …

~/.skill-git/
└── config.json        ← registered agents and skill paths
```

Each skill's `.git` is fully independent — moving or sharing a skill folder preserves its entire version history.

---

## Local development

```bash
claude --plugin-dir ./
```


---

## License

MIT © KnowledgeXLab
