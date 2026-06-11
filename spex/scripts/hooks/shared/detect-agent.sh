#!/bin/sh
# detect-agent.sh - Agent detection
#
# Identifies the running AI coding agent using a priority order:
#   1. Agent-specific environment variables
#   2. Agent directory presence in cwd
#   3. --ai value from .specify/init-options.json
#
# Usage:
#   agent=$(sh detect-agent.sh [cwd])
#   # agent is "claude", "codex", "opencode", or "claude" (default fallback)
#
# Environment variables checked:
#   CLAUDE_PROJECT_DIR  -> claude
#   CODEX_SESSION_ID    -> codex
#   (OpenCode sets no single reliable env var; detected via directory)

set -eu

CWD="${1:-.}"

# Priority 1: Environment variables
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo "claude"
  exit 0
fi

if [ -n "${CODEX_SESSION_ID:-}" ]; then
  echo "codex"
  exit 0
fi

# Priority 2: Agent directory presence
# Check in order of specificity (codex/opencode are more distinctive than .claude)
if [ -d "$CWD/.codex" ]; then
  echo "codex"
  exit 0
fi

if [ -d "$CWD/.opencode" ]; then
  echo "opencode"
  exit 0
fi

if [ -d "$CWD/.claude" ]; then
  echo "claude"
  exit 0
fi

# Priority 3: --ai value from init-options.json
INIT_OPTIONS="$CWD/.specify/init-options.json"
if [ -f "$INIT_OPTIONS" ] && command -v jq >/dev/null 2>&1; then
  AI_VALUE=$(jq -r '.ai // ""' "$INIT_OPTIONS" 2>/dev/null || echo "")
  case "$AI_VALUE" in
    claude|codex|opencode)
      echo "$AI_VALUE"
      exit 0
      ;;
  esac
fi

# Default fallback: Claude Code
echo "claude"
