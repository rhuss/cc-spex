#!/bin/bash
# spex-ship-statusline.sh - Read .specify/.spex-ship-phase and output compact status
# Usage: Called by Claude Code status line integration
# Output: "ship: <stage> [<index>/<total>] <ask>" or empty if no active pipeline

STATE_FILE=".specify/.spex-ship-phase"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

STAGE=$(jq -r '.stage // empty' "$STATE_FILE" 2>/dev/null)
INDEX=$(jq -r '.stage_index // empty' "$STATE_FILE" 2>/dev/null)
TOTAL=$(jq -r '.total_stages // 9' "$STATE_FILE" 2>/dev/null)
ASK=$(jq -r '.ask // "smart"' "$STATE_FILE" 2>/dev/null)
STATUS=$(jq -r '.status // "running"' "$STATE_FILE" 2>/dev/null)

if [ -z "$STAGE" ] || [ -z "$INDEX" ]; then
  exit 0
fi

DISPLAY_INDEX=$((INDEX + 1))

if [ "$STATUS" = "paused" ]; then
  echo "ship: $STAGE [$DISPLAY_INDEX/$TOTAL] $ASK (paused)"
else
  echo "ship: $STAGE [$DISPLAY_INDEX/$TOTAL] $ASK"
fi
