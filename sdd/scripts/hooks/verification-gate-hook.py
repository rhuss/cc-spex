#!/usr/bin/env python3
"""PreToolUse hook: blocks git commit when SDD verification hasn't been run.

When an SDD project is active (.specify/ directory exists), this hook intercepts
git commit commands and checks whether verification was completed this session.

The verification-before-completion skill writes a marker file on success.
If that marker is missing, the commit is blocked with a pointer to run verification.

The hook is non-intrusive:
- Only activates when .specify/ exists in the working directory
- Only intercepts Bash tool calls containing 'git commit'
- Allows commits when verification marker exists
- Allows the user to bypass with SKIP_SDD_VERIFY=1
"""
import json
import os
import re
import sys
from pathlib import Path


def get_marker_path(session_id):
    """Return the verification marker file path for a given session."""
    tmpdir = Path(os.environ.get('TMPDIR', '/tmp'))
    return tmpdir / f'.claude-sdd-verified-{session_id}'


def is_sdd_project(cwd):
    """Check if the working directory is an SDD-managed project."""
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
    # Environment bypass for when the user explicitly opts out
    if os.environ.get('SKIP_SDD_VERIFY') == '1':
        sys.exit(0)

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

    # Only activate for SDD-managed projects
    if not is_sdd_project(cwd):
        sys.exit(0)

    # Check if verification was completed this session
    marker = get_marker_path(session_id)
    if marker.exists():
        sys.exit(0)

    # Allow spec-only commits without verification (no code to check)
    if is_spec_only_commit(cwd):
        sys.exit(0)

    # Block the commit
    response = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "SDD VERIFICATION GATE: This is an SDD-managed project but "
                "verification has not been run this session. "
                "Before committing, run the code hygiene review and verification:\n\n"
                "  1. Run /sdd:verify to execute the verification workflow\n"
                "  2. Or ask the user if they want to skip verification\n\n"
                "If the user explicitly approves skipping verification, "
                "set SKIP_SDD_VERIFY=1 before the commit command."
            )
        }
    }
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
