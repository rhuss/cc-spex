---
name: worktree
description: Manage git worktrees for isolated feature development - create after specify, list active worktrees, cleanup merged branches
argument-hint: "[list|cleanup]"
---

# Git Worktree Management for SDD

## Overview

This skill manages git worktrees to isolate feature development. It supports three actions:

- **create**: Called by the `worktrees` trait overlay after `speckit.specify` completes. Creates a worktree, restores `main`, and prints switch instructions.
- **list**: Shows all active feature worktrees with path, branch, and feature name.
- **cleanup**: Detects worktrees whose branches are merged and offers removal.

## Action Routing

Determine the action from context:

- If invoked from the `speckit.specify` overlay (post-specify context), the action is **create**.
- If invoked with argument `cleanup`, the action is **cleanup**.
- Otherwise (no args, `list`, or invoked directly), the action is **list**.

## Prerequisites

The project must be a git repository.

```bash
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: Not a git repository"; exit 1; }
```

## Action: Create

This action runs after `speckit.specify` has created a feature branch and spec files.

### Step 1: Read Configuration

Read `base_path` from `.specify/sdd-traits.json`:

```bash
BASE_PATH=$(jq -r '.worktrees_config.base_path // ".."' .specify/sdd-traits.json 2>/dev/null)
```

Default: `..` (sibling directory to the repo root).

### Step 2: Get Current Branch

```bash
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
```

Verify it matches the `NNN-feature-name` pattern. If not, warn that worktree creation only applies to feature branches and skip.

### Step 3: Detect If Already in a Worktree

A git worktree has a `.git` file (not directory) pointing to the main repo. Detect this:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(git rev-parse --git-dir)

# If git-dir is not <repo>/.git, we're inside a worktree
if [ "$GIT_DIR" != "$REPO_ROOT/.git" ] && [ "$GIT_DIR" != ".git" ]; then
  echo "WARNING: Already inside a git worktree. Skipping worktree creation."
  echo "Worktree nesting is not supported."
  # Skip worktree creation but continue with the rest of the specify flow
fi
```

If inside a worktree, skip the entire create action (FR-009).

### Step 4: Compute Target Path and Validate

```bash
WORKTREE_PATH="$REPO_ROOT/$BASE_PATH/$BRANCH_NAME"
```

Check if the target path already exists (FR-008):

```bash
if [ -d "$WORKTREE_PATH" ] || [ -f "$WORKTREE_PATH" ]; then
  echo "ERROR: Target path already exists: $WORKTREE_PATH"
  echo "Remove it manually or choose a different base_path in .specify/sdd-traits.json"
  # Stop worktree creation, but don't fail the entire specify flow
fi
```

### Step 5: Commit Spec Files to Feature Branch

Before switching away from the feature branch, commit any spec files that `speckit.specify` created. Without this, the files would remain as untracked artifacts in the main worktree and would not appear in the feature worktree.

```bash
# Check for uncommitted spec files in the feature's spec directory
SPEC_DIR="specs/$BRANCH_NAME"
if [ -d "$SPEC_DIR" ]; then
  UNTRACKED=$(git status --porcelain "$SPEC_DIR" 2>/dev/null)
  if [ -n "$UNTRACKED" ]; then
    git add "$SPEC_DIR"
    git commit -m "feat: Add spec for $BRANCH_NAME

Assisted-By: 🤖 Claude Code"
  fi
fi
```

This ensures the spec files are persisted on the feature branch before the worktree is created from it.

### Step 6: Restore Main Branch (before worktree creation)

Git does not allow two worktrees to have the same branch checked out. Since `speckit.specify` just created and checked out the feature branch, we must switch back to `main` before creating a worktree for that branch.

```bash
if ! git checkout main 2>&1; then
  echo "WARNING: Could not switch back to main."
  echo "You likely have uncommitted changes. Commit or stash them first."
  echo "The repository remains on branch $BRANCH_NAME."
  echo "Worktree creation skipped (cannot create worktree while branch is checked out here)."
  # Stop here - worktree creation is not possible without switching branches first
fi
```

### Step 7: Create the Worktree

Now that the current worktree is on `main`, create a new worktree for the feature branch:

```bash
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
```

If this fails (disk full, permission denied, etc.), report the error clearly. The original repo is already back on `main`:

```bash
if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1; then
  echo "ERROR: Failed to create worktree at $WORKTREE_PATH"
  echo "The repository is on main. The feature branch $BRANCH_NAME still exists."
  echo "Resolve the issue and retry, or switch to the branch manually: git checkout $BRANCH_NAME"
  # Stop here
fi
```

### Step 8: Print Switch Instructions

Print clear instructions for the user (FR-004):

```
┌─────────────────────────────────────────────────────────────┐
│ Worktree created at <worktree-path>                         │
│                                                             │
│ To continue with planning/implementation:                   │
│   cd <worktree-path> && claude                              │
│                                                             │
│ The spec file contains all context from this session.       │
└─────────────────────────────────────────────────────────────┘
```

## Action: List

Show all active feature worktrees for the project (FR-005).

### Step 1: Get Worktree List

```bash
git worktree list --porcelain
```

Parse the output. Each worktree entry has:
- `worktree <path>`
- `HEAD <commit>`
- `branch refs/heads/<branch-name>`

### Step 2: Filter Feature Branches

Only show worktrees whose branch matches the `NNN-*` feature branch pattern (three-digit prefix followed by a hyphen).

Skip the main worktree (the original repo).

### Step 3: Format Output

Display a table:

```
Active Feature Worktrees:

  Path                              Branch              Feature
  ─────────────────────────────────────────────────────────────
  ../004-user-auth                  004-user-auth       user-auth
  ../007-worktrees-trait            007-worktrees-trait  worktrees-trait
```

If no feature worktrees exist:

```
No active feature worktrees found.

Create one by running /speckit.specify with the worktrees trait enabled.
```

## Action: Cleanup

Detect worktrees whose branches are merged and offer removal (FR-006, FR-007).

### Step 1: Get Merged Branches

```bash
# Get all branches merged into main
MERGED_BRANCHES=$(git branch --merged main | sed 's/^[* ]*//' | grep -E '^[0-9]{3}-')
```

### Step 2: Cross-Reference with Worktrees

For each worktree with a feature branch, check if its branch appears in the merged list.

### Step 3: Handle Merged Worktrees

For each merged worktree, present it to the user and ask for confirmation:

```
Worktree ../004-user-auth (branch 004-user-auth) is merged into main.
Remove this worktree? (yes/no)
```

If the user confirms, first switch to the main repo root (to avoid cwd pointing at the deleted directory), then remove the worktree:

```bash
# Switch cwd to the main worktree BEFORE removing the feature worktree.
# If cwd is inside the worktree being removed, all subsequent commands will
# fail with "Path does not exist" because the Bash tool persists cwd.
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
cd "$MAIN_WORKTREE"
git worktree remove <path>
git branch -d <branch-name>
```

### Step 4: Handle Unmerged Worktrees

For worktrees with unmerged branches, warn the user (FR-007):

```
Worktree ../007-worktrees-trait (branch 007-worktrees-trait) has NOT been merged.
Skipping. Use --force to remove unmerged worktrees (data may be lost).
```

Only remove unmerged worktrees if the user explicitly confirms after seeing the warning.
