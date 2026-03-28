#!/usr/bin/env python3
"""PreToolUse hook: reminds about spex verification before git commit.

When a spex project is active (.specify/ directory exists), this hook intercepts
git commit commands and checks whether verification was completed this session.

The verification-before-completion skill writes a marker file on success.
If that marker is missing, a reminder is injected asking the model to confirm
with the user before proceeding. The commit is NOT blocked.

The hook is non-intrusive:
- Only activates when .specify/ exists in the working directory
- Only intercepts Bash tool calls containing 'git commit'
- Allows commits when verification marker exists
- Reminds (not blocks) when verification hasn't been run
"""
import json
import os
import re
import sys
from pathlib import Path


def get_marker_path(session_id):
    """Return the verification marker file path for a given session."""
    tmpdir = Path(os.environ.get('TMPDIR', '/tmp'))
    return tmpdir / f'.claude-spex-verified-{session_id}'


def is_spex_project(cwd):
    """Check if the working directory is a spex-managed project."""
    return (Path(cwd) / '.specify').is_dir()


def is_git_commit(tool_input):
    """Check if the Bash command is a git commit."""
    command = tool_input.get('command', '')
    return bool(re.search(r'\bgit\s+commit\b', command))


def is_spec_only_commit(cwd):
    """Check if staged changes are spec/doc-only (no code to verify).

    Returns True when all staged files are under specs/, brainstorm/,
    or are markdown/documentation files that don't need code verification.
    """
    import subprocess
    try:
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only'],
            capture_output=True, text=True, cwd=cwd, timeout=5
        )
        if result.returncode != 0 or not result.stdout.strip():
            return False
        for f in result.stdout.strip().splitlines():
            f = f.strip()
            # Allow spec, brainstorm, doc paths and standalone markdown files
            if (f.startswith('specs/') or f.startswith('brainstorm/')
                    or f.startswith('docs/') or f.startswith('.specify/')
                    or f.endswith('.md')):
                continue
            # Any other file means this is a code commit
            return False
        return True
    except Exception:
        return False


def read_hook_input():
    """Read and parse hook input JSON from stdin."""
    try:
        return json.loads(sys.stdin.read())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(0)  # Non-blocking error: let tool proceed


def main():
    hook_input = read_hook_input()

    tool_name = hook_input.get('tool_name', '')
    tool_input = hook_input.get('tool_input', {})
    session_id = hook_input.get('session_id', 'unknown')
    cwd = hook_input.get('cwd', '.')

    # Only intercept Bash tool calls
    if tool_name != 'Bash':
        sys.exit(0)

    # Only check git commit commands
    if not is_git_commit(tool_input):
        sys.exit(0)

    # Only activate for spex-managed projects
    if not is_spex_project(cwd):
        sys.exit(0)

    # Check if verification was completed this session
    marker = get_marker_path(session_id)
    if marker.exists():
        sys.exit(0)

    # Allow spec-only commits without verification (no code to check)
    if is_spec_only_commit(cwd):
        sys.exit(0)

    # Remind about verification (non-blocking)
    response = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": (
                "spex verification reminder: Verification has not been run this session. "
                "Consider running /spex:verify first, or confirm with the user that "
                "they want to proceed without verification."
            )
        }
    }
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
