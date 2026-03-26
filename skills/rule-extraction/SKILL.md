---
name: Rule Extraction
description: Extract a structured list of rules from all markdown files at the top level of a skill directory. Use this skill whenever you need to parse rules out of a skill for conflict checking, merging, or diffing.
version: 1.1.0
---

# Rule Extraction

This skill teaches you how to extract a structured, line-numbered list of rules from a skill directory.

## What Counts as a Rule

A **rule** is any statement that prescribes or constrains agent behavior. Recognize rules by their form:

- **Imperative directives**: "Always add type annotations", "Never use `var`"
- **Prohibition patterns**: "Do not X", "Avoid X", "禁止 X"
- **Requirement patterns**: "Must X", "Should X", "需要 X", "必须 X"
- **Conditional behavior**: "If X, then Y", "When X, do Y"
- **Style/format mandates**: "Use camelCase", "Limit lines to 80 characters"
- **Preference statements**: "Prefer X over Y", "优先使用 X"

Rules can appear as:
- Bullet list items (`-` or `*` or `+`)
- Numbered list items (`1.`, `2.`)
- Bold or emphasized sentences (`**Always do X**`)
- Plain sentences within a paragraph that contain directive language
- Section headers that are themselves imperatives ("Never commit secrets")

## What Does NOT Count as a Rule

Exclude the following from extraction:

- **Descriptive text**: Explanations of why a rule exists, background context
- **Examples**: Code blocks, sample outputs, "for example..." passages
- **Metadata**: YAML frontmatter, version info, author notes
- **Headings that introduce a section** (unless the heading itself is an imperative rule)
- **Vague non-actionable statements**: "Do good work", "Be helpful" — extract these but flag them as `vague: true`

## Output Format

Return a JSON array. Each rule is an object:

```json
[
  {
    "id": 1,
    "file": "SKILL.md",
    "line": 12,
    "text": "Always add type annotations to function parameters",
    "source_text": "- Always add type annotations to function parameters",
    "vague": false
  },
  {
    "id": 2,
    "file": "SKILL.md",
    "line": 15,
    "text": "Do not use var, prefer const or let",
    "source_text": "**Do not use `var`** — prefer `const` or `let`",
    "vague": false
  },
  {
    "id": 3,
    "file": "examples.md",
    "line": 4,
    "text": "Do good work",
    "source_text": "- Do good work",
    "vague": true
  }
]
```

Field definitions:
- `id`: Sequential integer starting from 1, across all files combined
- `file`: Filename (basename only, e.g. `SKILL.md`, `examples.md`) where the rule appears
- `line`: Line number within that file where the rule appears (1-indexed)
- `text`: Cleaned rule text, stripped of markdown formatting
- `source_text`: Original raw line as it appears in the file
- `vague`: `true` if the rule is too broad to be actionable

## Input Scope

The input is a **skill directory path** (e.g. `~/.claude/skills/humanizer/`).

**Files to read:** all `*.md` files directly inside the skill directory — `SKILL.md` first, then any other `*.md` files in alphabetical order.

**Files to skip:**
- Subdirectories and any files inside them (no recursive scan)
- Non-markdown files (`.sh`, `.py`, `.js`, `.json`, etc.)

## Extraction Process

1. **List** all `*.md` files at the top level of the skill directory (non-recursive). Read `SKILL.md` first if present; read remaining `*.md` files in alphabetical order.
2. **For each file**, read it line by line, tracking line numbers within that file.
3. **Skip frontmatter** (everything between `---` delimiters at the top of each file)
4. **Skip code blocks** (between ` ``` ` fences) — these are examples, not rules
5. **For each line**, determine if it contains a rule using the criteria above
6. **For paragraph text**: split into sentences, check each sentence independently
7. **Clean the extracted text**: remove markdown syntax (`-`, `*`, `**`, backticks) but preserve the meaning
8. **Assign line numbers** based on where the rule text starts within its file
9. **Record the source filename** for every rule

## Handling Ambiguous Cases

- **Compound bullet**: "Use camelCase and limit lines to 80 chars" → split into two rules, both on the same line number
- **Nested bullets**: Treat each nested item as an independent rule
- **Conditional rules**: Keep the full conditional ("If Python, use type hints") as one rule — do not split on the condition
- **Negated rules**: "Don't use X" and "Never use X" are equivalent — normalize to a consistent form in `text`, preserve original in `source_text`

## Example

Input skill directory: `~/.claude/skills/code-style/`
Files found at top level: `SKILL.md`, `extra-rules.md`
(Any subdirectory contents are ignored.)

**SKILL.md:**
```
---
name: Code Style
---

# Code Style Guidelines

Keep code clean and maintainable.

## Naming
- Use camelCase for variables and functions
- Use PascalCase for classes and types
- Never use single-letter variable names except for loop indices

## Comments
Always write comments in English.
Do not write comments explaining what the code does — only explain why.

## Example
\`\`\`python
# good
def calculate_total(items):
    return sum(items)
\`\`\`
```

**extra-rules.md:**
```
- Prefer explicit returns over implicit ones
```

Output:
```json
[
  {
    "id": 1,
    "file": "SKILL.md",
    "line": 10,
    "text": "Use camelCase for variables and functions",
    "source_text": "- Use camelCase for variables and functions",
    "vague": false
  },
  {
    "id": 2,
    "file": "SKILL.md",
    "line": 11,
    "text": "Use PascalCase for classes and types",
    "source_text": "- Use PascalCase for classes and types",
    "vague": false
  },
  {
    "id": 3,
    "file": "SKILL.md",
    "line": 12,
    "text": "Never use single-letter variable names except for loop indices",
    "source_text": "- Never use single-letter variable names except for loop indices",
    "vague": false
  },
  {
    "id": 4,
    "file": "SKILL.md",
    "line": 15,
    "text": "Always write comments in English",
    "source_text": "Always write comments in English.",
    "vague": false
  },
  {
    "id": 5,
    "file": "SKILL.md",
    "line": 16,
    "text": "Do not write comments explaining what the code does — only explain why",
    "source_text": "Do not write comments explaining what the code does — only explain why.",
    "vague": false
  },
  {
    "id": 6,
    "file": "extra-rules.md",
    "line": 1,
    "text": "Prefer explicit returns over implicit ones",
    "source_text": "- Prefer explicit returns over implicit ones",
    "vague": false
  }
]
```

Notes:
- SKILL.md lines 18–23 (the code block) are skipped entirely
- `id` is sequential across all files; `line` resets to 1 for each new file
- Any subdirectories inside `~/.claude/skills/code-style/` are not scanned
