#!/usr/bin/env bash
# Detect git context for the finish command.
# Outputs JSON with worktree status, branches, and existing PR info.
set -euo pipefail

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || echo "")
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

IN_WORKTREE=false
if [ -n "$GIT_DIR" ] && [ -n "$REPO_ROOT" ]; then
  if [ "$GIT_DIR" != "$REPO_ROOT/.git" ] && [ "$GIT_DIR" != ".git" ]; then
    IN_WORKTREE=true
  fi
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
if [ -z "$DEFAULT_BRANCH" ]; then
  for candidate in main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}

MAIN_WORKTREE=""
if [ "$IN_WORKTREE" = "true" ]; then
  MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
fi

EXISTING_PR_NUMBER=""
EXISTING_PR_URL=""
if command -v gh >/dev/null 2>&1 && [ -n "$CURRENT_BRANCH" ]; then
  EXISTING_PR_NUMBER=$(gh pr view "$CURRENT_BRANCH" --json number -q '.number' 2>/dev/null || true)
  if [ -n "$EXISTING_PR_NUMBER" ]; then
    EXISTING_PR_URL=$(gh pr view "$CURRENT_BRANCH" --json url -q '.url' 2>/dev/null || true)
  fi
fi

jq -n \
  --arg git_dir "$GIT_DIR" \
  --arg repo_root "$REPO_ROOT" \
  --argjson in_worktree "$IN_WORKTREE" \
  --arg current_branch "$CURRENT_BRANCH" \
  --arg default_branch "$DEFAULT_BRANCH" \
  --arg main_worktree "$MAIN_WORKTREE" \
  --arg existing_pr_number "$EXISTING_PR_NUMBER" \
  --arg existing_pr_url "$EXISTING_PR_URL" \
  '{
    git_dir: $git_dir,
    repo_root: $repo_root,
    in_worktree: $in_worktree,
    current_branch: $current_branch,
    default_branch: $default_branch,
    main_worktree: $main_worktree,
    existing_pr_number: $existing_pr_number,
    existing_pr_url: $existing_pr_url
  }'
