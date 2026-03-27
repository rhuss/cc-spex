#!/usr/bin/env python3
"""Hook script for UserPromptSubmit event.
Injects SDD plugin context as system reminder when sdd commands detected.
Also writes a marker file for the PreToolUse skill gate hook to enforce
that the Skill tool is called before any other tool.
"""
import json
import os
import sys
from pathlib import Path


def get_marker_path(session_id):
    """Return the skill gate marker file path for a given session."""
    tmpdir = Path(os.environ.get('TMPDIR', '/tmp'))
    return tmpdir / f'.claude-sdd-skill-pending-{session_id}'


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


def main():
    hook_input = read_hook_input()

    prompt = hook_input.get('prompt', '')
    session_id = hook_input.get('session_id', 'unknown')
    cwd = Path(hook_input.get('cwd', '.'))

    # For non-SDD commands, clean up any stale marker and exit
    if not prompt.startswith('/sdd:'):
        clear_marker(session_id)
        sys.exit(0)

    # Resolve plugin root from script location:
    # scripts/hooks/context-hook.py -> scripts/hooks -> scripts -> plugin_root
    plugin_root = Path(__file__).parent.parent.parent

    # Resolve script paths
    init_script = plugin_root / 'scripts' / 'sdd-init.sh'
    traits_script = plugin_root / 'scripts' / 'sdd-traits.sh'
    # Check if SDD traits are configured
    sdd_configured = (cwd / '.specify' / 'sdd-traits.json').exists()

    # Check if project is fully initialized (mirrors check_ready() in sdd-init.sh)
    sdd_initialized = (
        (cwd / '.specify').is_dir()
        and (cwd / '.specify' / 'templates' / 'spec-template.md').exists()
        and any((cwd / '.claude' / 'commands').glob('speckit.*'))
    ) if (cwd / '.claude' / 'commands').is_dir() else False

    # Extract the skill name from the command (e.g., "/sdd:brainstorm foo" -> "sdd:brainstorm")
    skill_name = prompt.split()[0].lstrip('/')

    # Guard against hallucinated commands (e.g., /sdd:specify, /sdd:plan)
    KNOWN_SDD_COMMANDS = {
        'brainstorm', 'constitution', 'evolve', 'help', 'init',
        'review-code', 'review-plan', 'review-spec', 'traits', 'verify', 'worktree',
    }
    COMMAND_CORRECTIONS = {
        'specify': '/speckit.specify',
        'plan': '/speckit.plan',
        'tasks': '/speckit.tasks',
        'implement': '/speckit.implement',
    }
    command_short_check = skill_name.split(':', 1)[1] if ':' in skill_name else skill_name
    if command_short_check not in KNOWN_SDD_COMMANDS:
        suggestion = COMMAND_CORRECTIONS.get(
            command_short_check,
            'Run /sdd:help for valid commands'
        )
        response = {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": (
                    f"<sdd-error>"
                    f"ERROR: /{skill_name} does not exist. "
                    f"Did you mean {suggestion}? "
                    f"SDD commands: brainstorm, review-*, evolve, traits, init, help, constitution. "
                    f"Spec-kit commands: /speckit.specify, /speckit.plan, /speckit.tasks, /speckit.implement."
                    f"</sdd-error>"
                )
            }
        }
        print(json.dumps(response))
        sys.exit(0)

    # Only write the skill gate marker if the command delegates to a Skill.
    # Commands containing "{Skill: sdd:...}" need the gate to ensure the Skill
    # tool is called first. Direct workflow commands (init, traits, help, etc.)
    # already provide instructions inline and should NOT be gated.
    command_short = skill_name.split(':', 1)[1] if ':' in skill_name else skill_name
    command_file = plugin_root / 'commands' / f'{command_short}.md'
    delegates_to_skill = False
    if command_file.exists():
        try:
            content = command_file.read_text()
            delegates_to_skill = '{Skill:' in content
        except Exception:
            pass
    else:
        # No command file means it's skill-only; gate it
        delegates_to_skill = True

    if delegates_to_skill:
        marker = get_marker_path(session_id)
        marker.write_text(skill_name)
    else:
        clear_marker(session_id)

    # Parse init arguments (--refresh, --update)
    init_args = ''
    if prompt.startswith('/sdd:init'):
        parts = prompt.split()
        for part in parts[1:]:
            if part in ('--refresh', '--update', '-r', '-u'):
                init_args = f' {part}'
                break

    # Extract arguments after the command name for skill invocation
    prompt_parts = prompt.split(maxsplit=1)
    skill_args = prompt_parts[1] if len(prompt_parts) > 1 else ''

    # Build skill enforcement block only for skill-delegating commands
    enforcement = ''
    if delegates_to_skill:
        enforcement = f"""
<skill-enforcement>
MANDATORY FIRST ACTION: Call Skill(skill="{skill_name}"{f', args="{skill_args}"' if skill_args else ''}) as your VERY FIRST tool call.
Do NOT read files, explore code, or analyze anything before invoking the skill.
A PreToolUse hook will BLOCK any other tool call until the Skill tool is invoked.
</skill-enforcement>"""

    context = f"""<sdd-context>
<plugin-root>{plugin_root}</plugin-root>
<project-dir>{cwd}</project-dir>
<session-id>{session_id}</session-id>
<sdd-configured>{str(sdd_configured).lower()}</sdd-configured>
<sdd-initialized>{str(sdd_initialized).lower()}</sdd-initialized>
<sdd-init-command>{init_script}{init_args}</sdd-init-command>
<sdd-traits-command>{traits_script}</sdd-traits-command>
</sdd-context>{enforcement}"""

    response = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": context
        }
    }
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
