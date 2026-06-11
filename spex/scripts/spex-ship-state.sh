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
#   spex-ship-state.sh checkpoint-record --checkpoint <1|2> --findings <N> --fixed <N>
#   spex-ship-state.sh smoke-test-record [--completed BOOL] [--scenarios N] [--total N] [--skipped N]
#   spex-ship-state.sh watch-start [--pr-number N] [--pr-url URL] [--timeout M] [--interval S]
#   spex-ship-state.sh watch-update <key> <value> [<key> <value> ...]
#   spex-ship-state.sh watch-cleanup           # Remove state file, output WATCH_COMPLETE
#
# Must be run from the project root.

set -euo pipefail

STATE_FILE="${SHIP_STATE_FILE:-.specify/.spex-state}"

STAGES=("specify" "clarify" "review-spec" "plan" "tasks" "review-plan" "implement" "review-code" "smoke-test")

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
  # Verify expected file artifacts exist for the completed stage before advancing.
  # Only checks for files on disk. Gate flags (review_plan_passed, review_code_passed)
  # are a flow-mode concept managed by spex-flow-state.sh. Ship mode's sequential
  # pipeline already guarantees reviews ran before advance is called.
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
  esac
  return 0
}

do_advance() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "PIPELINE_COMPLETE"
    return 0
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

# --- Watch mode commands ---

do_watch_start() {
  local pr_number="" pr_url="" timeout_minutes=30 poll_interval=60

  while [ $# -gt 0 ]; do
    case "$1" in
      --pr-number) shift; pr_number="${1:-}" ;;
      --pr-url) shift; pr_url="${1:-}" ;;
      --timeout) shift; timeout_minutes="${1:-30}" ;;
      --interval) shift; poll_interval="${1:-60}" ;;
      *) echo "ERROR: Unknown flag '$1'" >&2; exit 2 ;;
    esac
    shift
  done

  if [ -z "$pr_number" ]; then
    echo "ERROR: --pr-number is required" >&2
    exit 2
  fi

  local feature_branch
  feature_branch="$(git branch --show-current 2>/dev/null || echo 'unknown')"

  cat > "$STATE_FILE" <<EOF
{
  "mode": "watch",
  "pr_number": $pr_number,
  "pr_url": "$pr_url",
  "watch_started_at": "$(now_iso)",
  "watch_timeout_minutes": $timeout_minutes,
  "watch_poll_interval_seconds": $poll_interval,
  "last_ci_status": "pending",
  "last_ci_check_at": null,
  "ci_fix_attempts": 0,
  "last_triage_at": null,
  "triage_count": 0,
  "feature_branch": "$feature_branch"
}
EOF
  echo "WATCH_STARTED pr=$pr_number timeout=${timeout_minutes}m interval=${poll_interval}s"
}

do_watch_update() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: No state file found" >&2
    exit 1
  fi

  # Accept key-value pairs: watch-update key1 value1 key2 value2 ...
  local tmp
  tmp=$(mktemp)
  cp "$STATE_FILE" "$tmp"

  while [ $# -ge 2 ]; do
    local key="$1" value="$2"
    shift 2

    # Determine if value is numeric, null, or string
    case "$value" in
      [0-9]*) # numeric
        local tmp2
        tmp2=$(mktemp)
        jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$tmp" > "$tmp2"
        mv "$tmp2" "$tmp"
        ;;
      null)
        local tmp2
        tmp2=$(mktemp)
        jq --arg k "$key" '.[$k] = null' "$tmp" > "$tmp2"
        mv "$tmp2" "$tmp"
        ;;
      *)
        local tmp2
        tmp2=$(mktemp)
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$tmp" > "$tmp2"
        mv "$tmp2" "$tmp"
        ;;
    esac
  done

  mv "$tmp" "$STATE_FILE"
  echo "WATCH_UPDATED"
}

do_watch_cleanup() {
  rm -f "$STATE_FILE"
  echo "WATCH_COMPLETE"
}

