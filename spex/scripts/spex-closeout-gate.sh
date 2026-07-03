#!/bin/bash
# spex-closeout-gate.sh - Enforce pass/fail based on unresolved review findings
#
# Usage:
#   spex-closeout-gate.sh <spec-dir>
#
# Arguments:
#   spec-dir    Path to the feature spec directory
#
# Environment:
#   SPEX_CLOSEOUT_STRICT   Set to "1" to fail when no review report exists
#
# Exit codes:
#   0   Pass (no unresolved Critical/Important, or no report in fail-open mode)
#   1   Fail (unresolved Critical/Important findings, or no report in strict mode)
#   2   Usage error
#
# Output (stdout):
#   CLOSEOUT_PASS           Gate passes
#   CLOSEOUT_FAIL critical=N important=M   Gate fails with counts
#   CLOSEOUT_SKIP           No report exists (fail-open)
#   CLOSEOUT_STRICT_FAIL    No report in strict mode

set -euo pipefail

usage() {
  echo "Usage: spex-closeout-gate.sh <spec-dir>" >&2
  echo "" >&2
  echo "Check REVIEW-CODE.md for unresolved Critical/Important findings." >&2
  echo "Set SPEX_CLOSEOUT_STRICT=1 to require a review report." >&2
  exit 2
}

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  usage
fi

SPEC_DIR="$1"

if [ ! -d "$SPEC_DIR" ]; then
  echo "ERROR: Spec directory not found: $SPEC_DIR" >&2
  exit 2
fi

REVIEW_FILE="$SPEC_DIR/REVIEW-CODE.md"

if [ ! -f "$REVIEW_FILE" ]; then
  if [ "${SPEX_CLOSEOUT_STRICT:-0}" = "1" ]; then
    echo "CLOSEOUT_STRICT_FAIL"
    echo "Closeout gate failed: no REVIEW-CODE.md found (strict mode)" >&2
    exit 1
  fi
  echo "CLOSEOUT_SKIP"
  exit 0
fi

parse_remaining() {
  local severity="$1"
  local val
  val=$(grep -i "^|[[:space:]]*${severity}" "$REVIEW_FILE" 2>/dev/null \
    | awk -F'|' '{gsub(/[[:space:]]/, "", $5); print $5}' \
    | head -1) || true
  case "$val" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$val" ;;
  esac
}

CRITICAL_REMAINING=$(parse_remaining "Critical")
IMPORTANT_REMAINING=$(parse_remaining "Important")

if [ "$CRITICAL_REMAINING" -gt 0 ] || [ "$IMPORTANT_REMAINING" -gt 0 ]; then
  echo "CLOSEOUT_FAIL critical=$CRITICAL_REMAINING important=$IMPORTANT_REMAINING"
  echo "Closeout gate failed: $CRITICAL_REMAINING unresolved Critical, $IMPORTANT_REMAINING unresolved Important findings" >&2
  exit 1
fi

echo "CLOSEOUT_PASS"
exit 0
