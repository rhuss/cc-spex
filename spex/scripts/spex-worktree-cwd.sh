#!/usr/bin/env bash
# Recover CWD to the correct worktree directory.
#
# After subagents return in Claude Code, the shell CWD may be reset to
# the main repo directory instead of the worktree. This script detects
# the mismatch and outputs the correct path to cd into.
#
# Usage:
#   WORKTREE_DIR=$(spex-worktree-cwd.sh)
#   [ -n "$WORKTREE_DIR" ] && cd "$WORKTREE_DIR"
#
# Uses SHIP_STATE_FILE (absolute path set during pipeline init) to find
# the worktree root. Falls back to git worktree detection if the env
# var is not set.
#
# Output:
#   - Prints the worktree path if CWD needs to change
#   - Prints nothing if CWD is already correct or not in a worktree
#   - Exit 0 always (safe to call unconditionally)
set -euo pipefail

# Strategy 1: Use SHIP_STATE_FILE absolute path
if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ]; then
  TARGET=$(cd "$(dirname "$SHIP_STATE_FILE")/.." && pwd -P)
  CURRENT=$(pwd -P)
  if [ "$TARGET" != "$CURRENT" ]; then
    echo "$TARGET"
  fi
  exit 0
fi

# Strategy 2: Detect worktree from git
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -z "$GIT_DIR" ] || [ -z "$REPO_ROOT" ]; then
  exit 0
fi

# Check if we're supposed to be in a worktree
if [ "$GIT_DIR" = "$REPO_ROOT/.git" ] || [ "$GIT_DIR" = ".git" ]; then
  # Not in a worktree, or already at main repo. Check if a feature
  # branch worktree exists that we should be in.
  BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [ -z "$BRANCH" ] || ! echo "$BRANCH" | grep -qE '^[0-9]{3}-'; then
    exit 0
  fi

  # Feature branch but not in a worktree — check if a worktree exists for this branch
  WORKTREE_PATH=$(git worktree list --porcelain 2>/dev/null | grep -B1 "branch refs/heads/$BRANCH" | head -1 | sed 's/^worktree //')
  if [ -n "$WORKTREE_PATH" ] && [ "$WORKTREE_PATH" != "$REPO_ROOT" ]; then
    echo "$WORKTREE_PATH"
  fi
fi

exit 0
