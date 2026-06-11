#!/bin/sh
# context-hook.sh - Command validation and context injection
#
# Validates /spex: commands against known command list and determines
# whether to write a skill-pending marker and inject context.
#
# Usage:
#   result=$(sh context-hook.sh <user_prompt> <session_id> <cwd> <plugin_root>)
#   # result is one of:
#   #   "skip" - not a spex command, no action needed
#   #   "error:<message>" - invalid command, inject error context
#   #   "inject:<skill_name>:<delegates>:<skill_args>" - valid command, inject context
#   #     delegates is "true" or "false" (whether to write skill-pending marker)
#
# Does NOT write marker files or format agent-specific responses.
# The caller (adapter) handles those side effects.

set -eu

USER_PROMPT="${1:-}"
SESSION_ID="${2:-unknown}"
CWD="${3:-.}"
PLUGIN_ROOT="${4:-.}"

# Not a spex command? Skip.
case "$USER_PROMPT" in
  /spex:*) ;;
  *)
    echo "skip"
    exit 0
    ;;
esac

# Extract skill name and args
SKILL_NAME=$(echo "$USER_PROMPT" | awk '{print $1}' | sed 's|^/||')
SKILL_ARGS=$(echo "$USER_PROMPT" | sed 's|^[^ ]* *||')
# If no args (prompt was just the command), clear
if [ "$SKILL_ARGS" = "$USER_PROMPT" ]; then
  SKILL_ARGS=""
fi

# Extract the short command name (after "spex:")
COMMAND_SHORT=$(echo "$SKILL_NAME" | sed 's|^spex:||')

# Known spex commands
KNOWN_COMMANDS="brainstorm constitution evolve help init review-code review-plan review-spec ship extensions deep-review stamp verify worktree"

# Check if command is known
IS_KNOWN=false
for cmd in $KNOWN_COMMANDS; do
  if [ "$cmd" = "$COMMAND_SHORT" ]; then
    IS_KNOWN=true
    break
  fi
done

if [ "$IS_KNOWN" = "false" ]; then
  # Check for common corrections
  SUGGESTION=""
  case "$COMMAND_SHORT" in
    specify) SUGGESTION="/speckit-specify" ;;
    plan) SUGGESTION="/speckit-plan" ;;
    tasks) SUGGESTION="/speckit-tasks" ;;
    implement) SUGGESTION="/speckit-implement" ;;
    *) SUGGESTION="Run /spex:help for valid commands" ;;
  esac
  echo "error:ERROR: /${SKILL_NAME} does not exist. Did you mean ${SUGGESTION}? spex commands: brainstorm, review-*, evolve, extensions, init, help, constitution. Spec-kit commands: /speckit-specify, /speckit-plan, /speckit-tasks, /speckit-implement."
  exit 0
fi

# Determine if this command delegates to a Skill tool
# Standalone skills don't need the skill gate
STANDALONE="init"
DELEGATES="true"

for s in $STANDALONE; do
  if [ "$s" = "$COMMAND_SHORT" ]; then
    DELEGATES="false"
    break
  fi
done

# If not standalone, check if the command file contains {Skill: delegation
if [ "$DELEGATES" = "true" ]; then
  FOUND_CMD_FILE=""
  # Search extension command files
  if [ -d "$PLUGIN_ROOT/extensions" ]; then
    for ext_dir in "$PLUGIN_ROOT/extensions"/*/; do
      [ -d "${ext_dir}commands" ] || continue
      for cmd_file in "${ext_dir}commands"/*.md; do
        [ -f "$cmd_file" ] || continue
        case "$cmd_file" in
          *".${COMMAND_SHORT}.md")
            FOUND_CMD_FILE="$cmd_file"
            break 2
            ;;
        esac
      done
    done
  fi

  if [ -n "$FOUND_CMD_FILE" ]; then
    if grep -q '{Skill:' "$FOUND_CMD_FILE" 2>/dev/null; then
      DELEGATES="true"
    else
      DELEGATES="false"
    fi
  else
    # No command file means it's skill-only; gate it
    DELEGATES="true"
  fi
fi

echo "inject:${SKILL_NAME}:${DELEGATES}:${SKILL_ARGS}"
