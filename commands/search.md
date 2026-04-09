---
name: skill-git:search
description: Discover skills from SkillHub (skills.sh) and ClawHub (clawhub.ai). Supports semantic search and finding online skills similar to a local skill. Triggers on "search for skills", "find a skill", "look for skill online", or "find something like my <skill>".
argument-hint: <query or natural language description>
allowed-tools: Bash(bash *), AskUserQuestion
---

You are running `/skill-git:search`. Follow these steps exactly.

All output shown to the user must be in English.

## Tool Loading

Before doing any work, load all required tools in a **single** ToolSearch call:
```
select:TaskCreate,TaskUpdate,TaskList,AskUserQuestion
```
Do not issue multiple ToolSearch calls.

## Task Tracking

You MUST create a task for each item below and update each task's status as you progress (pending → in_progress → completed):

1. **Detect intent** — parse $ARGUMENTS to determine mode, agent, and search query
2. **Init check** — validate local skill exists (similar mode only)
3. **Build search query** — use $ARGUMENTS directly (query mode) or extract from local skill (similar mode)
4. **Search registries** — query SkillHub and ClawHub in parallel
5. **Enrich ClawHub results** — fetch download counts from detail endpoint (similar mode: also filter locally installed skills)
6. **Filter and rank** — score candidates, select top 5
7. **Present results** — display summary table and detail blocks
8. **Offer to install** — prompt user to pick and install a result

---

## Step 0 — Intent Detection

Interpret `$ARGUMENTS` as natural language. Determine:

- **mode**: `query` or `similar`
  - `similar` if the user references a local skill they want to find online equivalents for (e.g. "something like my code-review", "类似我本地 tdd 的", "enhance my humanizer")
  - `query` otherwise (user describes what they want to find)
- **similar_skill**: the local skill name, if mode = `similar`; otherwise null
- **search_query**: the search keywords, if mode = `query`; for similar mode, this is not set here — it is built in Step 2
- **agent**: which agent's skill directory to use (default: `claude`; detect from phrases like "for gemini", "gemini 的", "on codex", etc.) — detected in all modes for consistency, but only used to resolve skill paths in similar mode

  | agent | base_dir |
  |-------|----------|
  | `claude` | `~/.claude` |
  | `gemini` | `~/.gemini` |
  | `codex` | `~/.codex` |
  | `openclaw` | `~/.openclaw` |

If mode is ambiguous between `similar` and `query` (e.g. user says "find skills like python testing" with no clear reference to a local skill), prefer `query` — do not ask for clarification.

If `$ARGUMENTS` is empty, use the AskUserQuestion tool:
- question: "What are you looking for? You can describe a skill you need, or mention a local skill you'd like to find online equivalents for."
- header: "Search"
- options: []
- multiSelect: false

Use the user's response as `$ARGUMENTS` and re-run intent detection.

---

## Step 1 — Init Check (similar mode only)

**Skip this step entirely if mode = `query`.**

Read `~/.skill-git/config.json`:
```bash
cat ~/.skill-git/config.json 2>/dev/null || echo "MISSING"
```

If the output is `MISSING`, the file does not exist, or the file has no `skills` under `agents.<agent>`:
```
skill-git is not initialized. Please run /skill-git:init first.
```
Stop.

Validate `similar_skill` against the `skills` map in `agents.<agent>.skills`. If not found:
```
Skill "<similar_skill>" not found.
Registered skills: <comma-separated list>
```
Stop.

Resolve `similar_skill_path` = `agents.<agent>.skills.<similar_skill>.path` from config.json.

Verify the path exists on disk:
```bash
[ -d "<similar_skill_path>" ] && echo "ok" || echo "missing"
```

If missing:
```
Skill path not found: <similar_skill_path>
Run /skill-git:init to re-register your skills.
```
Stop.

---

## Step 2 — Build Search Query

**Query mode:**

From `search_query`, extract 2–3 meaningful keywords by removing stop words and generic terms (e.g. "a", "the", "find", "skill", "功能", "一个", "做", "帮我"). Each keyword may be a single word or a two-word phrase — never three or more words. Store as `keywords[]` — each term is passed as a single argument to `npx skills find` and a single `curl` query in Step 3.

Examples:
- "我想找一个做ppt的功能" → `["ppt", "presentation slides", "slides"]`
- "how do I make my React app faster?" → `["react performance", "react"]`
- "can you help me with PR reviews?" → `["pr review", "code review"]`
- "I need to create a changelog" → `["changelog", "release notes"]`
- "Python code review automation" → `["python", "code review", "review automation"]`

**Similar mode:**

Extract keywords from the local skill's `description` frontmatter field.

