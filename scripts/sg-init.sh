#!/usr/bin/env bash
set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
AGENT=""
AGENT_EXPLICIT=false
PROJECT_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a) AGENT="${2:?'-a requires an agent name'}"; AGENT_EXPLICIT=true; shift 2 ;;
    --project) PROJECT_MODE=true; shift ;;
    *) echo "[skill-git] Error: unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Agent auto-detection (when -a is not provided) ────────────────────────────
if [ "$AGENT_EXPLICIT" = "false" ]; then
  PARENT_COMM=$(ps -p "$PPID" -o comm= 2>/dev/null | tr -d ' ' || true)
  DETECTED=""
  if   echo "$PARENT_COMM" | grep -qi "gemini";         then DETECTED="gemini"
  elif echo "$PARENT_COMM" | grep -qi "codex";          then DETECTED="codex"
  elif echo "$PARENT_COMM" | grep -qi "openclaw\|claw"; then DETECTED="openclaw"
  elif echo "$PARENT_COMM" | grep -qi "claude";         then DETECTED="claude"
  fi

  if [ -n "$DETECTED" ]; then
    AGENT="$DETECTED"
    echo "[info] Agent auto-detected from process: $AGENT"
    echo ""
  else
    AGENT="claude"
    echo "[info] Could not detect CLI agent from process — defaulting to claude."
    echo "       Use -a <agent> to specify: claude, gemini, codex, openclaw"
    echo ""
  fi
fi

# ── Directory resolution ──────────────────────────────────────────────────────
case "$AGENT" in
  claude)   GLOBAL_BASE="$HOME/.claude" ;;
  gemini)   GLOBAL_BASE="$HOME/.gemini" ;;
  codex)    GLOBAL_BASE="$HOME/.codex" ;;
  openclaw) GLOBAL_BASE="$HOME/.openclaw" ;;
  *)        GLOBAL_BASE="" ;;
esac

TARGET_DIRS=()  # entries: "label|path"
for subdir in skills; do
  candidate="$GLOBAL_BASE/$subdir"
  [ -d "$candidate" ] && TARGET_DIRS+=("Global $subdir|$candidate")
done

# openclaw also scans ~/.openclaw/workspace/skills/ as a second managed location
if [ "$AGENT" = "openclaw" ]; then
  workspace_dir="$HOME/.openclaw/workspace/skills"
  [ -d "$workspace_dir" ] && TARGET_DIRS+=("OpenClaw workspace skills|$workspace_dir")
fi

if $PROJECT_MODE; then
  # openclaw workspace skills live at <workspace>/skills, not <workspace>/.openclaw/skills
  if [ "$AGENT" = "openclaw" ]; then
    PROJECT_BASE="$PWD"
  else
    PROJECT_BASE="$PWD/.$AGENT"
  fi
  for subdir in skills; do
    candidate="$PROJECT_BASE/$subdir"
    [ -d "$candidate" ] && TARGET_DIRS+=("Project $subdir|$candidate")
  done
fi

