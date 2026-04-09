#!/usr/bin/env bash
# sg-delete.sh — list, inspect, and delete registered skills.
#
# Usage:
#   sg-delete.sh --list    <global_base> <skills_json>
#   sg-delete.sh --info    <skill_name> <global_base> <skills_json>
#   sg-delete.sh --execute <skill_name> <agent> <global_base> <skills_json>
#
# chmod +x scripts/sg-delete.sh

set -euo pipefail

source "$(dirname "$0")/sg-common.sh"

MODE="${1:-}"
shift

# ── --list ────────────────────────────────────────────────────────────────────
# Output all registered skills with their path, version, and dirty status.
# Output format (key=value lines):
#   SKILL_COUNT=N
#   SKILL_N_NAME=<name>
#   SKILL_N_VERSION=<version>
#   SKILL_N_PATH=<path>
#   SKILL_N_DIRTY=true|false
if [[ "$MODE" == "--list" ]]; then
  GLOBAL_BASE="$1"
  SKILLS_JSON="$2"

  if ! command -v jq &>/dev/null; then
    echo "STATUS=error"
    echo "REASON=jq_not_installed"
    exit 1
  fi

  SKILL_NAMES=()
  while IFS= read -r line; do
    SKILL_NAMES+=("$line")
  done < <(echo "$SKILLS_JSON" | jq -r 'keys | sort[]' 2>/dev/null)

  echo "SKILL_COUNT=${#SKILL_NAMES[@]}"

  i=1
  for name in "${SKILL_NAMES[@]}"; do
    path=$(echo "$SKILLS_JSON" | jq -r --arg n "$name" '.[$n].path')
    version=$(echo "$SKILLS_JSON" | jq -r --arg n "$name" '.[$n].version // "unknown"')

    dirty="false"
    if [[ -d "$path/.git" ]]; then
      status_out=$(git -C "$path" status --porcelain 2>/dev/null || true)
      [[ -n "$status_out" ]] && dirty="true"
    fi

    echo "SKILL_${i}_NAME=$name"
    echo "SKILL_${i}_VERSION=$version"
    echo "SKILL_${i}_PATH=$path"
    echo "SKILL_${i}_DIRTY=$dirty"
    i=$((i + 1))
  done
  exit 0
fi

# ── --info ────────────────────────────────────────────────────────────────────
# Return metadata for a single skill.
# Output format (key=value lines):
#   STATUS=ok
#   SKILL_PATH=<path>
#   SKILL_VERSION=<version>
#   IS_SYMLINK=true|false
#   IS_DIRTY=true|false
#   DIRTY_SUMMARY=<human-readable summary, empty if clean>
if [[ "$MODE" == "--info" ]]; then
  SKILL_NAME="$1"
  GLOBAL_BASE="$2"
  SKILLS_JSON="$3"

  if ! command -v jq &>/dev/null; then
    echo "STATUS=error"
    echo "REASON=jq_not_installed"
    exit 1
  fi

  exists=$(echo "$SKILLS_JSON" | jq -r --arg n "$SKILL_NAME" 'has($n)' 2>/dev/null || echo "false")
  if [[ "$exists" != "true" ]]; then
    echo "STATUS=not_found"
    exit 0
  fi

  path=$(echo "$SKILLS_JSON" | jq -r --arg n "$SKILL_NAME" '.[$n].path')
  version=$(echo "$SKILLS_JSON" | jq -r --arg n "$SKILL_NAME" '.[$n].version // "unknown"')

  is_symlink="false"
  [[ -L "$path" ]] && is_symlink="true"

  is_dirty="false"
  dirty_summary=""
  if [[ -d "$path/.git" ]]; then
    status_out=$(git -C "$path" status --porcelain 2>/dev/null || true)
    if [[ -n "$status_out" ]]; then
      is_dirty="true"
      modified=$(echo "$status_out" | grep -c '^ M\|^M ' || true)
      untracked=$(echo "$status_out" | grep -c '^??' || true)
      parts=()
      [[ $modified -gt 0 ]] && parts+=("${modified} file(s) modified")
      [[ $untracked -gt 0 ]] && parts+=("${untracked} untracked")
      dirty_summary=$(IFS=', '; echo "${parts[*]}")
    fi
  fi

  echo "STATUS=ok"
  echo "SKILL_PATH=$path"
  echo "SKILL_VERSION=$version"
  echo "IS_SYMLINK=$is_symlink"
  echo "IS_DIRTY=$is_dirty"
  echo "DIRTY_SUMMARY=$dirty_summary"
  exit 0
fi

# ── --execute ─────────────────────────────────────────────────────────────────
# Delete skill from disk then remove from config.json.
# If the path is a symlink, only the symlink is removed (source files untouched).
# rm failure aborts before touching config (keeps both in sync).
# Output format (key=value lines):
#   STATUS=ok
#   DELETED_PATH=<path>
#   PATH_EXISTED=true|false
#   WAS_SYMLINK=true|false
if [[ "$MODE" == "--execute" ]]; then
  SKILL_NAME="$1"
  AGENT="$2"
  GLOBAL_BASE="$3"
  SKILLS_JSON="$4"

  if ! command -v jq &>/dev/null; then
    echo "STATUS=error"
    echo "REASON=jq_not_installed"
    exit 1
  fi

  exists=$(echo "$SKILLS_JSON" | jq -r --arg n "$SKILL_NAME" 'has($n)' 2>/dev/null || echo "false")
  if [[ "$exists" != "true" ]]; then
    echo "STATUS=error"
    echo "REASON=not_found"
    exit 1
  fi

  path=$(echo "$SKILLS_JSON" | jq -r --arg n "$SKILL_NAME" '.[$n].path')

  path_existed="true"
  was_symlink="false"

  if [[ -L "$path" ]]; then
    # Symlink: remove only the link, leave source files untouched.
    was_symlink="true"
    if ! rm "$path"; then
      echo "STATUS=error"
      echo "REASON=rm_failed"
      exit 1
    fi
  elif [[ ! -d "$path" ]]; then
    path_existed="false"
  else
    if ! rm -rf "$path"; then
      echo "STATUS=error"
      echo "REASON=rm_failed"
      exit 1
    fi
  fi

  # Update config only after successful rm (or when path was already gone).
  bash "$(dirname "$0")/sg-config-del.sh" "$AGENT" "$SKILL_NAME"

  echo "STATUS=ok"
  echo "DELETED_PATH=$path"
  echo "PATH_EXISTED=$path_existed"
  echo "WAS_SYMLINK=$was_symlink"
  exit 0
fi

# ── Unknown mode ──────────────────────────────────────────────────────────────
echo "STATUS=error"
echo "REASON=unknown_mode: $MODE"
exit 1
