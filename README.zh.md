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
* 📦 **自包含且可移植：** 每个技能文件夹拥有独立的 `.git` 仓库。
* 🏷️ **语义化版本：** 每次提交自动打标签，技能历史一目了然。

---


## ⚡ 快速开始

一行命令安装插件到 Claude Code：
```bash
claude plugin marketplace add KnowledgeXLab/skill-git
claude plugin install skill-git@knowledgexlab
```

然后运行：

```bash
# 1. 初始化所有技能的版本追踪
/skill-git:init

# 2. 编辑技能后，快照保存变更
/skill-git:commit

# 3. 扫描技能库中的重叠项
/skill-git:scan

# 4. 将最佳候选合并为一个更强的技能
/skill-git:merge
```

> 运行一次 `/skill-git:init`，之后每次更新技能都 🔖 `commit`——技能库感觉冗余时就 🔎 `scan` + 🔀 `merge`。




## 🗂️ 典型工作流

### 🚀 从零开始对技能库进行版本管理
你刚配置好几个技能，想要开始正式追踪。
```
/skill-git:init
/skill-git:commit
```
→ 每个技能文件夹获得独立的 `.git` 仓库，打上 `v1.0.0` 标签。之后的变更只需一次 🔖 `commit`。

---

### 🔖 优化技能后保存新版本
你改进了 `humanizer` 技能，想要快照这次更新。
```
/skill-git:commit humanizer
```
→ Agent 分析 diff，推荐 patch 或 minor 版本升级，你确认后写入。例如新标签 `v1.0.2`。

---

### 🔀 将两个重叠技能合并为一个
你发现 `code-review` 和 `critic` 功能重复，想要整合。
```
/skill-git:scan code-review critic
/skill-git:merge code-review critic
```
→ 🔎 `scan` 评估重叠度（★★★ / ★★☆ / ★☆☆）。🔀 `merge` 交互式合并——确认前不写入任何内容。

---

### ⏪ 回滚破坏工作流的技能
你最新的 `planner` 更新引入了冲突，想要撤销。
```
/skill-git:revert planner
/skill-git:revert planner v1.0.2
```
→ 回滚到上一版本（或指定标签）。操作前自动备份，失败时自动恢复。

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

## 命令一览

| 命令 | 功能说明 |
|------|---------|
| 🚀 `init` | 初始化所有技能的版本追踪 |
| 🔖 `commit` | 快照变更，自动升级语义化版本标签 |
| ⏪ `revert` | 将技能回滚到任意历史版本 |
| 🛡️ `check` | 审查技能的规则冲突和安全问题 |
| 🔎 `scan` | 扫描语义重叠的技能并评级合并候选 |
| 🔀 `merge` | 将两个相似技能合并为一个更强的技能 |


### 🔖 `commit` — 保存新版本

```
/skill-git:commit
```

Agent 分析 diff 并推荐 patch 或 minor 升级。确认后写入。

### ⏪ `revert` — 回滚

```
/skill-git:revert humanizer
/skill-git:revert humanizer v1.0.2
```

省略版本号默认回滚到上一标签。操作原子化——先备份，失败自动恢复。

### 🛡️ `check` — 审查技能

```
/skill-git:check humanizer
```

检测内部规则冲突、矛盾配置和安全问题，返回结构化报告。

### 🔎 `scan` — 扫描重叠

```
/skill-git:scan
/skill-git:scan humanizer code-review
```

对技能库进行语义分析，找出规则重叠的技能对。每对评级 ★★★ / ★★☆ / ★☆☆，结果缓存供 `merge` 使用。

### 🔀 `merge` — 整合技能

```
/skill-git:merge
/skill-git:merge humanizer code-review
```

无参数运行时使用最新扫描结果。冲突交互式解决，确认前不写入任何内容。

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
