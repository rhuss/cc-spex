#!/bin/bash
# spex-ship-statusline.sh - Read .specify/.spex-state and output compact status
# Usage: Called by Claude Code status line integration
# Input: JSON via stdin from Claude Code with context_window info
# Output: Colored status line for ship or flow mode, or empty if no active state

# Read stdin non-blocking (Claude Code may pass context JSON)
STDIN_JSON=""
if read -t 0 2>/dev/null; then
  STDIN_JSON=$(cat 2>/dev/null)
fi

# Resolve state file using the session's actual working directory.
#
# Claude Code passes workspace.current_dir in the stdin JSON, which reflects
# the session's CWD (including worktrees). This is the primary source for
# finding the correct state file in parallel worktree sessions.
STATE_FILE=""

# Extract current_dir and project_dir from stdin JSON (if available)
SESSION_CWD=""
SESSION_PROJECT_DIR=""
if [ -n "$STDIN_JSON" ]; then
  SESSION_CWD=$(echo "$STDIN_JSON" | jq -r '.workspace.current_dir // empty' 2>/dev/null)
  SESSION_PROJECT_DIR=$(echo "$STDIN_JSON" | jq -r '.workspace.project_dir // empty' 2>/dev/null)
fi

# Priority 1: Explicit env var (set by ship pipeline during initialization)
if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ]; then
  STATE_FILE="$SHIP_STATE_FILE"
# Priority 2: Session's current working directory (from stdin JSON)
elif [ -n "$SESSION_CWD" ] && [ -f "$SESSION_CWD/.specify/.spex-state" ]; then
  STATE_FILE="$SESSION_CWD/.specify/.spex-state"
# Priority 3: CWD (may differ from session CWD)
elif [ -f ".specify/.spex-state" ]; then
  STATE_FILE=".specify/.spex-state"
# Priority 4: Session's project dir (from stdin JSON)
elif [ -n "$SESSION_PROJECT_DIR" ] && [ -f "$SESSION_PROJECT_DIR/.specify/.spex-state" ]; then
  STATE_FILE="$SESSION_PROJECT_DIR/.specify/.spex-state"
# Priority 5: CLAUDE_PROJECT_DIR env var (legacy fallback)
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/.specify/.spex-state" ]; then
  STATE_FILE="${CLAUDE_PROJECT_DIR}/.specify/.spex-state"
fi

# Chain to previous statusline if configured
CHAIN_FILE=""
for candidate in ".claude/.spex-previous-statusline" "${CLAUDE_PROJECT_DIR:-.}/.claude/.spex-previous-statusline"; do
  if [ -f "$candidate" ]; then
    CHAIN_FILE="$candidate"
    break
  fi
done

get_chain_output() {
  if [ -n "$CHAIN_FILE" ]; then
    local prev_cmd
    prev_cmd=$(cat "$CHAIN_FILE" 2>/dev/null)
    if [ -n "$prev_cmd" ] && [ -f "$prev_cmd" ]; then
      if [ -n "$STDIN_JSON" ]; then
        echo "$STDIN_JSON" | "$prev_cmd" 2>/dev/null || true
      else
        "$prev_cmd" 2>/dev/null || true
      fi
    fi
  fi
}

if [ -z "$STATE_FILE" ]; then
  # No spex state, just show the chained statusline
  get_chain_output
  exit 0
fi

# Read entire state file once for atomicity and performance
STATE_JSON=$(cat "$STATE_FILE" 2>/dev/null) || exit 0
MODE=$(echo "$STATE_JSON" | jq -r '.mode // empty' 2>/dev/null)

