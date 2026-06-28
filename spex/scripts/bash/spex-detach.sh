#!/bin/bash
# spex-detach.sh - Detach spec artifacts for upstream contributions
#
# Usage:
#   spex-detach.sh detach [--branch <name>] [--base <branch>] [--strip <path>...]
#   spex-detach.sh archive --target <path> [--project <name>] [--feature <name>] [--auto-commit]
#   spex-detach.sh is-enabled
#   spex-detach.sh clean-branch-name [--branch <name>]
#
# Exit codes:
#   0 - Success
#   1 - Error
#   2 - Empty diff (detach only: all changes were spec-only)

set -euo pipefail

# --- Helper: get project name from git remote ---
get_project_name() {
  local remote_url
  remote_url=$(git remote get-url upstream 2>/dev/null || git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$remote_url" ]; then
    echo "$remote_url" | sed 's|.*github\.com[:/]||; s|.*gitlab\.com[:/]||; s|\.git$||'
  else
    basename "$(git rev-parse --show-toplevel)"
  fi
}

# --- Helper: detect upstream default branch ---
# Checks upstream remote first (fork workflow), falls back to origin
detect_upstream_default() {
  local config_branch="$1"

  if [ -n "$config_branch" ]; then
    echo "$config_branch"
    return
  fi

  # Try upstream remote first (fork workflow)
  local ref
  ref=$(git symbolic-ref refs/remotes/upstream/HEAD 2>/dev/null || true)
  if [ -n "$ref" ]; then
    echo "${ref##*/}"
    return
  fi

  local head_branch
  head_branch=$(git remote show upstream 2>/dev/null | sed -n 's/  HEAD branch: //p' || true)
  if [ -n "$head_branch" ]; then
    echo "$head_branch"
    return
  fi

  # Fall back to origin
  ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$ref" ]; then
    echo "${ref##*/}"
    return
  fi

  head_branch=$(git remote show origin 2>/dev/null | sed -n 's/  HEAD branch: //p' || true)
  if [ -n "$head_branch" ]; then
    echo "$head_branch"
    return
  fi

  echo "main"
}

# --- Helper: read config value with default ---
# $key must be a hardcoded jq/yq path expression, never user input
read_config() {
  local key="$1"
  local default="$2"
  local config_file=".specify/extensions/spex-detach/spex-detach-config.yml"

  if [ ! -f "$config_file" ]; then
    echo "$default"
    return
  fi

  if ! command -v yq >/dev/null 2>&1; then
    echo "WARNING: yq not found; ignoring $config_file (using defaults)" >&2
    echo "$default"
    return
  fi

  local val
  val=$(yq -r "$key // empty" "$config_file" 2>/dev/null || true)
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "$default"
  else
    echo "$val"
  fi
}

# --- Helper: read strip_paths as newline-separated list ---
read_strip_paths() {
  local config_file=".specify/extensions/spex-detach/spex-detach-config.yml"

  if [ ! -f "$config_file" ] || ! command -v yq >/dev/null 2>&1; then
    printf '%s\n' ".specify" "specs" "brainstorm"
    return
  fi

  local paths
  paths=$(yq -r '.detach.strip_paths // [] | .[]' "$config_file" 2>/dev/null || true)
  if [ -z "$paths" ]; then
    printf '%s\n' ".specify" "specs" "brainstorm"
  else
    echo "$paths"
  fi
}

# --- Helper: validate path component (no traversal) ---
validate_path_component() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *".."* ]]; then
    echo "ERROR: $name contains '..' path traversal" >&2
    exit 1
  fi
}

# --- Helper: require argument value ---
require_arg() {
  local flag="$1"
  local remaining="$2"
  if [ "$remaining" -lt 2 ]; then
    echo "ERROR: $flag requires a value" >&2
    exit 1
  fi
}

# --- Subcommand: is-enabled ---
cmd_is_enabled() {
  if [ -d ".specify/extensions/spex-detach" ]; then
    exit 0
  else
    exit 1
  fi
}

