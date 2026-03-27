#  skill-git | Agent Skills Management Plugin

> **Git, but for your AI agent skills.** 🧠

![alt text](teaser.png)

Tired of messy, fragmented, or conflicting agent capabilities? **skill-git** brings the power of version control directly to your AI workflows. 

Track changes, seamlessly roll back bad edits, and—most importantly—**merge overlapping local skills into stronger, unified tools.** Works out-of-the-box across any AI Agent platform, including **Claude**, **OpenClaw**, **Gemini**, and **Codex**.

### 🌟 Key Features

* 🔀 **Combine & Conquer:** Stop adding duplicate micro-skills. Automatically scan for local similarities and merge them to make your agent smarter and more robust.
* 📦 **Self-Contained & Portable:** Each skill folder gets its own independent `.git` repository.
* 🏷️ **Semantic Versioning:** Every commit is auto-tagged, keeping your skill history perfectly organized.

---

## Commands

| Command | What it does |
|---------|-------------|
| 🚀 `init` | Initialize version tracking for all your skills |
| 🔖 `commit` | Snapshot changes with an auto-bumped semver tag |
| ⏪ `revert` | Roll back a skill to any previous version |
| 🛡️ `check` | Audit a skill for rule conflicts and security issues |
| 🔎 `scan` | Find semantically overlapping skills and rate merge candidates |
| 🔀 `merge` | Combine two similar skills into one stronger skill |

---

## Installation

**Claude** (Recommended)
```bash
/plugin marketplace add KnowledgeXLab/skill-git
/plugin install skill-git@skill-git
```

**OpenClaw**
```bash
clawhub install KnowledgeXLab/skill-git
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
