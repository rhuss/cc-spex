---
name: init
description: Initialize or update the project using the `specify` CLI (--refresh for templates, --update to upgrade CLI, --clear to reset status line). Do NOT search for speckit or spec-kit binaries.
---

You MUST complete ALL steps below. Do not stop after Step 1.

## Step 1: Run init script

Run the command from `<spex-init-command>` in the `<spex-context>` system reminder. This is your first and only Bash call. Do not run anything else before it.

- If output contains `NEED_INSTALL`: show output, STOP.
- If output contains `ERROR`: show error, STOP.
- If output contains `BEADS_MIGRATION_NEEDED`: go to Step 1b.
- If output contains `READY` or `RESTART_REQUIRED`: **do not summarize yet**, go to Step 2.

## Step 1b: Beads Migration (only if BEADS_MIGRATION_NEEDED)

The beads trait has been removed from spex. Show the user this message and ask for confirmation:

Use `AskUserQuestion` (`multiSelect: false`, header: "Beads Migration"):

**Message**: "The beads trait has been removed from spex. Task state is now tracked directly in tasks.md checkboxes, which is simpler and equally persistent via git. The beads integration added unnecessary complexity (Dolt database, bidirectional sync, fragile bd CLI piping) without meaningful benefit."

**Options**:
- "Migrate (recommended)": "Sync closed bd issues to tasks.md checkboxes, strip (bd-xxx) markers, disable beads trait"
- "Skip": "Leave tasks.md as-is (bd markers will remain but beads trait becomes inactive)"

If "Migrate": run the beads migration via Bash:
```bash
# Source the init script to get the migration function
INIT_SCRIPT="<value from spex-init-command>"
SCRIPT_DIR=$(dirname "$INIT_SCRIPT")
bash -c "source '$INIT_SCRIPT' && do_beads_migration"
```

Then continue to Step 2.

## Step 2: Ask about extensions and permissions

You MUST ask the user these two questions using AskUserQuestion before doing anything else:

1. (`multiSelect: true`, header: "Extensions"): "Which spex extensions do you want to enable?"
   - "spex-gates": "Quality gates on speckit commands (review-spec, review-code, verification)"
   - "spex-deep-review": "Multi-perspective code review with autonomous fix loop (5 agents: correctness, architecture, security, production-readiness, test-quality)"
   - "spex-teams": "Parallel implementation with spec guardian review via Claude Code Agent Teams (experimental, requires: spex-gates)"
   - "spex-worktrees": "Git worktree isolation after speckit-specify (creates sibling worktree, restores main)"

2. (`multiSelect: false`, header: "Permissions"): "How should spex commands handle permission prompts?"
   - "Standard (Recommended)": "Auto-approve spex plugin scripts (spex-init.sh, specify CLI)"
   - "YOLO": "Auto-approve everything: Bash, Read, Edit, Write, MCP, specify CLI"
   - "None": "Confirm every spex command before execution"

Then apply the selections:

**Extensions**: Extensions are already installed and enabled by the init script. For any extensions the user did NOT select, disable them:

```bash
# Disable unselected extensions (ignore errors if already in desired state)
specify extension disable <extension-name> 2>/dev/null || true
```

If the user selected all extensions, no action needed (all are enabled by default after init).

**Permissions**: The `specify` CLI does not manage permissions. Instead, write permission allowlists directly to `.claude/settings.json` based on the user's choice:

- **Standard**: Add allowlists for spex plugin scripts (`spex-init.sh`, `spex-ship-statusline.sh`) and the `specify` CLI
- **YOLO**: Add broad allowlists for Bash, Read, Edit, Write, MCP tools, and the `specify` CLI
- **None**: Do not modify permissions (leave defaults)

Use the existing project `.claude/settings.json` (create if missing). Merge permission entries without overwriting existing settings.

## Step 3: Detect companion plugins and seed memory

Scan the available skills list from the system reminder for companion plugins:

### 3a: Prose plugin

Check for the `prose:check` skill. If found, write a reminder to auto-memory so future sessions know to use it:

Write to the auto-memory `MEMORY.md` (create the file if it doesn't exist, or append a new section if it does). Only add this section if it isn't already present:

```markdown
## Content Creation: Always Use Prose Plugin

- When creating prose content (discussions, blog posts, PR descriptions, documentation), run `/prose:check` and `/prose:rewrite` before finalizing
- Applies to GitHub discussions, issue bodies, long-form text, anything beyond short inline responses
```

If the prose plugin is not detected, skip this step silently.

### 3b: Superpowers plugin

Check for any of these upstream superpowers skills: `test-driven-development`, `systematic-debugging`, `brainstorming`, `writing-plans`. These are skills from [obra/superpowers](https://github.com/obra/superpowers) that complement spex but are NOT bundled with it.

- If **found**: record "superpowers" as a detected companion plugin in the Step 4 report. No further action needed.
- If **not found** and the user enabled the `spex-gates` extension in Step 2: show a recommendation in the Step 4 report (see below). Do NOT block init or make it an error.

## Step 4: Report

Summarize: extensions enabled, permission level, and companion plugins detected. If Step 1 said RESTART_REQUIRED or Step 2 permissions said CHANGED, tell user to restart Claude Code.

If superpowers companion plugin was NOT detected (Step 3b), append this to the report:

> **Recommended companion:** The [Superpowers](https://github.com/obra/superpowers) plugin by Jesse Vincent adds TDD discipline and systematic debugging skills that complement spex's spec-first workflow. spex absorbs superpowers' quality gates and anti-rationalization patterns, but does not bundle these standalone skills:
> - **test-driven-development**: strict RED-GREEN-REFACTOR, no production code without failing test
> - **systematic-debugging**: 4-phase root cause analysis with defense-in-depth
>
> Install with: `/plugin install superpowers@claude-plugins-official` (or `claude plugin install superpowers@claude-plugins-official` from the terminal)
