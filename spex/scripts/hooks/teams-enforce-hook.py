#!/usr/bin/env python3
"""PreToolUse hook: blocks Agent tool with run_in_background during implementation phase."""
import json
import os
import sys


def main():
    hook_input = json.loads(sys.stdin.read())
    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})

    # Only care about Agent tool
    if tool_name != "Agent":
        print(json.dumps({"decision": "approve"}))
        return

    # Allow Agent calls with subagent_type (Explore, Plan, etc.)
    if tool_input.get("subagent_type"):
        print(json.dumps({"decision": "approve"}))
        return

    # Allow Agent calls with team_name (these are Agent Teams calls)
    if tool_input.get("team_name"):
        print(json.dumps({"decision": "approve"}))
        return

    # Check if run_in_background is set
    if not tool_input.get("run_in_background"):
        print(json.dumps({"decision": "approve"}))
        return

    # Check if teams trait is enabled
    traits_config = os.path.join(os.getcwd(), ".specify", "spex-traits.json")
    try:
        with open(traits_config) as f:
            config = json.load(f)
        teams_enabled = config.get("traits", {}).get("teams", False)
        if not teams_enabled:
            teams_enabled = (
                config.get("traits", {}).get("teams-vanilla", False)
                or config.get("traits", {}).get("teams-spec", False)
            )
    except (FileNotFoundError, json.JSONDecodeError):
        print(json.dumps({"decision": "approve"}))
        return

    if not teams_enabled:
        print(json.dumps({"decision": "approve"}))
        return

    # Only enforce during implementation phase (phase file set by speckit.implement)
    phase_file = os.path.join(os.getcwd(), ".specify", ".spex-phase")
    try:
        with open(phase_file) as f:
            phase = f.read().strip()
    except FileNotFoundError:
        print(json.dumps({"decision": "approve"}))
        return

    if phase != "implement":
        print(json.dumps({"decision": "approve"}))
        return

    # Block: implementation phase + teams trait active + background Agent
    print(json.dumps({
        "decision": "block",
        "reason": (
            "TEAMS ENFORCEMENT (implement phase): You are using Agent with "
            "run_in_background, which bypasses Agent Teams. Instead, delegate "
            "to {Skill: spex:teams-orchestrate} which provides: "
            "(1) worktree isolation for each teammate, "
            "(2) spec compliance review before merge."
        )
    }))


if __name__ == "__main__":
    main()
