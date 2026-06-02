---
name: init
description: Initialize or update the project using the `specify` CLI (--refresh for templates, --update to upgrade CLI, --clear to reset status line). Do NOT search for speckit or spec-kit binaries.
---

You MUST complete ALL steps below. Do not stop after Step 1.

## Step 1: Run init script

Run the command from `<spex-init-command>` in the `<spex-context>` system reminder. This is your first and only Bash call. Do not run anything else before it.

- If output contains `NEED_INSTALL`: show output, STOP.
- If output contains `ERROR`: show error, STOP.
- If the command was run with `--refresh` or `--update` and output contains `RESTART_REQUIRED`: **SKIP Steps 2 and 3.** Templates and extensions were refreshed but the existing configuration (enabled extensions, auto-commit, permissions) is preserved. Go directly to Step 4 and report that the refresh completed. Tell the user to restart Claude Code.
- If output contains `READY` or `RESTART_REQUIRED`: **do not summarize yet**, go to Step 2.

## Step 2: Ask about extensions, auto-commit, and permissions

You MUST ask all 4 questions below in a SINGLE AskUserQuestion call. Do NOT split, merge, reword, or reorder them. Pass them exactly as specified:

1. (`multiSelect: true`, header: "Quality"): "Which quality & review extensions do you want to enable?"
   - "spex-gates": "Quality gates on speckit commands (review-spec, review-code, verification)"
   - "spex-deep-review": "Multi-perspective code review with autonomous fix loop (5 agents)"
   - "spex-teams": "Parallel implementation with spec guardian review via Agent Teams (experimental, requires: spex-gates)"

2. (`multiSelect: true`, header: "Workflow"): "Which workflow extensions do you want to enable?"
   - "spex-worktrees": "Git worktree isolation after speckit-specify (creates sibling worktree)"
   - "spex-collab": "Phase-split collaboration with REVIEWERS.md for team PRs"

3. (`multiSelect: true`, header: "Auto-commit"): "When should spec-kit auto-commit? Select all that apply."
   - "After spec": "Auto-commit after specify completes"
   - "After plan+tasks": "Auto-commit after plan and tasks complete"
   - "After implement": "Auto-commit after implement completes"

4. (`multiSelect: false`, header: "Permissions"): "How should spex commands handle permission prompts?"
   - "Standard (Recommended)": "Auto-approve spex plugin scripts (spex-init.sh, specify CLI)"
   - "YOLO": "Auto-approve everything + enable auto mode for unattended workflows (requires Max/Team/Enterprise)"
   - "None": "Confirm every spex command before execution"

Then apply the selections:

**Dependency resolution**: If the user selected `spex-teams` but NOT `spex-gates`, auto-enable `spex-gates` and warn:
> **Note:** spex-gates was auto-enabled because spex-teams depends on it for spec guardian review.

**Extensions**: Extensions are already installed and enabled by the init script. For any extensions the user did NOT select (after dependency resolution), disable them:

```bash
# Disable unselected extensions (ignore errors if already in desired state)
specify extension disable <extension-name> 2>/dev/null || true
```

If the user selected all extensions, no action needed (all are enabled by default after init).

**Auto-commit**: Update `.specify/extensions/git/git-config.yml` based on the user's selections. Only modify if the file exists (git extension is installed by spec-kit core). Enable each selected option with `yq`. If the user selected nothing, no changes needed (default is already false).

- **After spec**: `yq -i '.auto_commit.after_specify.enabled = true' .specify/extensions/git/git-config.yml`
- **After plan+tasks**: `yq -i '.auto_commit.after_plan.enabled = true | .auto_commit.after_tasks.enabled = true' .specify/extensions/git/git-config.yml`
- **After implement**: `yq -i '.auto_commit.after_implement.enabled = true' .specify/extensions/git/git-config.yml`

Combine all selected options into a single `yq` call when multiple are chosen.

**Permissions**: The `specify` CLI does not manage permissions. Instead, write permission allowlists directly to `.claude/settings.json` based on the user's choice. Use the EXACT allow arrays below (copy verbatim, do not modify or rephrase the permission strings):

- **Standard**:
  ```json
  {"permissions": {"allow": ["Skill", "Bash(specify *)", "Bash(*spex-init.sh*)", "Bash(*spex-ship-statusline.sh*)"]}}
  ```
- **YOLO**:
  ```json
  {"permissions": {"defaultMode": "auto", "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)", "Skill", "mcp__*__*", "Bash(specify *)", "Bash(*spex-init.sh*)", "Bash(*spex-ship-statusline.sh*)"]}}
  ```
  Note: `defaultMode: "auto"` enables the classifier-based auto mode that replaces `bypassPermissions`. Auto mode auto-approves routine operations (file edits, skill invocations, local commands) while blocking genuinely dangerous actions. It requires Max, Team, Enterprise, or API plan. The broad `allow` rules serve as fallback for environments where auto mode is unavailable.
- **None**: Do not modify permissions (leave defaults)

IMPORTANT: The MCP permission rule is `mcp__*__*` (three parts separated by double underscores, NO parentheses). `mcp__*(*)` is INVALID and will cause a settings parse error.

Use the existing project `.claude/settings.json` (create if missing). Merge permission entries without overwriting existing settings.

## Step 3: Detect companion plugins and seed memory

Scan the available skills list from the system reminder for companion plugins:

### 3a: Superpowers plugin

Check for any of these upstream superpowers skills: `test-driven-development`, `systematic-debugging`, `brainstorming`, `writing-plans`. These are skills from [obra/superpowers](https://github.com/obra/superpowers) that complement spex but are NOT bundled with it.

- If **found**: record "superpowers" as a detected companion plugin in the Step 4 report. No further action needed.
- If **not found** and the user enabled the `spex-gates` extension in Step 2: show a recommendation in the Step 4 report (see below). Do NOT block init or make it an error.

## Step 4: Report

Summarize: extensions enabled, auto-commit level, permission level, and companion plugins detected. If Step 1 said RESTART_REQUIRED or Step 2 permissions said CHANGED, tell user to restart Claude Code.

If superpowers companion plugin was NOT detected (Step 3b), append this to the report:

> **Recommended companion:** The [Superpowers](https://github.com/obra/superpowers) plugin by Jesse Vincent adds TDD discipline and systematic debugging skills that complement spex's spec-first workflow. spex absorbs superpowers' quality gates and anti-rationalization patterns, but does not bundle these standalone skills:
> - **test-driven-development**: strict RED-GREEN-REFACTOR, no production code without failing test
> - **systematic-debugging**: 4-phase root cause analysis with defense-in-depth
>
> Install with: `/plugin install superpowers@claude-plugins-official` (or `claude plugin install superpowers@claude-plugins-official` from the terminal)
