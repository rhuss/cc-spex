# Brainstorm: Worktrees Trait for SDD

## Problem

When `speckit.specify` creates a new feature branch, it switches the branch in the shared working directory. This disrupts all other Claude Code sessions pointing at the same repo. The user's workflow is to brainstorm and specify from `main`, then work on the feature in isolation, potentially running multiple features in parallel.

## Solution: Context Handoff Pattern

A new `worktrees` trait that creates a git worktree for the feature branch after `speckit.specify` completes, restores `main` in the original repo, and instructs the user to start a fresh Claude session in the worktree directory.

## Why Not EnterWorktree?

Claude Code's built-in `EnterWorktree` tool was considered but ruled out for three reasons:

1. **Branch naming**: `EnterWorktree` creates its own branch from HEAD. spec-kit requires the branch to match `NNN-short-name` format (created by `speckit.specify`). These are incompatible.
2. **Worktree location**: Fixed at `.claude/worktrees/`, not configurable.
3. **Session resume**: `claude -r <session-id>` is directory-scoped (sessions stored under `~/.claude/projects/<encoded-path>/`). Resuming from a worktree directory would not find sessions created in the original repo.

## Design

### Flow

```
1. User starts Claude in main repo (on `main`)
2. Brainstorm -> speckit.specify
   -> creates branch NNN-feature-name, spec files, commits
3. Worktrees trait post-specify steps:
   a. git worktree add <base_path>/<branch-name> <branch-name>
   b. git checkout main  (restore main in original repo)
   c. Write context handoff file into the worktree
   d. Print instructions to user:
      "Worktree created. To continue: cd <path> && claude"
4. User starts fresh Claude in worktree
   -> All tracked files (CLAUDE.md, specs, constitution) available
   -> Handoff file provides brainstorm context continuity
```

### Context Handoff File

- **Location**: `<worktree>/.claude/handoff.md` (gitignored, session-specific)
- **Content**: Brief summary (5-10 lines) with pointers to data
  - Key decisions and constraints from brainstorm
  - Pointer to spec: `specs/NNN-feature/spec.md`
  - Suggested next step (e.g., "Run `/speckit.plan`")
- **Lifecycle**: Kept for reference (gitignored, no cleanup needed)

### Trait Configuration

In `.specify/sdd-traits.json`:

```json
{
  "worktrees": {
    "enabled": true,
    "base_path": ".."
  }
}
```

- `base_path`: Relative to repo root, default `..` (sibling directories)
- Worktree created at `<base_path>/<branch-name>`

### Components

1. **Trait overlay on `speckit.specify`**: Adds post-specify instructions to create worktree, restore main, write handoff, print switch instructions.
2. **`sdd:worktree` command**: Utility for worktree management.
   - `sdd:worktree list`: Show active worktrees and their feature/branch status
   - `sdd:worktree cleanup`: Offer removal of worktrees whose branches are merged

### cc-deck Sidebar Integration

No changes needed. When the user starts a new Claude session in the worktree directory:
- The shell's starship prompt shows the correct feature branch
- cc-deck hooks receive the correct CWD, sidebar updates naturally

### Upstream Alignment

spec-kit PR #1579 adds `SPECIFY_SPECS_DIR` for decoupled spec storage in worktree setups. This trait is compatible: if upstream merges that PR, `SPECIFY_SPECS_DIR` could be set to share specs across worktrees. For now, each worktree has its own copy of specs (from the branch), which is sufficient.

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Session continuity | Context handoff file (not session resume) | `claude -r` is directory-scoped, can't resume across directories |
| Worktree placement | Sibling directory (`../<branch>`) | User preference, matches existing cc-deck pattern |
| Handoff detail level | Brief summary + pointers | Spec itself captures the outcome |
| Handoff cleanup | Keep for reference | Gitignored, no harm in keeping |
| Worktree creation tool | Manual `git worktree add` | `EnterWorktree` can't control branch name or location |

## Alternatives Rejected

- **EnterWorktree**: Can't control branch name (spec-kit requirement), fixed location, session scoping issues
- **Manual worktree + Bash cd**: Session CWD doesn't update, `! cwd` shows wrong directory
- **Session symlink hack**: Fragile, depends on internal Claude Code storage format
- **spec-kit-plus "Mission Control"**: Tried and reverted upstream, too complex
