#!/usr/bin/env python3
"""Combined PreToolUse hook for the spex plugin.

Consolidates all PreToolUse gates into a single script to reduce
process spawn overhead (1 process instead of 5-6 per tool call).

Gates (checked in order, all results collected):
1. Skill gate     - blocks non-Skill tools when /spex: command pending
2. Teams enforce  - blocks background Agent during implementation when teams active
3. Ship pipeline  - enforces stage ordering during ship workflow
4. Verification   - reminds about verification before git commit
5. Prose enforce  - requires prose skills before content file creation

Side effects (always run):
- Clear skill-pending marker when Skill tool is called
- Set prose-active marker when prose: skill is invoked
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

    # Prose: set session marker when a prose: skill is invoked
    if tool_name == 'Skill':
        skill = tool_input.get('skill', '')
        if skill.startswith('prose:'):
            marker_path('prose-active', session_id).write_text(skill)

    # Ship done cleanup: remove completed ship state file
    state_file = Path(cwd) / '.specify' / '.spex-ship-phase'
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

    traits_config = Path(cwd) / '.specify' / 'spex-traits.json'
    try:
        config = json.loads(traits_config.read_text())
        traits = config.get('traits', {})
        teams_enabled = (
            traits.get('teams', False)
            or traits.get('teams-vanilla', False)
            or traits.get('teams-spec', False)
        )
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
    8: "spex:verification-before-completion",
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
    8: "stamp",
}

SKILL_TO_STAGE = {v: k for k, v in STAGE_SKILLS.items()}


def check_ship_pipeline(tool_name, tool_input, cwd):
    """Enforce stage ordering during ship workflow.

    Returns (deny_reason, context_text) tuple. Both may be None.
    """
    state_file = Path(cwd) / '.specify' / '.spex-ship-phase'
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
            "\n  2. Code Review Guide -> REVIEWERS.md"
            "\n  3. Deep review: 5 agents (correctness, architecture, security, production, tests)"
            "\n  4. CodeRabbit CLI: coderabbit review --agent --type all (LOCAL, no PR needed)"
            "\n  5. Fix loop for Critical/Important findings"
            "\n  6. Deep Review Report -> REVIEWERS.md"
            "\nThe advance script WILL REJECT advancement if REVIEWERS.md lacks a Deep Review Report section."
        ),
        8: (
            "\n--- STAGE 8 REQUIREMENTS ---"
            "\nYou MUST invoke {Skill: spex:verification-before-completion} which runs:"
            "\n  1. Test suite execution"
            "\n  2. Spec compliance validation"
            "\n  3. Drift check"
            "\nDo NOT claim completion without running actual verification commands."
        ),
    }
    return briefs.get(stage_index, '')


# ---------------------------------------------------------------------------
# Gate 4: Verification reminder
# ---------------------------------------------------------------------------

def check_verification_gate(tool_name, tool_input, session_id, cwd):
    """Remind about verification before git commit in spex projects.

    Returns context string (non-blocking reminder), or None.
    """
    if tool_name != 'Bash':
        return None

    command = tool_input.get('command', '')
    if not re.search(r'\bgit\s+commit\b', command):
        return None

    if not (Path(cwd) / '.specify').is_dir():
        return None

    if marker_path('spex-verified', session_id).exists():
        return None

    # Allow spec-only commits without verification
    if _is_spec_only_commit(cwd):
        return None

    return (
        "spex stamp reminder: Final verification has not been run this session. "
        "Consider running /spex:stamp first, or confirm with the user that "
        "they want to proceed without the final gate."
    )


def _is_spec_only_commit(cwd):
    """Check if staged changes are spec/doc-only (no code to verify)."""
    import subprocess
    try:
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only'],
            capture_output=True, text=True, cwd=cwd, timeout=5,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return False
        for f in result.stdout.strip().splitlines():
            f = f.strip()
            if (f.startswith(('specs/', 'brainstorm/', 'docs/', '.specify/'))
                    or f.endswith('.md')):
                continue
            return False
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Gate 5: Prose enforcement
# ---------------------------------------------------------------------------

CONTENT_EXTENSIONS = {'.md', '.adoc', '.asciidoc'}

PROSE_EXCLUDED_NAMES = {
    'CLAUDE.md', 'AGENTS.md', 'GEMINI.md', 'MEMORY.md',
    'tasks.md', 'plan.md', 'spec.md',
}

PROSE_EXCLUDED_DIRS = {
    '.claude', '.specify', '.github', '.git',
    'commands', 'skills', 'overlays', 'scripts',
    'node_modules', 'memory',
    'specs', 'brainstorm',
}


def check_prose_enforce(tool_name, tool_input, session_id):
    """Block Write to content files unless a prose skill was invoked.

    Returns deny reason string, or None if gate passes.
    Only enforced when the prose plugin is installed.
    """
    # Only enforce on Write (new content creation), not Edit
    if tool_name != 'Write':
        return None

    file_path = tool_input.get('file_path', '')
    if not file_path or not _is_content_file(file_path):
        return None

    if not _is_prose_installed():
        return None

    if marker_path('prose-active', session_id).exists():
        return None

    return (
        "PROSE GATE: The prose plugin is installed. "
        "You MUST invoke a prose skill before creating content files. "
        "Use Skill(skill=\"prose:write\") to generate content with human voice, "
        "or Skill(skill=\"prose:check\") to validate existing content. "
        "This ensures content quality and prevents AI writing patterns."
    )


def _is_content_file(file_path):
    """Check if a file path is a content file that should go through prose."""
    p = Path(file_path)
    if p.suffix.lower() not in CONTENT_EXTENSIONS:
        return False
    if p.name in PROSE_EXCLUDED_NAMES:
        return False
    return not any(d in p.parts for d in PROSE_EXCLUDED_DIRS)


def _is_prose_installed():
    """Check if the prose plugin is installed via Claude Code plugin registry."""
    plugins_file = Path.home() / '.claude' / 'plugins' / 'installed_plugins.json'
    if not plugins_file.exists():
        return False
    try:
        data = json.loads(plugins_file.read_text())
        return any(k.startswith('prose@') for k in data.get('plugins', {}))
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

    verify_ctx = check_verification_gate(tool_name, tool_input, session_id, cwd)
    if verify_ctx:
        contexts.append(verify_ctx)

    prose_deny = check_prose_enforce(tool_name, tool_input, session_id)
    if prose_deny:
        denies.append(prose_deny)

    # --- Output ---
    if denies:
        deny(" | ".join(denies))
    elif contexts:
        context("\n".join(contexts))

    sys.exit(0)


if __name__ == "__main__":
    main()