# Staleness check: if a FLOW state references a feature branch and we're not on it
# (e.g., merged back to main), auto-clear the stale state file.
# Skip this check for SHIP mode: the ship pipeline creates state on the starting
# branch (e.g., main) before specify creates the feature branch, so a branch
# mismatch is expected during Stage 0. The advance command updates feature_branch
# on each stage transition.
if [ "$MODE" = "flow" ]; then
  FEATURE_BRANCH=$(echo "$STATE_JSON" | jq -r '.feature_branch // empty' 2>/dev/null)
  if [ -n "$FEATURE_BRANCH" ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$FEATURE_BRANCH" ]; then
      rm -f "$STATE_FILE"
      exit 0
    fi
  fi
fi

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

# --- Context window percentage (from stdin JSON) ---
render_context() {
  if [ -z "$STDIN_JSON" ]; then
    return
  fi
  local used
  used=$(echo "$STDIN_JSON" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  if [ -z "$used" ]; then
    return
  fi
  local pct_int=${used%.*}
  local color="$GREEN"
  if [ "$pct_int" -ge 80 ] 2>/dev/null; then
    color="$RED"
  elif [ "$pct_int" -ge 60 ] 2>/dev/null; then
    color="$YELLOW"
  fi
  printf " ${DIM}|${RESET} ${color}${used}%%${RESET}"
}

# --- Extension display (appended to both modes) ---
# Shows only optional extensions (excludes git and spex core which are always on)
read_extensions() {
  local registry=".specify/extensions/.registry"
  if [ ! -f "$registry" ]; then
    return
  fi
  local names
  names=$(jq -r '.extensions // {} | to_entries[] | select(.value.enabled == true) | select(.key != "git" and .key != "spex") | .key' "$registry" 2>/dev/null)
  if [ -n "$names" ]; then
    # Use short names: strip "spex-" prefix for brevity
    local short
    short=$(echo "$names" | sed 's/^spex-//' | paste -sd ',' - | sed 's/,/, /g')
    printf " ${DIM}[%s]${RESET}" "$short"
  fi
}

# --- Flow mode ---
render_flow() {
  # Extract all flow fields in one jq call (use pipe delimiter, not @tsv,
  # because bash read collapses consecutive tabs for empty fields)
  local spec_dir implemented clarified running rev_spec rev_plan rev_code tri_spec tri_impl
  IFS='|' read -r spec_dir implemented clarified running rev_spec rev_plan rev_code tri_spec tri_impl < <(
    echo "$STATE_JSON" | jq -r '[.spec_dir // "", .implemented // false, .clarified // false, .running // "", .review_spec_passed // false, .review_plan_passed // false, .review_code_passed // false, .triage_spec_passed // false, .triage_impl_passed // false] | map(tostring) | join("|")' 2>/dev/null
  )

  if [ -z "$spec_dir" ] || [ ! -d "$spec_dir" ]; then
    exit 0
  fi

  # Milestone detection (linear stages)
  local has_spec=false has_plan=false has_tasks=false has_impl=false
  [ -f "$spec_dir/spec.md" ] && has_spec=true
  [ -f "$spec_dir/plan.md" ] && has_plan=true
  [ -f "$spec_dir/tasks.md" ] && has_tasks=true
  [ "$implemented" = "true" ] && has_impl=true

  # Quality gate detection (from state file)
  local has_clar=false has_rev_spec=false has_rev_plan=false has_rev_code=false
  [ "$clarified" = "true" ] && has_clar=true
  [ "$rev_spec" = "true" ] && has_rev_spec=true
  [ "$rev_plan" = "true" ] && has_rev_plan=true
  [ "$rev_code" = "true" ] && has_rev_code=true

  # Next milestone (first incomplete linear stage)
  local next_step=""
  if [ "$has_spec" = false ]; then next_step="specify"
  elif [ "$has_plan" = false ]; then next_step="plan"
  elif [ "$has_tasks" = false ]; then next_step="tasks"
  elif [ "$has_impl" = false ]; then next_step="implement"
  fi

  # All done = milestones + all gates (+ triage gates when collab is enabled)
  local all_done=false
  if [ "$has_spec" = true ] && [ "$has_plan" = true ] && [ "$has_tasks" = true ] && [ "$has_impl" = true ] \
     && [ "$has_clar" = true ] && [ "$has_rev_spec" = true ] && [ "$has_rev_plan" = true ] && [ "$has_rev_code" = true ]; then
    all_done=true
    # If collab is enabled, triage gates must also pass
    local collab_registry=".specify/extensions/.registry"
    if [ -f "$collab_registry" ] && jq -e '.extensions["spex-collab"].enabled == true' "$collab_registry" >/dev/null 2>&1; then
      if [ "$tri_spec" != "true" ] || [ "$tri_impl" != "true" ]; then
        all_done=false
      fi
    fi
  fi

  # Render milestones (linear, ▶ on next step, dim after)
  local mile_names=("spec" "plan" "tasks" "impl")
  local mile_done=("$has_spec" "$has_plan" "$has_tasks" "$has_impl")
  local mile_next=("specify" "plan" "tasks" "implement")
  local marks=""
  for idx in "${!mile_names[@]}"; do
    if [ -n "$running" ] && [ "$running" = "${mile_next[$idx]}" ]; then
      marks+=" ${CYAN}${BOLD}${mile_names[$idx]} ▶${RESET}"
    elif [ "${mile_done[$idx]}" = true ]; then
      marks+=" ${GREEN}${mile_names[$idx]} ✓${RESET}"
    else
      marks+=" ${DIM}${mile_names[$idx]} ○${RESET}"
    fi
  done

  # Render quality gates (independent checklist: C=clarify, S=review-spec, P=review-plan, R=review-code)
  local gate_c gate_s gate_p gate_r
  if [ "$running" = "clarify" ]; then gate_c="${CYAN}${BOLD}C ▶${RESET}";
  elif [ "$has_clar" = true ]; then gate_c="${GREEN}C ✓${RESET}"; else gate_c="${DIM}C ○${RESET}"; fi
  if [ "$running" = "review-spec" ]; then gate_s="${CYAN}${BOLD}S ▶${RESET}";
  elif [ "$has_rev_spec" = true ]; then gate_s="${GREEN}S ✓${RESET}"; else gate_s="${DIM}S ○${RESET}"; fi
  if [ "$running" = "review-plan" ]; then gate_p="${CYAN}${BOLD}P ▶${RESET}";
  elif [ "$has_rev_plan" = true ]; then gate_p="${GREEN}P ✓${RESET}"; else gate_p="${DIM}P ○${RESET}"; fi
  if [ "$running" = "review-code" ]; then gate_r="${CYAN}${BOLD}R ▶${RESET}";
  elif [ "$has_rev_code" = true ]; then gate_r="${GREEN}R ✓${RESET}"; else gate_r="${DIM}R ○${RESET}"; fi

  # Triage gate (only when spex-collab extension is enabled)
  local gate_t=""
  local collab_registry=".specify/extensions/.registry"
  local collab_enabled=false
  if [ -f "$collab_registry" ] && jq -e '.extensions["spex-collab"].enabled == true' "$collab_registry" >/dev/null 2>&1; then
    collab_enabled=true
  fi
  if [ "$collab_enabled" = true ]; then
    if [ "$running" = "triage-spec" ] || [ "$running" = "triage-impl" ]; then
      gate_t="${CYAN}${BOLD}T ▶${RESET}"
    elif [ "$tri_spec" = "true" ] || [ "$tri_impl" = "true" ]; then
      gate_t="${GREEN}T ✓${RESET}"
    else
      gate_t="${DIM}T ○${RESET}"
    fi
  fi

  # Smoke test indicator (shown when smoke test results exist in state)
  local gate_st=""
  local smoke_completed
  smoke_completed=$(echo "$STATE_JSON" | jq -r '.smoke_test_completed | tostring' 2>/dev/null)
  if [ "$smoke_completed" = "true" ]; then
    gate_st="${GREEN}ST ✓${RESET}"
  elif [ "$smoke_completed" = "false" ]; then
    local st_done st_total
    st_done=$(echo "$STATE_JSON" | jq -r '.smoke_test_scenarios // 0' 2>/dev/null)
    st_total=$(echo "$STATE_JSON" | jq -r '.smoke_test_total // 0' 2>/dev/null)
    gate_st="${YELLOW}ST ${st_done}/${st_total}${RESET}"
  fi

  # Build output
  local gate_section="${gate_c} ${gate_s} ${gate_p} ${gate_r}"
  if [ -n "$gate_t" ]; then
    gate_section="${gate_section} ${gate_t}"
  fi
  if [ -n "$gate_st" ]; then
    gate_section="${gate_section} ${gate_st}"
  fi
  printf "🧬 ${CYAN}${BOLD}spex${RESET}${marks} ${DIM}|${RESET} ${gate_section}"
  if [ "$all_done" = true ]; then
    printf " ${GREEN}${BOLD}🏁${RESET}"
  fi
  read_extensions
  render_context
}

# --- Ship mode ---
render_ship() {
  # Extract all ship fields in one jq call
  local STAGE INDEX TOTAL ASK STATUS
  read -r STAGE INDEX TOTAL ASK STATUS < <(
    echo "$STATE_JSON" | jq -r '[.stage // "", .stage_index // "", .total_stages // 8, .ask // "smart", .status // "running"] | @tsv' 2>/dev/null
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
    plan)         EMOJI="🗺"; COLOR="$GREEN";;
    tasks)        EMOJI="📋"; COLOR="$GREEN";;
    review-plan)  EMOJI="✅"; COLOR="$MAGENTA";;
    implement)    EMOJI="🔨"; COLOR="$YELLOW";;
    review-code)  EMOJI="🔎"; COLOR="$MAGENTA";;
    stamp|finish) EMOJI="🏁"; COLOR="$GREEN";;
    done)         EMOJI="✅"; COLOR="$GREEN";;
    *)            EMOJI="⚙"; COLOR="$WHITE";;
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
    always) ASK_ICON="👁";;
    smart)  ASK_ICON="🧠";;
    never)  ASK_ICON="🚀";;
  esac

  local PREFIX="🧬 ${COLOR}${BOLD}ship${RESET}"
  local STAGE_DISPLAY="${EMOJI} ${COLOR}${BOLD}${STAGE}${RESET}"
  local PROGRESS="${DIM}${BAR}${RESET} ${DIM}${DISPLAY_INDEX}/${TOTAL}${RESET}"

  if [ "$STAGE" = "done" ]; then
    printf "🧬 ${GREEN}${BOLD}ship${RESET} ✅ ${GREEN}${BOLD}done${RESET} ${DIM}▓▓▓▓▓▓▓▓${RESET} ${DIM}8/8${RESET}"
  elif [ "$STATUS" = "paused" ]; then
    printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON} ${RED}${BOLD}⏸ paused${RESET}"
  elif [ "$STATUS" = "failed" ]; then
    printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON} ${RED}${BOLD}✗ failed${RESET}"
  else
    printf "${PREFIX} ${STAGE_DISPLAY} ${PROGRESS} ${ASK_ICON}"
  fi
  read_extensions
  render_context
}

