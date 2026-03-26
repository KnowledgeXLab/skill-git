---
name: skill-git:scan
description: Scan registered skills for semantic overlap and get merge suggestions. Triggers on "scan my skills", "find overlapping skills", "which skills can I merge", or before running /skill-git:merge.
argument-hint: [<skill-name> ...] [-a <agent>] [-f]
allowed-tools: Bash(bash *)
---

You are running `/skill-git:scan`. Follow these steps exactly.

All output shown to the user must be in English.

---

## Prelude

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS`

Parse `$ARGUMENTS` for remaining flags (after the prelude has consumed `-a <value>`):
1. Scan for `-f` or `--force`. If present, set `force = true`; otherwise `force = false`.
2. Extract all remaining tokens (non-flag, non-flag-value) as `requested_skills` list.

If STATUS is not `ok`:
- Re-examine RAW_ARGUMENTS — check if the user expressed an agent name or intent that can be semantically resolved (e.g. a typo, a paraphrase, or an implicit default).
- If you can determine intent, note the resolution and proceed.
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is non-empty, suggest `/skill-git:init -a <agent>`.
- If STATUS is `error`, display REASON as a plain-language error and stop.
- If intent cannot be resolved, display a clear error and stop.

Use AGENT, GLOBAL_BASE, and SKILLS_JSON from prelude output for all subsequent steps. The `skills` map referred to throughout this document is the parsed content of SKILLS_JSON.

**Agent name in positional position:** If `$ARGUMENTS` contains a known agent name (claude, gemini, codex, openclaw) as a standalone positional token not preceded by `-a`, silently treat it as `-a <agent>`: override AGENT, re-read GLOBAL_BASE and SKILLS_JSON from `~/.skill-git/config.json` for that agent. Do not pass it to `requested_skills`.

---

## Step 1 — Resolve Target Skills

1. If `requested_skills` is non-empty:
   - Validate each name as an exact key in the SKILLS_JSON map from prelude output.
   - If any name is not found, respond:
     ```
     Skill "<name>" not found in config.json.
     Registered skills: <comma-separated list>
     Run /skill-git:init to register new skills.
     ```
     Then stop.
   - Use `requested_skills` as the target set.

2. If `requested_skills` is empty: use all skills from the `skills` map as the target set.

3. If the target set has fewer than 2 skills:
   - 0 skills: `No skills registered. Run /skill-git:init first.` → stop.
   - 1 skill: `Only 1 skill registered — nothing to compare.` → stop.

---

## Step 2 — Unregistered Skill Warning

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-warn-unregistered.sh" "<global_base>" '<skills_json>'
```

Display the script output if any (do not stop).

---

## Step 3 — Description-Based Pre-filtering (Full Scan Only)

**Skip this step entirely if `requested_skills` was non-empty.** When the user specifies skills explicitly, compare all of them regardless of similarity.

For full-scan mode (all registered skills):

**3a. Read descriptions in parallel.**

For each skill in the target set, read its `SKILL.md` up to and including the closing `---` of the YAML frontmatter block (i.e., stop reading after the second `---` line). Use the Read tool directly — do not spawn subagents, and do not read the full file body. Fall back to the skill folder name if no SKILL.md or no `name` field; treat `description` as empty string if absent.

**3b. Evaluate pair similarity.**

For every pair `(skill_A, skill_B)`, judge whether their combined `name + description` suggests they address meaningfully overlapping domains. Assign each pair:
- **include** (similarity > 50%): the skills plausibly share behavioral rules or address overlapping concerns — proceed with full extraction
- **skip** (similarity ≤ 50%): the skills clearly address different domains — do not extract rules for this pair

Heuristics:
- Skills describing similar *workflows, behaviors, or output standards* → include
- Skills addressing the same *user action or tool category* → include
- Skills with no obvious behavioral intersection (e.g. "text humanizer" vs "video downloader") → skip
- When in doubt (missing descriptions, ambiguous names): **default to include**

**3c. Reduce the target set.**