do_checkpoint_record() {
  local checkpoint="" findings=0 fixed=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --checkpoint) shift; checkpoint="${1:-}" ;;
      --findings) shift; findings="${1:-0}" ;;
      --fixed) shift; fixed="${1:-0}" ;;
      *) echo "ERROR: Unknown flag '$1'" >&2; exit 2 ;;
    esac
    shift
  done

  if [ -z "$checkpoint" ] || { [ "$checkpoint" != "1" ] && [ "$checkpoint" != "2" ]; }; then
    echo "ERROR: --checkpoint must be 1 or 2" >&2
    exit 2
  fi

  # Validate numeric inputs to prevent JSON corruption in heredoc path
  case "$findings" in
    ''|*[!0-9]*) echo "ERROR: --findings must be a non-negative integer" >&2; exit 2 ;;
  esac
  case "$fixed" in
    ''|*[!0-9]*) echo "ERROR: --fixed must be a non-negative integer" >&2; exit 2 ;;
  esac

  if [ ! -f "$STATE_FILE" ]; then
    # No state file exists; create a minimal one with checkpoint results
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<EOF
{
  "checkpoint_${checkpoint}_findings": $findings,
  "checkpoint_${checkpoint}_fixed": $fixed,
  "checkpoint_${checkpoint}_at": "$(now_iso)"
}
EOF
    echo "CHECKPOINT_RECORDED checkpoint=$checkpoint findings=$findings fixed=$fixed"
    return 0
  fi

  # Merge checkpoint fields into existing state file
  local tmp
  tmp=$(mktemp)
  jq --argjson findings "$findings" \
     --argjson fixed "$fixed" \
     --arg at "$(now_iso)" \
     --arg fkey "checkpoint_${checkpoint}_findings" \
     --arg xkey "checkpoint_${checkpoint}_fixed" \
     --arg akey "checkpoint_${checkpoint}_at" \
     '.[$fkey] = $findings | .[$xkey] = $fixed | .[$akey] = $at' \
     "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
  echo "CHECKPOINT_RECORDED checkpoint=$checkpoint findings=$findings fixed=$fixed"
}

do_smoke_test_record() {
  local completed="false" scenarios=0 total=0 skipped=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --completed) shift; completed="${1:-false}" ;;
      --scenarios) shift; scenarios="${1:-0}" ;;
      --total) shift; total="${1:-0}" ;;
      --skipped) shift; skipped="${1:-0}" ;;
      *) echo "ERROR: Unknown flag '$1'" >&2; exit 2 ;;
    esac
    shift
  done

  if [ ! -f "$STATE_FILE" ]; then
    # No state file exists; create a minimal one with smoke test results
    cat > "$STATE_FILE" <<EOF
{
  "smoke_test_completed": $completed,
  "smoke_test_at": "$(now_iso)",
  "smoke_test_scenarios": $scenarios,
  "smoke_test_total": $total,
  "smoke_test_skipped": $skipped
}
EOF
    echo "SMOKE_TEST_RECORDED"
    return 0
  fi

  # Merge smoke test fields into existing state file
  local tmp
  tmp=$(mktemp)
  jq --argjson completed "$completed" \
     --arg at "$(now_iso)" \
     --argjson scenarios "$scenarios" \
     --argjson total "$total" \
     --argjson skipped "$skipped" \
     '.smoke_test_completed = $completed | .smoke_test_at = $at | .smoke_test_scenarios = $scenarios | .smoke_test_total = $total | .smoke_test_skipped = $skipped' \
     "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
  echo "SMOKE_TEST_RECORDED"
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
  checkpoint-record)
    shift
    do_checkpoint_record "$@"
    ;;
  smoke-test-record)
    shift
    do_smoke_test_record "$@"
    ;;
  watch-start)
    shift
    do_watch_start "$@"
    ;;
  watch-update)
    shift
    do_watch_update "$@"
    ;;
  watch-cleanup)
    do_watch_cleanup
    ;;
  *)
    echo "Usage: spex-ship-state.sh {create|advance|status|pause|fail|cleanup|checkpoint-record|smoke-test-record|watch-start|watch-update|watch-cleanup}" >&2
    exit 2
    ;;
esac
