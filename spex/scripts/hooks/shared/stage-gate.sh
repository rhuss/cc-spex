#!/bin/sh
# stage-gate.sh - Ship pipeline stage ordering enforcement
#
# Enforces that ship pipeline stages are executed in order.
# For Skill tool calls, denies out-of-order stage invocations.
# For non-Skill tools, injects a stage reminder as context.
#
# Usage:
#   result=$(sh stage-gate.sh <tool_name> <skill_name> <state_file_path>)
#   # result is "deny:<reason>" or "context:<text>" or "allow"
#
# Reads .spex-state JSON for pipeline status, stage, and stage_index.

set -eu

TOOL_NAME="${1:-}"
SKILL_NAME="${2:-}"
STATE_FILE="${3:-}"

# No state file means no active pipeline
if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "allow"
  exit 0
fi

# Parse state file with jq
if ! command -v jq >/dev/null 2>&1; then
  echo "allow"
  exit 0
fi

STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null || echo "")
if [ "$STATUS" != "running" ] && [ "$STATUS" != "paused" ]; then
  echo "allow"
  exit 0
fi

CURRENT_INDEX=$(jq -r '.stage_index // "-1"' "$STATE_FILE" 2>/dev/null || echo "-1")
CURRENT_STAGE=$(jq -r '.stage // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")

# Stage skill mapping (index -> skill name)
stage_skill() {
  case "$1" in
    0) echo "speckit-specify" ;;
    1) echo "speckit-clarify" ;;
    2) echo "spex:review-spec" ;;
    3) echo "speckit-plan" ;;
    4) echo "speckit-tasks" ;;
    5) echo "spex:review-plan" ;;
    6) echo "speckit-implement" ;;
    7) echo "spex:review-code" ;;
    8) echo "spex:verification-before-completion" ;;
    *) echo "unknown" ;;
  esac
}

# Stage name mapping (index -> stage name)
stage_name() {
  case "$1" in
    0) echo "specify" ;;
    1) echo "clarify" ;;
    2) echo "review-spec" ;;
    3) echo "plan" ;;
    4) echo "tasks" ;;
    5) echo "review-plan" ;;
    6) echo "implement" ;;
    7) echo "review-code" ;;
    8) echo "stamp" ;;
    *) echo "unknown" ;;
  esac
}

# Skill to stage index mapping
skill_to_stage() {
  case "$1" in
    speckit-specify) echo "0" ;;
    speckit-clarify) echo "1" ;;
    spex:review-spec) echo "2" ;;
    speckit-plan) echo "3" ;;
    speckit-tasks) echo "4" ;;
    spex:review-plan) echo "5" ;;
    speckit-implement) echo "6" ;;
    spex:review-code) echo "7" ;;
    spex:verification-before-completion) echo "8" ;;
    *) echo "-1" ;;
  esac
}

# For Skill tool calls, enforce stage ordering
if [ "$TOOL_NAME" = "Skill" ]; then
  TARGET_INDEX=$(skill_to_stage "$SKILL_NAME")
  if [ "$TARGET_INDEX" = "-1" ]; then
    echo "allow"
    exit 0
  fi

  if [ "$TARGET_INDEX" -gt "$CURRENT_INDEX" ]; then
    # Build list of skipped stages
    SKIPPED=""
    i=$CURRENT_INDEX
    while [ "$i" -lt "$TARGET_INDEX" ]; do
      s_name=$(stage_name "$i")
      s_skill=$(stage_skill "$i")
      SKIPPED="${SKIPPED}  ${i}. ${s_name} (${s_skill})\n"
      i=$((i + 1))
    done
    TARGET_NAME=$(stage_name "$TARGET_INDEX")
    EXPECTED_SKILL=$(stage_skill "$CURRENT_INDEX")

    echo "deny:PIPELINE DISCIPLINE: You are trying to invoke ${SKILL_NAME} (stage ${TARGET_INDEX}: ${TARGET_NAME}) but the pipeline is at stage ${CURRENT_INDEX}: ${CURRENT_STAGE}. You MUST complete these stages first, in order:\n${SKIPPED}\nDo NOT skip stages. Do NOT shortcut. Invoke ${EXPECTED_SKILL} now."
    exit 0
  fi

  echo "allow"
  exit 0
fi

# For non-Skill tools, inject a stage reminder
EXPECTED_SKILL=$(stage_skill "$CURRENT_INDEX")

# Stage-specific briefs for review stages
BRIEF=""
case "$CURRENT_INDEX" in
  7)
    BRIEF="\n--- STAGE 7 REQUIREMENTS ---\nYou MUST invoke {Skill: spex:review-code} which runs:\n  1. Spec compliance check (compliance score)\n  2. Code Review Guide -> REVIEW-CODE.md\n  3. Deep review: 5 agents (correctness, architecture, security, production, tests)\n  4. CodeRabbit CLI: coderabbit review --agent --type all (LOCAL, no PR needed)\n  5. Fix loop for Critical/Important findings\n  6. Deep Review Report -> REVIEW-CODE.md\nThe advance script WILL REJECT advancement if REVIEW-CODE.md lacks a Deep Review Report section."
    ;;
  8)
    BRIEF="\n--- STAGE 8 REQUIREMENTS ---\nYou MUST invoke {Skill: spex:verification-before-completion} which runs:\n  1. Test suite execution\n  2. Spec compliance validation\n  3. Drift check\nDo NOT claim completion without running actual verification commands."
    ;;
esac

echo "context:<ship-pipeline stage=\"${CURRENT_STAGE}\" index=\"${CURRENT_INDEX}\" expected-skill=\"${EXPECTED_SKILL}\">Active ship pipeline at stage ${CURRENT_INDEX}/8: ${CURRENT_STAGE}. Next action: invoke ${EXPECTED_SKILL}. Do not explore or shortcut. Follow the pipeline.${BRIEF}</ship-pipeline>"
