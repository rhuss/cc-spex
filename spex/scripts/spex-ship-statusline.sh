#!/bin/bash
# spex-ship-statusline.sh - Read .specify/.spex-ship-phase and output compact status
# Usage: Called by Claude Code status line integration
# Output: Colored status with emoji per stage, or empty if no active pipeline

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

# Colors
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
BLUE="\033[34m"
GREEN="\033[32m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
RED="\033[31m"
WHITE="\033[37m"

# Per-stage emoji and color
case "$STAGE" in
  specify)      EMOJI="📝"; COLOR="$CYAN";;
  clarify)      EMOJI="🔍"; COLOR="$BLUE";;
  review-spec)  EMOJI="🔬"; COLOR="$MAGENTA";;
  plan)         EMOJI="🗺️";  COLOR="$GREEN";;
  tasks)        EMOJI="📋"; COLOR="$GREEN";;
  review-plan)  EMOJI="✅"; COLOR="$MAGENTA";;
  implement)    EMOJI="🔨"; COLOR="$YELLOW";;
  review-code)  EMOJI="🔎"; COLOR="$MAGENTA";;
  verify)       EMOJI="🏁"; COLOR="$GREEN";;
  done)         EMOJI="✅"; COLOR="$GREEN";;
  *)            EMOJI="⚙️";  COLOR="$WHITE";;
esac

# Build progress bar (filled/empty blocks)
FILLED=$((DISPLAY_INDEX * 9 / TOTAL))
EMPTY=$((9 - FILLED))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="▓"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

# Ask level indicator
case "$ASK" in
  always) ASK_ICON="👁️";;
  smart)  ASK_ICON="🧠";;
  never)  ASK_ICON="🚀";;
  *)      ASK_ICON="";;
esac

PREFIX="🧬 ${COLOR}${BOLD}spex:ship${RESET}"
STAGE_DISPLAY="${EMOJI} ${COLOR}${BOLD}${STAGE}${RESET}"
PROGRESS="${DIM}${BAR}${RESET} ${DIM}${DISPLAY_INDEX}/${TOTAL}${RESET}"

if [ "$STAGE" = "done" ]; then
  printf "🧬 ${GREEN}${BOLD}spex:ship${RESET} ✅ ${GREEN}${BOLD}done${RESET} ${DIM}▓▓▓▓▓▓▓▓▓${RESET} ${DIM}9/9${RESET}"
elif [ "$STATUS" = "paused" ]; then
  printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON} ${RED}${BOLD}⏸ paused${RESET}"
elif [ "$STATUS" = "failed" ]; then
  printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON} ${RED}${BOLD}✗ failed${RESET}"
else
  printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON}"
fi
