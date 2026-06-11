#!/bin/sh
# verify-gate.sh - Verify-before-commit enforcement
#
# Reminds about verification before git commit in spex projects.
# Non-blocking (returns context, not deny).
#
# Usage:
#   result=$(sh verify-gate.sh <tool_name> <command> <session_id> <cwd>)
#   # result is "context:<text>" or "allow"
#
# Reads .specify/.spex-state and $TMPDIR marker files

set -eu

TOOL_NAME="${1:-}"
COMMAND="${2:-}"
SESSION_ID="${3:-unknown}"
CWD="${4:-.}"

# Only applies to Bash tool
if [ "$TOOL_NAME" != "Bash" ]; then
  echo "allow"
  exit 0
fi

# Only applies to git commit commands
case "$COMMAND" in
  *git\ commit*|*git\ \ commit*) ;;
  *)
    echo "allow"
    exit 0
    ;;
esac

# Only applies in spex projects
if [ ! -d "$CWD/.specify" ]; then
  echo "allow"
  exit 0
fi

# Skip if already verified this session
TMPDIR="${TMPDIR:-/tmp}"
VERIFIED_MARKER="$TMPDIR/.claude-spex-verified-$SESSION_ID"
if [ -f "$VERIFIED_MARKER" ]; then
  echo "allow"
  exit 0
fi

# Skip reminder during pre-implementation phases
STATE_FILE="$CWD/.specify/.spex-state"
if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  MODE=$(jq -r '.mode // ""' "$STATE_FILE" 2>/dev/null || echo "")
  IMPLEMENTED=$(jq -r '.implemented // false' "$STATE_FILE" 2>/dev/null || echo "false")
  if [ "$MODE" = "flow" ] && [ "$IMPLEMENTED" != "true" ]; then
    echo "allow"
    exit 0
  fi
fi

# Check if this is a spec-only commit (no code to verify)
if command -v git >/dev/null 2>&1; then
  STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || echo "")
  if [ -n "$STAGED" ]; then
    SPEC_ONLY=true
    for f in $STAGED; do
      case "$f" in
        specs/*|brainstorm/*|docs/*|.specify/*|*.md) continue ;;
        *) SPEC_ONLY=false; break ;;
      esac
    done
    if [ "$SPEC_ONLY" = "true" ]; then
      echo "allow"
      exit 0
    fi
  fi
fi

echo "context:spex stamp reminder: Final verification has not been run this session. Consider running /speckit-spex-gates-stamp first, or confirm with the user that they want to proceed without the final gate."