1. Read the SKILL.md file in `<similar_skill_path>/`:
   ```bash
   cat "<similar_skill_path>/SKILL.md" 2>/dev/null | head -20
   ```
   If SKILL.md does not exist or has no `description` field in its frontmatter, set `keywords[] = [similar_skill]` (the folder name) and note `(no skill content found — searching by name only)` in the display. In this case, skip the `vs` line in Step 5b — there is no content to compare against.

2. Extract the `description` value from the YAML frontmatter (the text between `---` delimiters). Remove stop words and generic terms. Identify 2–3 meaningful keywords that capture the skill's purpose. Each keyword may be a single word or a two-word phrase — never three or more words (e.g., `description: "Improve academic paper writing"` → `["academic writing", "paper"]`).

3. Set `keywords[]` = those 2–3 keywords (each searched independently in Step 3).

Display:
```
Searching for skills similar to "<similar_skill>"...
Keywords: <keyword1>, <keyword2>, <keyword3>
```

---

## Step 3 — Search (SkillHub + ClawHub)

Run all search commands directly using the Bash tool — do **not** spawn subagents. Issue all Bash calls in a **single message** so they execute in parallel (SkillHub keywords + ClawHub keywords together). Do **not** use `&` within a single Bash call — each command runs once, sequentially within one shell invocation.

### 3a. SkillHub

Run one `npx skills find` call per keyword in `keywords[]`, all in the same Bash message as the ClawHub curl calls. Filter out the ASCII art banner printed by the CLI:

```bash
npx skills find "<keyword1>" 2>/dev/null
npx skills find "<keyword2>" 2>/dev/null
# ... one per keyword
```

Parse only lines matching `<owner>/<repo>@<skill>  <N> installs`; skip all other output (banner, decorators, empty lines) without error.

SkillHub CLI output format (one entry per skill):
```
<owner>/<repo>@<skill>  <N> installs
└ https://skills.sh/<owner>/<repo>/<skill>
```

Parse each entry into:
```json
{
  "source": "skillhub",
  "id": "<owner>/<repo>@<skill>",
  "name": "<skill>",
  "installs": <N>,
  "url": "https://skills.sh/<owner>/<repo>/<skill>",
  "install_cmd": "/skill-git:install skillhub:<owner>/<repo>@<skill>"
}
```

Collect all results from all keyword searches into `skillhub_raw`. A skill may appear multiple times (from different keyword searches) — duplicates are resolved in Step 3d.

SkillHub does not return descriptions in the find output. Leave `description` null.

If the output format does not match the expected pattern (e.g. a changed CLI version or a `No results found` message), treat it as zero results for that keyword. If **all** keywords fail, set `skillhub_error = "unexpected output format"`.

**On failure** (npx not installed, network error): set `skillhub_error = "<reason>"` and continue. Do not stop.

### 3b. ClawHub

Run one API call per keyword in `keywords[]` (in the same parallel Bash message as 3a), saving each response to a temp file:

```bash
curl -s "https://clawhub.ai/api/v1/search?q=<url-encoded-keyword1>" -o /tmp/sg_ch_k1.json
curl -s "https://clawhub.ai/api/v1/search?q=<url-encoded-keyword2>" -o /tmp/sg_ch_k2.json
# ... one file per keyword: sg_ch_k1.json, sg_ch_k2.json, sg_ch_k3.json
```

Response format per file: `{"results": [{"slug": "...", "displayName": "...", "summary": "...", "score": 3.4}]}`

ClawHub detail endpoint (`/api/v1/skills/<slug>`) response shape — do **not** probe this at runtime:
```json
{
  "skill": {
    "slug": "...",
    "displayName": "...",
    "summary": "...",
    "description": "...",
    "stats": { "downloads": 1234 }
  }
}
```
The correct description field is `summary`; `description` may also be present as a longer text. Always use `.summary // .description // ""`.

Do **not** parse the JSON in context — jq will process it in Step 3c.

**On failure** (curl not available, network error, non-200 response, malformed JSON): set `clawhub_error = "<reason>"` and continue. Do not stop.

### 3c. ClawHub Detail Enrichment

Run both sub-steps below using the Bash tool immediately after 3b completes.

**Step 3c-1** — filter, deduplicate, sort, extract top 8 slugs via jq.

Build `<kw_pattern>` by joining `keywords[]` with `|` (e.g. `recruitment|hiring`). Then run:

```bash
jq -rn '
  [inputs | .results[]] |
  unique_by(.slug) |
  map(select(
    (.displayName + " " + (.summary // "")) |
    ascii_downcase |
    test("<kw_pattern>")
  )) |
  sort_by(-.score) | .[0:8] | .[].slug
' /tmp/sg_ch_k1.json /tmp/sg_ch_k2.json > /tmp/sg_slugs.txt
# add /tmp/sg_ch_k3.json if a third keyword was used
```

