#!/bin/sh
# skill-gate.sh - Skill-first enforcement logic
#
# Blocks non-Skill tools when a /spex: command is pending.
# The marker file is written by context-hook and cleared when
# the Skill tool is invoked.
#
# Usage:
#   result=$(sh skill-gate.sh <tool_name> <session_id>)
#   # result is "deny:<reason>" or "allow"
#
# Side effect: clears marker when tool_name is "Skill"

set -eu

TOOL_NAME="${1:-}"
SESSION_ID="${2:-unknown}"

TMPDIR="${TMPDIR:-/tmp}"
MARKER="$TMPDIR/.claude-spex-skill-pending-$SESSION_ID"

# Side effect: clear marker when Skill tool is invoked
if [ "$TOOL_NAME" = "Skill" ]; then
  rm -f "$MARKER"
  echo "allow"
  exit 0
fi

# No marker means no pending skill command
if [ ! -f "$MARKER" ]; then
  echo "allow"
  exit 0
fi

# ToolSearch must pass so the deferred Skill tool can be loaded
if [ "$TOOL_NAME" = "ToolSearch" ]; then
  echo "allow"
  exit 0
fi

# Read pending skill name from marker
PENDING_SKILL=""
if [ -f "$MARKER" ]; then
  PENDING_SKILL=$(cat "$MARKER" 2>/dev/null || echo "")
fi

echo "deny:SKILL GATE: You MUST call Skill(skill=\"${PENDING_SKILL}\") as your FIRST tool call. Do NOT read files, explore code, or analyze anything before invoking the skill. The skill document contains the process to follow. Call it NOW."
