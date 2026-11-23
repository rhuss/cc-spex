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
"""
import json
import os
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

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
# Gate 1: Skill gate
# ---------------------------------------------------------------------------

def check_skill_gate(tool_name, session_id):
    """Block non-Skill tools when a /spex: command is pending.

    Returns deny reason string, or None if gate passes.
    Short-circuits: if this gate fires, no other gate matters because
    the model must invoke the skill before doing anything else.
    """
    marker = marker_path('spex-skill-pending', session_id)
    if not marker.exists():
        return None

    # ToolSearch must pass so the deferred Skill tool can be loaded
    if tool_name == 'ToolSearch':
        return None

    # Skill tool was already handled in side_effects (marker cleared)
    if tool_name == 'Skill':
        return None

    pending_skill = marker.read_text().strip()
    return (
        f"SKILL GATE: You MUST call Skill(skill=\"{pending_skill}\") "
        f"as your FIRST tool call. Do NOT read files, explore code, or "
        f"analyze anything before invoking the skill. The skill document "
        f"contains the process to follow. Call it NOW."
    )


# ---------------------------------------------------------------------------
# Gate 2: Teams enforcement
# ---------------------------------------------------------------------------

def check_teams_enforce(tool_name, tool_input, cwd):
    """Block background Agent during implementation when teams trait is active.

    Returns deny reason string, or None if gate passes.
    """
    if tool_name != 'Agent':
        return None

    if tool_input.get('subagent_type') or tool_input.get('team_name'):
        return None

    if not tool_input.get('run_in_background'):
        return None

    registry_file = Path(cwd) / '.specify' / 'extensions' / '.registry'
    try:
        registry = json.loads(registry_file.read_text())
        extensions = registry.get('extensions', {})
        teams_ext = extensions.get('spex-teams', {})
        teams_enabled = teams_ext.get('enabled', False)
    except Exception:
        return None

    if not teams_enabled:
        return None

    phase_file = Path(cwd) / '.specify' / '.spex-phase'
    try:
        phase = phase_file.read_text().strip()
    except FileNotFoundError:
        return None

    if phase != 'implement':
        return None

    return (
        "TEAMS ENFORCEMENT (implement phase): You are using Agent with "
        "run_in_background, which bypasses Agent Teams. Instead, delegate "
        "to {Skill: spex:teams-orchestrate} which provides: "
        "(1) worktree isolation for each teammate, "
        "(2) spec compliance review before merge."
    )


# ---------------------------------------------------------------------------
# Gate 3: Ship pipeline discipline
# ---------------------------------------------------------------------------

STAGE_SKILLS = {
    0: "speckit-specify",
    1: "speckit-clarify",
    2: "spex:review-spec",
    3: "speckit-plan",
    4: "speckit-tasks",
    5: "spex:review-plan",
    6: "speckit-implement",
    7: "spex:review-code",
}

STAGE_NAMES = {
    0: "specify",
    1: "clarify",
    2: "review-spec",
    3: "plan",
    4: "tasks",
    5: "review-plan",
    6: "implement",
    7: "review-code",
}

SKILL_TO_STAGE = {v: k for k, v in STAGE_SKILLS.items()}


def check_ship_pipeline(tool_name, tool_input, cwd):
    """Enforce stage ordering during ship workflow.

    Returns (deny_reason, context_text) tuple. Both may be None.
    """
    state_file = Path(cwd) / '.specify' / '.spex-state'
    if not state_file.exists():
        return None, None

    try:
        state = json.loads(state_file.read_text())
    except Exception:
        return None, None

    status = state.get('status', '')
    if status not in ('running', 'paused'):
        return None, None

    current_index = state.get('stage_index', -1)
    current_stage = state.get('stage', 'unknown')

    # For Skill tool calls, enforce stage ordering
    if tool_name == 'Skill':
        skill_name = tool_input.get('skill', '')
        if skill_name in SKILL_TO_STAGE:
            target_index = SKILL_TO_STAGE[skill_name]
            if target_index > current_index:
                skipped = [
                    f"  {i}. {STAGE_NAMES[i]} ({STAGE_SKILLS[i]})"
                    for i in range(current_index, target_index)
                ]
                return (
                    f"PIPELINE DISCIPLINE: You are trying to invoke "
                    f"{skill_name} (stage {target_index}: "
                    f"{STAGE_NAMES[target_index]}) but the pipeline is "
                    f"at stage {current_index}: {current_stage}. "
                    f"You MUST complete these stages first, in order:\n"
                    + "\n".join(skipped) + "\n\n"
                    f"Do NOT skip stages. Do NOT shortcut. "
                    f"Invoke {STAGE_SKILLS[current_index]} now."
                ), None
        return None, None

    # For non-Skill tools, inject a stage reminder with stage-specific briefs
    expected_skill = STAGE_SKILLS.get(current_index, 'unknown')
    brief = _stage_brief(current_index)
    ctx = (
        f"<ship-pipeline stage=\"{current_stage}\" index=\"{current_index}\" "
        f"expected-skill=\"{expected_skill}\">"
        f"Active ship pipeline at stage {current_index}/{8}: {current_stage}. "
        f"Next action: invoke {expected_skill}. "
        f"Do not explore or shortcut. Follow the pipeline."
        f"{brief}"
        f"</ship-pipeline>"
    )
    return None, ctx


# Stage-specific briefs for review stages (where context dilution is worst)
def _stage_brief(stage_index):
    briefs = {
        7: (
            "\n--- STAGE 7 REQUIREMENTS ---"
            "\nYou MUST invoke {Skill: spex:review-code} which runs:"
            "\n  1. Spec compliance check (compliance score)"
            "\n  2. Code Review Guide -> REVIEW-CODE.md"
            "\n  3. Deep review: 5 agents (correctness, architecture, security, production, tests)"
            "\n  4. CodeRabbit CLI: coderabbit review --agent --type all (LOCAL, no PR needed)"
            "\n  5. Fix loop for Critical/Important findings"
            "\n  6. Deep Review Report -> REVIEW-CODE.md"
            "\nThe advance script WILL REJECT advancement if REVIEW-CODE.md lacks a Deep Review Report section."
        ),
    }
    return briefs.get(stage_index, '')


# ---------------------------------------------------------------------------
# Gate 4: Verification reminder
# ---------------------------------------------------------------------------

def check_verification_gate(tool_name, tool_input, cwd, session_id='unknown'):
    """Remind about verification before git commit on a feature in progress.

    Only fires when the current branch belongs to a spex feature that has
    reached implementation (tasks.md exists), the commit carries code (not
    only specs/docs), no verification is recorded for the current code, and
    the reminder was not already shown for this feature in this session.
    Mirrors spex/scripts/hooks/shared/verify-gate.sh.

    Returns context string (non-blocking reminder), or None.
    """
    if tool_name != 'Bash':
        return None

    command = tool_input.get('command', '')
    if not re.search(r'\bgit\s+commit\b', command):
        return None

    if not (Path(cwd) / '.specify').is_dir():
        return None

    # Ad-hoc work (main, non-feature branches) or a feature before implement
    feature = _active_feature(cwd)
    if feature is None:
        return None

    # Spec/doc-only commits (and empty ones) have no code to verify
    if not _commit_has_code(cwd, command):
        return None

    # Once per session per feature
    marker = None
    if session_id and session_id != 'unknown':
        marker = marker_path('spex-verify-reminded', f'{session_id}-{feature}')
        if marker.exists():
            return None

    # Last, because it hashes the working tree
    if _is_verified(cwd):
        return None

    if marker is not None:
        try:
            marker.touch()
        except Exception:
            pass
    return verify_reminder(feature)


def verify_reminder(feature):
    return (
        f"spex verify reminder: Feature {feature} has code changes with no "
        "recorded verification. Consider running /speckit-spex-gates-verify or "
        "/speckit-spex-finish before committing, or confirm with the user that "
        "they want to proceed without the final gate. "
        "(Shown once per session for this feature.)"
    )


# Spec-kit feature branches: 056-name or 20260101-120000-name
FEATURE_BRANCH_RE = re.compile(r'^(\d{3,}|\d{8}-\d{6})-')
DOC_PREFIXES = ('specs/', 'brainstorm/', 'docs/', '.specify/')


def _git(cwd, *args):
    """Run git, return stdout or None on any failure."""
    import subprocess
    try:
        result = subprocess.run(
            ['git', *args], capture_output=True, text=True, cwd=cwd, timeout=5,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def _active_feature(cwd):
    """Name of the feature in progress on the current branch, or None.

    The feature dir comes from .spex-state (when it belongs to this branch),
    specs/<branch>, or a unique specs/<number>-* match. It counts as in
    progress once tasks.md exists, unless flow mode says implement has not
    run yet.
    """
    out = _git(cwd, 'rev-parse', '--abbrev-ref', 'HEAD')
    branch = out.strip() if out else ''
    if not branch or branch == 'HEAD':
        return None

    root = Path(cwd)
    state = {}
    state_file = root / '.specify' / '.spex-state'
    if state_file.is_file():
        try:
            state = json.loads(state_file.read_text())
        except Exception:
            state = {}
    state_branch = state.get('feature_branch')
    if state_branch in (None, '', branch):
        if state.get('mode') == 'flow' and state.get('implemented') is not True:
            return None

    candidates = []
    if state_branch == branch and state.get('spec_dir'):
        candidates.append(root / state['spec_dir'])
    candidates.append(root / 'specs' / branch)
    match = FEATURE_BRANCH_RE.match(branch)
    if match:
        prefixed = sorted((root / 'specs').glob(f'{match.group(1)}-*'))
        if len(prefixed) == 1:
            candidates.append(prefixed[0])

    for spec_dir in candidates:
        if (spec_dir / 'tasks.md').is_file():
            return spec_dir.name
    return None


def _commit_paths(cwd, command):
    """Paths the commit is likely to include.

    At PreToolUse time a `git add ... && git commit` or `git commit -a` has not
    staged anything yet, so those use all working tree changes instead of the
    index.
    """
    stages_itself = (
        re.search(r'\bgit\s+add\b', command)
        or re.search(r'\bgit\s+commit\b[^;&|]*\s(-[a-zA-Z]*a[a-zA-Z]*|--all)\b', command)
    )
    if not stages_itself:
        out = _git(cwd, 'diff', '--cached', '--name-only')
        return None if out is None else [l.strip() for l in out.splitlines() if l.strip()]

    out = _git(cwd, 'status', '--porcelain', '-uall')
    if out is None:
        return None
    paths = []
    for line in out.splitlines():
        path = line[3:]
        if ' -> ' in path:
            path = path.split(' -> ', 1)[1]
        path = path.strip().strip('"')
        if path:
            paths.append(path)
    return paths


def _commit_has_code(cwd, command):
    """True when the commit carries anything besides specs and docs.

    Git errors count as code (reminder fires); an empty change set does not.
    """
    paths = _commit_paths(cwd, command)
    if paths is None:
        return True
    return any(
        not (p.startswith(DOC_PREFIXES) or p.endswith('.md')) for p in paths
    )


def _verify_record_script(cwd):
    """Locate spex-verify-record.sh (plugin copy first, then project install)."""
    candidates = [
        Path(__file__).resolve().parent.parent / 'spex-verify-record.sh',
        Path(cwd) / '.specify' / 'extensions' / 'spex-gates' / 'scripts' / 'spex-verify-record.sh',
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def _is_verified(cwd):
    """True when the shared verification record matches the current code.

    Missing script, errors, and timeouts count as not verified (reminder fires).
    """
    import subprocess
    script = _verify_record_script(cwd)
    if script is None:
        return False
    try:
        # Own process group, so a timeout also kills the fingerprint helpers
        # (python, git add) instead of leaving them running.
        proc = subprocess.Popen(
            ['sh', str(script), 'check'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            cwd=cwd, start_new_session=True,
        )
    except Exception:
        return False
    try:
        return proc.wait(timeout=5) == 0
    except subprocess.TimeoutExpired:
        # SIGTERM first so the fingerprint helper can remove its temp index,
        # then SIGKILL whatever is left in the group.
        import signal
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except Exception:
            proc.terminate()
        # Wait for the whole group to drain, not just the leader (sh exits
        # at once on SIGTERM while python is still removing its temp dir).
        import time
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            try:
                os.killpg(proc.pid, 0)
            except Exception:
                break
            try:
                proc.poll()
            except Exception:
                pass
            time.sleep(0.05)
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        try:
            proc.wait(timeout=1)
        except Exception:
            pass
        return False
    except Exception:
        return False


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
    skill_deny = check_skill_gate(tool_name, session_id)
    if skill_deny:
        deny(skill_deny)

    # --- Gates 2-5: collected ---
    denies = []
    contexts = []

    teams_deny = check_teams_enforce(tool_name, tool_input, cwd)
    if teams_deny:
        denies.append(teams_deny)

    ship_deny, ship_ctx = check_ship_pipeline(tool_name, tool_input, cwd)
    if ship_deny:
        denies.append(ship_deny)
    if ship_ctx:
        contexts.append(ship_ctx)

    verify_ctx = check_verification_gate(tool_name, tool_input, cwd, session_id)
    if verify_ctx:
        contexts.append(verify_ctx)

    # --- Output ---
    if denies:
        deny(" | ".join(denies))
    elif contexts:
        context("\n".join(contexts))

    sys.exit(0)


if __name__ == "__main__":
    main()
