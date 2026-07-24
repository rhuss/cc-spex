#!/usr/bin/env python3
"""Codex CLI PreToolUse hook adapter for spex.

Reads JSON from stdin per Codex's v0.144+ hook contract, calls shared POSIX
shell enforcement functions, and formats responses per Codex's expected output.

Codex hook contract (stdin JSON, v0.144+):
  - tool_name: string (name of the tool being called)
  - tool_input: object (arguments to the tool)
  - turn_id: string (session/turn identifier, used as session_id for markers)
  - cwd: string (working directory)
  - permission_mode: string (ignored)

Codex hook response (stdout JSON, v0.144+):
  - For deny: {"hookSpecificOutput": {"hookEventName": "PreToolUse",
      "permissionDecision": "deny", "permissionDecisionReason": "<reason>"}}
  - For context: {"systemMessage": "<text>"}
  - For allow: exit 0 with no output

Side effects mirror Claude Code's pretool-gate.py behavior.
"""
import json
import os
import subprocess
import sys
from pathlib import Path


SHARED_DIR = Path(__file__).parent.parent.parent / 'hooks' / 'shared'
PLUGIN_ROOT = Path(__file__).resolve().parent.parent.parent.parent
STATE_TOOL = PLUGIN_ROOT / 'scripts' / 'spex-ship-state.sh'
NON_MUTATING_TOOLS = {
    'skill', 'read', 'grep', 'glob', 'find', 'ls', 'view', 'view_image',
    'websearch', 'web_search', 'todowrite', 'todo_write',
}


def git_root(cwd):
    try:
        result = subprocess.run(
            ['git', '-C', str(cwd), 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return Path(result.stdout.strip()).resolve() if result.returncode == 0 else None


def state_candidates(root):
    candidates = [root / '.specify' / '.spex-state']
    try:
        result = subprocess.run(
            ['git', '-C', str(root), 'worktree', 'list', '--porcelain'],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            candidates.extend(
                Path(line[9:]).resolve() / '.specify' / '.spex-state'
                for line in result.stdout.splitlines()
                if line.startswith('worktree ')
            )
    except (OSError, subprocess.TimeoutExpired):
        pass
    return [path for path in candidates if path.is_file()]


def resolve_project_context(cwd):
    root = git_root(cwd)
    if root is None:
        return {'error': 'Cannot establish a Git project root', 'project_dir': cwd,
                'git_root': None, 'state': None, 'state_file': None}
    base = {'git_root': root, 'project_dir': root, 'state': None, 'state_file': None}
    if not STATE_TOOL.is_file():
        if state_candidates(root):
            base['error'] = 'Workflow state exists but the validated state resolver is unavailable'
        return base
    environment = os.environ.copy()
    environment.pop('SHIP_STATE_FILE', None)
    try:
        result = subprocess.run(
            ['sh', str(STATE_TOOL), 'resolve'], cwd=root, env=environment,
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        base['error'] = f'Workflow state resolution failed: {exc}'
        return base
    try:
        payload = json.loads(result.stdout) if result.stdout.strip() else None
    except json.JSONDecodeError:
        payload = None
    if result.returncode == 0 and isinstance(payload, dict):
        context = payload.get('context', {})
        base.update({
            'state': payload,
            'project_dir': Path(context['active_worktree']).resolve(),
            'state_file': Path(context['state_file']).resolve(),
            'spec_dir': Path(context['spec_dir']).resolve(),
        })
        return base
    diagnostics = payload.get('diagnostics', []) if isinstance(payload, dict) else []
    has_candidate = any(isinstance(item, dict) and item.get('candidate') for item in diagnostics)
    if has_candidate or state_candidates(root):
        reasons = []
        for item in diagnostics:
            if isinstance(item, dict):
                reasons.extend(item.get('reasons', []))
        detail = '; '.join(dict.fromkeys(str(reason) for reason in reasons if reason))
        base['error'] = f'Ambiguous or invalid workflow state{": " + detail if detail else ""}'
    return base


def is_mutating_tool(tool_name):
    return tool_name.lower() not in NON_MUTATING_TOOLS


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
    """Print a Codex v0.144+ deny response and exit."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def codex_context(text):
    """Print a Codex v0.144+ context response and exit."""
    print(json.dumps({"systemMessage": text}))
    sys.exit(0)


def side_effects(tool_name, tool_input, session_id, state_file):
    """Run marker/state side effects (identical to Claude Code adapter)."""
    if tool_name == 'Skill':
        marker_path('spex-skill-pending', session_id).unlink(missing_ok=True)

    state_path = Path(state_file) if state_file else None
    if state_path and state_path.exists():
        try:
            state = json.loads(state_path.read_text())
            if state.get('status') == 'completed' and state.get('stage') == 'done':
                state_path.unlink(missing_ok=True)
        except Exception:
            pass


def main():
    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    tool_name = hook_input.get('tool_name', '')
    tool_input = hook_input.get('tool_input', {})
    session_id = hook_input.get('turn_id', 'unknown')
    cwd = Path(hook_input.get('cwd', '.')).resolve()

    resolved = resolve_project_context(cwd)
    pending_skill = marker_path('spex-skill-pending', session_id).exists()
    resolution_error = resolved.get('error')
    if resolution_error and (resolved.get('git_root') is not None or pending_skill):
        if is_mutating_tool(tool_name):
            codex_deny(f"{resolution_error}. Refusing feature mutation until authority is resolved.")
        codex_context(f"<spex-error>{resolution_error}. Feature mutations are blocked.</spex-error>")

    project_dir = resolved.get('project_dir') or cwd
    state_file = resolved.get('state_file')
    active_state = resolved.get('state')
    invocation_root = resolved.get('git_root')
    if (active_state is not None and invocation_root != project_dir
            and is_mutating_tool(tool_name)):
        codex_deny(
            f"Active Spex worktree is {project_dir}, but the hook was invoked from "
            f"{invocation_root or cwd}. "
            "Re-establish the validated worktree before mutating files."
        )

    # --- Side effects ---
    side_effects(tool_name, tool_input, session_id, state_file)

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
        tool_name, json.dumps(tool_input), project_dir
    ])
    teams_type, teams_content = parse_result(teams_result)
    if teams_type == 'deny':
        denies.append(teams_content)

    # Gate 3: Ship pipeline
    skill_name = tool_input.get('skill', '') if tool_name == 'Skill' else ''
    state_file = str(state_file or (project_dir / '.specify' / '.spex-state'))
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
        tool_name, command, session_id, project_dir
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