# --- Subcommand: clean-branch-name ---
cmd_clean_branch_name() {
  local branch=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) require_arg "--branch" "$#"; branch="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [ -z "$branch" ]; then
    branch=$(git branch --show-current 2>/dev/null || echo "")
  fi

  if [ -z "$branch" ]; then
    echo "ERROR: Could not determine branch name" >&2
    exit 1
  fi

  echo "pr/$branch"
}

# --- Subcommand: detach ---
cmd_detach() {
  local branch=""
  local base=""
  local strip_args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) require_arg "--branch" "$#"; branch="$2"; shift 2 ;;
      --base) require_arg "--base" "$#"; base="$2"; shift 2 ;;
      --strip)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in --*) break ;; esac
          strip_args+=("$1"); shift
        done
        ;;
      *) shift ;;
    esac
  done

  if [ -z "$branch" ]; then
    branch=$(git branch --show-current 2>/dev/null || echo "")
  fi

  if [ -z "$branch" ]; then
    jq -n '{"error": "Could not determine feature branch"}' >&2
    exit 1
  fi

  # Guard: refuse to operate on a dirty working tree
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    jq -n '{"error": "Working tree has uncommitted changes. Commit or stash before detaching."}' >&2
    exit 1
  fi

  # Determine base branch
  local config_default
  config_default=$(read_config '.upstream.default_branch' '')
  if [ -z "$base" ]; then
    base=$(detect_upstream_default "$config_default")
  fi

  # Resolve base to remote tracking branch if it exists
  local resolved_base="$base"
  if git rev-parse --verify "origin/$base" >/dev/null 2>&1; then
    resolved_base="origin/$base"
  fi

  # Determine strip paths (array-safe)
  local strip_paths_arr=()
  if [ ${#strip_args[@]} -gt 0 ]; then
    strip_paths_arr=("${strip_args[@]}")
  else
    while IFS= read -r p; do
      [ -n "$p" ] && strip_paths_arr+=("$p")
    done < <(read_strip_paths)
  fi

  # Compute merge-base
  local merge_base
  merge_base=$(git merge-base "$resolved_base" "$branch" 2>/dev/null) || {
    jq -n --arg base "$resolved_base" --arg branch "$branch" \
      '{"error": ("Could not compute merge-base between " + $base + " and " + $branch)}' >&2
    exit 1
  }

  local pr_branch="pr/$branch"

  # Build pathspec exclusions
  local pathspec_excludes=()
  for p in "${strip_paths_arr[@]}"; do
    pathspec_excludes+=(":(exclude)$p")
  done

  # Generate filtered diff
  local diff_output
  diff_output=$(git diff --binary "$merge_base".."$branch" -- . "${pathspec_excludes[@]}" 2>/dev/null) || {
    jq -n '{"error": "Failed to generate diff"}' >&2
    exit 1
  }

  # Check for empty diff
  if [ -z "$diff_output" ]; then
    jq -n --arg pr "$pr_branch" --arg mb "$merge_base" \
      '{"pr_branch": $pr, "merge_base": $mb, "commit": "", "files_changed": 0, "empty": true}'
    exit 2
  fi

  # Delete existing PR branch if present (idempotent)
  git branch -D "$pr_branch" 2>/dev/null || true

  local original_branch="$branch"

  # Trap: restore original branch on any failure after checkout
  trap 'git checkout "$original_branch" --quiet 2>/dev/null || true; git branch -D "$pr_branch" 2>/dev/null || true' EXIT

  # Create PR branch from merge-base
  git checkout -b "$pr_branch" "$merge_base" --quiet

  # Apply filtered diff
  echo "$diff_output" | git apply --index 2>/dev/null || {
    jq -n '{"error": "Failed to apply filtered diff"}' >&2
    exit 1
  }

  # Count files changed
  local files_changed
  files_changed=$(git diff --cached --name-only | wc -l | tr -d ' ')

  # Generate commit message from feature branch (most recent code-touching commit)
  local commit_subject
  commit_subject=$(git log --format='%s' "$merge_base".."$original_branch" -- . "${pathspec_excludes[@]}" 2>/dev/null | head -1)
  if [ -z "$commit_subject" ]; then
    commit_subject="feat: $(echo "$original_branch" | sed 's/[-_]/ /g')"
  fi

  git commit -m "$commit_subject" --quiet

  local commit_sha
  commit_sha=$(git rev-parse HEAD)

  # Return to feature branch and clear trap
  git checkout "$original_branch" --quiet
  trap - EXIT

  jq -n --arg pr "$pr_branch" --arg mb "$merge_base" --arg c "$commit_sha" \
    --argjson fc "$files_changed" \
    '{"pr_branch": $pr, "merge_base": $mb, "commit": $c, "files_changed": $fc, "empty": false}'
}

# --- Subcommand: archive ---
cmd_archive() {
  local target=""
  local project=""
  local feature=""
  local auto_commit=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --target) require_arg "--target" "$#"; target="$2"; shift 2 ;;
      --project) require_arg "--project" "$#"; project="$2"; shift 2 ;;
      --feature) require_arg "--feature" "$#"; feature="$2"; shift 2 ;;
      --auto-commit) auto_commit=true; shift ;;
      *) shift ;;
    esac
  done

  if [ -z "$target" ]; then
    target=$(read_config '.archive.path' '')
  fi

  if [ -z "$target" ]; then
    jq -n '{"error": "No archive target specified. Set archive.path in spex-detach-config.yml or use --target"}' >&2
    exit 1
  fi

  if [ ! -d "$target" ]; then
    jq -n --arg t "$target" '{"error": ("Archive target not reachable: " + $t)}' >&2
    exit 1
  fi

  if [ -z "$project" ]; then
    project=$(get_project_name)
  fi

  if [ -z "$feature" ]; then
    feature=$(git branch --show-current 2>/dev/null || echo "unknown")
  fi

  # Validate path components against traversal
  validate_path_component "project" "$project"
  validate_path_component "feature" "$feature"

  local archive_dir="$target/$project/$feature"
  mkdir -p "$archive_dir"

  local files_copied=0

  if [ -d ".specify" ]; then
    cp -R .specify "$archive_dir/"
    files_copied=$((files_copied + $(find .specify -type f | wc -l | tr -d ' ')))
  fi

  local spec_dir="specs/$feature"
  if [ -d "$spec_dir" ]; then
    mkdir -p "$archive_dir/specs"
    cp -R "$spec_dir" "$archive_dir/specs/"
    files_copied=$((files_copied + $(find "$spec_dir" -type f | wc -l | tr -d ' ')))
  fi

  local committed=false

  if [ "$auto_commit" = true ] || [ "$(read_config '.archive.auto_commit' 'true')" = "true" ]; then
    if git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$target" add "$project/$feature" 2>/dev/null || true
      if ! git -C "$target" diff --cached --quiet 2>/dev/null; then
        git -C "$target" commit -m "archive: $project/$feature specs

Assisted-By: 🤖 Claude Code" --quiet 2>/dev/null && committed=true
      fi
    fi
  fi

  jq -n --arg path "$archive_dir" --argjson fc "$files_copied" --argjson cm "$committed" \
    '{"archive_path": $path, "files_copied": $fc, "committed": $cm}'
}

# --- Main: subcommand routing ---
subcmd="${1:-}"
shift || true

case "$subcmd" in
  detach)
    cmd_detach "$@"
    ;;
  archive)
    cmd_archive "$@"
    ;;
  is-enabled)
    cmd_is_enabled
    ;;
  clean-branch-name)
    cmd_clean_branch_name "$@"
    ;;
  *)
    echo "Usage: spex-detach.sh <detach|archive|is-enabled|clean-branch-name> [options]" >&2
    exit 1
    ;;
esac
