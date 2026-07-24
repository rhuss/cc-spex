#!/usr/bin/env bash
# Shared isolation helpers for shell tests. Source this file; do not execute it.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "test_helpers.sh must be sourced" >&2
  exit 2
fi

SPEX_TEST_TEMP_PATHS=()
SPEX_TEST_WORKTREES=()

spex_test_assign() {
  local variable_name="$1"
  local value="$2"
  if [[ -n "$variable_name" ]]; then
    printf -v "$variable_name" '%s' "$value"
  else
    printf '%s\n' "$value"
  fi
}

spex_test_make_temp_dir() {
  local variable_name="${1:-}"
  local created
  created=$(mktemp -d "${TMPDIR:-/tmp}/spex-test.XXXXXX")
  SPEX_TEST_TEMP_PATHS+=("$created")
  spex_test_assign "$variable_name" "$created"
}

spex_test_make_home() {
  local variable_name="${1:-}"
  local path
  spex_test_make_temp_dir path
  mkdir -p "$path/.config" "$path/.cache"
  spex_test_assign "$variable_name" "$path"
}

spex_test_use_home() {
  local path="$1"
  export HOME="$path"
  export XDG_CONFIG_HOME="$path/.config"
  export XDG_CACHE_HOME="$path/.cache"
  export CODEX_HOME="$path/.codex"
  export CLAUDE_CONFIG_DIR="$path/.claude"
  mkdir -p "$CODEX_HOME" "$CLAUDE_CONFIG_DIR"
}

spex_test_make_repo() {
  local variable_name="${1:-}"
  local parent repo
  spex_test_make_temp_dir parent
  repo="$parent/repo"
  git init -q "$repo"
  git -C "$repo" config user.name "Spex Test"
  git -C "$repo" config user.email "spex-test@example.invalid"
  git -C "$repo" commit --allow-empty -q -m "Initial test commit"
  spex_test_assign "$variable_name" "$repo"
}

spex_test_make_worktree() {
  local repo="$1"
  local branch="$2"
  local variable_name="${3:-}"
  local parent worktree
  spex_test_make_temp_dir parent
  worktree="$parent/worktree"
  git -C "$repo" worktree add -q -b "$branch" "$worktree"
  SPEX_TEST_WORKTREES+=("$repo" "$worktree")
  spex_test_assign "$variable_name" "$worktree"
}

spex_test_cleanup() {
  local index repo worktree path
  for ((index=${#SPEX_TEST_WORKTREES[@]} - 2; index >= 0; index-=2)); do
    repo="${SPEX_TEST_WORKTREES[index]}"
    worktree="${SPEX_TEST_WORKTREES[index + 1]}"
    git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
    git -C "$repo" worktree prune >/dev/null 2>&1 || true
  done
  for ((index=${#SPEX_TEST_TEMP_PATHS[@]} - 1; index >= 0; index--)); do
    path="${SPEX_TEST_TEMP_PATHS[index]}"
    [[ -n "$path" && -d "$path" ]] && rm -rf -- "$path"
  done
  SPEX_TEST_WORKTREES=()
  SPEX_TEST_TEMP_PATHS=()
}
