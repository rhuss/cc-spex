<!-- OpenCode Skill Preamble
     Include this snippet at the top of skills when running on OpenCode.
     It replaces the context injection that context-hook.py provides on
     Claude Code and Codex (since OpenCode has no UserPromptSubmit hook). -->

## OpenCode Context (Auto-Injected)

Before executing this skill, perform these validation steps:

### 1. Command Validation

Verify the invoked command is a known spex or speckit command:

**spex commands**: brainstorm, constitution, evolve, help, init,
review-code, review-plan, review-spec, ship, extensions,
deep-review, stamp, verify, worktree

**speckit commands**: /speckit-specify, /speckit-plan, /speckit-tasks, /speckit-implement

If the command is not in these lists, stop and report:
"ERROR: This command does not exist. Run /spex:help for valid commands."

### 2. Context Discovery

Locate the spex plugin root and project state:

```bash
# Find plugin root (parent of scripts/ directory)
PLUGIN_ROOT=$(find . -path "*/spex/scripts/spex-init.sh" -exec dirname {} \; 2>/dev/null | head -1 | xargs dirname)

# Check project state
SPEX_CONFIGURED=$(test -f .specify/extensions/.registry && echo true || echo false)
SPEX_INITIALIZED=$(test -d .specify && test -f .specify/templates/spec-template.md && echo true || echo false)
```

### 3. Interactive Prompts

When this skill instructs you to present options to the user:
- Use the **question** tool (NOT AskUserQuestion, which does not exist on OpenCode)
- Structure choices with clear labels
- Wait for the user's response before proceeding

### 4. Parallel Work

When this skill references Agent Teams or parallel dispatch:
- Use the **Task** tool for parallel execution
- Each task should be independent
- Coordinate completion before proceeding
