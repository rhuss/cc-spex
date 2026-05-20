---
description: "Complete a feature: verify, then merge/PR/keep with worktree-aware cleanup"
argument-hint: "[--create-pr]"
---

# Finish - Verify and Complete a Feature

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field and `create_pr` flag:

```bash
AUTONOMOUS_MODE=false
AUTO_CREATE_PR=false
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  ASK=$(jq -r '.ask // "always"' .specify/.spex-state 2>/dev/null)
  CREATE_PR=$(jq -r '.create_pr // false' .specify/.spex-state 2>/dev/null)
  if [ "$STATUS" = "running" ] && [ "$ASK" != "always" ]; then
    AUTONOMOUS_MODE=true
  fi
  if [ "$CREATE_PR" = "true" ]; then
    AUTO_CREATE_PR=true
  fi
fi
```

In autonomous mode: suppress all AskUserQuestion prompts. Auto-select "Merge to default branch" (or "Create PR" if `create_pr` is true in state or `--create-pr` argument is passed).

## Argument Parsing

If the argument `--create-pr` is passed, set `AUTO_CREATE_PR=true`. This skips the options prompt and goes directly to PR creation.

## Phase 1: Verification

Invoke `/speckit-spex-gates-verify` (the full verification gate). This runs:
1. Full test suite
2. Code hygiene review
3. Spec compliance validation (100% required)
4. Spec drift check
5. Success criteria verification

**If verification fails:** STOP. Display the verification report with blocking issues. Do not proceed to merge/PR options. The user must fix the issues and re-run `/speckit-spex-finish`.

**If verification passes:** Continue to Phase 2.

## Phase 2: Commit Outstanding Changes

Stage and commit any remaining tracked modifications:

```bash
git add -u
if ! git diff --cached --quiet; then
  git commit -m "chore: final changes before merge

Assisted-By: 🤖 Claude Code"
fi
```

If the working tree is clean, skip this step.

## Phase 3: Context Detection

Detect the current environment to determine how to proceed:

```bash
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
IN_WORKTREE=false
if [ "$GIT_DIR" != "$REPO_ROOT/.git" ] && [ "$GIT_DIR" != ".git" ]; then
  IN_WORKTREE=true
fi

CURRENT_BRANCH=$(git branch --show-current)

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

**If already on the default branch:** Report "Verification passed. You are already on the default branch; no merge needed." Clean up state file (`rm -f .specify/.spex-state`). STOP.

## Phase 4: Select Action

If `AUTO_CREATE_PR` is true (from `--create-pr` argument or state file): skip the prompt and go directly to **Option B: Create PR**.

If `AUTONOMOUS_MODE` is true: skip the prompt and go directly to **Option A: Merge to default branch**.

Otherwise, present options using `AskUserQuestion` (`multiSelect: false`, header: "Finish"):

**"Feature verified. How would you like to complete it?"**

Options:
1. **"Merge to default branch (Recommended)"**: "Fast-forward merge into the default branch, clean up branch and worktree"
2. **"Push and create PR"**: "Push branch and open a pull request for team review"
3. **"Keep branch as-is"**: "Leave branch for manual handling later"

## Phase 5: Execute Action

### Option A: Merge to Default Branch

**If in a worktree (`IN_WORKTREE` is true):**

```bash
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
WORKTREE_PATH=$(git rev-parse --show-toplevel)

# CRITICAL: Switch cwd to main worktree BEFORE any destructive operations.
# If cwd is inside the worktree being removed, subsequent commands fail.
cd "$MAIN_WORKTREE"

git checkout "$DEFAULT_BRANCH"

# Try fast-forward first, fall back to merge commit
git merge --ff-only "$CURRENT_BRANCH" 2>&1
```

If fast-forward fails (branches diverged), ask the user (unless autonomous mode):

In autonomous mode: create a merge commit automatically.

Otherwise use `AskUserQuestion` (`multiSelect: false`, header: "Merge"):
- "Create merge commit": "Branches have diverged, merge with a merge commit"
- "Abort": "Keep worktree, resolve manually"

If "Abort": STOP. The cwd is already at the main worktree.

If merge commit:
```bash
git merge "$CURRENT_BRANCH" -m "Merge branch '$CURRENT_BRANCH'

