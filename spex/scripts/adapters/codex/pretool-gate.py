#!/usr/bin/env python3
"""Codex CLI PreToolUse hook adapter for spex.

Reads JSON from stdin per Codex's hook contract, calls shared POSIX shell
enforcement functions, and formats responses per Codex's expected output.

Codex hook contract (stdin JSON):
  - session_id: string
  - cwd: string
  - tool_name: string
  - tool_input: object

Codex hook response (stdout JSON):
  - For deny: {"action": "deny", "message": "<reason>"}
  - For context: {"action": "context", "message": "<text>"}
  - For allow: exit 0 with no output (or {"action": "allow"})

Side effects mirror Claude Code's pretool-gate.py behavior.
"""
import json
import os
import subprocess
import sys
from pathlib import Path


SHARED_DIR = Path(__file__).parent.parent.parent / 'hooks' / 'shared'


def tmpdir():
    return Path(os.environ.get('TMPDIR', '/tmp'))


def marker_path(prefix, session_id):
    return tmpdir() / f'.claude-{prefix}-{session_id}'


def run_shared(script_name, args):
    """Run a shared shell function and return its stdout."""
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
    """Parse shared function result: 'deny:<reason>', 'context:<text>', or 'allow'."""
    if result is None:
        return 'allow', None
    if result.startswith('deny:'):
        return 'deny', result[5:]
    if result.startswith('context:'):
        return 'context', result[8:]
    return 'allow', None


def codex_deny(reason):
    """Print a Codex-format deny response and exit."""
    print(json.dumps({"action": "deny", "message": reason}))
    sys.exit(0)


def codex_context(text):
    """Print a Codex-format context response and exit."""
    print(json.dumps({"action": "context", "message": text}))
    sys.exit(0)


def side_effects(tool_name, tool_input, session_id, cwd):
    """Run marker/state side effects (identical to Claude Code adapter)."""
    if tool_name == 'Skill':
        marker_path('spex-skill-pending', session_id).unlink(missing_ok=True)

    state_file = Path(cwd) / '.specify' / '.spex-state'
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text())
            if state.get('status') == 'completed' and state.get('stage') == 'done':
                state_file.unlink(missing_ok=True)
        except Exception:
            pass


def main():
    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get('tool_name', '')
    tool_input = hook_input.get('tool_input', {})
    session_id = hook_input.get('session_id', 'unknown')
    cwd = hook_input.get('cwd', '.')

    # --- Side effects ---
    side_effects(tool_name, tool_input, session_id, cwd)

    # --- Gate 1: Skill gate (short-circuits) ---
    skill_result = run_shared('skill-gate.sh', [tool_name, session_id])
    skill_type, skill_reason = parse_result(skill_result)
    if skill_type == 'deny':
        codex_deny(skill_reason)

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
        codex_deny(" | ".join(denies))
    elif contexts:
        codex_context("\n".join(contexts))

    # Allow: exit cleanly with no output
    sys.exit(0)


if __name__ == "__main__":
    main()
