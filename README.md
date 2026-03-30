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
* 📦 **Self-Contained & Portable:** Each skill folder gets its own independent `.git` repository.
* 🏷️ **Semantic Versioning:** Every commit is auto-tagged, keeping your skill history perfectly organized.

---


## ⚡ Quick Start

One line install the plugin to Claude code:
```bash
claude plugin marketplace add KnowledgeXLab/skill-git
claude plugin install skill-git@skill-git
```

Then run:

```bash
# 1. Initialize version tracking for all your skills
/skill-git:init

# 2. After editing a skill, snapshot the change
/skill-git:commit

# 3. Find overlapping skills in your library
/skill-git:scan

# 4. Merge the best candidates into one stronger skill
/skill-git:merge
```

> Run `/skill-git:init` once. Then 🔖 `commit` after every skill update — 🔎 `scan` and 🔀 `merge` whenever your library feels redundant.




## 🗂️ Example Workflows

### 🚀 Version-control your skill library from scratch
You just set up a few skills and want to start tracking them properly.
```
/skill-git:init
/skill-git:commit
```
→ Every skill folder gets its own `.git` repo, tagged `v1.0.0`. Future changes are one 🔖 `commit` away.

---

### 🔖 Save a new version after improving a skill
You've refined your `humanizer` skill and want to snapshot the update.
```
/skill-git:commit
```
→ The agent diffs the changes, recommends a patch or minor bump, and tags the new version (e.g. `v1.0.2`). You confirm before anything is written.

---

### 🔀 Merge two overlapping skills into one
You notice `code-review` and `critic` feel redundant and want to consolidate.
```
/skill-git:scan code-review critic
/skill-git:merge code-review critic
```
→ 🔎 `scan` rates the overlap (★★★ / ★★☆ / ★☆☆). 🔀 `merge` combines them interactively — nothing is written until you confirm.

---

### ⏪ Roll back a skill that broke your workflow
Your latest `planner` update introduced conflicts and you want to undo it.
```
/skill-git:revert planner
/skill-git:revert planner v1.0.2
```
→ Reverts to the previous version (or a specific tag). A backup is taken first and restored automatically if anything fails.

---

## Installation

**Claude** (Recommended)
```bash
claude plugin marketplace add KnowledgeXLab/skill-git
claude plugin install skill-git@skill-git
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

## Usage

| Command | What it does |
|---------|-------------|
| 🚀 `init` | Initialize version tracking for all your skills |
| 🔖 `commit` | Snapshot changes with an auto-bumped semver tag |
| ⏪ `revert` | Roll back a skill to any previous version |
| 🛡️ `check` | Audit a skill for rule conflicts and security issues |
| 🔎 `scan` | Find semantically overlapping skills and rate merge candidates |
| 🔀 `merge` | Combine two similar skills into one stronger skill |


### 🔖 `commit` — Save a new version

```
/skill-git:commit
```

The agent analyzes the diff and recommends a patch or minor bump. You confirm before anything is written.

### ⏪ `revert` — Roll back

```
/skill-git:revert humanizer
/skill-git:revert humanizer v1.0.2
```

Omitting the version defaults to the previous tag. The operation is atomic — a backup is taken first and restored automatically if anything fails.

### 🛡️ `check` — Audit a skill

```
/skill-git:check humanizer
```

Detects internal rule conflicts, contradictory configs, and security issues. Returns a structured report.

### 🔎 `scan` — Find overlap

```
/skill-git:scan
/skill-git:scan humanizer code-review
```

Runs semantic analysis across your skills to find pairs with overlapping rules. Each pair is rated ★★★ / ★★☆ / ★☆☆ and results are cached for `merge` to pick up.

### 🔀 `merge` — Consolidate skills

```
/skill-git:merge
/skill-git:merge humanizer code-review
```

Running without arguments picks up the latest scan results. Conflicts are resolved interactively. Nothing is written until you confirm.

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
