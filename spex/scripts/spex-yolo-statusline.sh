#!/bin/bash
# spex-yolo-statusline.sh - Read .specify/.spex-yolo-phase and output compact status
# Usage: Called by Claude Code status line integration
# Output: "yolo: <stage> [<index>/<total>] <autonomy>" or empty if no active pipeline

STATE_FILE=".specify/.spex-yolo-phase"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

STAGE=$(jq -r '.stage // empty' "$STATE_FILE" 2>/dev/null)
INDEX=$(jq -r '.stage_index // empty' "$STATE_FILE" 2>/dev/null)
TOTAL=$(jq -r '.total_stages // 9' "$STATE_FILE" 2>/dev/null)
AUTONOMY=$(jq -r '.autonomy // "balanced"' "$STATE_FILE" 2>/dev/null)
STATUS=$(jq -r '.status // "running"' "$STATE_FILE" 2>/dev/null)

if [ -z "$STAGE" ]; then
  exit 0
fi

DISPLAY_INDEX=$((INDEX + 1))

if [ "$STATUS" = "paused" ]; then
  echo "yolo: $STAGE [$DISPLAY_INDEX/$TOTAL] $AUTONOMY (paused)"
else
  echo "yolo: $STAGE [$DISPLAY_INDEX/$TOTAL] $AUTONOMY"
fi
