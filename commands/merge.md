---
name: skill-git:merge
description: Merge two or more similar skills into one stronger, more complete skill. Triggers on "merge skills", "combine skills", "consolidate skills", or after running /skill-git:scan. Usage: /skill-git:merge [skill-name skill-name ...]
argument-hint: <skill-a> <skill-b> [<skill-c> ...] [-a <agent>]
allowed-tools: Bash(bash *), AskUserQuestion
---

You are running `/skill-git:merge`. Follow these steps exactly.

Merge never overwrites anything silently. Every destructive action requires explicit user confirmation before execution.

## Task Tracking

You MUST create a task for each item below and update each task's status as you progress (pending → in_progress → completed):

1. **Resolve skills to merge** — parse arguments or select from latest scan results
2. **Load topics and show overlap** — extract/cache rules, cluster into topics, display summary
3. **Resolve conflicts** — present each conflicting topic and record user decisions (skip if none)
4. **Choose name and base folder** — prompt for merged skill name and which folder to use as base
5. **Synthesize merged SKILL.md** — generate draft, show for approval, iterate on edits
6. **Write files** — write SKILL.md, copy non-SKILL.md files, update config.json, delete sources
7. **Commit merged skill** — pre-flight check, confirm, run git add/commit/tag

---

## Prelude

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" $ARGUMENTS`

If STATUS is not `ok`:
- Re-examine RAW_ARGUMENTS — check if the user expressed an agent name or intent that can be semantically resolved.
- If you can determine intent, note the resolution and proceed.
- If STATUS is `not_initialized` and INITIALIZED_AGENTS is non-empty, suggest `/skill-git:init -a <agent>`.
- If STATUS is `error`, display REASON as a plain-language error and stop.
- If intent cannot be resolved, display a clear error and stop.

Use AGENT, GLOBAL_BASE, and SKILLS_JSON from prelude output for all subsequent steps. The `skills` map referred to throughout this document is the parsed content of SKILLS_JSON.

**Agent name in positional position:** If `$ARGUMENTS` contains a known agent name (claude, gemini, codex, openclaw) as a standalone positional token not preceded by `-a`, silently treat it as `-a <agent>`: override AGENT, re-read GLOBAL_BASE and SKILLS_JSON from `~/.skill-git/config.json` for that agent. Do not pass it to `requested_skills`.

---

## Step 1 — Argument Parsing

Parse `$ARGUMENTS`. The `-a <value>` flag is handled by the Prelude above.

Extract all remaining tokens (non-flag, non-flag-value) as `requested_skills`.

If `requested_skills` has exactly 1 name, respond:
  Error: merge requires at least 2 skills.
  Usage: /skill-git:merge <skill-a> <skill-b> [skill-c ...]
Then stop.

---

## Step 2 — Resolve Skills to Merge

### If `requested_skills` has 2+ names:

Validate each against the SKILLS_JSON map from prelude output using **exact match first, then fuzzy fallback**:

- **Exact match**: skill name is a key in `skills` → use directly.
- **Fuzzy fallback** (if exact match fails): search for registered skill names that contain the input as a substring (case-insensitive).
  - Exactly 1 fuzzy match → use it and note: `Resolved "<input>" → "<full-name>"`
  - 0 fuzzy matches → stop:
    ```
    Skill "<name>" not found in config.json.
    Registered skills: <comma-separated list>
    ```
  - 2+ fuzzy matches → stop:
    ```
    Ambiguous name "<name>" — matches multiple skills:
      <match-1>
      <match-2>
    Please specify the full name.
    ```

Set `merge_targets = requested_skills` (using resolved names). Skip to Step 3.

### If `requested_skills` is empty:

Check `~/.skill-git/cache/<agent>/scans/latest.json`.

**If `latest.json` does not exist:**

```
No scan results found. Running /skill-git:scan first...
```

Execute the full scan workflow inline (same logic as `scan.md` Steps 1–7, using `agent` and no skill filters). If scan finds no ★★★ or ★★☆ pairs, display the scan report and stop:
```
No merge candidates found. All pairs are below 30% overlap.
```

**If `latest.json` exists:**

