---
name: speckit.spex-worktrees.worktree
description: Manage git worktrees for isolated feature development - create after specify, list active worktrees, finish and cleanup
argument-hint: "[list|cleanup|finish]"
---

# Git Worktree Management for spex

## Overview

This command manages git worktrees to isolate feature development. It supports four actions:

- **create**: Called by the `after_specify` hook after `speckit-specify` completes. Creates a worktree, restores `main`, and prints switch instructions.
- **list**: Shows all active feature worktrees with path, branch, and feature name.
- **finish**: Merges the current worktree's branch into the default branch and removes the worktree. Use when implementation is complete.
- **cleanup**: Detects worktrees whose branches are merged and offers removal.

## Action Routing

Determine the action from context:

- If invoked from the `after_specify` hook (post-specify context), the action is **create**.
- If invoked with argument `finish`, the action is **finish**.
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

Read `base_path` from the worktrees extension config (or default to `..`):

```bash
WORKTREE_CONFIG=".specify/extensions/spex-worktrees/worktree-config.yml"
BASE_PATH=$(yq -r '.worktrees.base_path // ".."' "$WORKTREE_CONFIG" 2>/dev/null || echo "..")
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
  echo "Check worktrees.base_path in .specify/extensions/spex-worktrees/worktree-config.yml"
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
  echo "Remove it manually or choose a different base_path in .specify/extensions/spex-worktrees/worktree-config.yml"
  # Stop here. Do not proceed to subsequent steps.
fi
```

### Step 5: Commit All Tracked Changes to Feature Branch

Before switching away from the feature branch, commit all modified tracked files. This includes spec files, `.specify/` configuration changes, and any other modified tracked files. Stage changes in two passes to avoid capturing unintended untracked files:

```bash
# Stage modifications to already-tracked files
git add -u

# Stage new spec and brainstorm artifacts (these are untracked but expected)
[ -d "specs/$BRANCH_NAME" ] && git add "specs/$BRANCH_NAME"
[ -d "brainstorm" ] && git add brainstorm/
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

### Step 8: Copy Configuration to Worktree

Gitignored config directories (`.claude/` and `.specify/`) won't exist in the new worktree. Copy them so spec-kit extensions, skills, and settings work immediately without re-running init:

```bash
# Copy .specify/ (extensions registry, hooks, state, config)
if [ -d ".specify" ]; then
  rsync -a --exclude='.git' ".specify/" "$WORKTREE_PATH/.specify/"
fi

# Copy .claude/ (skills, settings, commands)
if [ -d ".claude" ]; then
  rsync -a ".claude/" "$WORKTREE_PATH/.claude/"
fi
```

This ensures the worktree has the same extensions, hooks, permissions, and skills as the main repo. No `/spex:init` needed in the worktree.

### Step 8b: Update feature.json for the Worktree Branch

The copied `.specify/feature.json` still points to whatever feature was active in the source repo. Update it to reference the correct spec directory for this worktree's branch:

```bash
FEATURE_JSON="$WORKTREE_PATH/.specify/feature.json"
if [ -f "$FEATURE_JSON" ]; then
  # Use jq to update the feature_directory to match the worktree's branch
  jq --arg dir "specs/$BRANCH_NAME" '.feature_directory = $dir' "$FEATURE_JSON" > "${FEATURE_JSON}.tmp" \
    && mv "${FEATURE_JSON}.tmp" "$FEATURE_JSON"
fi
```

This prevents spec-kit commands in the worktree from operating on the wrong spec directory.

### Step 9: Print Switch Instructions

Print clear instructions for the user showing the worktree path:

```
┌─────────────────────────────────────────────────────────────┐
│ Worktree created at <worktree-path>                         │
│                                                             │
│ To continue with planning/implementation:                   │
│   cd <worktree-path> && claude                              │
│                                                             │
│ Config (.claude/ and .specify/) has been copied.            │
│ All extensions and skills are ready to use.                 │
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

## Action: Finish

Merges the current worktree's feature branch into the default branch and removes the worktree. This is the recommended way to complete work in a spex worktree.

**IMPORTANT:** Do NOT use Claude Code's `ExitWorktree` tool. Spex worktrees are created via `git worktree add`, not `EnterWorktree`, so `ExitWorktree` will refuse to operate on them. Always use git commands directly.

### Step 1: Verify We're in a Worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(git rev-parse --git-dir)

# A worktree has a .git file (not directory) pointing to the main repo
if [ "$GIT_DIR" = "$REPO_ROOT/.git" ] || [ "$GIT_DIR" = ".git" ]; then
  echo "ERROR: Not inside a git worktree. Use 'finish' from within a spex worktree."
  # Stop here.
fi
```

### Step 2: Get Branch and Main Worktree Info

```bash
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
WORKTREE_PATH=$(git rev-parse --show-toplevel)

# Find the main worktree (first entry in worktree list)
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

# Detect default branch
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
```

### Step 3: Ensure All Changes Are Committed

```bash
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: Uncommitted changes in worktree. Commit or stash before finishing."
  # Stop here.
fi
```

### Step 4: Ask User How to Proceed

Use AskUserQuestion with:
- header: "Finish"
- multiSelect: false
- Options:
  - "Merge and remove (Recommended)": "Fast-forward merge branch into default, remove worktree and branch"
  - "Remove only": "Remove worktree and branch without merging (changes stay in git reflog)"
  - "Cancel": "Keep worktree as-is"

If "Cancel": stop.

### Step 5: Switch CWD to Main Worktree

**CRITICAL:** Switch the working directory to the main worktree BEFORE doing anything destructive. If cwd is inside the worktree being removed, all subsequent Bash commands will fail with "path does not exist".

```bash
cd "$MAIN_WORKTREE"
```

### Step 6: Merge (if selected)

If the user chose "Merge and remove":

```bash
cd "$MAIN_WORKTREE"
git checkout "$DEFAULT_BRANCH"
git merge --ff-only "$BRANCH_NAME" 2>&1
```

If fast-forward merge fails (branches diverged), ask the user:

Use AskUserQuestion with:
- header: "Merge"
- multiSelect: false
- Options:
  - "Create merge commit": "Merge with a merge commit (branches have diverged)"
  - "Abort": "Keep worktree, resolve manually"

If "Create merge commit":
```bash
git merge "$BRANCH_NAME" -m "Merge branch '$BRANCH_NAME'

Assisted-By: 🤖 Claude Code" 2>&1
```

If "Abort": stop. The cwd is already at the main worktree, so the user can navigate back.

### Step 7: Remove Worktree and Branch

```bash
# Remove worktree (cwd is already at main worktree from Step 5)
git worktree remove "$WORKTREE_PATH" 2>&1

# Delete the feature branch (it's merged or user chose remove-only)
git branch -d "$BRANCH_NAME" 2>&1 || git branch -D "$BRANCH_NAME" 2>&1
```

### Step 8: Clear Flow State

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
fi
```

### Step 9: Report

```
┌─────────────────────────────────────────────────────────┐
│ Feature branch <branch> finished.                       │
│                                                         │
│ - Merged to <default-branch> (if selected)              │
│ - Worktree removed: <worktree-path>                     │
│ - Branch deleted: <branch>                              │
│ - Flow state cleared                                    │
│                                                         │
│ You are now in the main repo on <default-branch>.       │
└─────────────────────────────────────────────────────────┘
```

If the user wants to push: `git push origin $DEFAULT_BRANCH`

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