If `/tmp/sg_slugs.txt` is empty, set `clawhub_error = "no relevant results"` and continue.

**Step 3c-2** — fetch detail pages for the selected slugs in parallel:

```bash
count=0
while IFS= read -r slug; do
  curl -s "https://clawhub.ai/api/v1/skills/$slug" -o "/tmp/sg_detail_${slug}.json" &
  count=$((count + 1))
done < /tmp/sg_slugs.txt
wait
echo "Fetched $count detail pages"
```

On failure for an individual slug: the output file will be missing or malformed; the jq scoring in Step 4 will skip it via `select(.skill != null)`. Do not stop.

### 3d. Error Handling After Both Complete

If **both** failed:
```
Could not reach either registry.

  SkillHub: <skillhub_error>
  ClawHub:  <clawhub_error>

Check your internet connection and try again.
```
Stop.

If only one failed, display a single-line warning before results:
```
⚠️  SkillHub unavailable (<reason>). Showing ClawHub results only.
```
or:
```
⚠️  ClawHub unavailable (<reason>). Showing SkillHub results only.
```

Proceed with whichever source succeeded.

### 3e. Merge and Deduplicate

**ClawHub**: already deduplicated and filtered by the jq pipeline in Step 3c. No further processing needed.

**SkillHub**: a skill may appear in multiple keyword searches. Within `skillhub_raw`, keep the entry with the highest install count for each unique `id`.

**No cross-source deduplication**: keep SkillHub and ClawHub as separate entries even if they share the same name.

Combine the deduplicated SkillHub entries with the ClawHub slugs list into a single `candidates` list.

If `candidates` is empty after merging:
```
No skills found for "<search_query>" on SkillHub or ClawHub.

Browse manually:
  https://skills.sh/
  https://clawhub.ai/
```
If mode = `similar`, additionally display:
```
Consider trying a broader query — e.g. the general domain of your skill:
  /skill-git:search <domain keywords from your skill>
```
Stop.

### 3f. Local Skill Filter (similar mode only)

**Skip this step entirely if mode = `query`.**

Use the skills map already loaded from config.json in Step 1. Build `local_names`: normalize each skill folder name (lowercase, replace `-`/`_` with space, strip `-skill`/`-skills` suffixes).

For each candidate in `candidates`, normalize its name the same way. If it matches any entry in `local_names`, remove it from `candidates` and add it to `local_excluded[]`.

If `local_excluded` is not empty, display one line before the results table:
```
(Skipped <N> already-installed skill(s): <comma-separated names>)
```

If all candidates were excluded and `candidates` is now empty:
```
All online results match skills you already have installed locally.

Your installed skills: <comma-separated list>

Consider trying a broader query:
  /skill-git:search <domain keywords from your skill>
```
Stop.

---

## Step 4 — Quality Filter and Ranking

### ClawHub scoring (jq — do not score in context)

Use the same `<kw_pattern>` from Step 3c. Run:

```bash
jq -rn --arg kws "<kw_pattern>" '
  [inputs | select(.skill != null) | .skill] |
  map({
    source:    "clawhub",
    slug:      .slug,
    name:      (.displayName // .slug),
    desc:      (.summary // .description // ""),
    downloads: (.stats.downloads // 0),
    url:       ("https://clawhub.ai/skills/" + .slug),
    install:   ("/skill-git:install clawhub:" + .slug)
  }) |
  map(. + {
    install_pts: (if .downloads >= 10000 then 3 elif .downloads >= 1000 then 2 elif .downloads >= 100 then 1 else 0 end),
    trust_pts:   (if .downloads >= 1000 then 1 else 0 end),
    rel_pts:     (if (.name + " " + .desc) | ascii_downcase | test($kws) then 1 else 0 end),
    flags:       ([(if .downloads < 100 then "⚠️ low installs" else empty end), (if .downloads >= 10000 then "✅ high downloads" else empty end)] | join(" "))
  }) |
  map(. + { total: (.install_pts + .trust_pts + .rel_pts) }) |
  sort_by(-.total, -.downloads) |
  .[0:5]
' /tmp/sg_detail_*.json
```

Read the JSON array output — this is your ranked ClawHub candidate list. Do not re-score it.

### SkillHub scoring (in context)

SkillHub results are plain text and small in volume. Score each entry in `skillhub_raw` in context on the same three dimensions:

1. **Install count** (0–3 pts): ≥10,000 → 3 + `✅ high downloads` / 1,000–9,999 → 2 / 100–999 → 1 / <100 → 0 + `⚠️ low installs`
2. **Source trust** (0–2 pts): Tier 1 authors (`vercel-labs`, `anthropic`, `google-labs-code`, `microsoft`, `composio`) → 2 + `✅ verified` / ≥1K installs → 1 / else → 0
3. **Relevance** (0–2 pts): keywords matched in name — 2+ → 2 / 1 → 1 / 0 → 0

### Final merge

Combine the jq-ranked ClawHub list with scored SkillHub entries. Sort combined list by `total` descending. Select top 5 overall.

If fewer than 5 candidates exist, show all. Never hide a result entirely — always show it with the appropriate `⚠️` markers.

---

## Step 5 — Present Results

Display results as a summary table followed by a detail block for each entry.

### 5a. Summary Table

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Search results for "<search_query>"  (SkillHub + ClawHub)

  #   Source      Skill                                          Installs   Flags
  ─── ─────────── ────────────────────────────────────────────── ────────── ──────────────────
  [1]  SkillHub    <owner/repo@skill>                              <N>
  [2]  ClawHub     <name>                                          <N>
  [3]  ClawHub     <name>                                          <N>
  [4]  SkillHub    <owner/repo@skill>                              <N>
  [5]  ClawHub     <name>                                          <N>        ⚠️ low installs
```

Column rules:
- **#**: selection number used in Step 6.
- **Source**: `SkillHub` or `ClawHub`.
- **Skill**: for SkillHub entries, use the full `id` (`owner/repo@skill`); for ClawHub entries, use the `name` field. Truncate to 50 chars with `…` if longer.
- **Installs**: right-aligned integer.
- **Flags**: `⚠️ low installs` (under 100), `✅ high downloads` (ClawHub ≥10K), `✅ verified` (SkillHub Tier 1 authors). Blank when none.

### 5b. Detail List

After the table, print the detail block for each entry in the same order:

```
─── [1] SkillHub — <owner/repo@skill> ───────────────────────────────────────────
  Installs : <N>
  Desc     : <description or "(no description)">
  Install  : /skill-git:install skillhub:<owner/repo@skill>
  URL      : <url>

─── [2] ClawHub — <name> ────────────────────────────────────────────────────────
  Installs : <N>
  Desc     : <description or "(no description)">
  Install  : /skill-git:install clawhub:<slug>
  URL      : <url>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After printing the closing separator, clean up temp files:
```bash
rm -f /tmp/sg_ch_k*.json /tmp/sg_slugs.txt /tmp/sg_detail_*.json
```

**Detail block rules:**

- **Desc**: always show this field. If no description is available from either source, print `(no description)`. Never leave the field blank or omit it.
- **Flags**: shown inline in the section header line after the skill name (e.g. `─── [5] ClawHub — design-doc-helper  ⚠️ low installs ───`).

**For similar mode**, add a `vs` line between `Desc` and `Install` — but only if skill content was successfully read in Step 2. If Step 2 fell back to name-only search, omit the `vs` line entirely:
```
  Desc     : <description>
  vs       : <1-sentence comparison against the local skill>
  Install  : <install command>
```

---

## Step 6 — Offer to Install

After displaying results, use the AskUserQuestion tool:
- question: "Install one of these?"
- header: "Install"
- options: one option per result in the top-5 list, using label `[N] <skill name>` and description `<install command>`; plus a final option with label `Skip` and description `Don't install anything`
- multiSelect: false

Wait for user input:

- **Number entered (e.g. `1`)**: resolve the selected entry.

  - **SkillHub result**: use the AskUserQuestion tool:
    - question: "Install with: /skill-git:install skillhub:<entry.id> ?  (y/n)"
    - header: "Confirm install"
    - options:
      - label: "Yes", description: "Run: /skill-git:install skillhub:<entry.id>"
      - label: "No", description: "Show the install command for manual use"
    - multiSelect: false

    If "Yes": delegate to the `/skill-git:install` command with argument `skillhub:<entry.id>`.
    If "No": display `Run manually: /skill-git:install skillhub:<entry.id>` and stop.

  - **ClawHub result**: use the AskUserQuestion tool:
    - question: "Install with: /skill-git:install clawhub:<slug> ?  (y/n)"
    - header: "Confirm install"
    - options:
      - label: "Yes", description: "Run: /skill-git:install clawhub:<slug>"
      - label: "No", description: "Show the install command for manual use"
    - multiSelect: false

    If "Yes": delegate to the `/skill-git:install` command with argument `clawhub:<slug>`.
    If "No": display `Run manually: /skill-git:install clawhub:<slug>` and stop.

- **"Skip" selected**: stop without installing. Display:
  ```
  To install later, use one of the install commands shown above.
  ```
