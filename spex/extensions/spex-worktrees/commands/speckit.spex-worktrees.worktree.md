---
name: speckit.spex-worktrees.worktree
description: Manage git worktrees for isolated feature development - create after specify, list active worktrees, cleanup merged branches
argument-hint: "[list|cleanup]"
---

# Git Worktree Management for spex

## Overview

This command manages git worktrees to isolate feature development. It supports three actions:

- **create**: Called by the `after_specify` hook after `speckit-specify` completes. Creates a worktree, restores `main`, and prints switch instructions.
- **list**: Shows all active feature worktrees with path, branch, and feature name.
- **cleanup**: Detects worktrees whose branches are merged and offers removal.

## Action Routing

Determine the action from context:

- If invoked from the `after_specify` hook (post-specify context), the action is **create**.
- If invoked with argument `cleanup`, the action is **cleanup**.
- Otherwise (no args, `list`, or invoked directly), the action is **list**.

## Prerequisites

The project must be a git repository.

```bash
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: Not a git repository"; exit 1; }
```

## Action: Create

This action runs after `speckit-specify` has created a feature branch and spec files.

### Step 1: Read Configuration

Read `base_path` from `.specify/spex-traits.json`:

```bash
BASE_PATH=$(jq -r '.worktrees_config.base_path // ".."' .specify/spex-traits.json 2>/dev/null)
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
  # Stop here. Do not proceed to subsequent steps.
fi
```

If inside a worktree, skip the entire create action. Do not proceed to any subsequent Create steps.

### Step 4: Compute Target Path and Validate

Derive the repo name from the repository root and build the worktree path:

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

