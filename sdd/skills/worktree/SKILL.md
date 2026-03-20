---
name: worktree
description: Manage git worktrees for isolated feature development - create after specify, list active worktrees, cleanup merged branches
argument-hint: "[list|cleanup]"
---

# Git Worktree Management for SDD

## Overview

This skill manages git worktrees to isolate feature development. It supports three actions:

- **create**: Called by the `worktrees` trait overlay after `speckit.specify` completes. Creates a worktree, restores `main`, writes a handoff file, and prints switch instructions.
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

### Step 5: Create the Worktree

```bash
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
```

If this fails (disk full, permission denied, etc.), report the error clearly and stop. The original repo remains on the feature branch (edge case 3):

```bash
if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>&1; then
  echo "ERROR: Failed to create worktree at $WORKTREE_PATH"
  echo "The repository remains on branch $BRANCH_NAME."
  echo "Resolve the issue and retry, or continue working in this directory."
  # Stop here - do not attempt to restore main
fi
```

### Step 6: Restore Main Branch

Switch the original repo back to `main` (FR-002):

```bash
if ! git checkout main 2>&1; then
  echo "WARNING: Could not switch back to main."
  echo "You likely have uncommitted changes. Commit or stash them first."
  echo "The worktree at $WORKTREE_PATH was created successfully."
  echo "The repository remains on branch $BRANCH_NAME."
  # Do not abort - worktree is already created
fi
```

### Step 7: Write Context Handoff File

Create the handoff file in the worktree at `<worktree>/.claude/handoff.md` (FR-003):

```bash
mkdir -p "$WORKTREE_PATH/.claude"
```

Write `handoff.md` with:
- A brief summary (5-10 lines) of key decisions from the brainstorm/specify session
- A pointer to the spec file: `specs/<branch-name>/spec.md`
- The suggested next step: "Run `/speckit.plan` to create the implementation plan"

The handoff content should be generated from the current conversation context, summarizing:
- What problem the feature solves
- Key design decisions made during brainstorm
- Any constraints or alternatives that were discussed

Example format:

```markdown
# Context Handoff: <feature-name>

## Summary
<Brief description of what was discussed and decided during brainstorm/specify>

## Key Decisions
- <Decision 1>
- <Decision 2>

## Spec Location
- Feature spec: `specs/<branch-name>/spec.md`

## Next Step
Run `/speckit.plan` to create the implementation plan, then `/speckit.tasks` for task breakdown.
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
│ The handoff file at .claude/handoff.md contains             │
│ context from this brainstorm/specify session.               │
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

If the user confirms, remove it:

```bash
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
