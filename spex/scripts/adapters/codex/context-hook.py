#!/usr/bin/env python3
"""Codex CLI UserPromptSubmit hook adapter for spex.

Reads JSON from stdin per Codex's hook contract, validates /spex: commands
via the shared context-hook.sh, writes skill-pending markers, and injects
spex context into the Codex session.

Codex hook contract (stdin JSON):
  - session_id: string
  - cwd: string
  - model: string
  - permission_mode: string
  - prompt: string (user's input)

Codex hook response (stdout JSON):
  - For context injection: {"action": "context", "message": "<text>"}
  - For errors: {"action": "context", "message": "<error>"}
  - For pass-through: exit 0 with no output
"""
import json
import os
import subprocess
import sys
from pathlib import Path


SHARED_DIR = Path(__file__).parent.parent.parent / 'hooks' / 'shared'


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
    session_id = hook_input.get('session_id', 'unknown')
    cwd = Path(hook_input.get('cwd', '.'))

    # For non-spex commands, clean up any stale marker and exit
    if not prompt.startswith('/spex:'):
        clear_marker(session_id)
        sys.exit(0)

    # Resolve plugin root from script location:
    # scripts/adapters/codex/context-hook.py -> adapters/codex -> adapters -> scripts -> plugin_root
    plugin_root = Path(__file__).parent.parent.parent.parent

    # Delegate command validation to shared shell function
    shared_result = run_shared('context-hook.sh', [
        prompt, session_id, str(cwd), str(plugin_root)
    ])

    if shared_result is None or shared_result == 'skip':
        clear_marker(session_id)
        sys.exit(0)

    if shared_result.startswith('error:'):
        error_msg = shared_result[6:]
        print(json.dumps({
            "action": "context",
            "message": f"<spex-error>{error_msg}</spex-error>"
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
    spex_configured = (cwd / '.specify' / 'extensions' / '.registry').exists()
    spex_initialized = (
        (cwd / '.specify').is_dir()
        and (cwd / '.specify' / 'templates' / 'spec-template.md').exists()
    )

    init_script = plugin_root / 'scripts' / 'spex-init.sh'

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
<plugin-root>{plugin_root}</plugin-root>
<project-dir>{cwd}</project-dir>
<session-id>{session_id}</session-id>
<agent>codex</agent>
<spex-configured>{str(spex_configured).lower()}</spex-configured>
<spex-initialized>{str(spex_initialized).lower()}</spex-initialized>
<spex-init-command>{init_script}{init_args}</spex-init-command>
</spex-context>{enforcement}"""

    print(json.dumps({"action": "context", "message": ctx}))
    sys.exit(0)


if __name__ == "__main__":
    main()