Check staleness: for each skill in `latest.json["target_skills"]`, run:
```bash
git -C <skill_path> rev-parse --short HEAD 2>/dev/null
```
Compare against `latest.json["skill_versions"][<skill>]["commit_sha"]`. If any SHA has changed, display:
```
⚠️  Scan results may be stale — the following skills have changed since the last scan:
    - <skill-name>  (last scanned: v1.0.1, current: v1.0.2)
```

Then use the AskUserQuestion tool:
- question: "Scan results may be stale. How would you like to proceed?"
- header: "Action"
- options:
  - label: "Use stale results", description: "Continue with the existing scan results"
  - label: "Cancel", description: "Stop — run /skill-git:scan -f to refresh first"
- multiSelect: false

If "Cancel", stop.

**Select a pair:**

Display ★★★ and ★★☆ pairs from `latest.json["pairs"]` only. If none exist:
```
No merge candidates found (all pairs below 30% overlap).
Run /skill-git:scan to re-analyze, or specify skills directly:
  /skill-git:merge <skill-a> <skill-b>
```
Stop.

Display the last scan info and insight paragraph, then use the AskUserQuestion tool:
- question: "Select a pair to merge:"
- header: "Pair"
- options: build from ★★★ and ★★☆ pairs in `latest.json["pairs"]`, up to 3 pairs (label: "★★★  skill-a + skill-b  68%", description: "recommend merge" or "merge with caution"), plus a 4th option label: "Quit", description: "Exit without merging". If there are more than 3 candidate pairs, include the top 3 by overlap%.
- multiSelect: false

If "Quit" is selected, stop. Otherwise set `merge_targets` to the two skills of the chosen pair.

---

## Step 3 — Load Topics

**If `merge_targets` came from scan results** (`latest.json`):

Look up the matching pair in `latest.json["pairs"]`. Resolve the full topic objects for `shared_topic_ids`, `conflict_topic_ids`, and `unmatched_topic_ids` from `latest.json["topics"]`.

**If `merge_targets` were specified directly as arguments:**

For each skill in `merge_targets`, check rule cache at `~/.skill-git/cache/<agent>/rules/<skill-name>.json`:
- If cache exists and `commit_sha` matches `git -C <skill_path> rev-parse --short HEAD` → use cached rules
- Otherwise → read all files in the skill folder (`SKILL.md`, other `*.md`, scripts) and extract rules directly (same methodology as `scan` Phase 1)

Then run global clustering across all skills in `merge_targets` (same methodology as `scan` Phase 2 steps 5a–5b) to produce:
- `topics`: list of rule topics with entries
- Per pair: `shared_topics`, `conflict_topics`, `unmatched` topics

**After loading, display:**

```
Merging: <skill-a> + <skill-b>

  <N> shared topics        → will appear once in merged skill
  <N> unique to <skill-a>  → will be added
  <N> unique to <skill-b>  → will be added
  <N> conflicting topics   → need your decision
```

If there are 0 conflicting topics, note: `No conflicts — ready to synthesize.`

---

## Step 4 — Interactive Conflict Resolution

Skip this step entirely if there are 0 conflicting topics.

For each conflicting topic, display the separator and `Why:` explanation (mandatory — never omit it), then wait for user response before moving to the next.

The `Why:` line should explain the semantic difference in plain language (e.g. "skill-a gates changes with a scoring threshold; skill-b promotes based on recurrence count — different decision frameworks for when to act on a learning").

Use the AskUserQuestion tool for each conflict:
- question: "Conflict <N> of <total>: <topic label>. Why: <one-sentence explanation of the conflict>. Which rule to keep?"
- header: "Conflict <N>/<total>"
- options: build dynamically from the conflicting entries, up to 2 skill entries (label: "Keep <skill-name> rule", description: "<skill>:<line>  \"<rule text>\""). Always append:
  - label: "Write custom rule", description: "Enter replacement text in Other"
  - label: "Keep both", description: "Include both entries marked with <!-- TODO: resolve conflict -->"
- multiSelect: false
(For 3+ skill entries, include up to 2 in the options and note the others in descriptions; the user can use Other to specify.)

Record each decision:
- "Keep <skill> rule" → keep that entry verbatim
- "Write custom rule" → use the Other text as the custom rule
- "Keep both" → mark `keep_both: true`; all entries will be included with `<!-- TODO: resolve conflict -->` between them

