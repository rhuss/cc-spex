#!/bin/bash
# spex-flow-state.sh - Manage flow state file for step-by-step SDD workflow
#
# Usage:
#   spex-flow-state.sh create [--spec-dir <dir>]  # Create/update flow state
#   spex-flow-state.sh running <phase>            # Set active phase
#   spex-flow-state.sh running done               # Clear active phase
#   spex-flow-state.sh clarified                  # Mark clarification complete
#   spex-flow-state.sh implemented                # Mark implementation complete
#   spex-flow-state.sh gate <name>                # Mark quality gate passed
#   spex-flow-state.sh cleanup                    # Remove state file
#
# Gate actions output confirmation to stdout; other actions are silent unless an error occurs.
# Must be run from the project root.

set -euo pipefail

STATE_FILE="${SHIP_STATE_FILE:-.specify/.spex-state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="${SPEX_PROGRESS_FILE:-$(dirname "$STATE_FILE")/.spex-progress.jsonl}"

emit_progress() {
  local kind="$1" status="$2" message="$3" stage="${4:-flow}"
  python3 "$SCRIPT_DIR/spex-ship-state.py" progress-emit \
    --state-file "$STATE_FILE" --event-log "$PROGRESS_FILE" \
    --kind "$kind" --status "$status" --message "$message" --stage "$stage" \
    >/dev/null || echo "progress unavailable after persisted flow transition" >&2
}

is_flow() {
  [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1
}

is_ship() {
  [ -f "$STATE_FILE" ] && jq -e '.mode == "ship"' "$STATE_FILE" >/dev/null 2>&1
}

ensure_flow() {
  if [ ! -f "$STATE_FILE" ]; then
    do_create
  fi
}

update_state() {
  local expr="$1"
  ensure_flow
  if is_flow; then
    local tmp
    tmp=$(mktemp)
    jq "$expr" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
}

do_create() {
  # Ship mode takes precedence
  if is_ship; then
    exit 0
  fi

  local spec_dir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --spec-dir) shift; spec_dir="${1:-}" ;;
      *) ;;
    esac
    shift
  done

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  spec_dir="${spec_dir:-specs/$branch}"

  mkdir -p "$(dirname "$STATE_FILE")"

  local existing_flow=false
  if is_flow; then
    existing_flow=true
    # Merge: preserve gate fields, update branch and spec_dir
    local tmp
    tmp=$(mktemp)
    jq --arg branch "$branch" --arg dir "$spec_dir" \
      '.feature_branch = $branch | .spec_dir = $dir' \
      "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  else
    # Check if spex-collab extension is enabled
    local collab_enabled=false
    local registry=".specify/extensions/.registry"
    if [ -f "$registry" ] && jq -e '.extensions["spex-collab"].enabled == true' "$registry" >/dev/null 2>&1; then
      collab_enabled=true
    fi

    if [ "$collab_enabled" = true ]; then
      cat > "$STATE_FILE" <<EOF
{
  "mode": "flow",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "feature_branch": "$branch",
  "spec_dir": "$spec_dir",
  "implemented": false,
  "clarified": false,
  "triage_spec_passed": false,
  "triage_impl_passed": false
}
EOF
    else
      cat > "$STATE_FILE" <<EOF
{
  "mode": "flow",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "feature_branch": "$branch",
  "spec_dir": "$spec_dir",
  "implemented": false,
  "clarified": false
}
EOF
    fi
  fi
  if [ "$existing_flow" = true ]; then
    emit_progress normal updated "Flow context updated" specify
  else
    emit_progress normal started "Flow started" specify
  fi
}

do_running() {
  local phase="${1:-}"
  if [ "$phase" = "done" ]; then
    update_state '.running = ""'
    emit_progress normal succeeded "Flow phase completed" flow
  elif [ -n "$phase" ]; then
    update_state "$(printf '.running = "%s"' "$phase")"
    emit_progress normal updated "Flow phase started: $phase" "$phase"
  fi
}

do_clarified() {
  update_state '.clarified = true | .running = ""'
  emit_progress normal succeeded "Clarification completed" clarify
}

do_implemented() {
  update_state '.implemented = true | .running = ""'
  emit_progress delegated succeeded "Implementation completed" implement
}

do_gate() {
  local gate="${1:-}"
  local field=""
  case "$gate" in
    review-spec) field="review_spec_passed" ;;
    review-plan) field="review_plan_passed" ;;
    review-code) field="review_code_passed" ;;
    triage-spec) field="triage_spec_passed" ;;
    triage-impl) field="triage_impl_passed" ;;
    *) exit 0 ;;
  esac
  ensure_flow
  if is_flow; then
    update_state "$(printf '."%s" = true | .running = ""' "$field")"
    emit_progress normal succeeded "$gate gate passed" "$gate"
    echo "$gate gate: updated"
  elif [ -f "$STATE_FILE" ]; then
    echo "$gate gate: skipped (mode=$(jq -r '.mode // "unknown"' "$STATE_FILE" 2>/dev/null))" >&2
  fi
}

do_cleanup() {
  if is_flow; then
    emit_progress complete succeeded "Flow completed" flow
  fi
  rm -f "$STATE_FILE"
}

case "${1:-}" in
  create)
    shift
    do_create "$@"
    ;;
  running)
    shift
    do_running "${1:-}"
    ;;
  clarified)
    do_clarified
    ;;
  implemented)
    do_implemented
    ;;
  gate)
    shift
    do_gate "${1:-}"
    ;;
  cleanup)
    do_cleanup
    ;;
  *)
    echo "Usage: spex-flow-state.sh {create|running|clarified|implemented|gate|cleanup}" >&2
    exit 2
    ;;
esac