# Handle both absolute and relative base paths
if [[ "$BASE_PATH" = /* ]]; then
  RESOLVED_BASE=$(cd "$BASE_PATH" && pwd)
else
  RESOLVED_BASE=$(cd "$REPO_ROOT/$BASE_PATH" && pwd)
fi
```

If the `cd` fails (directory does not exist), report a clear error and stop:

```bash
if [ -z "$RESOLVED_BASE" ]; then
  echo "ERROR: base_path '$BASE_PATH' does not resolve to a valid directory."
  echo "Check worktrees_config.base_path in .specify/spex-traits.json"
  # Stop here. Do not proceed to subsequent steps.
fi
```

Build the worktree path using `@` as separator between repo name and branch:

```bash
WORKTREE_PATH="${RESOLVED_BASE}/${REPO_NAME}@${BRANCH_NAME}"
```

Verify the worktree path is not inside the main repository (a `base_path` of `.` would cause this):

```bash
case "$WORKTREE_PATH" in
  "$REPO_ROOT"/*)
    echo "ERROR: Worktree path is inside the main repository: $WORKTREE_PATH"
    echo "Set base_path to a directory outside the repo (default: '..')"
    # Stop here. Do not proceed to subsequent steps.
    ;;
esac
```

Check if the target path already exists:

```bash
if [ -d "$WORKTREE_PATH" ] || [ -f "$WORKTREE_PATH" ]; then
  echo "ERROR: Target path already exists: $WORKTREE_PATH"
  echo "Remove it manually or choose a different base_path in .specify/spex-traits.json"
  # Stop here. Do not proceed to subsequent steps.
fi
```

### Step 5: Commit All Tracked Changes to Feature Branch

Before switching away from the feature branch, commit all modified tracked files. This includes spec files, `.specify/` configuration changes, and any other modified tracked files. Stage changes in two passes to avoid capturing unintended untracked files:

```bash
# Stage modifications to already-tracked files
git add -u

# Stage new spec artifacts (these are untracked but expected)
[ -d "specs/$BRANCH_NAME" ] && git add "specs/$BRANCH_NAME"
[ -d ".specify" ] && git add .specify/

if ! git diff --cached --quiet; then
  git commit -m "feat: Add spec for $BRANCH_NAME

Assisted-By: 🤖 Claude Code"
fi
```

Using `git add -u` (tracked modifications only) plus explicit paths for new spec artifacts limits the commit scope to intended files. The `git diff --cached --quiet` guard skips the commit when there are no staged changes, avoiding empty commits.

### Step 6: Restore Default Branch (before worktree creation)

Git does not allow two worktrees to have the same branch checked out. Since `speckit-specify` just created and checked out the feature branch, we must switch back to the default branch before creating a worktree for that branch.

Detect the default branch dynamically with a fallback chain:

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  # origin/HEAD not set (common with git init + remote add). Try common names.
  for candidate in main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
```

```bash
if ! git checkout "$DEFAULT_BRANCH" 2>&1; then
  echo "WARNING: Could not switch back to $DEFAULT_BRANCH."
  echo "You likely have uncommitted changes. Commit or stash them first."
  echo "The repository remains on branch $BRANCH_NAME."
  echo "Worktree creation skipped (cannot create worktree while branch is checked out here)."
  # Stop here. Do not proceed to subsequent steps.
fi
```

### Step 7: Create the Worktree

Now that the current worktree is on the default branch, create a new worktree for the feature branch. If this fails (disk full, permission denied, etc.), report the error clearly:

```bash
if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1; then
  echo "ERROR: Failed to create worktree at $WORKTREE_PATH"
  echo "The repository is on $DEFAULT_BRANCH. The feature branch $BRANCH_NAME still exists."
  echo "Resolve the issue and retry, or switch to the branch manually: git checkout $BRANCH_NAME"
  # Stop here. Do not proceed to subsequent steps.
fi
```

### Step 8: Copy Flow State to Worktree

The `.specify/.spex-state` file is gitignored (runtime state), so it won't exist in the new worktree. Copy it so the status line works immediately in the new session:

```bash
if [ -f ".specify/.spex-state" ]; then
  mkdir -p "$WORKTREE_PATH/.specify"
  cp ".specify/.spex-state" "$WORKTREE_PATH/.specify/.spex-state"
fi
```

### Step 9: Print Switch Instructions

Print clear instructions for the user showing the worktree path:

```
┌─────────────────────────────────────────────────────────────┐
│ Worktree created at <worktree-path>                         │
│                                                             │
│ To continue with planning/implementation:                   │
│   cd <worktree-path> && claude                              │
│                                                             │
│ In the new session, run /spex:init to set up spec-kit        │
│ commands and spex traits in the worktree.                   │
│                                                             │
│ The spec file contains all context from this session.       │
└─────────────────────────────────────────────────────────────┘
```

Use the actual `WORKTREE_PATH` value (computed in Step 4) in the output. This ensures the path is correct regardless of the configured `base_path`.

## Action: List

Show all active feature worktrees for the project.

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

Display a table with worktree directory names (`@` separator):

```
Active Feature Worktrees:

  Path                              Branch              Feature
  ─────────────────────────────────────────────────────────────
  cc-spex@004-user-auth             004-user-auth       user-auth
  cc-spex@007-worktrees-trait       007-worktrees-trait  worktrees-trait
```

Derive the display path by extracting the last path component from the worktree's absolute path.

If no feature worktrees exist:

```
No active feature worktrees found.

Create one by running /speckit-specify with the worktrees extension enabled.
```

## Action: Cleanup

Detect worktrees whose branches are merged and offer removal.

### Step 1: Get Merged Branches

```bash
# Detect default branch with fallback chain
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  for candidate in main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}

# Get all feature branches merged into the default branch
MERGED_BRANCHES=$(git branch --merged "$DEFAULT_BRANCH" | sed 's/^[* ]*//' | grep -E '^[0-9]{3}-')
```

### Step 2: Cross-Reference with Worktrees

For each worktree with a feature branch, check if its branch appears in the merged list.

### Step 3: Handle Merged Worktrees

For each merged worktree, present it to the user and ask for confirmation:

```
Worktree cc-spex@004-user-auth (branch 004-user-auth) is merged into main.
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

For worktrees with unmerged branches, warn the user:

```
Worktree cc-spex@007-worktrees-trait (branch 007-worktrees-trait) has NOT been merged.
Skipping. Use --force to remove unmerged worktrees (data may be lost).
```

Only remove unmerged worktrees if the user explicitly confirms after seeing the warning.

---

## Worktree Context for Downstream Commands

When running in a worktree created by this extension, downstream spec-kit commands should be aware of the worktree context:

### Planning Context

You are likely running in a worktree created by the `worktrees` extension. The spec file in this worktree contains all decisions from the brainstorm/specify session. No separate handoff file is needed.

### Implementation Context

You are likely running in a worktree created by the `worktrees` extension. The spec and plan files in this worktree contain all context needed for implementation. No separate handoff file is needed.
