#  skill-git | Agent Skill 版本管理插件

![License](https://img.shields.io/badge/license-MIT-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)
[![ClawhHub](https://img.shields.io/badge/ClawhHub-skill--git-orange)](https://clawhub.ai/zijinoier/skill-git)
![Platforms](https://img.shields.io/badge/platforms-Claude%20%7C%20Gemini%20%7C%20Codex%20%7C%20OpenClaw-brightgreen)

> **Git，但专为你的 AI Agent 技能而生。** 🧠

![alt text](teaser.png)

厌倦了技能之间冲突、重叠、越来越难管理？**skill-git** 将版本控制的力量直接引入你的 AI 工作流。

追踪变更、一键回滚错误编辑，最重要的是——**将重叠的本地技能合并成更强大的统一工具。** 开箱即用，支持 **Claude**、**OpenClaw**、**Gemini** 和 **Codex** 等主流 AI Agent 平台。

### 🌟 核心特性

* 🔀 **合并增强：** 不再堆积重复的微技能。自动扫描本地相似项，合并后让 Agent 更智能、更稳定。
* 🔍 **发现与安装：** 按关键词搜索 SkillHub 和 ClawHub 注册表，或为本地技能找到最佳在线替代——一条命令完成安装。
* 📦 **自包含且可移植：** 每个技能文件夹拥有独立的 `.git` 仓库。
* 🏷️ **语义化版本：** 每次提交自动打标签，技能历史一目了然。

---

## 📅 更新日志

我们保持每周更新节奏，以下是最近的发布：

| 日期 | 版本 | 新功能 |
|------|------|-------|
| 2026-04-09 | v1.1 | `search` — 从 SkillHub & ClawHub 搜索技能；`install` — 一键安装并自动处理冲突；`list` — 查看本地技能库 |
| 2026-03-30 | v1.0 | `init`、`commit`、`revert`、`check`、`scan`、`merge` — 完整的版本控制与合并工作流 |

---


## ⚡ 快速开始

一行命令安装插件到 Claude Code：
```bash
claude plugin marketplace add KnowledgeXLab/skill-git
claude plugin install skill-git@knowledgexlab
```

然后运行：

```bash
/skill-git:init
```

---

## 功能一览

| 命令 | 功能说明 |
|------|---------|
| 🚀 `init` | 初始化所有技能的版本追踪 |
| 🔖 `commit` | 快照变更，自动升级语义化版本标签 |
| ⏪ `revert` | 将技能回滚到任意历史版本 |
| 🛡️ `check` | 审查技能的规则冲突和安全问题 |
| 🔎 `scan` | 扫描语义重叠的技能并评级合并候选 |
| 🔀 `merge` | 将两个相似技能合并为一个更强的技能 |
| 🔍 `search` | 按关键词或相似度在 SkillHub / ClawHub 上搜索技能 |
| 📥 `install` | 一条命令从 SkillHub 或 ClawHub 安装技能 |
| 📋 `list` | 查看所有已安装技能及其当前版本 |
| 🗑️ `delete` | 从磁盘和配置中永久删除一个技能 |


---


## 🗂️ 最佳实践

### 1. 🔍 一次会话内完成搜索、安装、版本管理
你想添加一个代码审查技能，但不确定有哪些选择。
```
/skill-git:search I want to do code review
```
→ 从 SkillHub 和 ClawHub 返回 Top 5 结果，按相关度和下载量排序。选一个——它会预览内容并询问你确认。
```
/skill-git:install clawhub:code-review   # 或你选中的那个
```
→ 文件落地到 `~/.claude/skills/code-review/`，自动打上 `v1.0.0` 标签。从第一天起就有版本记录。

---

### 2. ⏪ 编辑技能，保留好的，撤销坏的
你调整了 `planner` 技能。一些改动有效，但一周后某次更新破坏了工作流。
```
/skill-git:commit             # 一次好的编辑后 — 打标签 v1.0.1
/skill-git:commit             # 又一次 — 打标签 v1.0.2
/skill-git:revert planner     # 出问题了 → 立刻回滚到 v1.0.1
```
→ 每次 commit 记录完整 diff 并自动升级版本。revert 是原子操作——先备份，失败自动恢复。没有任何编辑会永久消失。

---

### 3. 🔀 合并重叠技能，精简你的技能库
你陆续积累了 `code-review`、`critic`、`pr-feedback`，它们开始互相矛盾。
```
/skill-git:scan                        # 扫描所有重叠对，评级 ★★★ / ★★☆ / ★☆☆
/skill-git:merge code-review critic    # 交互式合并得分最高的一对
/skill-git:commit                      # 快照合并结果，打标签 v1.1.0
/skill-git:delete critic               # 删除已被吸收的冗余技能
```
→ `scan` 在你动手之前就告诉你重叠程度。`merge` 交互式解决冲突，确认前不写入任何内容。`delete` 需要明确确认，若有未提交变更会提前警告。最终是一个更精简的技能库，每个技能都物尽其用。

---

## 安装

**Claude**（推荐）
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

然后初始化：

```
/skill-git:init
```

通过 `-a <agent>` 支持多平台：

```
/skill-git:init -a claude
/skill-git:init -a gemini
/skill-git:init -a codex
/skill-git:init -a openclaw
```

---

## 工作原理

```
~/.claude/skills/
├── humanizer/
│   ├── SKILL.md
│   └── .git/          ← 独立技能仓库，标签 v1.0.0, v1.0.1 …
├── mcp-builder/
│   ├── SKILL.md
│   └── .git/
└── …

~/.skill-git/
└── config.json        ← 已注册的 Agent 和技能路径
```

每个技能的 `.git` 完全独立——移动或分享技能文件夹时，完整版本历史一并保留。

---

## 本地开发

```bash
claude --plugin-dir ./
```

---

## 许可证

MIT © KnowledgeXLab