Remove from the target set any skill that has **zero** qualifying (included) pairs. These skills will not undergo rule extraction in Step 4.

Store the count of skipped pairs as `pairs_prefilt_skipped` for Step 6 and Step 7.

If the filtered target set has fewer than 2 skills, display:
```
All skill pairs are in distinct domains — no merges to analyze.
(N pairs skipped as unrelated)
```
Then skip directly to Step 6 (save empty result) and Step 7 (no actionable pairs report).

**3d. Display pre-filter summary** (printed once, before Step 4):
```
Pre-filtering N skills by description... M pairs to analyze (K pairs skipped as unrelated)
```

---

## Step 4 — Phase 1: Parallel Rule Extraction

If `force = true`, display: `Scanning N skills... (force refresh, cache ignored)`
Otherwise display: `Scanning N skills...`

This line is printed once before subagents are launched; do not repeat it in the final report.

Divide the target skill list into batches of at most 10. Process batches serially; within each batch, spawn one subagent per skill in parallel. Wait for all subagents in a batch to complete before starting the next batch.

**Each subagent receives:** `skill_name`, `skill_path` (the skill folder path, e.g. `~/.claude/skills/humanizer/`), `agent`, `force`

**Each subagent does:**

1. Check if `<skill_path>` exists on disk. If the directory is missing entirely, return:
   ```json
   { "name": "<skill_name>", "error": "path not found" }
   ```

2. **Cache check** (skip entirely if `force = true`):
   - Read `~/.skill-git/cache/<agent>/rules/<skill_name>.json`
   - If the file exists:
     - Run `git -C <skill_path> rev-parse --short HEAD 2>/dev/null`
     - If the skill has a git repo and current SHA equals `commit_sha` in cache → return the cached result immediately (add `"from_cache": true`)
     - If no git repo: compare `stat`-based mtime of all files in `<skill_path>` against `extracted_at` — if no file is newer, return cached result
   - If cache miss or `force = true`: proceed to extraction

3. List all `.md` files inside `<skill_path>/`:
   - `SKILL.md` (primary, read first if present)
   - Other `*.md` files (e.g. `examples.md`, `context.md`)

   Script files (`.sh`, `.py`, `.js`, etc.) are intentionally excluded — scripts are implementation, not behavioral specification.

4. Read all collected files.

5. Extract rules from all collected files. Apply the rule extraction methodology directly — a rule is any of:
   - Explicit behavioral directive ("always do X", "never do Y")
   - Format or style requirement ("use 4-space indent")
   - Process constraint ("run tests before commit")
   - Tool or flag configuration that reflects behavior intent (e.g. `eslint --max-warnings=0`)

   Each rule carries:
   - `file`: source filename (e.g. `SKILL.md`, `examples.md`)
   - `line`: line number in that file
   - `text`: verbatim excerpt (do not rephrase)

6. Write the extracted rules to cache:
   - Get current git SHA: `git -C <skill_path> rev-parse --short HEAD 2>/dev/null` (null if no git repo)
   - Get current git tag: `git -C <skill_path> describe --tags --abbrev=0 2>/dev/null` (null if no tags)
   - Write `~/.skill-git/cache/<agent>/rules/<skill_name>.json`:
     ```json
     {
       "skill": "<skill_name>",
       "path": "<skill_path>",
       "version": "<tag or 'untracked'>",
       "commit_sha": "<sha or null>",
       "extracted_at": "<ISO 8601 UTC timestamp>",
       "rules": [ ... ]
     }
     ```

7. Return:
   ```json
   {
     "name": "code-style",
     "from_cache": false,
     "rules": [
       { "file": "SKILL.md",    "line": 12, "text": "always add type annotations to function signatures" },
       { "file": "examples.md", "line": 3,  "text": "use descriptive variable names, avoid x/y/z" }
     ]
   }
   ```