After all conflicts are resolved:
```
All conflicts resolved. ✅
```

---

## Step 5 — Choose Merge Output

Ask both questions before proceeding.

**5a. Name:**

Use the AskUserQuestion tool:
- question: "Name for the merged skill? Suggested: '<short name derived from shared topic labels>'"
- header: "Skill name"
- options:
  - label: "Accept suggestion", description: "Use '<suggestion>' as the merged skill name"
  - label: "Enter custom name", description: "Type your preferred name in Other"
- multiSelect: false

If the name already exists as a folder under `<global_base>/skills/`, warn the user and use the AskUserQuestion tool:
- question: "'<name>' already exists as a skill folder. How to proceed?"
- header: "Name clash"
- options:
  - label: "Overwrite <name>", description: "Replace the existing skill folder with the merged result"
  - label: "Enter a different name", description: "Provide a new name in Other"
- multiSelect: false

**5b. Base folder:**

Use the AskUserQuestion tool:
- question: "Which folder to use as the base for the merged skill?"
- header: "Base folder"
- options:
  - label: "<skill-a>", description: "<path>  (reuses existing git history)"
  - label: "<skill-b>", description: "<path>  (reuses existing git history)"
  - label: "New folder", description: "<global_base>/skills/<merged-name>/  (fresh git history)"
- multiSelect: false

Choosing `[1]` or `[2]` writes the merged SKILL.md into that folder, preserving its git history. The folder name stays unchanged; only the `name` field in frontmatter updates to `<merged-name>`.

---

## Step 6 — Synthesize Merged SKILL.md

Generate the merged skill content:

```markdown
---
name: <merged name>
description: <synthesized description covering the full scope of merged skills>
version: 1.0.0
---

# <Merged Name>

<1–2 sentence introduction explaining what this skill covers>

## <Topic heading>

<rule text>

## <Topic heading>

<rule text>
```

**Synthesis rules:**
- **Shared topics**: write one best-worded rule — synthesize if both entries add nuance, otherwise pick the clearer one. Never duplicate.
- **Unique topics**: include verbatim. Integrate logically by topic; do not add section labels like "From code-style".
- **Resolved conflicts**: use the chosen text. For `keep_both`, include all entries with `<!-- TODO: resolve conflict -->` between them.
- **Non-SKILL.md files**: do not auto-merge. Append a note comment at the end of the file:
  ```
  <!-- Files to review (not auto-merged):
       <skill-a>: run.sh
       <skill-b>: examples.md, run.sh
  -->
  ```

Display the full draft:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Draft: <merged-name>

<full SKILL.md content>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then use the AskUserQuestion tool:
- question: "Approve this draft for '<merged-name>'?"
- header: "Draft"
- options:
  - label: "Yes, write it", description: "Write this SKILL.md and proceed to file operations"
  - label: "Edit draft", description: "Describe what to change in Other — draft will be regenerated"
  - label: "Quit", description: "Exit without saving — no files will be written"
- multiSelect: false

If "Edit draft": apply the Other revision instructions, regenerate the draft, display again, and repeat. If "Quit": stop. No files are written. config.json is unchanged.

---

## Step 7 — Write Files

Only execute after the user chooses `[y]` in Step 6.

**7a. Write SKILL.md:**

```bash
# base is an existing folder (choice [1] or [2]):
cat > <base_skill_path>/SKILL.md << 'EOF'
<merged content>
EOF

# new folder (choice [3]):
mkdir -p <global_base>/skills/<merged-name>
cat > <global_base>/skills/<merged-name>/SKILL.md << 'EOF'
<merged content>
EOF
git -C <global_base>/skills/<merged-name> init
```

**7b. Handle non-SKILL.md files:**

First, enumerate all non-SKILL.md, non-.git files and directories in each source skill folder:

```bash
find <skill-path> -not -path '*/.git/*' -not -name '.git' -not -name 'SKILL.md' \
  -mindepth 1 | sort
```

**Before copying, apply these filters:**

