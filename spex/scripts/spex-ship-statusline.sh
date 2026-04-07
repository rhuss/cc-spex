#!/bin/bash
# spex-ship-statusline.sh - Read .specify/.spex-state and output compact status
# Usage: Called by Claude Code status line integration
# Output: Colored status line for ship or flow mode, or empty if no active state

STATE_FILE=".specify/.spex-state"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Read entire state file once for atomicity and performance
STATE_JSON=$(cat "$STATE_FILE" 2>/dev/null) || exit 0
MODE=$(echo "$STATE_JSON" | jq -r '.mode // empty' 2>/dev/null)

# Colors (shared between modes)
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

# --- Trait display (appended to both modes) ---
read_traits() {
  local traits_file=".specify/spex-traits.json"
  if [ ! -f "$traits_file" ]; then
    return
  fi
  local names
  names=$(jq -r '.traits // {} | to_entries[] | select(.value == true) | .key' "$traits_file" 2>/dev/null)
  if [ -n "$names" ]; then
    local joined
    joined=$(echo "$names" | paste -sd ',' - | sed 's/,/, /g')
    printf " ${DIM}[%s]${RESET}" "$joined"
  fi
}

# --- Flow mode ---
render_flow() {
  # Extract all flow fields in one jq call
  local spec_dir implemented
  read -r spec_dir implemented < <(
    echo "$STATE_JSON" | jq -r '[.spec_dir // "", .implemented // false] | @tsv' 2>/dev/null
  )

  if [ -z "$spec_dir" ] || [ ! -d "$spec_dir" ]; then
    exit 0
  fi

  # Milestone detection
  local has_spec=false has_plan=false has_tasks=false has_impl=false
  [ -f "$spec_dir/spec.md" ] && has_spec=true
  [ -f "$spec_dir/plan.md" ] && has_plan=true
  [ -f "$spec_dir/tasks.md" ] && has_tasks=true
  [ "$implemented" = "true" ] && has_impl=true

  # Review artifact detection
  local has_rev_spec=false has_rev_plan=false has_rev_code=false
  [ -f "$spec_dir/REVIEW-SPEC.md" ] && has_rev_spec=true
  [ -f "$spec_dir/REVIEW-PLAN.md" ] && has_rev_plan=true
  [ -f "$spec_dir/REVIEW-CODE.md" ] && has_rev_code=true

  # Next step computation (FR-004)
  local next_step=""
  if [ "$has_spec" = false ]; then
    next_step="specify"
  elif [ "$has_plan" = false ]; then
    next_step="plan"
  elif [ "$has_tasks" = false ]; then
    next_step="tasks"
  elif [ "$has_impl" = false ]; then
    next_step="implement"
  elif [ "$has_rev_spec" = false ]; then
    next_step="review-spec"
  elif [ "$has_rev_plan" = false ]; then
    next_step="review-plan"
  elif [ "$has_rev_code" = false ]; then
    next_step="review-code"
  else
    next_step="stamp"
  fi

  # Render milestone checkmarks via loop
  local names=("spec" "plan" "tasks" "impl")
  local has_vals=("$has_spec" "$has_plan" "$has_tasks" "$has_impl")
  local next_names=("specify" "plan" "tasks" "implement")
  local marks=""
  for idx in "${!names[@]}"; do
    if [ "${has_vals[$idx]}" = true ]; then
      marks+=" ${GREEN}✓${names[$idx]}${RESET}"
    elif [ "$next_step" = "${next_names[$idx]}" ]; then
      marks+=" ${CYAN}${BOLD}○${names[$idx]}${RESET}"
    else
      marks+=" ${DIM}○${names[$idx]}${RESET}"
    fi
  done

  # Render review checklist (abbreviated)
  local rev_s rev_p rev_c
  if [ "$has_rev_spec" = true ]; then rev_s="${GREEN}✓S${RESET}"; else rev_s="${DIM}○S${RESET}"; fi
  if [ "$has_rev_plan" = true ]; then rev_p="${GREEN}✓P${RESET}"; else rev_p="${DIM}○P${RESET}"; fi
  if [ "$has_rev_code" = true ]; then rev_c="${GREEN}✓C${RESET}"; else rev_c="${DIM}○C${RESET}"; fi

  # Build output
  printf "🧬 ${CYAN}${BOLD}spex${RESET}${marks} ${DIM}|${RESET} ${rev_s} ${rev_p} ${rev_c} ${DIM}|${RESET} ${DIM}next:${RESET} ${YELLOW}${BOLD}${next_step}${RESET}"
  read_traits
}

