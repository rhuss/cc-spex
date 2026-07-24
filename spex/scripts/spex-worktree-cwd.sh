#!/usr/bin/env bash
# Print the validated active worktree when the caller's CWD needs recovery.
#
# Usage:
#   WORKTREE_DIR=$(spex-worktree-cwd.sh)
#   [ -n "$WORKTREE_DIR" ] && cd "$WORKTREE_DIR"
#
# The workflow-state resolver is the sole authority. SHIP_STATE_FILE and the
# caller's CWD may help that resolver discover candidates, but neither is
# trusted as a destination until the resolver validates the full identity.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
STATE_TOOL="$SCRIPT_DIR/spex-ship-state.sh"

refuse() {
  local reason=$1
  jq -cn --arg reason "$reason" \
    '{status:"failed_validation",diagnostics:[{candidate:"spex-worktree-cwd",accepted:false,reasons:[$reason]}]}' >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"status":"failed_validation","diagnostics":[{"candidate":"spex-worktree-cwd","accepted":false,"reasons":["jq is required to validate resolver output"]}]}' >&2
  exit 1
fi

if [ ! -x "$STATE_TOOL" ]; then
  refuse "workflow-state resolver is unavailable: $STATE_TOOL"
fi

ERROR_FILE=$(mktemp "${TMPDIR:-/tmp}/spex-worktree-cwd.XXXXXX")
trap 'rm -f "$ERROR_FILE"' EXIT

set +e
RESOLUTION=$("$STATE_TOOL" resolve 2>"$ERROR_FILE")
RESOLVE_STATUS=$?
set -e

if [ "$RESOLVE_STATUS" -ne 0 ]; then
  if printf '%s\n' "$RESOLUTION" | jq -e '.status == "failed_validation" and (.diagnostics | type == "array")' >/dev/null 2>&1; then
    printf '%s\n' "$RESOLUTION" | jq -c . >&2
  else
    DETAIL=$(tr '\n' ' ' <"$ERROR_FILE")
    refuse "workflow-state resolution failed${DETAIL:+: $DETAIL}"
  fi
  exit "$RESOLVE_STATUS"
fi

if ! printf '%s\n' "$RESOLUTION" | jq -e \
  '.context.active_worktree | type == "string" and startswith("/")' >/dev/null 2>&1; then
  refuse "workflow-state resolver returned no absolute active_worktree"
fi

TARGET=$(printf '%s\n' "$RESOLUTION" | jq -r '.context.active_worktree')
STATE_FILE=$(printf '%s\n' "$RESOLUTION" | jq -r '.context.state_file // empty')
FEATURE_BRANCH=$(printf '%s\n' "$RESOLUTION" | jq -r '.context.feature_branch // empty')

if [ ! -d "$TARGET" ]; then
  refuse "resolved active_worktree is not a directory: $TARGET"
fi

CANONICAL_TARGET=$(cd "$TARGET" && pwd -P)
if [ "$TARGET" != "$CANONICAL_TARGET" ]; then
  refuse "resolved active_worktree is not canonical: $TARGET"
fi
if [ "$STATE_FILE" != "$CANONICAL_TARGET/.specify/.spex-state" ]; then
  refuse "resolved state_file does not belong to active_worktree"
fi

GIT_ROOT=$(git -C "$CANONICAL_TARGET" rev-parse --show-toplevel 2>/dev/null || true)
GIT_BRANCH=$(git -C "$CANONICAL_TARGET" branch --show-current 2>/dev/null || true)
if [ "$GIT_ROOT" != "$CANONICAL_TARGET" ] || [ -z "$FEATURE_BRANCH" ] || [ "$GIT_BRANCH" != "$FEATURE_BRANCH" ]; then
  refuse "resolved active_worktree no longer matches its validated git identity"
fi

CURRENT=$(pwd -P)
if [ "$CANONICAL_TARGET" != "$CURRENT" ]; then
  printf '%s\n' "$CANONICAL_TARGET"
fi
