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

---

## Revisit: 2026-07-08

### Updated Problem Framing

The original fix (moving to `.claude/worktrees/`) solved CWD persistence for Claude Code but introduced a harness coupling. Each agent harness has different worktree conventions:

- **Claude Code**: Native `EnterWorktree` tool uses `.claude/worktrees/`. Spex worktrees use `git worktree add` directly but default to the same path.
- **Codex**: No native worktree tool. Raw `git worktree add` only. No `.codex/worktrees/` convention exists.
- **OpenCode**: Same as Codex, raw git commands only.

Two problems surfaced during feature 037-workflow-setup:

1. **Harness-coupled default path**: `.claude/worktrees/` ties the worktree extension to Claude Code's directory layout. Codex and OpenCode users get a `.claude/` directory they didn't ask for.

2. **Statusline can't see worktree state from main repo**: When a session opens the main repo while a ship pipeline runs in a worktree, the statusline shows nothing. The script checks `workspace.current_dir` (from Claude Code's stdin JSON), CWD, and `CLAUDE_PROJECT_DIR`, none of which point to the worktree.

### Analysis: Statusline Visibility

The statusline currently has 5 resolution priorities:
1. `SHIP_STATE_FILE` env var
2. `workspace.current_dir` from stdin JSON
3. CWD `.specify/.spex-state`
4. `workspace.project_dir` from stdin JSON
5. `CLAUDE_PROJECT_DIR` env var

With parallel worktree sessions, a main-repo session cannot meaningfully show a single worktree's status (which one?). The correct behavior: each session shows its own state, based on its CWD. Main repo sessions correctly show nothing (no pipeline running there).

This means the fix is "ensure sessions always have the correct CWD", not "scan worktrees from the main repo."

### New Approaches Considered

#### D: Neutral default path `.worktrees/`

Change the default `base_path` from `.claude/worktrees` to `.worktrees/`. No harness prefix. Add `.worktrees/` to `.gitignore` during setup.

- Pros: Harness-neutral, no `.claude/` directory on non-Claude harnesses, short path
- Cons: New top-level dotdir. Not inside any harness's project boundary by default (CWD persistence depends on harness behavior).

#### E: Per-harness CWD switch strategy

Each harness needs a different mechanism to switch CWD and keep it stable:

| Harness | CWD Switch Mechanism | Persistence |
|---------|---------------------|-------------|
| Claude Code | `EnterWorktree` or `cd` (if inside project boundary) | Stable if worktree is inside project boundary |
| Codex | `cd` in hook or instruction | Unknown, needs testing |
| OpenCode | `cd` in plugin | Unknown, needs testing |

The worktree manage command would detect the harness and use the appropriate mechanism.

#### F: Worktree lifecycle per harness

The full worktree lifecycle has 4 phases, each needing harness-specific behavior:

| Phase | Claude Code | Codex | OpenCode |
|-------|------------|-------|----------|
| **Create** | `git worktree add .worktrees/<branch>` | Same | Same |
| **Switch CWD** | `cd` (inside project boundary) or `EnterWorktree` | `cd` + restart instruction | `cd` + restart instruction |
| **State file** | `.worktrees/<branch>/.specify/.spex-state` | Same | Same |
| **Cleanup** | `git worktree remove` + `rm -rf` | Same | Same |

Create, state, and cleanup are identical across harnesses. Only CWD switching differs.

### Updated Decision

**Approach D + F: Neutral `.worktrees/` path with per-harness CWD switching.**

1. Change default `base_path` to `.worktrees/` (harness-neutral)
2. Add `.worktrees/` to `.gitignore` in setup workflow and `configure_gitignore()`
3. Keep `base_path` configurable for users who want a different location
4. Detect harness in the manage command and use the appropriate CWD switch
5. Statusline stays as-is (relies on `workspace.current_dir`, correct by design)

### Key Requirements

- Change default `worktrees.base_path` from `.claude/worktrees` to `.worktrees` in `worktree-config.yml`
- Update `spex-init.sh` and `setup.yml` gitignore patterns to include `.worktrees/`
- Update the worktree manage command to detect harness and emit correct CWD switch instructions
- Test CWD persistence on Codex and OpenCode (may need harness-specific workarounds)
- Backward compatibility: detect existing `.claude/worktrees/` and continue using it if populated

### Open Questions

- Does Codex persist CWD after `cd` within a session, or does it reset like Claude Code did with sibling dirs?
- Should the setup workflow configure the worktree base path during `adapt-harness` (per-harness default)?
- Is `.worktrees/` visible enough for users to find their worktrees, or does the `list` action in the manage command make discoverability a non-issue?
