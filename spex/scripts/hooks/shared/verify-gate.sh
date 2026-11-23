#!/bin/sh
# verify-gate.sh - Verify-before-commit reminder
#
# Reminds about verification before git commit on a spex feature in progress.
# Non-blocking (returns context, not deny). Mirrors check_verification_gate in
# spex/scripts/hooks/pretool-gate.py.
#
# Fires only when all of these hold:
#   - the command is a git commit in a spex project (.specify/ exists)
#   - the current branch belongs to a feature that reached implementation
#     (tasks.md exists in its spec dir; flow mode must say implemented)
#   - the commit carries code, not only specs/docs
#   - the reminder was not shown for this feature in this session yet
#   - no verification is recorded for the current code
#
# Usage:
#   result=$(sh verify-gate.sh <tool_name> <command> <session_id> <cwd>)
#   # result is "context:<text>" or "allow"
#
# Reads .specify/.spex-state and the shared verification record via
# spex-verify-record.sh check (the same record finish reads; it is tied to the
# code state, not the session, so it survives /clear and new sessions).

set -eu

TOOL_NAME="${1:-}"
COMMAND="${2:-}"
SESSION_ID="${3:-unknown}"
CWD="${4:-.}"

allow() {
  echo "allow"
  exit 0
}

# Only applies to Bash git commit commands in spex projects
[ "$TOOL_NAME" = "Bash" ] || allow
printf '%s\n' "$COMMAND" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+commit([^[:alnum:]_-]|$)' || allow
[ -d "$CWD/.specify" ] || allow
command -v git >/dev/null 2>&1 || allow

# --- Active feature on this branch -----------------------------------------
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ] || allow

STATE_FILE="$CWD/.specify/.spex-state"
STATE_BRANCH=""
STATE_DIR=""
if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  STATE_BRANCH=$(jq -r '.feature_branch // ""' "$STATE_FILE" 2>/dev/null || echo "")
  STATE_DIR=$(jq -r '.spec_dir // ""' "$STATE_FILE" 2>/dev/null || echo "")
  if [ -z "$STATE_BRANCH" ] || [ "$STATE_BRANCH" = "$BRANCH" ]; then
    MODE=$(jq -r '.mode // ""' "$STATE_FILE" 2>/dev/null || echo "")
    IMPLEMENTED=$(jq -r '.implemented // false' "$STATE_FILE" 2>/dev/null || echo "false")
    # Flow mode before implement: nothing to verify yet
    if [ "$MODE" = "flow" ] && [ "$IMPLEMENTED" != "true" ]; then
      allow
    fi
  fi
fi

FEATURE=""
try_spec_dir() {
  if [ -z "$FEATURE" ] && [ -n "$1" ] && [ -f "$1/tasks.md" ]; then
    FEATURE=$(basename "$1")
  fi
}
if [ "$STATE_BRANCH" = "$BRANCH" ] && [ -n "$STATE_DIR" ]; then
  try_spec_dir "$CWD/$STATE_DIR"
fi
try_spec_dir "$CWD/specs/$BRANCH"
# Spec-kit branch numbering: 056-name or 20260101-120000-name
PREFIX=$(printf '%s\n' "$BRANCH" | sed -nE 's/^([0-9]{8}-[0-9]{6}|[0-9]{3,})-.*/\1/p')
if [ -z "$FEATURE" ] && [ -n "$PREFIX" ]; then
  set -- "$CWD"/specs/"$PREFIX"-*
  if [ "$#" -eq 1 ] && [ -d "$1" ]; then
    try_spec_dir "$1"
  fi
fi
# Ad-hoc work on main or a non-feature branch, or a feature before tasks
[ -n "$FEATURE" ] || allow

# --- Does the commit carry code? -------------------------------------------
# At PreToolUse time `git add ... && git commit` and `git commit -a` have not
# staged anything yet, so those look at all working tree changes.
if printf '%s\n' "$COMMAND" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+add([^[:alnum:]_-]|$)' \
  || printf '%s\n' "$COMMAND" | grep -Eq 'git[[:space:]]+commit[^;&|]*[[:space:]](-[a-zA-Z]*a[a-zA-Z]*|--all)([^[:alnum:]_-]|$)'; then
  if STATUS=$(git -C "$CWD" status --porcelain -uall 2>/dev/null); then
    PATHS=$(printf '%s\n' "$STATUS" | cut -c4- | sed -e 's/.* -> //' -e 's/^"//' -e 's/"$//')
  else
    PATHS="__git_error__"
  fi
else
  PATHS=$(git -C "$CWD" diff --cached --name-only 2>/dev/null) || PATHS="__git_error__"
fi

HAS_CODE=false
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    specs/*|brainstorm/*|docs/*|.specify/*|*.md) continue ;;
    *) HAS_CODE=true; break ;;
  esac
done <<EOF
$PATHS
EOF
[ "$HAS_CODE" = "true" ] || allow

# --- Once per session per feature ------------------------------------------
MARKER=""
if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "unknown" ]; then
  MARKER="${TMPDIR:-/tmp}"
  MARKER="${MARKER%/}/.claude-spex-verify-reminded-$SESSION_ID-$FEATURE"
  [ ! -e "$MARKER" ] || allow
fi

# Skip if a verification pass is recorded for the current code state.
# Runs last because it hashes the working tree; the cheap skips above go
# first. Missing script or any error means "not verified" (the reminder fires).
RECORD="$(dirname "$0")/../../spex-verify-record.sh"
[ -f "$RECORD" ] || RECORD="$CWD/.specify/extensions/spex-gates/scripts/spex-verify-record.sh"
if [ -f "$RECORD" ] && (cd "$CWD" && sh "$RECORD" check >/dev/null 2>&1); then
  allow
fi

[ -z "$MARKER" ] || touch "$MARKER" 2>/dev/null || true

echo "context:spex verify reminder: Feature $FEATURE has code changes with no recorded verification. Consider running /speckit-spex-gates-verify or /speckit-spex-finish before committing, or confirm with the user that they want to proceed without the final gate. (Shown once per session for this feature.)"
