# Review Guide: Post-Specify Worktree Creation

**Branch**: `015-worktree-post-specify` | **Date**: 2026-04-06

## What This Feature Does

Updates the worktrees trait so that after `speckit.specify` completes, a git worktree is created using the `<repo-name>:<branch-name>` naming convention (e.g., `cc-spex:015-feature`), with all modified tracked files committed before switching to `main`.

## Key Review Areas

### 1. Colon Naming Convention (FR-003)
**File**: `spex/skills/worktree/SKILL.md` (Step 4)
**What to check**: Path computation derives `REPO_NAME` from `basename $(git rev-parse --show-toplevel)` and constructs `<base>/<repo>:<branch>`. Verify the path resolution handles relative `..` correctly.

### 2. Commit Scope (FR-001)
**File**: `spex/skills/worktree/SKILL.md` (Step 5)
**What to check**: Changed from `git add "$SPEC_DIR"` to `git add -A`. Verify there's a `git diff --cached --quiet` guard to skip empty commits. Confirm `.claude/skills/` is in `.gitignore` so regenerated files aren't committed.

### 3. Trait Overlay Ordering
**File**: `spex/overlays/worktrees/skills/speckit-specify/SKILL.append.md`
**What to check**: Overlay delegates to `{Skill: spex:worktree}` and stays under 30 lines. Superpowers overlay should be appended before worktrees overlay (determined by trait order in `spex-traits.json`).

### 4. Worktree Detection (FR-005)
**File**: `spex/skills/worktree/SKILL.md` (Step 3)
**What to check**: Correctly identifies when running inside a worktree (`.git` is a file) and skips creation. No changes expected here, but verify it still works with the new path format.

### 5. Listing Output (FR-007)
**File**: `spex/skills/worktree/SKILL.md` (List action)
**What to check**: Output shows colon-format paths consistent with the new naming convention.

## Spec Artifacts

| File | Purpose |
|------|---------|
| `spec.md` | Feature specification with 12 FRs, 4 user stories, 6 edge cases |
| `plan.md` | Implementation plan with technical context and project structure |
| `research.md` | 5 research decisions (naming, commit scope, ordering, detection, gap analysis) |
| `data-model.md` | Entity definitions and state transition diagram |
| `tasks.md` | 11 tasks across 5 phases, organized by user story |
| `quickstart.md` | Implementation quick reference |

## Supersedes

This feature supersedes `007-worktrees-trait` for the worktree creation flow. Listing and cleanup behaviors are carried forward with updates for the new naming convention.