1. **`_meta.json` — never copy; always regenerate.**
   If `_meta.json` exists in any source skill, skip it from the copy step. Instead, after writing SKILL.md, generate a fresh `_meta.json` for the merged skill:
   ```json
   {
     "ownerId": "<ownerId from the base skill, or whichever source the user chose as [1]/[2]; omit if base is [3] and both differ>",
     "slug": "<merged-name>",
     "version": "1.0.0",
     "publishedAt": <current unix timestamp in milliseconds>
   }
   ```
   If base is `[3]` (new folder) and both sources have different `ownerId` values, ask:
   ```
   Which ownerId to use for the merged skill's _meta.json?
     [1] <skill-a> ownerId: <value>
     [2] <skill-b> ownerId: <value>
     [3] Omit ownerId (unpublished)
   ```

2. **Backup/draft files — skip and report.**
   Do not copy files matching these patterns (they are source-skill history artifacts):
   - `SKILL-v*.md`
   - `*-backup.*`, `*-draft.*`, `*.bak`

   List any skipped files in the final Output Summary under a `Skipped (source artifacts)` line.

3. **Identical file conflict — skip prompt silently.**
   When a file exists in both sources (conflict candidate), first check if the contents are identical:
   ```bash
   cmp -s <file-from-skill-a> <file-from-skill-b>
   ```
   If identical → keep base version silently, no prompt shown. Track in an `auto-merged (identical)` list for the summary.
   If different → show the conflict prompt as normal.

**Case A — base is an existing skill folder ([1] or [2]):**

All files already in the base folder are preserved automatically. Only files from the other source skill(s) need attention.

For each non-base source skill, list its non-SKILL.md contents. If any exist:

Display the list of files to copy from the other skill folder, then use the AskUserQuestion tool:
- question: "Copy these files from <other-skill> into <merged-skill-path>/?"
- header: "Copy files"
- options:
  - label: "Yes, copy files (Recommended)", description: "Files that conflict with the base will be shown for your decision"
  - label: "No, skip", description: "Do not copy any files from <other-skill>"
- multiSelect: false

Default is "Yes". If "Yes, copy files":
- For each file/directory unique to the other skill: copy preserving structure
  ```bash
  cp -r <other-skill-path>/<item> <merged-skill-path>/
  ```
- For each file that already exists in the base folder: use the AskUserQuestion tool:
  - question: "Conflict: '<filename>' exists in both <base-skill> and <other-skill>. Which version to keep?"
  - header: "File clash"
  - options:
    - label: "Keep base version", description: "Keep the <base-skill> copy, discard <other-skill>'s version"
    - label: "Use other version", description: "Replace with the <other-skill> copy"
    - label: "Keep both", description: "Rename <other-skill>'s copy to <filename>.<other-skill>"
  - multiSelect: false

**Case B — base is a new folder ([3]):**

Both source skills' files must be copied. Enumerate all non-SKILL.md, non-.git contents from both and display the file list, then use the AskUserQuestion tool:
- question: "Copy all files into <merged-skill-path>/?"
- header: "Copy files"
- options:
  - label: "Yes, copy files (Recommended)", description: "Files that exist in both sources will be shown for your decision"
  - label: "No, skip", description: "Do not copy any non-SKILL.md files"
- multiSelect: false

Default is "Yes". If "Yes, copy files":
1. Copy all files from skill-a first:
   ```bash
   find <skill-a-path> -not -path '*/.git/*' -not -name '.git' -not -name 'SKILL.md' \
     -mindepth 1 -maxdepth 1 | xargs -I{} cp -r {} <merged-skill-path>/
   ```
2. For each item from skill-b: if no conflict, copy directly. If a file or directory already exists from skill-a, use the AskUserQuestion tool:
   - question: "Conflict: '<filename>' exists in both <skill-a> and <skill-b>. Which version to keep?"
   - header: "File clash"
   - options:
     - label: "Keep <skill-a> version", description: "Use the copy from <skill-a>"
     - label: "Use <skill-b> version", description: "Replace with the copy from <skill-b>"
     - label: "Keep both", description: "Rename the <skill-b> copy to <filename>.<skill-b>"
   - multiSelect: false

If no non-SKILL.md files exist in any source skill, skip this sub-step silently.

**7c. Update config.json:**

