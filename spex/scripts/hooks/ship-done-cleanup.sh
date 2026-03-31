#!/bin/bash
# ship-done-cleanup.sh - Remove the "done" state file on the next interaction
# Called as a PreToolUse hook. Cleans up the brief "done" display.

STATE_FILE=".specify/.spex-ship-phase"

[ -f "$STATE_FILE" ] || exit 0

STATUS=$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null)
STAGE=$(jq -r '.stage // empty' "$STATE_FILE" 2>/dev/null)

if [ "$STATUS" = "completed" ] && [ "$STAGE" = "done" ]; then
  rm -f "$STATE_FILE"
fi
