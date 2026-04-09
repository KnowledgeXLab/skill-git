#!/usr/bin/env bash
# sg-list.sh — list all registered skills with their versions and descriptions.
#
# Usage: sg-list.sh <global_base> <skills_json> [flags] [filter]
#
# Flags:
#   -v / --verbose    show full path and description on separate lines
#   -a <agent>        consumed by prelude; silently ignored here
#
# Filter:
#   Any non-flag positional argument is used as a case-insensitive substring
#   filter applied to both skill name and description.
#
# chmod +x scripts/sg-list.sh

set -euo pipefail

GLOBAL_BASE="$1"
SKILLS_JSON="$2"
shift 2

# ── Parse remaining flags ─────────────────────────────────────────────────────
VERBOSE=false
FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      ;;
    -a)
      # Already consumed by prelude; skip the value token too.
      shift
      ;;
    -*)
      # Ignore unknown flags silently.
      ;;
    *)
      FILTER="$1"
      ;;
  esac
  shift
done

# ── Validate dependencies ─────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

# ── Extract skill names (sorted alphabetically) ───────────────────────────────
SKILL_NAMES=()
while IFS= read -r line; do
  SKILL_NAMES+=("$line")
done < <(echo "$SKILLS_JSON" | jq -r 'keys | sort[]' 2>/dev/null)
TOTAL=${#SKILL_NAMES[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo "No skills registered. Run /skill-git:init to register skills."
  exit 0
fi

# ── Helper: read description from SKILL.md YAML frontmatter ──────────────────
# Handles both quoted and unquoted single-line values.
# Returns empty string if SKILL.md or description field is missing.
get_description() {
  local skill_md="$1"
  [[ -f "$skill_md" ]] || { echo ""; return; }
  awk '
    BEGIN { in_front=0 }
    /^---/ {
      if (in_front) { exit }
      in_front=1; next
    }
    in_front && /^description:/ {
      sub(/^description:[[:space:]]*/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")  # strip surrounding quotes
      print
      exit
    }
  ' "$skill_md"
}

# ── Compute column widths ─────────────────────────────────────────────────────
MAX_NAME=4  # minimum: "Name"
MAX_VER=7   # minimum: "Version"
for name in "${SKILL_NAMES[@]}"; do
  [[ ${#name} -gt $MAX_NAME ]] && MAX_NAME=${#name}
  ver=$(echo "$SKILLS_JSON" | jq -r --arg n "$name" '.[$n].version // "—"')
  [[ ${#ver} -gt $MAX_VER ]] && MAX_VER=${#ver}
done

# ── Build rows, applying filter ───────────────────────────────────────────────
OUTPUT_ROWS=()
MISSING_SKILLS=()
MATCHED=0

for name in "${SKILL_NAMES[@]}"; do
  path=$(echo "$SKILLS_JSON" | jq -r --arg n "$name" '.[$n].path')
  version=$(echo "$SKILLS_JSON" | jq -r --arg n "$name" '.[$n].version // "—"')
  description=$(get_description "$path/SKILL.md")

  # Apply filter (case-insensitive substring match on name + description).
  if [[ -n "$FILTER" ]]; then
    combined="$name $description"
    if ! echo "$combined" | grep -qi "$FILTER"; then
      continue
    fi
  fi

  MATCHED=$((MATCHED + 1))
  path_missing=false
  [[ ! -d "$path" ]] && path_missing=true && MISSING_SKILLS+=("$name")

  if [[ "$VERBOSE" == "true" ]]; then
    OUTPUT_ROWS+=("NAME:$name")
    OUTPUT_ROWS+=("VER:$version")
    OUTPUT_ROWS+=("PATH:$path")
    OUTPUT_ROWS+=("DESC:${description:-(no description)}")
    [[ "$path_missing" == "true" ]] && OUTPUT_ROWS+=("WARN:path not found on disk")
    OUTPUT_ROWS+=("SEP:")
  else
    # Compact: single line, truncate description at 58 chars.
    desc_display="${description:-(no description)}"
    if [[ ${#desc_display} -gt 58 ]]; then
      desc_display="${desc_display:0:55}..."
    fi
    missing_flag=""
    [[ "$path_missing" == "true" ]] && missing_flag="  ⚠️"
    OUTPUT_ROWS+=("ROW:$name|$version|$desc_display$missing_flag")
  fi
done

# ── Print header ──────────────────────────────────────────────────────────────
SEP="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$SEP"
if [[ -n "$FILTER" ]]; then
  echo "Skills matching \"$FILTER\"  ($MATCHED of $TOTAL registered)"
else
  echo "Skills ($TOTAL registered)"
fi
echo ""

# ── Print rows ────────────────────────────────────────────────────────────────
if [[ $MATCHED -eq 0 ]]; then
  echo "  No skills match \"$FILTER\"."
elif [[ "$VERBOSE" == "true" ]]; then
  for row in "${OUTPUT_ROWS[@]}"; do
    tag="${row%%:*}"
    val="${row#*:}"
    case "$tag" in
      NAME) printf "  %s\n" "$val" ;;
      VER)  printf "    version:  %s\n" "$val" ;;
      PATH) printf "    path:     %s\n" "$val" ;;
      DESC) printf "    desc:     %s\n" "$val" ;;
      WARN) printf "    ⚠️   %s\n" "$val" ;;
      SEP)  echo "" ;;
    esac
  done
else
  # Print compact table with header row.
  name_fmt="%-${MAX_NAME}s"
  ver_fmt="%-${MAX_VER}s"
  printf "  ${name_fmt}  ${ver_fmt}  %s\n" "Name" "Version" "Description"
  printf "  ${name_fmt}  ${ver_fmt}  %s\n" \
    "$(printf '%0.s─' $(seq 1 $MAX_NAME))" \
    "$(printf '%0.s─' $(seq 1 $MAX_VER))" \
    "$(printf '%0.s─' $(seq 1 40))"
  for row in "${OUTPUT_ROWS[@]}"; do
    tag="${row%%:*}"
    [[ "$tag" != "ROW" ]] && continue
    val="${row#ROW:}"
    IFS='|' read -r r_name r_ver r_desc <<< "$val"
    printf "  ${name_fmt}  ${ver_fmt}  %s\n" "$r_name" "$r_ver" "$r_desc"
  done
fi

echo ""
echo "$SEP"

# ── Footer hints ──────────────────────────────────────────────────────────────
if [[ ${#MISSING_SKILLS[@]} -gt 0 ]]; then
  echo ""
  echo "  ⚠️  ${#MISSING_SKILLS[@]} skill(s) have missing paths (marked above)."
  echo "  Run /skill-git:init to re-register or remove stale entries."
fi

# ── Unregistered folders warning ─────────────────────────────────────────────
bash "${BASH_SOURCE[0]%/*}/sg-warn-unregistered.sh" "$GLOBAL_BASE" "$SKILLS_JSON"
