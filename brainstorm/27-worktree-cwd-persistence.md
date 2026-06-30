# Brainstorm: Worktree CWD Persistence

**Date:** 2026-06-30
**Status:** active

## Problem Framing

When the ship pipeline runs in a git worktree (created by the `spex-worktrees` extension), the shell CWD resets to the main repo directory after subagents return. This happens because worktrees are currently created as sibling directories (e.g., `cc-spex@031-feature`) outside the project boundary. Claude Code only persists CWD changes within the project directory or explicitly added directories. When `cd` lands outside the project boundary, the harness resets CWD to the project root.

This causes the post-pipeline completion prompt to run from the main repo instead of the worktree, and commands that depend on CWD (like `git branch --show-current`, state file reads, and `advance`) can operate on the wrong directory.

## Approaches Considered

### A: `--add-dir` at session start

Start Claude with the worktree path added: `claude --add-dir /path/to/worktree`. Extends the allowed CWD boundary so `cd` persists.

- Pros: No code changes needed, works immediately
- Cons: Requires knowing the worktree path before starting the session. Doesn't work for ship pipelines that create worktrees mid-session.

### B: Move worktrees inside `.claude/worktrees/` (Chosen)

Change the default `base_path` in `worktree-config.yml` from `..` (sibling) to `.claude/worktrees` (inside project). Since `.claude/` is already gitignored, worktrees inside it are invisible to git. Claude Code's `EnterWorktree` tool natively uses `.claude/worktrees/`, so this aligns with the platform's own convention.

- Pros: CWD persists because worktree is inside the project boundary. `EnterWorktree` works natively. No manual `--add-dir` needed. Aligns with Claude Code's standard worktree location.
- Cons: Worktrees are nested inside the project (less visible in file manager). Slightly deeper path. Existing sibling worktrees won't be affected (config change only applies going forward).

### C: `/cd` command for manual recovery

User types `/cd /path/to/worktree` after the pipeline creates it. Relocates the session's primary working directory.

- Pros: No code changes. Works for any directory.
- Cons: Manual, error-prone. Users forget. Doesn't solve the automated pipeline case.

## Decision

**Approach B: Move worktrees inside `.claude/worktrees/`.** This is the most reliable solution because it works within Claude Code's existing project boundary enforcement rather than fighting it. The worktree path naming changes from `cc-spex@031-feature` (sibling) to `.claude/worktrees/031-feature` (inside project).

## Key Requirements

- Change default `base_path` in `worktree-config.yml` template from `..` to `.claude/worktrees`
- Update the `speckit.spex-worktrees.manage.md` command to use `.claude/worktrees` as default
- Update worktree path computation: `${BASE_PATH}/${BRANCH_NAME}` instead of `${BASE_PATH}/${REPO_NAME}@${BRANCH_NAME}` (no repo name prefix needed when inside the project)
- Ensure `.claude/worktrees/` is in `.gitignore` (should already be covered by `.claude/` ignore)
- Update the ship pipeline's worktree detection to look in the new location
- The `spex-worktree-cwd.sh` recovery script can be simplified (worktree is always inside project boundary, CWD shouldn't reset)

## Open Questions

- Should existing sibling worktrees be automatically detected and offered for migration?
- Should the `EnterWorktree` tool be used instead of raw `git worktree add` when inside Claude Code? (It handles CWD switching at the harness level)
- Does the worktree finish/cleanup flow need changes when worktrees are inside `.claude/`?