**Error cases per subagent:**
- Path does not exist on disk → return `{ "name": "<name>", "error": "path not found" }`
- Folder exists but is completely empty or has no readable files → return `{ "name": "<name>", "error": "empty skill folder" }`
- `SKILL.md` not found but other files exist → still extract from available files; note `(no SKILL.md)` in report.

**After all batches complete:**

Count how many skills returned `"from_cache": true` vs `false`. If `force = false` and any skills were cached, update the progress line (or print a follow-up):
```
Scanning N skills... (X from cache, Y re-extracted)
```

Collect all subagents that returned an error. For each:
- `path not found`: auto-remove from config.json and display canonical warning:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-handle-missing.sh" "<agent>" "<skill_name>" "<path>"
  ```
  Note: `<agent>` is the AGENT value from the prelude output (passed to the subagent). `<path>` is the skill folder path that was passed to the subagent.
- `empty skill folder` or other errors: skip this skill in Phase 2; note in report as `(skipped: empty skill folder)`.

Remove all errored skills from the analyzable set. If the remaining analyzable set has fewer than 2 skills, display:
```
Not enough skills to compare after skipping errors.
```
Then stop.

---

## Step 5 — Phase 2: Global Clustering + Pairwise Derivation

Take all rule lists from Phase 1 and run two sub-steps. No additional subagents needed.

**5a. Global Rule Clustering**

Pool **all** rules from **all** skills into one collection. Group them into **rule topics** by semantic similarity.

A rule topic groups rules that address the same behavior or constraint, regardless of skill or wording.

For each topic, record:
- `label`: short descriptive name (e.g. `"type annotations"`, `"quote style"`)
- `entries`: list of `{ skill, file, line, text }`, one per rule

**Clustering rules:**
- Each rule belongs to exactly one topic.
- Multiple rules from the same skill can share one topic (e.g. two indentation rules → one `"indentation"` topic).
- Prefer fine-grained topics; do not force unrelated rules together.
- Pre-filter non-behavioral rules (meta-commentary, writing advice, examples within rules) — they do not form topics.

**Conflict detection within topics:**

After clustering, check every topic with entries from more than one skill:
- **Direct contradiction**: entries explicitly state opposite behaviors (`always X` vs `never X`, `use X` vs `do not use X`)
- **Semantic contradiction**: entries address the same constraint but can't both be satisfied simultaneously

Mark conflicted topics with `"conflicted": true` and `"conflict_type": "direct"|"semantic"`. Scope overlaps (compatible, one more specific) are **not** conflicts.

**5b. Pairwise Metric Derivation**

For each pair `(skill_A, skill_B)`, derive all metrics from the topic list — no re-scanning needed:

- **`shared_topics`**: topics with entries from both skill_A and skill_B
- **`conflict_topics`**: shared topics where `conflicted: true` and the conflicting entries span both skills
- **`unmatched`**: topics with entries from skill_A **or** skill_B but not both (`skill` field identifies the source)
- **`A_topic_count`**: distinct topics containing at least one entry from skill_A
- **`B_topic_count`**: same for skill_B

**Overlap percentage:**
```
overlap% = (|shared_topics| × 2) / (A_topic_count + B_topic_count) × 100
```

**Star rating:**
- ≥60% → ★★★ (recommend merge)
- 30–59% → ★★☆ (merge with caution)
- <30% → ★☆☆ (no merge needed)

---

## Step 6 — Save Scan Results

Run Step 7 (Output Report) **first** to generate the insight paragraph, then persist the complete result — including `insight` — to disk.

**6a. Build the result object:**
```json
{
  "scanned_at": "<ISO 8601 UTC timestamp>",
  "agent": "<agent>",
  "target_skills": ["code-style", "code-review", "humanizer"],
  "skill_versions": {
    "code-style":  { "version": "v1.0.2", "commit_sha": "abc123de" },
    "code-review": { "version": "v1.1.0", "commit_sha": "ff8821bc" }
  },
  "topics": [
    {
      "id": 1,
      "label": "type annotations",
      "conflicted": false,
      "entries": [
        { "skill": "code-style",  "file": "SKILL.md", "line": 12, "text": "always add type annotations" },
        { "skill": "code-review", "file": "SKILL.md", "line": 8,  "text": "annotate all function signatures" }
      ]
    },
    {
      "id": 2,
      "label": "quote style",
      "conflicted": true,
      "conflict_type": "direct",
      "entries": [
        { "skill": "code-style",  "file": "SKILL.md", "line": 8,  "text": "use single quotes" },
        { "skill": "code-review", "file": "SKILL.md", "line": 12, "text": "use double quotes" }
      ]
    },
    {
      "id": 3,
      "label": "indentation",
      "conflicted": false,
      "entries": [
        { "skill": "code-style", "file": "SKILL.md", "line": 5, "text": "use 2-space indentation" }
      ]
    }
  ],
  "pairs": [
    {
      "skill_a": "code-style",
      "skill_b": "code-review",
      "overlap_pct": 68,
      "rating": "3star",
      "shared_topic_ids": [1],
      "conflict_topic_ids": [2],
      "unmatched_topic_ids": [3]
    }
  ],
  "summary": {
    "total_skills": 3,
    "total_pairs_analyzed": 3,
    "pairs_prefilt_skipped": 0,
    "recommended": 1,
    "optional": 0,
    "below_threshold": 2
  },
  "insight": "<the insight paragraph generated in Step 7>"
}
```

Field notes:
- `topics`: global topic list defined once; pairs reference by id — no rule text duplication
- `topics[].conflicted`: `true` when entries from different skills contradict each other; `conflict_type` is `"direct"` or `"semantic"`
- `pairs[].shared_topic_ids`: topics containing entries from both skills
- `pairs[].conflict_topic_ids`: subset of `shared_topic_ids` where `conflicted: true` and conflict spans both skills
- `pairs[].unmatched_topic_ids`: topics with entries from only one of the two skills
- `insight`: the natural language paragraph generated in Step 7 — write it to the result object **after** generating it, before saving to disk
- `rating`: `"3star"` / `"2star"` / `"1star"` (avoid Unicode star characters in JSON)
- `skill_versions`: collect from each subagent's cache write result (version + commit_sha)
- `summary.total_pairs_analyzed`: pairs that passed the description pre-filter and were fully analyzed
- `summary.pairs_prefilt_skipped`: pairs skipped in Step 3 as unrelated; `0` when `requested_skills` was non-empty

**6b. Ensure directories exist:**
```bash
mkdir -p ~/.skill-git/cache/<agent>/scans/history
```

**6c. Write `latest.json`:**
```bash
# write result JSON to latest.json
cat > ~/.skill-git/cache/<agent>/scans/latest.json << 'EOF'
<result JSON>
EOF
```

**6d. Write timestamped history file:**

Use the `scanned_at` timestamp as filename, replacing `:` with `-`:
```bash
# e.g. 2026-03-23T14-30-00Z.json
cp ~/.skill-git/cache/<agent>/scans/latest.json \
   ~/.skill-git/cache/<agent>/scans/history/<timestamp>.json
