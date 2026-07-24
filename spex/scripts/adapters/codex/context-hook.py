#!/usr/bin/env python3
"""Codex CLI UserPromptSubmit hook adapter for spex.

Reads JSON from stdin per Codex's v0.144+ hook contract, validates /spex:
commands via the shared context-hook.sh, writes skill-pending markers, and
injects spex context into the Codex session.

Codex hook contract (stdin JSON, v0.144+):
  - prompt: string (user's input)
  - turn_id: string (session/turn identifier, used as session_id for markers)
  - cwd: string (working directory)
  - permission_mode: string (ignored)
  - transcript_path: string (ignored)

Codex hook response (stdout JSON, v0.144+):
  - For context injection: {"systemMessage": "<text>"}
  - For pass-through: exit 0 with no output
"""
import json
import os
import subprocess
import sys
from pathlib import Path


SHARED_DIR = Path(__file__).parent.parent.parent / 'hooks' / 'shared'
PLUGIN_ROOT = Path(__file__).resolve().parent.parent.parent.parent
STATE_TOOL = PLUGIN_ROOT / 'scripts' / 'spex-ship-state.sh'


def git_root(cwd):
    """Return the physical Git root for cwd, or None outside a repository."""
    try:
        result = subprocess.run(
            ['git', '-C', str(cwd), 'rev-parse', '--show-toplevel'],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip()).resolve()


def state_candidates(root):
    """Find state presence only; candidates never become authority here."""
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
    """Resolve project/state authority without trusting cwd or env state paths."""
    root = git_root(cwd)
    if root is None:
        return {'error': 'Cannot establish a Git project root', 'project_dir': None}
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


def get_marker_path(session_id):
    """Return the skill gate marker file path for a given session."""
    tmpdir = Path(os.environ.get('TMPDIR', '/tmp'))
    return tmpdir / f'.claude-spex-skill-pending-{session_id}'


def clear_marker(session_id):
    """Remove any stale skill gate marker for this session."""
    marker = get_marker_path(session_id)
    marker.unlink(missing_ok=True)


def run_shared(script_name, args):
    """Run a shared shell script and return its stdout."""
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


def main():
    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    prompt = hook_input.get('prompt', '')
    session_id = hook_input.get('turn_id', 'unknown')
    cwd = Path(hook_input.get('cwd', '.')).resolve()

    # For non-spex commands, clean up any stale marker and exit
    if not prompt.startswith('/spex:'):
        clear_marker(session_id)
        sys.exit(0)

    resolved = resolve_project_context(cwd)
    if resolved.get('error'):
        clear_marker(session_id)
        print(json.dumps({
            "systemMessage": f"<spex-error>{resolved['error']}. Refusing feature workflow dispatch.</spex-error>"
        }))
        sys.exit(0)
    project_dir = resolved['project_dir']
    if project_dir is None:
        clear_marker(session_id)
        print(json.dumps({
            "systemMessage": "<spex-error>Cannot resolve the repository for this Spex command.</spex-error>"
        }))
        sys.exit(0)

    # Delegate command validation to shared shell function
    shared_result = run_shared('context-hook.sh', [
        prompt, session_id, str(project_dir), str(PLUGIN_ROOT)
    ])

    if shared_result is None or shared_result == 'skip':
        clear_marker(session_id)
        sys.exit(0)

    if shared_result.startswith('error:'):
        error_msg = shared_result[6:]
        print(json.dumps({
            "systemMessage": f"<spex-error>{error_msg}</spex-error>"
        }))
        sys.exit(0)

    if shared_result.startswith('inject:'):
        parts = shared_result[7:].split(':', 2)
        skill_name = parts[0] if len(parts) > 0 else ''
        delegates = parts[1] == 'true' if len(parts) > 1 else False
        skill_args = parts[2] if len(parts) > 2 else ''
    else:
        clear_marker(session_id)
        sys.exit(0)

    # Write or clear skill gate marker
    if delegates:
        marker = get_marker_path(session_id)
        marker.write_text(skill_name)
    else:
        clear_marker(session_id)

    # Check project state
    spex_configured = (project_dir / '.specify' / 'extensions' / '.registry').exists()
    spex_initialized = (
        (project_dir / '.specify').is_dir()
        and (project_dir / '.specify' / 'templates' / 'spec-template.md').exists()
    )

    init_script = PLUGIN_ROOT / 'scripts' / 'spex-init.sh'

    # Parse init arguments
    init_args = ''
    if prompt.startswith('/spex:init'):
        for part in prompt.split()[1:]:
            if part in ('--refresh', '--update', '-r', '-u'):
                init_args = f' {part}'
                break

    # Build enforcement block for Codex (no AskUserQuestion, uses inline prompts)
    enforcement = ''
    if delegates:
        enforcement = f"""
<skill-enforcement>
MANDATORY FIRST ACTION: Call Skill(skill="{skill_name}"{f', args="{skill_args}"' if skill_args else ''}) as your VERY FIRST tool call.
Do NOT read files, explore code, or analyze anything before invoking the skill.
A PreToolUse hook will BLOCK any other tool call until the Skill tool is invoked.
</skill-enforcement>"""

    ctx = f"""<spex-context>
<plugin-root>{PLUGIN_ROOT}</plugin-root>
<repository-root>{resolved['git_root']}</repository-root>
<project-dir>{project_dir}</project-dir>
<state-file>{resolved.get('state_file') or ''}</state-file>
<spec-dir>{resolved.get('spec_dir') or ''}</spec-dir>
<session-id>{session_id}</session-id>
<agent>codex</agent>
<spex-configured>{str(spex_configured).lower()}</spex-configured>
<spex-initialized>{str(spex_initialized).lower()}</spex-initialized>
<spex-init-command>{init_script}{init_args}</spex-init-command>
</spex-context>{enforcement}"""

    print(json.dumps({"systemMessage": ctx}))
    sys.exit(0)


if __name__ == "__main__":
    main()