if [ ${#TARGET_DIRS[@]} -eq 0 ]; then
  echo "[skill-git] Error: no tracked directories found for agent '$AGENT'" >&2
  exit 1
fi

# ── Per-item counters ─────────────────────────────────────────────────────────
COUNT_TOTAL=0
COUNT_INITIALIZED=0
COUNT_TAGGED=0
COUNT_SKIPPED=0
COUNT_ERROR=0

# ── Skills registry (bash 3.2 compatible: plain array of "name|path|version") ─
SKILL_ENTRIES=()

# ── Helpers ───────────────────────────────────────────────────────────────────

_case_a() {
  local item_dir="$1" name="$2"
  # Exclude OS noise before staging
  echo ".DS_Store" >> "$item_dir/.gitignore"
  if git init "$item_dir" > /dev/null 2>&1 \
    && git -C "$item_dir" \
         -c user.email="skill-git@local" -c user.name="skill-git" \
         add . > /dev/null 2>&1 \
    && git -C "$item_dir" \
         -c user.email="skill-git@local" -c user.name="skill-git" \
         commit --allow-empty -m "initial commit" > /dev/null 2>&1 \
    && git -C "$item_dir" tag v1.0.0 > /dev/null 2>&1; then
    printf "  [ok] %-24s initialized  v1.0.0\n" "$name"
    ((COUNT_INITIALIZED++)) || true
    SKILL_ENTRIES+=("$name|$item_dir|v1.0.0")
  else
    printf "  [err] %-23s error        git init failed\n" "$name"
    ((COUNT_ERROR++)) || true
  fi
}

_case_c() {
  local item_dir="$1" name="$2"
  local first
  first=$(git -C "$item_dir" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
  if [ -z "$first" ]; then
    printf "  [err] %-23s error        could not find first commit\n" "$name"
    ((COUNT_ERROR++)) || true
    return
  fi
  if git -C "$item_dir" tag v1.0.0 "$first" > /dev/null 2>&1; then
    printf "  [ok] %-24s tagged       v1.0.0\n" "$name"
    ((COUNT_TAGGED++)) || true
    SKILL_ENTRIES+=("$name|$item_dir|v1.0.0")
  else
    printf "  [err] %-23s error        git tag failed\n" "$name"
    ((COUNT_ERROR++)) || true
  fi
}

_case_d() {
  local item_dir="$1" name="$2"
  local latest
  latest=$(git -C "$item_dir" describe --tags --abbrev=0 2>/dev/null)
  printf "  [ok] %-24s skipped      %s (already versioned)\n" "$name" "$latest"
  ((COUNT_SKIPPED++)) || true
  SKILL_ENTRIES+=("$name|$item_dir|$latest")
}

init_item() {
  local item_dir="$1"
  local name; name=$(basename "$item_dir")
  ((COUNT_TOTAL++)) || true

  if [ ! -d "$item_dir/.git" ]; then
    _case_a "$item_dir" "$name"
  elif ! git -C "$item_dir" rev-parse HEAD > /dev/null 2>&1; then
    # Case B: .git exists but no commits — remove and reinit fresh
    rm -rf "$item_dir/.git"
    _case_a "$item_dir" "$name"
  elif [ -z "$(git -C "$item_dir" tag --list 'v*' 2>/dev/null)" ]; then
    _case_c "$item_dir" "$name"
  else
    _case_d "$item_dir" "$name"
  fi
}

# ── Main loop ────────────────────────────────────────────────────────────────
echo "[skill-git] Starting initialization..."
echo "[info] Scope: global only. To also init project-level skills, re-run with --project."
echo ""

DIRS_ENTERED=0

for entry in "${TARGET_DIRS[@]}"; do
  label="${entry%%|*}"
  target_path="${entry#*|}"

  echo "--- $label: $target_path ---"
  echo ""
  ((DIRS_ENTERED++)) || true

  # Nested git check: inspect TARGET_DIR's *parent* for an enclosing repo.
  # Checking the parent avoids false positives from item-level .git repos
  # that we are about to create inside TARGET_DIR.
  parent_dir="$(dirname "$target_path")"
  if git -C "$parent_dir" rev-parse --git-dir > /dev/null 2>&1; then
    parent_git=$(git -C "$parent_dir" rev-parse --show-toplevel 2>/dev/null || echo "unknown")
    echo "[warn] This directory is inside an existing git repo ($parent_git)."
    echo "       Items initialized here will be nested git repos and will NOT appear in your"
    echo "       project's git history. This is expected behavior."
    echo ""
  fi

  # Scan real subdirs and symlinks to directories (-L follows symlinks; -type d matches both)
  found=0
  while IFS= read -r -d '' item_dir; do
    init_item "$item_dir"
    found=1
  done < <(find -L "$target_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

  if [ "$found" -eq 0 ]; then
    echo "[info] No items found in $target_path"
  fi
  echo ""
done

# ── Write config.json ─────────────────────────────────────────────────────────
SKILL_GIT_DIR="$HOME/.skill-git"
mkdir -p "$SKILL_GIT_DIR"
CONFIG_FILE="$SKILL_GIT_DIR/config.json"
LOCAL_CONFIG="$SKILL_GIT_DIR/config.local.md"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

EXISTING="{}"
[ -f "$CONFIG_FILE" ] && EXISTING=$(cat "$CONFIG_FILE")

# Preserve existing initialized_at for this agent if already set
EXISTING_TS=$(echo "$EXISTING" | jq -r --arg a "$AGENT" '.agents[$a].initialized_at // empty' 2>/dev/null || true)
INIT_TS="${EXISTING_TS:-$NOW}"

# Merge: update only current agent's entry, preserve all others.
# Preserve existing skills map so prior entries are not wiped on re-init.
UPDATED=$(echo "$EXISTING" | jq \
  --arg agent "$AGENT" \
  --arg base "$GLOBAL_BASE" \
  --arg ts "$INIT_TS" \
  '
  .agents[$agent].global_base    = $base |
  .agents[$agent].initialized_at = $ts   |
  .agents[$agent].skills         = (.agents[$agent].skills // {})
  ')

# Write each successfully processed skill into the registry.
# Case D rule: if the skill already exists in config.json with a version,
# preserve that version (registry is authoritative; do not re-read the tag).
for entry in "${SKILL_ENTRIES[@]}"; do
  skill_name="${entry%%|*}"
  rest="${entry#*|}"
  skill_path="${rest%%|*}"
  skill_ver="${rest##*|}"

  EXISTING_VER=$(echo "$UPDATED" | jq -r \
    --arg a "$AGENT" --arg n "$skill_name" \
    '.agents[$a].skills[$n].version // empty' 2>/dev/null || true)

  if [ -n "$EXISTING_VER" ]; then
    # Registry already has a version — preserve it (Case D authoritative rule)
    UPDATED=$(echo "$UPDATED" | jq \
      --arg a "$AGENT" --arg n "$skill_name" --arg p "$skill_path" \
      '.agents[$a].skills[$n].path = $p')
  else
    UPDATED=$(echo "$UPDATED" | jq \
      --arg a "$AGENT" --arg n "$skill_name" \
      --arg p "$skill_path" --arg v "$skill_ver" \
      '.agents[$a].skills[$n] = {"path": $p, "version": $v}')
  fi
done

echo "$UPDATED" > "$CONFIG_FILE"

# ── Write config.local.md (template, only if not already present) ─────────────
if [ ! -f "$LOCAL_CONFIG" ]; then
  cat > "$LOCAL_CONFIG" << 'EOF'
---
# skill-git user configuration
# Edit this file to customize skill-git behavior.
# This file is never overwritten by skill-git updates.

# default_agent: which agent to use when -a is not specified.
# Supported values: claude, gemini, codex, openclaw
# If omitted, skill-git auto-detects from the running process.
#
# default_agent: claude

# Custom agent definitions (optional).
# Use this section to add agents not built into skill-git.
#
# agents:
#   my-custom-agent:
#     project_config: "MY-AGENT.md"
#     global_config: "~/.my-agent/MY-AGENT.md"
#     project_skill_paths:
#       - ".my-agent/skills/"
#       - ".my-agent/plugins/*/skills/"
#     global_skill_paths:
#       - "~/.my-agent/skills/"
#       - "~/.my-agent/plugins/*/skills/"
---
EOF
  echo "[info] Created ~/.skill-git/config.local.md (edit to customize defaults)"
  echo ""
fi

# ── Summary ───────────────────────────────────────────────────────────────────
DIR_WORD="directories"
[ "$DIRS_ENTERED" -eq 1 ] && DIR_WORD="directory"

echo "--- Summary ---"
echo ""
echo "  Agent:   $AGENT"
echo "  Scanned: $COUNT_TOTAL items across $DIRS_ENTERED $DIR_WORD"
echo "  Result:  $COUNT_INITIALIZED initialized, $COUNT_TAGGED tagged, $COUNT_SKIPPED skipped, $COUNT_ERROR errors"
echo ""
echo "[skill-git] Done. Run /skill-git:commit to save your next snapshot."
