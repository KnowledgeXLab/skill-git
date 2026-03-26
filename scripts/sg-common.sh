#!/usr/bin/env bash
# sg-common.sh — source-only bash library for skill-git scripts.
# Never executed directly. Source it from wrapper scripts:
#   source "${BASH_SOURCE[0]%/*}/sg-common.sh"
#
# Wrapper scripts are responsible for setting:
#   set -euo pipefail
#
# chmod +x scripts/sg-common.sh

# Guard against direct execution.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[sg-common] Error: this file must be sourced, not executed directly." >&2
  exit 1
fi

# ── Constants ─────────────────────────────────────────────────────────────────
_SG_CONFIG_FILE="$HOME/.skill-git/config.json"
_SG_CONFIG_TMP="/tmp/sg-cfg-$$.json"

# ── sg_config_set_version ─────────────────────────────────────────────────────
# Updates .agents[$agent].skills[$skill_name].version atomically.
#
# Usage: sg_config_set_version <agent> <skill_name> <version>
sg_config_set_version() {
  local agent="$1" skill_name="$2" version="$3"

  jq \
    --arg a "$agent" \
    --arg n "$skill_name" \
    --arg v "$version" \
    '.agents[$a].skills[$n].version = $v' \
    "$_SG_CONFIG_FILE" > "$_SG_CONFIG_TMP" \
  && mv "$_SG_CONFIG_TMP" "$_SG_CONFIG_FILE"
}

# ── sg_config_add_skill ───────────────────────────────────────────────────────
# Sets .agents[$agent].skills[$skill_name] = {"path": $path, "version": $version}.
#
# Usage: sg_config_add_skill <agent> <skill_name> <path> <version>
sg_config_add_skill() {
  local agent="$1" skill_name="$2" path="$3" version="$4"

  jq \
    --arg a "$agent" \
    --arg n "$skill_name" \
    --arg p "$path" \
    --arg v "$version" \
    '.agents[$a].skills[$n] = {"path": $p, "version": $v}' \
    "$_SG_CONFIG_FILE" > "$_SG_CONFIG_TMP" \
  && mv "$_SG_CONFIG_TMP" "$_SG_CONFIG_FILE"
}

# ── sg_config_del_skill ───────────────────────────────────────────────────────
# Removes .agents[$agent].skills[$skill_name].
#
# Usage: sg_config_del_skill <agent> <skill_name>
sg_config_del_skill() {
  local agent="$1" skill_name="$2"

  jq \
    --arg a "$agent" \
    --arg n "$skill_name" \
    'del(.agents[$a].skills[$n])' \
    "$_SG_CONFIG_FILE" > "$_SG_CONFIG_TMP" \
  && mv "$_SG_CONFIG_TMP" "$_SG_CONFIG_FILE"
}

# ── sg_git ────────────────────────────────────────────────────────────────────
# Runs git inside a skill's own .git repo with a fixed identity so commits
# are reproducible regardless of the user's global git config.
#
# Usage: sg_git <skill_path> [git args...]
sg_git() {
  local skill_path="$1"
  shift
  git \
    -c user.email="skill-git@local" \
    -c user.name="skill-git" \
    -C "$skill_path" \
    "$@"
}

# ── sg_warn_unregistered ──────────────────────────────────────────────────────
# Scans <global_base>/skills/*/ and warns about folders not present in the
# skills_json map.
#
# Output format (only when unregistered folders are found):
#   ⚠️  N skill folder(s) not registered in config.json:
#     - <name>    (has .git, not registered)
#     - <name>    (no git, never initialized)
#   Run /skill-git:init to register them.
#
# Usage: sg_warn_unregistered <global_base> <skills_json>
#   skills_json: the compact JSON object from .agents[$agent].skills
sg_warn_unregistered() {
  local global_base="$1" skills_json="$2"
  local skills_dir="$global_base/skills"

  [ -d "$skills_dir" ] || return 0

  local unregistered=()

  while IFS= read -r -d '' folder; do
    [ -L "$folder" ] && continue  # skip symlinks
    local name
    name=$(basename "$folder")

    # Check if name is a key in skills_json.
    local registered
    registered=$(echo "$skills_json" | jq -r --arg n "$name" 'has($n)' 2>/dev/null || echo "false")

    if [ "$registered" != "true" ]; then
      if [ -d "$folder/.git" ]; then
        unregistered+=("$name (has .git, not registered)")
      else
        unregistered+=("$name (no git, never initialized)")
      fi
    fi
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  if [ ${#unregistered[@]} -eq 0 ]; then
    return 0
  fi

  local count=${#unregistered[@]}
  echo "⚠️  $count skill folder(s) not registered in config.json:"
  local entry
  for entry in "${unregistered[@]}"; do
    echo "  - $entry"
  done
  echo "Run /skill-git:init to register them."
}

# ── sg_handle_missing_skill ───────────────────────────────────────────────────
# Removes a skill from config.json when its path no longer exists on disk,
# and prints a warning message.
#
# Usage: sg_handle_missing_skill <agent> <skill_name> <path>
sg_handle_missing_skill() {
  local agent="$1" skill_name="$2" path="$3"

  sg_config_del_skill "$agent" "$skill_name"
  echo "⚠️  Skill path not found and removed from config.json: $skill_name ($path)"
}
