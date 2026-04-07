#!/bin/bash
# spex-ship-state.sh - Manage ship pipeline state file
#
# Usage:
#   spex-ship-state.sh create <brainstorm-file> [--ask <level>] [--start-from <stage>]
#   spex-ship-state.sh advance                 # Advance to next stage
#   spex-ship-state.sh status                  # Show current state
#   spex-ship-state.sh pause                   # Set status to paused
#   spex-ship-state.sh fail                    # Set status to failed
#   spex-ship-state.sh cleanup                 # Remove state file (pipeline done)
#
# Must be run from the project root.

set -euo pipefail

STATE_FILE=".specify/.spex-state"

STAGES=("specify" "clarify" "review-spec" "plan" "tasks" "review-plan" "implement" "review-code" "stamp")

stage_index() {
  local name="$1"
  for i in "${!STAGES[@]}"; do
    [ "${STAGES[$i]}" = "$name" ] && echo "$i" && return 0
  done
  echo "ERROR: Invalid stage '$name'" >&2
  return 1
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

write_state() {
  local stage="$1" index="$2" status="$3" ask="$4" started="$5" brainstorm="$6"
  cat > "$STATE_FILE" <<EOF
{
  "mode": "ship",
  "stage": "$stage",
  "stage_index": $index,
  "total_stages": ${#STAGES[@]},
  "ask": "$ask",
  "started_at": "$started",
  "retries": 0,
  "status": "$status",
  "brainstorm_file": "$brainstorm",
  "feature_branch": "$(git branch --show-current 2>/dev/null || echo 'unknown')"
}
EOF
}

do_create() {
  local brainstorm="" ask="smart" start_stage="specify"

  while [ $# -gt 0 ]; do
    case "$1" in
      --ask) shift; ask="${1:-smart}" ;;
      --start-from) shift; start_stage="${1:-specify}" ;;
      -*) echo "ERROR: Unknown flag '$1'" >&2; exit 2 ;;
      *) brainstorm="$1" ;;
    esac
    shift
  done

  if [ -z "$brainstorm" ]; then
    echo "ERROR: Brainstorm file required" >&2
    exit 2
  fi

  local idx
  idx=$(stage_index "$start_stage")
  mkdir -p "$(dirname "$STATE_FILE")"
  write_state "$start_stage" "$idx" "running" "$ask" "$(now_iso)" "$brainstorm"
  echo "CREATED stage=$start_stage index=$idx ask=$ask"
}

