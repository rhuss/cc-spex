#!/usr/bin/env python3
"""PreToolUse hook: enforces pipeline stage discipline during spex:ship execution.

When a ship pipeline is active (.specify/.spex-ship-phase exists with status "running"),
this hook enforces that stages run in strict sequential order:

1. Blocks Skill/command invocations that skip ahead to a later stage
2. Injects a reminder about the current stage on every tool call so the model
   stays focused on the right stage

The hook does NOT block general tools (Read, Write, Bash, Edit, etc.) since they
are needed within each stage. It only enforces that stage transitions happen in order.
"""
import json
import os
import sys
from pathlib import Path


# Maps each pipeline stage index to the skill/command that runs it.
# The ship skill invokes these in order; this hook prevents skipping.
STAGE_SKILLS = {
    0: "speckit.specify",
    1: "speckit.clarify",
    2: "spex:review-spec",
    3: "speckit.plan",
    4: "speckit.tasks",
    5: "spex:review-plan",
    6: "speckit.implement",
    7: "spex:deep-review",
    8: "spex:verification-before-completion",
}

STAGE_NAMES = {
    0: "specify",
    1: "clarify",
    2: "review-spec",
    3: "plan",
    4: "tasks",
    5: "review-plan",
    6: "implement",
    7: "deep-review",
    8: "verify",
}

# Reverse lookup: skill name -> stage index
SKILL_TO_STAGE = {v: k for k, v in STAGE_SKILLS.items()}


def read_ship_state(cwd):
    """Read the ship pipeline state file. Returns None if not active."""
    state_file = Path(cwd) / '.specify' / '.spex-ship-phase'
    if not state_file.exists():
        return None
    try:
        with open(state_file) as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return None


def main():
    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get('tool_name', '')
    tool_input = hook_input.get('tool_input', {})
    cwd = hook_input.get('cwd', '.')

    # Only active when a ship pipeline is running
    state = read_ship_state(cwd)
    if state is None:
        sys.exit(0)

    status = state.get('status', '')
    if status not in ('running', 'paused'):
        sys.exit(0)

    current_index = state.get('stage_index', -1)
    current_stage = state.get('stage', 'unknown')

    # For Skill tool calls, enforce stage ordering
    if tool_name == 'Skill':
        skill_name = tool_input.get('skill', '')

        # Check if this skill corresponds to a pipeline stage
        if skill_name in SKILL_TO_STAGE:
            target_index = SKILL_TO_STAGE[skill_name]

            if target_index > current_index:
                # Trying to skip ahead
                skipped = [
                    f"  {i}. {STAGE_NAMES[i]} ({STAGE_SKILLS[i]})"
                    for i in range(current_index, target_index)
                ]
                response = {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            f"PIPELINE DISCIPLINE: You are trying to invoke "
                            f"{skill_name} (stage {target_index}: "
                            f"{STAGE_NAMES[target_index]}) but the pipeline is "
                            f"at stage {current_index}: {current_stage}. "
                            f"You MUST complete these stages first, in order:\n"
                            + "\n".join(skipped) + "\n\n"
                            f"Do NOT skip stages. Do NOT shortcut. "
                            f"Invoke {STAGE_SKILLS[current_index]} now."
                        )
                    }
                }
                print(json.dumps(response))
                sys.exit(0)

        # Allow the skill call (correct stage or non-pipeline skill)
        sys.exit(0)

    # For all other tools, inject a reminder about the current stage
    # This keeps the model focused and prevents drift into exploration
    expected_skill = STAGE_SKILLS.get(current_index, 'unknown')
    response = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": (
                f"<ship-pipeline stage=\"{current_stage}\" index=\"{current_index}\" "
                f"expected-skill=\"{expected_skill}\">"
                f"Active ship pipeline at stage {current_index}/{8}: {current_stage}. "
                f"Next action: invoke {expected_skill}. "
                f"Do not explore or shortcut. Follow the pipeline."
                f"</ship-pipeline>"
            )
        }
    }
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
