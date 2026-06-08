#!/usr/bin/env python3
"""Hook script for UserPromptSubmit event.
Injects spex plugin context as system reminder when spex commands detected.
Also writes a marker file for the PreToolUse skill gate hook to enforce
that the Skill tool is called before any other tool.

This hook delegates command validation to the shared context-hook.sh,
making the validation logic reusable across agent adapters.
"""
import json
import os
import subprocess
import sys
from pathlib import Path


SHARED_DIR = Path(__file__).parent / 'shared'


def get_marker_path(session_id):
    """Return the skill gate marker file path for a given session."""
    tmpdir = Path(os.environ.get('TMPDIR', '/tmp'))
    return tmpdir / f'.claude-spex-skill-pending-{session_id}'


def clear_marker(session_id):
    """Remove any stale skill gate marker for this session."""
    marker = get_marker_path(session_id)
    marker.unlink(missing_ok=True)


def read_hook_input():
    """Read and parse hook input JSON from stdin."""
    try:
        return json.loads(sys.stdin.read())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(2)


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
    hook_input = read_hook_input()

    prompt = hook_input.get('prompt', '')
    session_id = hook_input.get('session_id', 'unknown')
    cwd = Path(hook_input.get('cwd', '.'))

    # For non-spex commands, clean up any stale marker and exit
    if not prompt.startswith('/spex:'):
        clear_marker(session_id)
        sys.exit(0)

    # Resolve plugin root from script location:
    # scripts/hooks/context-hook.py -> scripts/hooks -> scripts -> plugin_root
    plugin_root = Path(__file__).parent.parent.parent

    # Delegate command validation to shared shell function
    shared_result = run_shared('context-hook.sh', [
        prompt, session_id, str(cwd), str(plugin_root)
    ])

    # Fallback: if shared script fails, use inline validation
    if shared_result is None:
        shared_result = _inline_validate(prompt, plugin_root)

    if shared_result == 'skip':
        clear_marker(session_id)
        sys.exit(0)

    if shared_result.startswith('error:'):
        error_msg = shared_result[6:]
        response = {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": f"<spex-error>{error_msg}</spex-error>"
            }
        }
        print(json.dumps(response))
        sys.exit(0)

    if shared_result.startswith('inject:'):
        parts = shared_result[7:].split(':', 2)
        skill_name = parts[0] if len(parts) > 0 else ''
        delegates = parts[1] == 'true' if len(parts) > 1 else False
        skill_args = parts[2] if len(parts) > 2 else ''
    else:
        # Unexpected result, fail open
        clear_marker(session_id)
        sys.exit(0)

    # Write or clear skill gate marker
    if delegates:
        marker = get_marker_path(session_id)
        marker.write_text(skill_name)
    else:
        clear_marker(session_id)

    # Check if spex extensions are configured (via registry)
    spex_configured = (cwd / '.specify' / 'extensions' / '.registry').exists()

    # Check if project is fully initialized
    spex_initialized = (
        (cwd / '.specify').is_dir()
        and (cwd / '.specify' / 'templates' / 'spec-template.md').exists()
        and any((cwd / '.claude' / 'commands').glob('speckit-*'))
    ) if (cwd / '.claude' / 'commands').is_dir() else False

    # Resolve script paths
    init_script = plugin_root / 'scripts' / 'spex-init.sh'

    # Parse init arguments (--refresh, --update)
    init_args = ''
    if prompt.startswith('/spex:init'):
        parts = prompt.split()
        for part in parts[1:]:
            if part in ('--refresh', '--update', '-r', '-u'):
                init_args = f' {part}'
                break

    # Build skill enforcement block only for skill-delegating commands
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
<spex-configured>{str(spex_configured).lower()}</spex-configured>
<spex-initialized>{str(spex_initialized).lower()}</spex-initialized>
<spex-init-command>{init_script}{init_args}</spex-init-command>
</spex-context>{enforcement}"""

    response = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": ctx
        }
    }
    print(json.dumps(response))
    sys.exit(0)


def _inline_validate(prompt, plugin_root):
    """Fallback inline validation when shared script is unavailable."""
    skill_name = prompt.split()[0].lstrip('/')
    command_short = skill_name.split(':', 1)[1] if ':' in skill_name else skill_name

    KNOWN_SPEX_COMMANDS = {
        'brainstorm', 'constitution', 'evolve', 'help', 'init',
        'review-code', 'review-plan', 'review-spec', 'ship', 'extensions',
        'deep-review', 'stamp', 'verify', 'worktree',
    }
    COMMAND_CORRECTIONS = {
        'specify': '/speckit-specify',
        'plan': '/speckit-plan',
        'tasks': '/speckit-tasks',
        'implement': '/speckit-implement',
    }

    if command_short not in KNOWN_SPEX_COMMANDS:
        suggestion = COMMAND_CORRECTIONS.get(
            command_short,
            'Run /spex:help for valid commands'
        )
        return (
            f"error:ERROR: /{skill_name} does not exist. "
            f"Did you mean {suggestion}? "
            f"spex commands: brainstorm, review-*, evolve, extensions, init, help, constitution. "
            f"Spec-kit commands: /speckit-specify, /speckit-plan, /speckit-tasks, /speckit-implement."
        )

    # Determine delegation
    STANDALONE_SKILLS = {'init'}
    if command_short in STANDALONE_SKILLS:
        delegates = False
    else:
        command_file = None
        for ext_dir in (plugin_root / 'extensions').iterdir():
            if ext_dir.is_dir():
                for cmd_file in (ext_dir / 'commands').glob('*.md'):
                    if cmd_file.stem.endswith(f'.{command_short}'):
                        command_file = cmd_file
                        break
                if command_file:
                    break
        delegates = False
        if command_file and command_file.exists():
            try:
                content = command_file.read_text()
                delegates = '{Skill:' in content
            except Exception:
                pass
        else:
            delegates = True

    prompt_parts = prompt.split(maxsplit=1)
    skill_args = prompt_parts[1] if len(prompt_parts) > 1 else ''

    return f"inject:{skill_name}:{'true' if delegates else 'false'}:{skill_args}"


if __name__ == "__main__":
    main()
