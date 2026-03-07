#!/usr/bin/env python3
"""PreToolUse hook: blocks all tools until Skill is invoked when /sdd: command pending.

When a user submits a /sdd: slash command, the UserPromptSubmit hook (context-hook.py)
writes a marker file with the pending skill name. This hook checks for that marker
and blocks any non-Skill tool call until the Skill tool is invoked first.

ToolSearch is always allowed through because Skill is a deferred tool that must be
loaded via ToolSearch before it can be called.

This prevents the model from drifting into file exploration or analysis before
invoking the skill that contains the process to follow.
"""
import json
import os
import sys
from pathlib import Path


def get_marker_path(session_id):
    """Return the marker file path for a given session."""
    tmpdir = Path(os.environ.get('TMPDIR', '/tmp'))
    return tmpdir / f'.claude-sdd-skill-pending-{session_id}'


def read_hook_input():
    """Read and parse hook input JSON from stdin."""
    try:
        return json.loads(sys.stdin.read())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(0)  # Non-blocking error: let tool proceed


def main():
    hook_input = read_hook_input()

    session_id = hook_input.get('session_id', 'unknown')
    tool_name = hook_input.get('tool_name', '')

    marker = get_marker_path(session_id)

    if not marker.exists():
        sys.exit(0)  # No pending skill, allow everything

    if tool_name == 'ToolSearch':
        # ToolSearch must be allowed through so the deferred Skill tool can be loaded
        sys.exit(0)

    if tool_name == 'Skill':
        # Skill tool invoked, clear the gate
        marker.unlink(missing_ok=True)
        sys.exit(0)

    # A non-Skill tool is being called while a skill invocation is pending
    pending_skill = marker.read_text().strip()

    response = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"SKILL GATE: You MUST call Skill(skill=\"{pending_skill}\") "
                f"as your FIRST tool call. Do NOT read files, explore code, or "
                f"analyze anything before invoking the skill. The skill document "
                f"contains the process to follow. Call it NOW."
            )
        }
    }
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