Assisted-By: 🤖 Claude Code" 2>&1
```

After merge succeeds, remove worktree and branch:
```bash
git worktree remove "$WORKTREE_PATH" 2>&1
git branch -d "$CURRENT_BRANCH" 2>&1 || git branch -D "$CURRENT_BRANCH" 2>&1
```

**If NOT in a worktree:**

```bash
git checkout "$DEFAULT_BRANCH"
git merge --ff-only "$CURRENT_BRANCH" 2>&1
```

If fast-forward fails: same divergence handling as worktree path above.

After merge:
```bash
git branch -d "$CURRENT_BRANCH"
```

Report:
```
Merged `<branch>` into `<default-branch>`. Feature branch deleted.
```

### Option B: Push and Create PR

```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
BRANCH=$(git branch --show-current)
SPEC_DIR="specs/${BRANCH}"
FEATURE_NAME=$(head -1 "$SPEC_DIR/spec.md" | sed 's/^# Feature Specification: //')

REVIEWERS_REL="$SPEC_DIR/REVIEWERS.md"
REVIEWERS_LINK=""
if [ -f "$REVIEWERS_REL" ]; then
  REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
  REVIEWERS_URL="${REMOTE_URL}/blob/${BRANCH}/${REVIEWERS_REL}"
  REVIEWERS_LINK="> **[Review Guide](${REVIEWERS_URL})** for full context: motivation, key decisions, and scope boundaries."
fi

COLLAB_CONFIG=".specify/extensions/spex-collab/collab-config.yml"
LABEL_FLAG=""
if [ -f "$COLLAB_CONFIG" ]; then
  LABELS_ENABLED=$(yq -r '.labels.enabled // true' "$COLLAB_CONFIG" 2>/dev/null || echo "true")
  IMPL_LABEL=$(yq -r '.labels.implement // "spex/implement"' "$COLLAB_CONFIG" 2>/dev/null || echo "spex/implement")
  if [ "$LABELS_ENABLED" = "true" ]; then
    LABEL_FLAG="--label ${IMPL_LABEL}"
  fi
fi

git push -u "$REMOTE" "$BRANCH"

gh pr create \
  --title "$FEATURE_NAME [Spec + Impl]" ${LABEL_FLAG} \
  --body "$(cat <<PREOF
$REVIEWERS_LINK

## Summary

Implementation of $FEATURE_NAME.

## Artifacts

- Spec: \`$SPEC_DIR/spec.md\`
- Plan: \`$SPEC_DIR/plan.md\`
- Tasks: \`$SPEC_DIR/tasks.md\`

Assisted-By: 🤖 Claude Code
PREOF
)"
```

Report the PR URL.

If in a worktree, also report: "Run `/speckit-spex-finish` again after the PR is merged to merge and clean up the worktree."

### Option C: Keep Branch

Report based on context:

If in a worktree:
```
Branch <branch> is verified and ready. Nothing was merged or pushed.

When ready to finish:
  /speckit-spex-finish    Run again to merge or create PR
```

If NOT in a worktree:
```
Branch <branch> is verified and ready. Nothing was merged or pushed.

When ready to finish:
  /speckit-spex-finish    Run again to merge or create PR
```

## Phase 6: State and Status Line Cleanup

After executing any option (merge, PR, or keep), remove the state file from both possible locations (absolute path from ship pipeline, and relative path from flow mode):

```bash
rm -f .specify/.spex-state
if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ]; then
  rm -f "$SHIP_STATE_FILE"
fi
```

This removes the state file, which dismisses the status line (the statusline script exits silently when no state file exists). Works for both ship mode (where `SHIP_STATE_FILE` may point to a worktree path) and flow mode (where the state file is always relative).