```

**6e. Trim history to 20 most recent files:**
```bash
ls -1t ~/.skill-git/cache/<agent>/scans/history/*.json \
  | tail -n +21 \
  | xargs -r rm --
```

---

## Step 7 — Output Report

Format and display the final report. The `Scanning N skills...` line was already printed in Step 4 and is **not** repeated here.

Render each pair by looking up topic details from the `topics` list using the id arrays in each pair.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Merge suggestions (N skills, M pairs analyzed):

  ★★★  code-style + code-review     68%  → recommend merge

       Shared topics (3):
         type annotations
           code-style:12   "always add type annotations"
           code-review:8   "annotate all function signatures"

         naming conventions
           code-style:20   "use descriptive variable names"
           code-review:15  "avoid single-letter variable names"

         complexity limits
           code-style:18   "max cyclomatic complexity: 10"
           code-review:31  "flag functions over complexity 10"

       Only in code-style (2 topics):
         • indentation     "use 2-space indentation"            (code-style:5)
         • arrow functions "prefer arrow functions"             (code-style:20)

       Only in code-review (1 topic):
         • PR annotations  "flag TODO comments in PR reviews"   (code-review:45)

       ⚠️  Conflicting topics (1):
         quote style
           code-style:8    "use single quotes"
           code-review:12  "use double quotes"

  ★★☆  testing + tdd                41%  → merge with caution

       Shared topics (1):
         test-first
           testing:5   "write tests before implementation"
           tdd:2       "no production code without a failing test"

       Only in testing (3 topics):
         • coverage      "aim for 80% coverage minimum"          (testing:21)
         • mocking       "mock external dependencies"            (testing:14)
         • ... and 1 more topic

       Only in tdd (2 topics):
         • red-green     "red-green-refactor cycle required"     (tdd:8)
         • no-impl-first "no implementation before test"         (tdd:15)

       ✅ No conflicting topics

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: X recommended, Y optional, Z pairs below threshold (no action needed)

<insight paragraph>

Results saved to ~/.skill-git/cache/<agent>/scans/latest.json
  → Run /skill-git:merge to start the merge workflow.
  (Rules extracted from .md files only — script files excluded)
```

**`<insight paragraph>` rules:**

Write 2–4 sentences of natural language insight based on the actual scan results. Do NOT use a fixed template — tailor it to what was found. Cover:
- What the high-overlap pairs have in common (shared topic areas)
- Whether conflicts complicate a merge, and how significant they are
- A concrete suggestion: which pair to merge first and why, or why no action is needed

Examples:

> `code-style` and `code-review` share three rule topics — type safety, naming, and complexity — covering 68% of their combined rules. One direct conflict on quote style must be resolved before merging. Start here.

> `testing` and `tdd` share a single topic (test-first principle) but diverge significantly on tooling and workflow. No conflicts, but the unmatched rules reflect different philosophies — a merge requires reconciliation.

> All pairs scored below 30%. Your skills cover distinct domains and do not need consolidation at this time.

**Display rules:**

*Sorting:* ★★★ first, then ★★☆, sorted by overlap% descending within each group.

*Shared topics block:* Show at most 3 topics; if more exist, append `  ... and N more shared topics` after the third. For each displayed topic, list all entries from both skills. If a topic has 3+ entries from the same skill, show the first 2 and append `  + N more from <skill>`.

*★☆☆ pairs:* Do **not** list them — **except** if they have conflicting topics. A ★☆☆ pair with conflicts gets a compact entry:
```
  ★☆☆  humanizer + code-review      12%
       ⚠️  Conflicting topics (1):
         tone
           humanizer:3    "always respond in formal tone"
           code-review:7  "match the user's tone and register"
```

*Conflicting topics:* Show all skills' entries in the topic side by side (not just the two skills in the current pair — a topic may involve 3+ skills):
```
       ⚠️  Conflicting topics (1):
         quote style                        ← 3 positions
           code-style:8    "use single quotes"
           code-review:12  "use double quotes"
           linting:3       "enforce quotes via eslint config"
```

*Per-section display limits:*
| Section | Max shown | Overflow label |
|---------|-----------|----------------|
| Shared topics | 3 topics | `... and N more shared topics` |
| Only in skill_X (per skill) | 3 topics | `... and N more topics` |
| Conflicting topics | **all** | (never truncated) |

*`(source:line)` reference* omits `SKILL.md` filename:
- Rule from `SKILL.md` line 12 of `code-style` → `code-style:12`
- Rule from `examples.md` line 3 of `code-style` → `code-style:examples.md:3`

**No actionable pairs (and no conflicts):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Merge suggestions (N skills, M pairs analyzed):

  No merges recommended.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 0 recommended, 0 optional, M pairs below threshold (no action needed)

<insight paragraph>

Results saved to ~/.skill-git/cache/<agent>/scans/latest.json
  → Run /skill-git:merge to start the merge workflow.
  (Rules extracted from .md files only — script files excluded)
```
