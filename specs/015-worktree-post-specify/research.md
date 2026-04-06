# Research: Post-Specify Worktree Creation

**Branch**: `015-worktree-post-specify` | **Date**: 2026-04-06

## R1: Colon Naming Convention for Worktrees

**Decision**: Use `<repo-name>:<branch-name>` naming (e.g., `cc-spex:015-feature`)

**Rationale**: Matches the existing worktree naming convention already in use in this project. The `git worktree add` command accepts arbitrary paths, so colon characters in directory names are valid on both macOS and Linux.

**How to derive repo name**: `basename $(git rev-parse --show-toplevel)` from the main worktree. When running inside a worktree, the repo root is the worktree root, but the main worktree path can be obtained via `git worktree list --porcelain | head -1 | sed 's/^worktree //'` and then taking its basename. However, when the create action runs, we are still in the main repo (before worktree creation), so `basename $(git rev-parse --show-toplevel)` gives the correct repo name.

**Edge case**: If the repo root already contains a colon (e.g., `cc-spex:015-worktree-specify`), we are inside a worktree. FR-005 catches this case and skips creation.

**Alternatives considered**:
- Simple `<branch-name>` only: Doesn't group worktrees with parent repo visually
- Configurable pattern: Over-engineering for this use case

## R2: Commit Scope Before Branch Switch

**Decision**: Commit all modified tracked files, not just `specs/<branch>/`

**Rationale**: `speckit.specify` may modify `.specify/spex-traits.json` (if traits were toggled), `.specify/` scripts, or other tracked files during the session. Leaving uncommitted changes would cause `git checkout main` to fail or lose work.

**Implementation**: Replace the current `git add "$SPEC_DIR"` with `git add -A` followed by a check for actual staged changes before committing.

**Safeguard**: `git add -A` in the context of speckit.specify should be safe because:
- `.claude/skills/` is gitignored (regenerated per session)
- `.env` and credentials should already be in `.gitignore`
- The user is on a feature branch, not main

**Alternatives considered**:
- Explicit file list (`specs/`, `.specify/`): Too brittle, would miss unexpected changes
- `git stash` before checkout: Loses work in the stash, requires manual recovery

## R3: Trait Overlay Ordering

**Decision**: Rely on trait ordering in `spex-traits.json` for overlay application order

**Rationale**: The `do_apply()` function in `spex-traits.sh` iterates traits using `jq -r '.traits | to_entries[] | select(.value == true) | .key'`. The `jq` `to_entries` function preserves JSON object key order, so traits listed earlier in the JSON get their overlays applied first. Since `superpowers` appears before `worktrees` in the config, the superpowers review gate is appended before the worktree creation step.

**Verification**: Confirmed by reading `spex-traits.sh` lines 538-676. The iteration order is deterministic based on JSON key order.

**Risk**: If someone manually edits `spex-traits.json` and reorders keys, the ordering changes. This is an acceptable risk since:
- `spex-traits.sh init` generates the config with correct ordering
- Manual editing is explicitly unsupported (config changes go through `spex-traits.sh`)

## R4: Main Worktree Detection for Repo Name

**Decision**: Detect whether we're in the main repo or a worktree to derive the correct repo name

**Rationale**: When `create` runs, the code is executing in the main repo (not a worktree), so `basename $(git rev-parse --show-toplevel)` works. But we must handle the case where the main repo itself was cloned with a non-standard name.

**Implementation**:
```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
WORKTREE_PATH="$(cd "$REPO_ROOT/$BASE_PATH" && pwd)/${REPO_NAME}:${BRANCH_NAME}"
```

Using `cd ... && pwd` resolves the base path to an absolute path, avoiding issues with relative `..` when the path is displayed to the user.

## R5: Existing Worktree Skill Gap Analysis

**Current state** (SKILL.md): The existing skill already implements create, list, and cleanup actions with correct structure. Changes needed:

| Area | Current | Needed | Impact |
|------|---------|--------|--------|
| Path computation (Step 4) | `$REPO_ROOT/$BASE_PATH/$BRANCH_NAME` | `$BASE_PATH_RESOLVED/$REPO_NAME:$BRANCH_NAME` | FR-003 |
| Commit scope (Step 5) | `git add "$SPEC_DIR"` only | `git add -A` (all tracked changes) | FR-001 |
| FR references | FR-004 through FR-009 (old numbering) | FR-001 through FR-012 (new numbering) | Consistency |
| Switch instructions (Step 8) | Shows `cd <worktree-path>` | Update path format in instructions | FR-004 |
| List output | Shows `../004-user-auth` format | Update to show `cc-spex:004-user-auth` format | FR-007 |