# --- Watch mode ---
render_watch() {
  # Extract watch fields in one jq call
  local PR_NUMBER CI_STATUS STARTED_AT TIMEOUT TRIAGE_COUNT FIX_ATTEMPTS
  read -r PR_NUMBER CI_STATUS STARTED_AT TIMEOUT TRIAGE_COUNT FIX_ATTEMPTS < <(
    echo "$STATE_JSON" | jq -r '[.pr_number // "", .last_ci_status // "pending", .watch_started_at // "", .watch_timeout_minutes // 30, .triage_count // 0, .ci_fix_attempts // 0] | @tsv' 2>/dev/null
  )

  if [ -z "$PR_NUMBER" ] || [ -z "$STARTED_AT" ]; then
    exit 0
  fi

  # Calculate elapsed time
  local now_epoch started_epoch elapsed_seconds elapsed_min
  now_epoch=$(date -u +%s 2>/dev/null)
  # Parse ISO 8601 date - handle both GNU and BSD date
  started_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || date -u -d "$STARTED_AT" +%s 2>/dev/null || echo "$now_epoch")
  elapsed_seconds=$((now_epoch - started_epoch))
  elapsed_min=$((elapsed_seconds / 60))

  # CI status color coding
  local CI_ICON CI_COLOR
  case "$CI_STATUS" in
    passing) CI_ICON="✓"; CI_COLOR="$GREEN" ;;
    failing) CI_ICON="✗"; CI_COLOR="$RED" ;;
    pending) CI_ICON="…"; CI_COLOR="$YELLOW" ;;
    none)    CI_ICON="—"; CI_COLOR="$DIM" ;;
    *)       CI_ICON="?"; CI_COLOR="$WHITE" ;;
  esac

  # Build output: 👀 PR #42 | 5m | CI ✓ | T:2
  printf "👀 ${CYAN}${BOLD}PR #%s${RESET}" "$PR_NUMBER"
  printf " ${DIM}|${RESET} ${DIM}%sm${RESET}" "$elapsed_min"
  printf " ${DIM}|${RESET} ${CI_COLOR}CI %s${RESET}" "$CI_ICON"

  # Show fix attempts if any
  if [ "$FIX_ATTEMPTS" -gt 0 ] 2>/dev/null; then
    printf " ${RED}F:%s${RESET}" "$FIX_ATTEMPTS"
  fi

  # Show triage count if > 0
  if [ "$TRIAGE_COUNT" -gt 0 ] 2>/dev/null; then
    printf " ${DIM}|${RESET} ${MAGENTA}T:%s${RESET}" "$TRIAGE_COUNT"
  fi

  # Show timeout warning if close to expiry
  if [ "$elapsed_min" -ge "$((TIMEOUT - 5))" ] 2>/dev/null; then
    printf " ${RED}${BOLD}⏰${RESET}"
  fi

  read_extensions
  render_context
}

# --- Mode dispatch ---
# Run chained statusline first (previous statusline output appears before spex)
CHAIN_OUTPUT=$(get_chain_output)
if [ -n "$CHAIN_OUTPUT" ]; then
  printf "%s " "$CHAIN_OUTPUT"
fi

case "$MODE" in
  flow) render_flow ;;
  ship) render_ship ;;
  watch) render_watch ;;
  *)
    # Backward compatibility: no mode field means old ship format
    # Check if it has ship-specific fields
    if echo "$STATE_JSON" | jq -e '.stage' >/dev/null 2>&1; then
      render_ship
    fi
    ;;
esac
