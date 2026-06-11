#!/bin/sh
# teams-gate.sh - Teams enforcement logic
#
# Blocks background Agent usage during implementation when teams extension
# is active. Forces use of the teams orchestration skill instead.
#
# Usage:
#   result=$(sh teams-gate.sh <tool_name> <tool_input_json> <cwd>)
#   # result is "deny:<reason>" or "allow"
#
# Reads .specify/extensions/.registry and .specify/.spex-phase

set -eu

TOOL_NAME="${1:-}"
TOOL_INPUT_JSON="${2:-{}}"
CWD="${3:-.}"

# Only applies to Agent tool
if [ "$TOOL_NAME" != "Agent" ]; then
  echo "allow"
  exit 0
fi

# Check if this is a subagent/team call (those are allowed)
if ! command -v jq >/dev/null 2>&1; then
  echo "allow"
  exit 0
fi

HAS_SUBAGENT=$(echo "$TOOL_INPUT_JSON" | jq -r '.subagent_type // ""' 2>/dev/null || echo "")
HAS_TEAM=$(echo "$TOOL_INPUT_JSON" | jq -r '.team_name // ""' 2>/dev/null || echo "")
if [ -n "$HAS_SUBAGENT" ] || [ -n "$HAS_TEAM" ]; then
  echo "allow"
  exit 0
fi

# Only block background agents
RUN_BG=$(echo "$TOOL_INPUT_JSON" | jq -r '.run_in_background // false' 2>/dev/null || echo "false")
if [ "$RUN_BG" != "true" ]; then
  echo "allow"
  exit 0
fi

# Check if teams extension is enabled
REGISTRY_FILE="$CWD/.specify/extensions/.registry"
if [ ! -f "$REGISTRY_FILE" ]; then
  echo "allow"
  exit 0
fi

TEAMS_ENABLED=$(jq -r '.extensions["spex-teams"].enabled // false' "$REGISTRY_FILE" 2>/dev/null || echo "false")
if [ "$TEAMS_ENABLED" != "true" ]; then
  echo "allow"
  exit 0
fi

# Check if we are in implement phase
PHASE_FILE="$CWD/.specify/.spex-phase"
if [ ! -f "$PHASE_FILE" ]; then
  echo "allow"
  exit 0
fi

PHASE=$(cat "$PHASE_FILE" 2>/dev/null || echo "")
if [ "$PHASE" != "implement" ]; then
  echo "allow"
  exit 0
fi

echo "deny:TEAMS ENFORCEMENT (implement phase): You are using Agent with run_in_background, which bypasses Agent Teams. Instead, delegate to {Skill: spex:teams-orchestrate} which provides: (1) worktree isolation for each teammate, (2) spec compliance review before merge."