find_spec_dir() {
  # Find the spec directory from the brainstorm file path or by looking for recent specs
  local brainstorm="$1"
  if [ -n "$brainstorm" ]; then
    # Derive spec dir from brainstorm filename (e.g., brainstorm/030-foo.md -> specs/030-foo/)
    local base
    base=$(basename "$brainstorm" .md)
    # Try common patterns
    for dir in "specs/$base" "specs/${base%-*}" "specs/"*; do
      [ -d "$dir" ] && echo "$dir" && return 0
    done
  fi
  # Fallback: most recently modified spec dir
  local latest
  latest=$(ls -td specs/*/ 2>/dev/null | head -1)
  [ -n "$latest" ] && echo "${latest%/}" && return 0
  return 1
}

verify_stage_artifacts() {
  # Verify expected artifacts exist for the completed stage before advancing.
  # Returns 0 if OK, 1 if artifacts missing (with error message on stdout).
  local stage_index="$1"
  local brainstorm="$2"
  local spec_dir
  spec_dir=$(find_spec_dir "$brainstorm") || spec_dir=""

  case "$stage_index" in
    0) # specify -> must have spec.md
      if [ -z "$spec_dir" ] || [ ! -f "$spec_dir/spec.md" ]; then
        echo "ARTIFACT_MISSING: spec.md not found. Stage 'specify' did not produce a specification."
        return 1
      fi
      ;;
    3) # plan -> must have plan.md
      if [ -z "$spec_dir" ] || [ ! -f "$spec_dir/plan.md" ]; then
        echo "ARTIFACT_MISSING: plan.md not found. Stage 'plan' did not produce an implementation plan."
        return 1
      fi
      ;;
    4) # tasks -> must have tasks.md
      if [ -z "$spec_dir" ] || [ ! -f "$spec_dir/tasks.md" ]; then
        echo "ARTIFACT_MISSING: tasks.md not found. Stage 'tasks' did not produce a task breakdown."
        return 1
      fi
      ;;
    5) # review-plan -> must have REVIEW-PLAN.md (with REVIEWERS.md fallback)
      if [ -z "$spec_dir" ]; then
        echo "ARTIFACT_MISSING: spec directory not found. Stage 'review-plan' requires a spec directory."
        return 1
      fi
      if [ ! -f "$spec_dir/REVIEW-PLAN.md" ] && [ ! -f "$spec_dir/REVIEWERS.md" ]; then
        echo "ARTIFACT_MISSING: REVIEW-PLAN.md not found. Stage 'review-plan' did not produce a review document."
        return 1
      fi
      ;;
    7) # review-code -> must have REVIEW-CODE.md (with REVIEWERS.md fallback for deep review)
      if [ -z "$spec_dir" ]; then
        echo "ARTIFACT_MISSING: spec directory not found. Stage 'review-code' requires a spec directory."
        return 1
      fi
      if [ ! -f "$spec_dir/REVIEW-CODE.md" ] && [ ! -f "$spec_dir/REVIEWERS.md" ]; then
        echo "ARTIFACT_MISSING: REVIEW-CODE.md not found. Stage 'review-code' requires REVIEW-CODE.md."
        return 1
      fi
      # Check for Deep Review Report in either file
      local review_file="$spec_dir/REVIEW-CODE.md"
      [ ! -f "$review_file" ] && review_file="$spec_dir/REVIEWERS.md"
      if ! grep -q "Deep Review Report\|deep.review.report\|## Deep Review" "$review_file" 2>/dev/null; then
        echo "ARTIFACT_MISSING: $review_file lacks a Deep Review Report section. The deep-review agents must run before advancing past review-code."
        return 1
      fi
      ;;
  esac
  return 0
}

do_advance() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: No state file found" >&2
    exit 1
  fi

  local current_index
  current_index=$(jq -r '.stage_index' "$STATE_FILE")
  local ask
  ask=$(jq -r '.ask // "smart"' "$STATE_FILE")
  local started
  started=$(jq -r '.started_at' "$STATE_FILE")
  local brainstorm
  brainstorm=$(jq -r '.brainstorm_file' "$STATE_FILE")

  # Verify artifacts before advancing
  local artifact_check
  artifact_check=$(verify_stage_artifacts "$current_index" "$brainstorm" 2>/dev/null) || true
  if [ -n "$artifact_check" ]; then
    echo "$artifact_check"
    exit 1
  fi

  local next_index=$((current_index + 1))

  if [ "$next_index" -ge "${#STAGES[@]}" ]; then
    # Write a "done" state for the statusline to display briefly
    write_state "done" "$next_index" "completed" "$ask" "$started" "$brainstorm"
    echo "PIPELINE_COMPLETE"
    return 0
  fi

  local next_stage="${STAGES[$next_index]}"
  write_state "$next_stage" "$next_index" "running" "$ask" "$started" "$brainstorm"
  echo "ADVANCED stage=$next_stage index=$next_index"
}

do_status() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "NO_PIPELINE"
    exit 0
  fi
  jq -c '{mode, stage, stage_index, status, ask}' "$STATE_FILE"
}

do_pause() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: No state file found" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  jq '.status = "paused"' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
  echo "PAUSED"
}

do_fail() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: No state file found" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  jq '.status = "failed"' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
  echo "FAILED"
}

do_cleanup() {
  rm -f "$STATE_FILE"
  echo "CLEANUP_DONE"
}

case "${1:-}" in
  create)
    shift
    do_create "$@"
    ;;
  advance)
    do_advance
    ;;
  status)
    do_status
    ;;
  pause)
    do_pause
    ;;
  fail)
    do_fail
    ;;
  cleanup)
    do_cleanup
    ;;
  *)
    echo "Usage: spex-ship-state.sh {create|advance|status|pause|fail|cleanup}" >&2
    exit 2
    ;;
esac
