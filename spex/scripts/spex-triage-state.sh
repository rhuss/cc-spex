#!/bin/bash
# spex-triage-state.sh - Manage PR triage state file
#
# Usage:
#   spex-triage-state.sh init <pr_number>
#   spex-triage-state.sh get <pr_number> <comment_id>
#   spex-triage-state.sh set <pr_number> <comment_id> <action> <reply_id>
#   spex-triage-state.sh list-unhandled <pr_number> <comment_ids_json>
#   spex-triage-state.sh cleanup [<pr_number>]
#
# State file: .specify/.pr-triage-state.json
# Must be run from the project root.

set -euo pipefail

STATE_FILE="${TRIAGE_STATE_FILE:-.specify/.pr-triage-state.json}"

_TMPFILES=()
_cleanup_tmp() { rm -f ${_TMPFILES[@]+"${_TMPFILES[@]}"}; }
trap _cleanup_tmp EXIT

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

ensure_file() {
  if [ ! -f "$STATE_FILE" ]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    echo '{}' > "$STATE_FILE"
  fi
}

do_init() {
  [ $# -eq 1 ] || { echo "Usage: spex-triage-state.sh init <pr_number>" >&2; exit 2; }
  local pr="$1"
  [ -n "$pr" ] || { echo "ERROR: pr_number cannot be empty" >&2; exit 2; }
  ensure_file
  local tmp
  tmp=$(mktemp); _TMPFILES+=("$tmp")
  if jq -e --arg pr "$pr" '.[$pr]' "$STATE_FILE" >/dev/null 2>&1; then
    jq --arg pr "$pr" --arg ts "$(now_iso)" \
      '.[$pr].lastRun = $ts' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  else
    jq --arg pr "$pr" --arg ts "$(now_iso)" \
      '.[$pr] = {"lastRun": $ts, "comments": {}}' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
  echo "INIT pr=$pr"
}

do_get() {
  [ $# -eq 2 ] || { echo "Usage: spex-triage-state.sh get <pr_number> <comment_id>" >&2; exit 2; }
  local pr="$1" comment_id="$2"
  ensure_file
  local result
  result=$(jq -r --arg pr "$pr" --arg cid "$comment_id" \
    '.[$pr].comments[$cid] // empty' "$STATE_FILE" 2>/dev/null)
  if [ -n "$result" ]; then
    echo "$result"
  else
    echo "NOT_FOUND"
  fi
}

do_set() {
  [ $# -eq 4 ] || { echo "Usage: spex-triage-state.sh set <pr_number> <comment_id> <action> <reply_id>" >&2; exit 2; }
  local pr="$1" comment_id="$2" action="$3" reply_id="$4"
  [ -n "$pr" ] && [ -n "$comment_id" ] && [ -n "$action" ] && [ -n "$reply_id" ] || {
    echo "ERROR: all arguments must be non-empty" >&2; exit 2
  }
  ensure_file
  local tmp
  tmp=$(mktemp); _TMPFILES+=("$tmp")
  jq --arg pr "$pr" --arg cid "$comment_id" --arg act "$action" \
     --arg rid "$reply_id" --arg ts "$(now_iso)" \
    '.[$pr].comments[$cid] = {"handledAt": $ts, "action": $act, "ourReplyId": $rid}' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  echo "SET pr=$pr comment=$comment_id action=$action"
}

do_list_unhandled() {
  [ $# -eq 2 ] || { echo "Usage: spex-triage-state.sh list-unhandled <pr_number> <comment_ids_json>" >&2; exit 2; }
  local pr="$1" comment_ids_json="$2"
  if ! echo "$comment_ids_json" | jq empty 2>/dev/null; then
    echo "ERROR: comment_ids_json is not valid JSON" >&2
    return 1
  fi
  ensure_file
  local handled
  handled=$(jq --arg pr "$pr" '[.[$pr].comments // {} | keys[]]' "$STATE_FILE" 2>/dev/null)
  echo "$comment_ids_json" | jq -r --argjson handled "$handled" '
    [.[] | select(. as $id | $handled | index($id | tostring) | not)]
  '
}

do_cleanup() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "NO_STATE"
    return 0
  fi
  if [ $# -gt 0 ]; then
    local pr="$1"
    [ -n "$pr" ] || { echo "ERROR: pr_number cannot be empty" >&2; exit 2; }
    local tmp
    tmp=$(mktemp); _TMPFILES+=("$tmp")
    jq --arg pr "$pr" 'del(.[$pr])' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "CLEANUP pr=$pr"
  else
    rm -f "$STATE_FILE"
    echo "CLEANUP_ALL"
  fi
}

case "${1:-}" in
  init)
    shift; do_init "$@" ;;
  get)
    shift; do_get "$@" ;;
  set)
    shift; do_set "$@" ;;
  list-unhandled)
    shift; do_list_unhandled "$@" ;;
  cleanup)
    shift; do_cleanup "$@" ;;
  *)
    echo "Usage: spex-triage-state.sh {init|get|set|list-unhandled|cleanup}" >&2
    exit 2 ;;
esac