# --- Ship mode ---
render_ship() {
  # Extract all ship fields in one jq call
  local STAGE INDEX TOTAL ASK STATUS
  read -r STAGE INDEX TOTAL ASK STATUS < <(
    echo "$STATE_JSON" | jq -r '[.stage // "", .stage_index // "", .total_stages // 9, .ask // "smart", .status // "running"] | @tsv' 2>/dev/null
  )

  if [ -z "$STAGE" ] || [ -z "$INDEX" ]; then
    exit 0
  fi

  local DISPLAY_INDEX=$((INDEX + 1))

  # Per-stage emoji and color
  local EMOJI COLOR
  case "$STAGE" in
    specify)      EMOJI="📝"; COLOR="$CYAN";;
    clarify)      EMOJI="🔍"; COLOR="$BLUE";;
    review-spec)  EMOJI="🔬"; COLOR="$MAGENTA";;
    plan)         EMOJI="🗺️";  COLOR="$GREEN";;
    tasks)        EMOJI="📋"; COLOR="$GREEN";;
    review-plan)  EMOJI="✅"; COLOR="$MAGENTA";;
    implement)    EMOJI="🔨"; COLOR="$YELLOW";;
    review-code)  EMOJI="🔎"; COLOR="$MAGENTA";;
    stamp)        EMOJI="🏁"; COLOR="$GREEN";;
    done)         EMOJI="✅"; COLOR="$GREEN";;
    *)            EMOJI="⚙️";  COLOR="$WHITE";;
  esac

  # Build progress bar
  local FILLED=$((DISPLAY_INDEX * 9 / TOTAL))
  local EMPTY=$((9 - FILLED))
  local BAR=""
  for ((i=0; i<FILLED; i++)); do BAR+="▓"; done
  for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

  # Ask level indicator
  local ASK_ICON=""
  case "$ASK" in
    always) ASK_ICON="👁️";;
    smart)  ASK_ICON="🧠";;
    never)  ASK_ICON="🚀";;
  esac

  local PREFIX="🧬 ${COLOR}${BOLD}spex:ship${RESET}"
  local STAGE_DISPLAY="${EMOJI} ${COLOR}${BOLD}${STAGE}${RESET}"
  local PROGRESS="${DIM}${BAR}${RESET} ${DIM}${DISPLAY_INDEX}/${TOTAL}${RESET}"

  if [ "$STAGE" = "done" ]; then
    printf "🧬 ${GREEN}${BOLD}spex:ship${RESET} ✅ ${GREEN}${BOLD}done${RESET} ${DIM}▓▓▓▓▓▓▓▓▓${RESET} ${DIM}9/9${RESET}"
  elif [ "$STATUS" = "paused" ]; then
    printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON} ${RED}${BOLD}⏸ paused${RESET}"
  elif [ "$STATUS" = "failed" ]; then
    printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON} ${RED}${BOLD}✗ failed${RESET}"
  else
    printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON}"
  fi
  read_traits
}

# --- Mode dispatch ---
case "$MODE" in
  flow) render_flow ;;
  ship) render_ship ;;
  *)
    # Backward compatibility: no mode field means old ship format
    # Check if it has ship-specific fields
    if echo "$STATE_JSON" | jq -e '.stage' >/dev/null 2>&1; then
      render_ship
    fi
    ;;
esac
