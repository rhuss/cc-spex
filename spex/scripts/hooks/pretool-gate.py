#!/usr/bin/env python3
"""Combined PreToolUse hook for the spex plugin.

Consolidates all PreToolUse gates into a single script to reduce
process spawn overhead (1 process instead of 5-6 per tool call).

Gates (checked in order, all results collected):
1. Skill gate     - blocks non-Skill tools when /spex: command pending
2. Teams enforce  - blocks background Agent during implementation when teams active
3. Ship pipeline  - enforces stage ordering during ship workflow
4. Verification   - reminds about verification before git commit

Side effects (always run):
- Clear skill-pending marker when Skill tool is called
- Remove completed ship state files (ship-done cleanup)

This hook delegates enforcement decisions to shared POSIX shell functions
under hooks/shared/, making the logic reusable across agent adapters.
"""
import json
import os
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

SHARED_DIR = Path(__file__).parent / 'shared'


def tmpdir():
    return Path(os.environ.get('TMPDIR', '/tmp'))


def marker_path(prefix, session_id):
    return tmpdir() / f'.claude-{prefix}-{session_id}'


def deny(reason):
    """Print a deny response and exit."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def context(text):
    """Print an additionalContext response and exit."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": text,
        }
    }))
    sys.exit(0)


def run_shared(script_name, args):
    """Run a shared shell function and return its stdout.

    Returns the output string, or None on failure.
    Fails open: if the shared script is missing or errors, returns None
    so the hook does not block the developer.
    """
    script = SHARED_DIR / script_name
    if not script.exists():
        return None
    try:
        result = subprocess.run(
            ['sh', str(script)] + [str(a) for a in args],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            print(f"WARNING: {script_name} failed: {result.stderr.strip()}", file=sys.stderr)
            return None
        return result.stdout.strip()
    except Exception as e:
        print(f"WARNING: {script_name} error: {e}", file=sys.stderr)
        return None


def parse_result(result):
    """Parse a shared function result string.

    Returns (result_type, content) where result_type is 'deny', 'context', or 'allow'.
    """
    if result is None:
        return 'allow', None
    if result.startswith('deny:'):
        return 'deny', result[5:]
    if result.startswith('context:'):
        return 'context', result[8:]
    return 'allow', None


# ---------------------------------------------------------------------------
# Side effects (always run, before gate checks)
# ---------------------------------------------------------------------------

def side_effects(tool_name, tool_input, session_id, cwd):
    """Run all marker/state side effects. These must execute regardless of gates."""

    # Skill gate: clear pending marker when Skill tool is invoked
    if tool_name == 'Skill':
        marker_path('spex-skill-pending', session_id).unlink(missing_ok=True)

    # Ship done cleanup: remove completed ship state file
    state_file = Path(cwd) / '.specify' / '.spex-state'
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
            if state.get('status') == 'completed' and state.get('stage') == 'done':
                state_file.unlink(missing_ok=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get('tool_name', '')
    tool_input = hook_input.get('tool_input', {})
    session_id = hook_input.get('session_id', 'unknown')
    cwd = hook_input.get('cwd', '.')

    # --- Side effects (always run) ---
    side_effects(tool_name, tool_input, session_id, cwd)

    # --- Gate 1: Skill gate (short-circuits) ---
    skill_result = run_shared('skill-gate.sh', [tool_name, session_id])
    skill_type, skill_reason = parse_result(skill_result)
    if skill_type == 'deny':
        deny(skill_reason)

    # --- Gates 2-4: collected ---
    denies = []
    contexts = []

    # Gate 2: Teams enforcement
    teams_result = run_shared('teams-gate.sh', [
        tool_name, json.dumps(tool_input), cwd
    ])
    teams_type, teams_content = parse_result(teams_result)
    if teams_type == 'deny':
        denies.append(teams_content)

    # Gate 3: Ship pipeline
    skill_name = tool_input.get('skill', '') if tool_name == 'Skill' else ''
    state_file = str(Path(cwd) / '.specify' / '.spex-state')
    ship_result = run_shared('stage-gate.sh', [
        tool_name, skill_name, state_file
    ])
    ship_type, ship_content = parse_result(ship_result)
    if ship_type == 'deny':
        denies.append(ship_content)
    elif ship_type == 'context':
        contexts.append(ship_content)

    # Gate 4: Verification reminder
    command = tool_input.get('command', '')
    verify_result = run_shared('verify-gate.sh', [
        tool_name, command, session_id, cwd
    ])
    verify_type, verify_content = parse_result(verify_result)
    if verify_type == 'context':
        contexts.append(verify_content)

    # --- Output ---
    if denies:
        deny(" | ".join(denies))
    elif contexts:
        context("\n".join(contexts))

    sys.exit(0)


if __name__ == "__main__":
    main()
