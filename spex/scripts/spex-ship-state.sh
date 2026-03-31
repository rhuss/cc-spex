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

STATE_FILE=".specify/.spex-ship-phase"

STAGES=("specify" "clarify" "review-spec" "plan" "tasks" "review-plan" "implement" "review-code" "verify")

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
  jq -c '{stage, stage_index, status, ask}' "$STATE_FILE"
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