Add the merged skill entry (if new folder) or update the existing entry version. Source skills that will be deleted are removed in step 7d.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-config-add.sh" "<agent>" "<merged-name>" "<merged-skill-path>" "v1.0.0"
```

**7d. Delete source skill folders:**

If base was `[3]` (new folder), both source folders still exist. Use the AskUserQuestion tool:
- question: "Delete source skills now that they have been merged into '<merged-name>'?"
- header: "Del sources"
- options:
  - label: "Yes, delete both", description: "Remove <skill-a> (<path>) and <skill-b> (<path>) from disk and config"
  - label: "No, keep them", description: "Leave source folders in place — you can delete them manually later"
- multiSelect: false

If base was `[1]` or `[2]`, only the other source still exists. Use the AskUserQuestion tool:
- question: "Delete <other-skill> now that it has been merged into '<merged-name>'?"
- header: "Del source"
- options:
  - label: "Yes, delete it", description: "Remove <other-skill> (<path>) from disk and config"
  - label: "No, keep it", description: "Leave <other-skill> in place — you can delete it manually later"
- multiSelect: false

Before deleting any folder, check for uncommitted changes:
```bash
git -C <skill-path> status --porcelain
```
If output is non-empty, use the AskUserQuestion tool:
- question: "<skill-name> has uncommitted changes. Delete anyway?"
- header: "Confirm"
- options:
  - label: "Yes, delete anyway", description: "Uncommitted changes will be permanently lost"
  - label: "No, cancel delete", description: "Skip deleting this skill folder"
- multiSelect: false

If confirmed, delete and remove from config.json:
```bash
rm -rf <skill-path>

bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-config-del.sh" "<agent>" "<skill-name>"
```

---

## Step 8 — Commit

Commit the merged skill using the same logic as `commit.md` Steps 4–5:

1. Determine version:
   - New folder (base `[3]`): `v1.0.0`
   - Reusing existing folder: run `git -C <path> describe --tags --abbrev=0 2>/dev/null`, increment MINOR (e.g. `v1.0.2` → `v1.1.0`)

2. Generate commit message: `merge <skill-a> and <skill-b> into <merged-name>`

3. Run a pre-flight check — verify each prior step completed successfully:
   - SKILL.md exists at `<merged-skill-path>/SKILL.md`
   - `config.json` contains an entry for `<merged-name>`
   - Source skill folders are in expected state (deleted or still present per user choice)

   Then display the pre-flight summary and use the AskUserQuestion tool. **This prompt is mandatory and must not be skipped.**

   Display:
   ```
   ⚠️  This will create a permanent git commit and version tag.

     Pre-flight:
       ✅ SKILL.md written to <merged-skill-path>
       ✅ config.json updated
       ✅ Source skills: <deleted / kept as chosen>
       [❌ <describe any failed check — stop and report if any ❌ present>]

     Ready to commit:
       <merged-name>  <current> → <new-version>
       "merge <skill-a> and <skill-b> into <merged-name>"
   ```

   Then use the AskUserQuestion tool:
   - question: "Proceed with creating the git commit and version tag for '<merged-name>'?"
   - header: "Commit"
   - options:
     - label: "Yes, proceed", description: "Create commit and tag <new-version> (permanent)"
     - label: "No, cancel", description: "Exit without committing"
   - multiSelect: false

   If any pre-flight item shows ❌, do not commit. Report what's missing and stop.

4. Execute:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<merged-skill-path>" add -A
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<merged-skill-path>" commit -m "<message>"
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-git.sh" "<merged-skill-path>" tag <new-version>
   ```

   If any command fails, show the git error and stop.

5. Update config.json with the new version:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-config-set.sh" "<agent>" "<merged-name>" "<new-version>"
   ```

---

## Output Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Merge complete ✅

  <merged-name>  <version>
  Path: <merged-skill-path>/SKILL.md

  Sources merged:  <skill-a> (<version-a>) + <skill-b> (<version-b>)
  Shared topics:   <N>  (unified)
  Added topics:    <N>  (<x> from <skill-a>, <y> from <skill-b>)
  Conflicts:       <N>  (resolved)  [or "<N> left as TODO" if any keep_both]

  Deleted: <skill-a>, <skill-b>   [omit line if nothing deleted]

  Auto-merged (identical):  <file-list, or omit line if none>
  Skipped (source artifacts):  <file-list, or omit line if none>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
