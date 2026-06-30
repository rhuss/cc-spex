# Implementation Plan: Worktree CWD Persistence

**Branch**: `032-worktree-cwd-persistence` | **Date**: 2026-06-30 | **Spec**: [spec.md](spec.md)

## Summary

Change the default worktree location from sibling directories (`../repo@branch`) to inside the project (`.claude/worktrees/branch`). This keeps worktrees within Claude Code's project boundary so CWD persists across Bash tool calls and subagent returns.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown (skill files)
**Primary Dependencies**: `git worktree`, `yq`, `jq`
**Testing**: `make release` (plugin validation)
**Project Type**: Claude Code plugin
**Scale/Scope**: 4 files modified, 2 files updated (docs)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| II. Extension Architecture | PASS | Changes within spex-worktrees extension |
| III. Extension Composability | PASS | No cross-extension dependencies changed |
| VII. State as Scripts | PASS | Recovery script already exists |

## Files to Modify

```text
spex/extensions/spex-worktrees/commands/
  speckit.spex-worktrees.manage.md    # Default base_path, path format, inside-repo guard
spex/scripts/
  spex-worktree-cwd.sh               # Simplify recovery for inside-project worktrees
README.md                            # Update worktree location docs
spex/docs/help.md                    # Update worktree help text
```

## Design

### Path Format

| Worktree location | Path format | Example |
|-------------------|-------------|---------|
| Inside project (default) | `.claude/worktrees/<branch>` | `.claude/worktrees/032-feature` |
| Outside project (custom) | `<base>/<repo>@<branch>` | `../cc-spex@032-feature` |

Detection: if resolved base path is inside `.claude/worktrees`, use branch-only format. Otherwise, use repo@branch format.

### Manage Command Changes

**Step 1 (Read Configuration)**: Change default from `".."` to `".claude/worktrees"`:
```bash
BASE_PATH=$(yq -r '.worktrees.base_path // ".claude/worktrees"' "$WORKTREE_CONFIG" 2>/dev/null || echo ".claude/worktrees")
```

**Step 4 (Compute Target Path)**: Branch on whether base is inside or outside project:
```bash
INSIDE_PROJECT=false
case "$BASE_PATH" in
  .claude/worktrees*) INSIDE_PROJECT=true ;;
esac

if [ "$INSIDE_PROJECT" = true ]; then
  mkdir -p "$REPO_ROOT/$BASE_PATH"
  WORKTREE_PATH="$REPO_ROOT/$BASE_PATH/$BRANCH_NAME"
else
  REPO_NAME=$(basename "$REPO_ROOT")
  RESOLVED_BASE=$(cd "$REPO_ROOT/$BASE_PATH" && pwd)
  WORKTREE_PATH="${RESOLVED_BASE}/${REPO_NAME}@${BRANCH_NAME}"
fi
```

**Step 4 inside-repo guard**: Modify to allow `.claude/worktrees/`:
```bash
case "$WORKTREE_PATH" in
  "$REPO_ROOT"/.claude/worktrees/*)
    ;; # Allowed
  "$REPO_ROOT"/*)
    echo "ERROR: Worktree path is inside the main repository"
    ;;
esac
```

### Ship Pipeline (Stage 0)

The worktree detection uses `git worktree list --porcelain` which returns absolute paths and searches by branch name. No path format assumptions. Works unchanged with inside-project worktrees.

The `cd "$WORKTREE_PATH"` persists because the worktree is inside the project boundary.

### CWD Recovery Script

No logic changes needed. Strategy 1 (SHIP_STATE_FILE) remains primary. Strategy 2 (git detection) still works. The script is already a safety net; with inside-project worktrees, it should rarely fire.

## Implementation Order

1. Modify manage command (default, path format, guard)
2. Update CWD recovery script comments
3. Update docs (README, help.md)
4. Commit and verify with `make release`
