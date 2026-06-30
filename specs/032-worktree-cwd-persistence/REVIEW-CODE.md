# Code Review: 032-worktree-cwd-persistence

**Date:** 2026-06-30
**Branch:** 032-worktree-cwd-persistence
**Spec compliance:** PASS (9/9 FRs implemented)

## Deep Review Report

**Date:** 2026-06-30
**Branch:** 032-worktree-cwd-persistence
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** ship-pipeline (direct review, subagent timed out)

### Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 0 | 0 | 0 |
| Notable | 1 | - | 1 |
| **Total** | **1** | **0** | **1** |

**Review method:** Direct diff review (5-agent dispatch timed out)

### Notable Observations

#### NOTABLE-1
- **File:** spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md
- **Category:** architecture
- **Description:** The `INSIDE_PROJECT` detection uses a string prefix match (`case "$BASE_PATH" in .claude/worktrees*)`). This is simple and correct for the default case, but a user could theoretically set `base_path: ".claude/worktrees-custom"` and get the inside-project treatment (branch-only path, no repo prefix). In practice this is harmless since any `.claude/` path is inside the project, but the intent check is path-prefix, not semantic.

## Spec Compliance

| FR | Status | Implementation |
|----|--------|---------------|
| FR-001 | PASS | Default changed from `".."` to `".claude/worktrees"` in yq fallback and echo fallback |
| FR-002 | PASS | Manage command uses `.claude/worktrees` when no config override |
| FR-003 | PASS | Inside-project paths use `$REPO_ROOT/$BASE_PATH/$BRANCH_NAME` (no repo prefix) |
| FR-004 | PASS | Outside-project paths keep `${RESOLVED_BASE}/${REPO_NAME}@${BRANCH_NAME}` |
| FR-005 | PASS | `mkdir -p "$REPO_ROOT/$BASE_PATH"` before worktree creation |
| FR-005b | PASS | Guard allows `$REPO_ROOT/.claude/worktrees/*`, rejects other inside-project paths |
| FR-006 | PASS | Ship pipeline uses `git worktree list --porcelain` which searches by branch (path-agnostic) |
| FR-007 | PASS | Recovery script handles both via SHIP_STATE_FILE (strategy 1) and git detection (strategy 2) |
| FR-008 | PASS | README updated: extension description + worktree integration section |
| FR-009 | PASS | help.md updated with `.claude/worktrees/` default and config override note |

## Code Hygiene

- rsync excludes `worktrees/` to prevent recursive copy into itself
- Inside-repo guard correctly allows `.claude/worktrees/*` as first case before rejecting other inside paths
- Backward compatibility preserved: custom `base_path: ".."` still uses the old repo@branch format
- No dead code, no orphaned references
