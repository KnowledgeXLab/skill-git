#!/usr/bin/env bash
# sg-prelude.sh — injected at skill-load time via Claude Code's ! command injection.
# Parses $ARGUMENTS, resolves the active agent, checks initialization state,
# and outputs key=value lines for the LLM to parse.
#
# Usage (from a command file):
#   !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" "$ARGUMENTS"`
#   !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/sg-prelude.sh" "--agent-only $ARGUMENTS"`
#
# chmod +x scripts/sg-prelude.sh

set -uo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
AGENT=""
AGENT_EXPLICIT=false
AGENT_ONLY=false
RAW_ARGUMENTS="$*"

# Walk tokens; consume -a <value> and --agent-only; ignore everything else.
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  token="${ARGS[$i]}"
  case "$token" in
    -a)
      i=$((i + 1))
      if [ $i -lt ${#ARGS[@]} ]; then
        AGENT="${ARGS[$i]}"
        AGENT_EXPLICIT=true
      fi
      ;;
    --agent-only)
      AGENT_ONLY=true
      ;;
    *)
      ;;
  esac
  i=$((i + 1))
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
  else
    AGENT="claude"  # fallback default
  fi
fi

# ── Agent validation ──────────────────────────────────────────────────────────
case "$AGENT" in
  claude|gemini|codex|openclaw)
    ;;
  *)
    echo "STATUS=not_detected"
    echo "REASON=unknown_agent"
    echo "RAW_ARGUMENTS=$RAW_ARGUMENTS"
    exit 0
    ;;
esac

# ── Directory resolution (tilde-expanded via $HOME) ───────────────────────────
case "$AGENT" in
  claude)   GLOBAL_BASE="$HOME/.claude" ;;
  gemini)   GLOBAL_BASE="$HOME/.gemini" ;;
  codex)    GLOBAL_BASE="$HOME/.codex" ;;
  openclaw) GLOBAL_BASE="$HOME/.openclaw" ;;
esac

# ── --agent-only mode: skip init check ───────────────────────────────────────
if [ "$AGENT_ONLY" = "true" ]; then
  echo "STATUS=ok"
  echo "AGENT=$AGENT"
  echo "GLOBAL_BASE=$GLOBAL_BASE"
  exit 0
fi

# ── Read config.json and verify agent is initialized ─────────────────────────
CONFIG_FILE="$HOME/.skill-git/config.json"

# Build comma-separated list of initialized agents from config.json (best-effort).
_initialized_agents() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    return
  fi
  if ! command -v jq > /dev/null 2>&1; then
    echo ""
    return
  fi
  jq -r '(.agents // {}) | keys | join(",")' "$CONFIG_FILE" 2>/dev/null || echo ""
}

if [ ! -f "$CONFIG_FILE" ]; then
  echo "STATUS=not_initialized"
  echo "INITIALIZED_AGENTS="
  echo "RAW_ARGUMENTS=$RAW_ARGUMENTS"
  exit 0
fi

if ! command -v jq > /dev/null 2>&1; then
  echo "STATUS=error"
  echo "REASON=jq_not_installed"
  exit 0
fi

# Validate JSON is parseable.
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "STATUS=error"
  echo "REASON=config_json_malformed"
  exit 0
fi

# Check that .agents[$agent].skills exists.
SKILLS_JSON=$(jq -c --arg a "$AGENT" '.agents[$a].skills // empty' "$CONFIG_FILE" 2>/dev/null || true)

if [ -z "$SKILLS_JSON" ]; then
  INITIALIZED_AGENTS=$(_initialized_agents)
  echo "STATUS=not_initialized"
  echo "INITIALIZED_AGENTS=$INITIALIZED_AGENTS"
  echo "RAW_ARGUMENTS=$RAW_ARGUMENTS"
  exit 0
fi

# ── Success ───────────────────────────────────────────────────────────────────
echo "STATUS=ok"
echo "AGENT=$AGENT"
echo "GLOBAL_BASE=$GLOBAL_BASE"
echo "SKILLS_JSON=$SKILLS_JSON"
