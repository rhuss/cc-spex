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

In autonomous mode: suppress all interactive prompts, UNLESS running inside a worktree (`IN_WORKTREE` is true, detected in Phase 3). When in a worktree, always present the user with the action prompt (Phase 4) regardless of autonomous mode. Never auto-merge or auto-delete a worktree.

## Argument Parsing

Parse the following flags from arguments:

- If `--create-pr` is passed, set `AUTO_CREATE_PR=true`. This skips the options prompt and goes directly to PR creation.
- If `--watch` is passed, set `WATCH_MODE=true`. After PR creation/push, enter a monitoring loop instead of cleaning up state immediately.

```bash
WATCH_MODE=false
# Parse --watch from arguments
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH_MODE=true ;;
  esac
done
```

### Watch Mode Configuration

When `WATCH_MODE` is true, read watch configuration from `.specify/extensions/spex/spex-config.yml`:

```bash
if [ "$WATCH_MODE" = true ]; then
  SPEX_CONFIG=".specify/extensions/spex/spex-config.yml"
  WATCH_TIMEOUT=$(yq -r '.watch.timeout_minutes // 30' "$SPEX_CONFIG" 2>/dev/null)
  WATCH_TIMEOUT=${WATCH_TIMEOUT:-30}
  WATCH_INTERVAL=$(yq -r '.watch.poll_interval_seconds // 60' "$SPEX_CONFIG" 2>/dev/null)
  WATCH_INTERVAL=${WATCH_INTERVAL:-60}
fi
```

## Pre-Execution Checks

**Check for extension hooks (before finish)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_finish` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- Convert hook command names from dot notation to hyphen notation for slash command invocation (e.g., `speckit.spex.smoke-test` becomes `/speckit-spex-smoke-test`)
- Determine prompt behavior based on autonomous mode: when `.specify/.spex-state` exists with `ask` of `smart` or `never`, optional hooks execute without prompting (treated as mandatory). When `ask` is `"always"` or no state file exists, optional hooks prompt as normal.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`) in interactive mode:
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Optional hook** (`optional: true`) in autonomous mode (`ask` is `smart` or `never`):
    Treat as mandatory (auto-execute without prompting).
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to Phase 1 Verification.
    ```
  - If a mandatory hook fails or is declined by the user, STOP. Output an error message indicating which hook failed and do NOT proceed to Phase 1 Verification.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

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

Stage and commit ALL changes, including untracked new files created during implementation:

```bash
# IMPORTANT: Use git add -A (not -u) to catch untracked files.
# Implementation subagents may create new files that were never staged.
# Using -u would silently lose these files on worktree removal.
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: final changes before merge

Assisted-By: 🤖 Claude Code"
fi
```

If the working tree is clean (no staged or untracked changes), skip this step.

## Phase 2b: Detach Detection (spex-detach)

If the `spex-detach` extension is installed, create the clean PR branch now (after all changes are committed):

```bash
DETACH_ENABLED=false
DETACH_RESULT=""
DETACH_PR_BRANCH=""
if [ -d ".specify/extensions/spex-detach" ]; then
  DETACH_SCRIPT=$(find ~/.claude -name 'spex-detach.sh' 2>/dev/null | head -1)
  if [ -n "$DETACH_SCRIPT" ] && [ -x "$DETACH_SCRIPT" ]; then
    DETACH_ENABLED=true
    DETACH_RESULT=$("$DETACH_SCRIPT" detach 2>&1) || {
      DETACH_EXIT=$?
      if [ "$DETACH_EXIT" -eq 2 ]; then
        echo "WARNING: All changes are spec-only. The clean PR branch would be empty."
        echo "No clean PR branch was created."
        DETACH_ENABLED=false
      else
        echo "ERROR: spex-detach failed: $DETACH_RESULT"
        DETACH_ENABLED=false
      fi
    }
    if [ "$DETACH_ENABLED" = true ]; then
      DETACH_PR_BRANCH=$(echo "$DETACH_RESULT" | jq -r '.pr_branch')
      DETACH_FILES=$(echo "$DETACH_RESULT" | jq -r '.files_changed')
      echo "Created clean PR branch: $DETACH_PR_BRANCH ($DETACH_FILES files)"
    fi
  fi
fi
```

If detach was successful, verify the clean branch contains no spec directories (FR-008):

```bash
if [ "$DETACH_ENABLED" = true ] && [ -n "$DETACH_PR_BRANCH" ]; then
  SPEC_DIRS_FOUND=false
  for check_dir in .specify specs brainstorm; do
    if git ls-tree -d "$DETACH_PR_BRANCH" "$check_dir" >/dev/null 2>&1; then
      SPEC_DIRS_FOUND=true
      echo "ERROR: Clean branch still contains '$check_dir' directory"
    fi
  done
  if [ "$SPEC_DIRS_FOUND" = true ]; then
    echo "ERROR: Clean branch verification failed. Spec artifacts were not properly stripped."
    DETACH_ENABLED=false
  fi
fi
```

## Phase 3: Context Detection

Detect the current environment by running the context detection script:

```bash
FINISH_CONTEXT=$(find ~/.claude -name 'spex-finish-context.sh' 2>/dev/null | head -1)
CTX=$("$FINISH_CONTEXT")
```

Parse the JSON output to extract context variables:

- `IN_WORKTREE`: boolean, whether the current directory is a git worktree
- `CURRENT_BRANCH`: the current branch name
- `DEFAULT_BRANCH`: the default branch (main/master)
- `MAIN_WORKTREE`: path to the main worktree (only set when `IN_WORKTREE` is true)
- `EXISTING_PR_NUMBER`: PR number if one exists for this branch (empty if none)
- `EXISTING_PR_URL`: PR URL if one exists

**If already on the default branch:** Report "Verification passed. You are already on the default branch; no merge needed." Clean up state file (`rm -f .specify/.spex-state`). STOP.

## Phase 4: Select Action

If `AUTO_CREATE_PR` is true (from `--create-pr` argument or state file) AND `IN_WORKTREE` is false: skip the prompt and go directly to **Option B1** if `EXISTING_PR_NUMBER` is set (push to existing PR), otherwise **Option B2** (create new PR).

If `AUTONOMOUS_MODE` is true AND `IN_WORKTREE` is false: skip the prompt and go directly to **Option A: Merge to default branch**.

**Worktree override:** When `IN_WORKTREE` is true, ALWAYS present the prompt below regardless of autonomous mode or `--create-pr`. Worktrees are never auto-merged or auto-deleted.

Present options to the user (single-select, header: "Finish"):

**"Feature verified. How would you like to complete it?"**

**When `DETACH_ENABLED` is true**, present these options:
1. **"Push clean PR branch to upstream" (Recommended)**: "Push `${DETACH_PR_BRANCH}` with only code changes for an upstream PR"
2. **"Merge to default branch"**: "Fast-forward merge into the default branch, clean up branch and worktree"
3. **"Keep branch as-is"**: "Leave branch for manual handling later"

**When `DETACH_ENABLED` is false** (standard behavior), present these options:
1. **If `EXISTING_PR_NUMBER` is set:** **"Push to PR #${EXISTING_PR_NUMBER}" (Recommended)**: "Push new commits to the existing pull request"
   **Otherwise:** **"Push and create PR" (Recommended)**: "Push branch and open a pull request for team review"
2. **"Merge to default branch"**: "Fast-forward merge into the default branch, clean up branch and worktree"
3. **"Keep branch as-is"**: "Leave branch for manual handling later"

## Phase 5: Execute Action

### Option D: Push Clean PR Branch to Upstream (spex-detach)

Only available when `DETACH_ENABLED` is true and the user selected "Push clean PR branch to upstream".

```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
git push -u "$REMOTE" "$DETACH_PR_BRANCH"

FEATURE_BRANCH=$(git branch --show-current)
SPEC_DIR="specs/${FEATURE_BRANCH}"
FEATURE_NAME=$(head -1 "$SPEC_DIR/spec.md" 2>/dev/null | sed 's/^# Feature Specification: //' || echo "$FEATURE_BRANCH")

# Determine target repo for PR
REPO_FLAG=""
if git remote | grep -qx upstream 2>/dev/null; then
  UPSTREAM_REPO=$(git remote get-url upstream 2>/dev/null | sed 's|.*github\.com[:/]||; s|\.git$||')
  [ -n "$UPSTREAM_REPO" ] && REPO_FLAG="--repo $UPSTREAM_REPO"
fi

gh pr create ${REPO_FLAG} \
  --head "$DETACH_PR_BRANCH" \
  --title "$FEATURE_NAME" \
  --body "$(cat <<PREOF
## Summary

$FEATURE_NAME

> Spec artifacts are preserved on the \`$FEATURE_BRANCH\` feature branch.

Assisted-By: 🤖 Claude Code
PREOF
)"
```

After PR creation:
```bash
ACTION_TAKEN="pr"
PR_URL=$(gh pr view "$DETACH_PR_BRANCH" --json url -q '.url' 2>/dev/null || true)
PR_NUMBER=$(gh pr view "$DETACH_PR_BRANCH" --json number -q '.number' 2>/dev/null || true)
```

Report:
```
Created PR from clean branch $DETACH_PR_BRANCH: <PR_URL>
Spec artifacts preserved on feature branch $FEATURE_BRANCH.
```

If in a worktree, also report: "Run `/speckit-spex-finish` again after the PR is merged to merge and clean up the worktree."

### Option A: Merge to Default Branch

**If in a worktree (`IN_WORKTREE` is true):**

Use `MAIN_WORKTREE` and `REPO_ROOT` (as `WORKTREE_PATH`) from the Phase 3 context detection output.

```bash
# CRITICAL: Switch cwd to main worktree BEFORE any destructive operations.
# If cwd is inside the worktree being removed, subsequent commands fail.
cd "$MAIN_WORKTREE"

git checkout "$DEFAULT_BRANCH"

# Try fast-forward first, fall back to merge commit
git merge --ff-only "$CURRENT_BRANCH" 2>&1
```

If fast-forward fails (branches diverged), ask the user (unless autonomous mode):

In autonomous mode: create a merge commit automatically.

Otherwise present options to the user (`multiSelect: false`, header: "Merge"):
- "Create merge commit": "Branches have diverged, merge with a merge commit"
- "Abort": "Keep worktree, resolve manually"

If "Abort": STOP. The cwd is already at the main worktree.

If merge commit:
```bash
git merge "$CURRENT_BRANCH" -m "Merge branch '$CURRENT_BRANCH'

Assisted-By: 🤖 Claude Code" 2>&1
```

After merge succeeds, check for uncommitted changes in the worktree BEFORE removing it:

```bash
# Safety check: ensure no uncommitted files remain in the worktree.
# The implementation subagent may have created files that Phase 2 missed.
cd "$WORKTREE_PATH"
UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -v -E '^\?\? \.specify/' || true)
if [ -n "$UNCOMMITTED" ]; then
  echo "WARNING: Worktree has uncommitted changes that would be lost:"
  echo "$UNCOMMITTED"
  git add -A
  git commit -m "chore: rescue uncommitted files before worktree removal

Assisted-By: 🤖 Claude Code"
  # Re-merge the new commit into the default branch
  cd "$MAIN_WORKTREE"
  git merge --ff-only "$CURRENT_BRANCH" 2>&1 || git merge "$CURRENT_BRANCH" -m "Merge rescued commit from '$CURRENT_BRANCH'

Assisted-By: 🤖 Claude Code" 2>&1
fi
cd "$MAIN_WORKTREE"
```

Then clean up state files in BOTH locations: the worktree AND the main repo. The ship pipeline creates the state file in the main repo before the worktree exists, so both copies must be removed:
```bash
# Clean state in the worktree (while it still exists)
rm -f "$WORKTREE_PATH/.specify/.spex-state"
# Clean state in the main worktree (created before worktree switch)
rm -f "$MAIN_WORKTREE/.specify/.spex-state"
# Clean state via absolute path (ship pipeline env var)
if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ]; then
  rm -f "$SHIP_STATE_FILE"
fi
STATE_CLEANED=true
ACTION_TAKEN="merge"

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
ACTION_TAKEN="merge"
```

Report:
```
Merged `<branch>` into `<default-branch>`. Feature branch deleted.
```

### Option B1: Push to Existing PR

When `EXISTING_PR_NUMBER` is set and the user selected "Push to PR #...":

```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
git push "$REMOTE" "$CURRENT_BRANCH"
ACTION_TAKEN="pr"
PR_NUMBER="$EXISTING_PR_NUMBER"
PR_URL="$EXISTING_PR_URL"
```

Report:
```
Pushed to PR #<number>: <EXISTING_PR_URL>
```

If in a worktree, also report: "Run `/speckit-spex-finish` again after the PR is merged to merge and clean up the worktree."

### Option B2: Push and Create PR

```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
BRANCH=$(git branch --show-current)
SPEC_DIR="specs/${BRANCH}"
FEATURE_NAME=$(head -1 "$SPEC_DIR/spec.md" | sed 's/^# Feature Specification: //')

# When working in a fork, target PRs against the upstream repository
REPO_FLAG=""
if git remote | grep -qx upstream 2>/dev/null; then
  UPSTREAM_REPO=$(git remote get-url upstream 2>/dev/null | sed 's|.*github\.com[:/]||; s|\.git$||')
  [ -n "$UPSTREAM_REPO" ] && REPO_FLAG="--repo $UPSTREAM_REPO"
fi

REVIEWERS_REL="$SPEC_DIR/REVIEWERS.md"
REVIEWERS_LINK=""
if [ -f "$REVIEWERS_REL" ]; then
  REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
  REVIEWERS_URL="${REMOTE_URL}/blob/${BRANCH}/${REVIEWERS_REL}"
  REVIEWERS_LINK="> **[Review Guide](${REVIEWERS_URL})** for full context: motivation, key decisions, and scope boundaries."
fi

COLLAB_CONFIG=".specify/extensions/spex-collab/collab-config.yml"
LABELS_ENABLED=$(yq -r '.labels.enabled // true' "$COLLAB_CONFIG" 2>/dev/null || echo "true")
IMPL_LABEL=$(yq -r '.labels.implement // "spex/implement"' "$COLLAB_CONFIG" 2>/dev/null || echo "spex/implement")
LABEL_FLAG=""
if [ "$LABELS_ENABLED" = "true" ]; then
  LABEL_FLAG="--label ${IMPL_LABEL}"
fi

# Exclude brainstorm files from the PR branch.
# Brainstorms belong on main, not in feature PRs.
BRAINSTORM_FILES=$(git diff "$DEFAULT_BRANCH"..."$BRANCH" --name-only | grep '^brainstorm/' || true)
if [ -n "$BRAINSTORM_FILES" ]; then
  git reset HEAD -- brainstorm/ >/dev/null 2>&1 || true
  git checkout -- brainstorm/ >/dev/null 2>&1 || true
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "chore: exclude brainstorm files from PR branch

Assisted-By: 🤖 Claude Code"
  fi
fi

git push -u "$REMOTE" "$BRANCH"

gh pr create ${REPO_FLAG} \
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

If the label doesn't exist in the repo, `gh pr create --label` will fail. In that case, retry without the label and warn:
```
Warning: Label "${IMPL_LABEL}" not found in this repo. PR created without label.
To create it: gh label create "${IMPL_LABEL}" --color 0e8a16 --description "Implementation PR"
Or disable labels: set labels.enabled to false in .specify/extensions/spex-collab/collab-config.yml
```

After PR creation, capture the PR number and URL:
```bash
ACTION_TAKEN="pr"
PR_URL=$(gh pr view "$BRANCH" --json url -q '.url' 2>/dev/null || true)
PR_NUMBER=$(gh pr view "$BRANCH" --json number -q '.number' 2>/dev/null || true)
```

Report the PR URL.

If in a worktree, also report: "Run `/speckit-spex-finish` again after the PR is merged to merge and clean up the worktree."

### Option C: Keep Branch

```bash
ACTION_TAKEN="keep"
```

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

After executing any option (merge, PR, or keep), handle the state file. If watch mode is active AND a PR was created or pushed to (Options B1 or B2), skip cleanup and proceed to Phase 7 instead. Otherwise, remove the state file immediately.

**Watch mode guard**: If `WATCH_MODE` is true but no PR was involved (Option A merge or Option C keep), warn and skip watch mode:
```bash
if [ "$WATCH_MODE" = true ] && [ "$ACTION_TAKEN" != "pr" ]; then
  echo "Watch mode requires a PR. Ignoring --watch."
  WATCH_MODE=false
fi
```

**Also check `gh` availability for watch mode**:
```bash
if [ "$WATCH_MODE" = true ] && ! command -v gh >/dev/null 2>&1; then
  echo "Watch mode requires the gh CLI. Falling back to normal finish."
  WATCH_MODE=false
fi
```

If `WATCH_MODE` is true and a PR exists (`ACTION_TAKEN` is `"pr"`), skip cleanup and proceed to Phase 7.

Otherwise, clean up normally. Skip if already cleaned during worktree removal (Option A sets `STATE_CLEANED=true`):

```bash
if [ "${STATE_CLEANED:-false}" != "true" ]; then
  rm -f .specify/.spex-state
  if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ]; then
    rm -f "$SHIP_STATE_FILE"
  fi
fi
```

This removes the state file, which dismisses the status line (the statusline script exits silently when no state file exists). Works for both ship mode (where `SHIP_STATE_FILE` may point to a worktree path) and flow mode (where the state file is always relative). In the worktree merge path, cleanup happens before the worktree directory is deleted to avoid ENOENT errors.

**After cleanup (when watch mode is NOT active), execute after_finish hooks, then the command is complete.**

## Post-Completion Hooks

**Check for extension hooks (after finish)**:

This section runs after Phase 6 cleanup completes, but only when watch mode is NOT active. When watch mode IS active (`WATCH_MODE` is true and `ACTION_TAKEN` is `"pr"`), skip this section entirely; the after_finish hooks fire during the watch cleanup paths instead (after watch mode exits in Phase 7).

- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.after_finish` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- Convert hook command names from dot notation to hyphen notation for slash command invocation (e.g., `speckit.spex.flow-state` becomes `/speckit-spex-flow-state`)
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`) in interactive mode:
    ```
    ## Extension Hooks

    **Optional Post-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Optional hook** (`optional: true`) in autonomous mode (`ask` is `smart` or `never`):
    Treat as mandatory (auto-execute without prompting).
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Post-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

**After post-completion hooks execute (or are skipped), the command is complete. STOP here.**

## Phase 7: Watch Mode (Post-PR Monitoring Loop)

This phase only executes when `WATCH_MODE` is true and a PR was created or pushed to.

### Step 1: Initialize Watch State

Locate the state script and create the watch state:

```bash
SHIP_STATE="$(find ~/.claude -name 'spex-ship-state.sh' 2>/dev/null | head -1)"

# PR_NUMBER and PR_URL come from Option B1 (existing PR) or B2 (newly created PR)
"$SHIP_STATE" watch-start \
  --pr-number "$PR_NUMBER" \
  --pr-url "$PR_URL" \
  --timeout "$WATCH_TIMEOUT" \
  --interval "$WATCH_INTERVAL"
```

Where `PR_NUMBER` is set during Option B1 (`EXISTING_PR_NUMBER`) or Option B2 (extracted from `gh pr create` output), and `PR_URL` is the corresponding URL.

### Step 2: Initial CI Wait

CI checks may not appear immediately after push. Wait up to 5 polling cycles for checks to appear:

```bash
INITIAL_WAIT_POLLS=0
MAX_INITIAL_POLLS=5
while [ "$INITIAL_WAIT_POLLS" -lt "$MAX_INITIAL_POLLS" ]; do
  CHECK_OUTPUT=$(gh pr checks "$PR_NUMBER" 2>&1 || true)
  if [ -n "$CHECK_OUTPUT" ] && ! echo "$CHECK_OUTPUT" | grep -q "no checks"; then
    break
  fi
  INITIAL_WAIT_POLLS=$((INITIAL_WAIT_POLLS + 1))
  if [ "$INITIAL_WAIT_POLLS" -ge "$MAX_INITIAL_POLLS" ]; then
    echo "No CI checks detected after 5 minutes. Exiting watch mode."
    "$SHIP_STATE" watch-cleanup
    exit 0
  fi
  sleep "$WATCH_INTERVAL"
done
```

### Step 3: Watch Loop

Each iteration of the watch loop performs these checks in order:

```
LOOP:
  (a) Check timeout
  (b) Check PR state (closed/merged externally)
  (c) Poll CI status
  (d) If all checks pass → check for review comments → possibly exit
  (e) If checks failing → attempt fix
  (f) Schedule next poll
```

#### (a) Timeout Check

```bash
WATCH_STATE=$(cat .specify/.spex-state 2>/dev/null)
STARTED_AT=$(echo "$WATCH_STATE" | jq -r '.watch_started_at')
TIMEOUT_MIN=$(echo "$WATCH_STATE" | jq -r '.watch_timeout_minutes')

# Calculate elapsed time
NOW_EPOCH=$(date -u +%s)
STARTED_EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null || date -u -d "$STARTED_AT" +%s 2>/dev/null)
ELAPSED_SEC=$((NOW_EPOCH - STARTED_EPOCH))
TIMEOUT_SEC=$((TIMEOUT_MIN * 60))

if [ "$ELAPSED_SEC" -ge "$TIMEOUT_SEC" ]; then
  FINAL_CI=$(gh pr checks "$PR_NUMBER" 2>&1 || true)
  echo "Watch timeout reached (${TIMEOUT_MIN}m). Final CI status:"
  echo "$FINAL_CI"
  "$SHIP_STATE" watch-cleanup
  # STOP - timeout reached
fi
```

#### (b) PR State Check

```bash
PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
if [ "$PR_STATE" = "CLOSED" ] || [ "$PR_STATE" = "MERGED" ]; then
  echo "PR #$PR_NUMBER has been ${PR_STATE,,} externally. Exiting watch mode."
  "$SHIP_STATE" watch-cleanup
  # STOP - PR no longer active
fi
```

#### (c) CI Status Poll

```bash
CHECK_OUTPUT=$(gh pr checks "$PR_NUMBER" 2>&1 || true)
"$SHIP_STATE" watch-update last_ci_check_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Determine overall CI status
if echo "$CHECK_OUTPUT" | grep -qi "fail\|error"; then
  CI_STATUS="failing"
elif echo "$CHECK_OUTPUT" | grep -qi "pending\|queued\|in_progress\|waiting"; then
  CI_STATUS="pending"
elif echo "$CHECK_OUTPUT" | grep -qi "pass\|success"; then
  CI_STATUS="passing"
else
  CI_STATUS="pending"
fi

"$SHIP_STATE" watch-update last_ci_status "$CI_STATUS"
```

#### (d) All Checks Passing

When `CI_STATUS` is `"passing"`:

1. Check if spex-collab is enabled:
   ```bash
   COLLAB_ENABLED=$(jq -r '.extensions["spex-collab"].enabled // false' .specify/extensions/.registry 2>/dev/null)
   ```

2. **If spex-collab is enabled**: Check for new review comments since last triage:
   ```bash
   LAST_TRIAGE=$(echo "$WATCH_STATE" | jq -r '.last_triage_at // empty')
   REPO_INFO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)

   if [ -n "$LAST_TRIAGE" ]; then
     NEW_COMMENTS=$(gh api "repos/$REPO_INFO/pulls/$PR_NUMBER/comments" --jq "[.[] | select(.created_at > \"$LAST_TRIAGE\")] | length" 2>/dev/null || echo "0")
     NEW_REVIEW_COMMENTS=$(gh api "repos/$REPO_INFO/pulls/$PR_NUMBER/reviews" --jq "[.[] | select(.submitted_at > \"$LAST_TRIAGE\" and .state != \"APPROVED\")] | length" 2>/dev/null || echo "0")
   else
     NEW_COMMENTS=$(gh api "repos/$REPO_INFO/pulls/$PR_NUMBER/comments" --jq 'length' 2>/dev/null || echo "0")
     NEW_REVIEW_COMMENTS=$(gh api "repos/$REPO_INFO/pulls/$PR_NUMBER/reviews" --jq '[.[] | select(.state != "APPROVED")] | length' 2>/dev/null || echo "0")
   fi

   TOTAL_NEW=$((NEW_COMMENTS + NEW_REVIEW_COMMENTS))
   ```

   If `TOTAL_NEW` > 0: Invoke `/speckit-spex-collab-triage --pr $PR_NUMBER`. The triage command inherits the current `ask` level from the ship pipeline state to control triage autonomy. After triage completes, update state:
   ```bash
   "$SHIP_STATE" watch-update last_triage_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   CURRENT_TRIAGE=$(echo "$WATCH_STATE" | jq -r '.triage_count // 0')
   "$SHIP_STATE" watch-update triage_count "$((CURRENT_TRIAGE + 1))"
   ```
   Then continue the loop (schedule next poll).

   If `TOTAL_NEW` is 0: CI passing and no new comments. Watch is complete:
   ```bash
   echo "CI passing, no pending review comments. Watch complete."
   echo "PR: $PR_URL"
   "$SHIP_STATE" watch-cleanup
   # STOP - success
   ```

3. **If spex-collab is NOT enabled**: Check for review comments but do not triage:
   ```bash
   COMMENT_COUNT=$(gh api "repos/$REPO_INFO/pulls/$PR_NUMBER/comments" --jq 'length' 2>/dev/null || echo "0")
   REVIEW_COUNT=$(gh api "repos/$REPO_INFO/pulls/$PR_NUMBER/reviews" --jq '[.[] | select(.state != "APPROVED")] | length' 2>/dev/null || echo "0")
   TOTAL_COMMENTS=$((COMMENT_COUNT + REVIEW_COUNT))

   if [ "$TOTAL_COMMENTS" -gt 0 ]; then
     echo "CI passing. $TOTAL_COMMENTS review comment(s) found but spex-collab is not enabled."
     echo "Enable spex-collab for automated comment triage: specify extension enable spex-collab"
   fi

   echo "CI passing. Watch complete."
   echo "PR: $PR_URL"
   "$SHIP_STATE" watch-cleanup
   # STOP - success (without triage)
   ```

#### (e) CI Failing

When `CI_STATUS` is `"failing"`:

1. Read current fix attempts:
   ```bash
   FIX_ATTEMPTS=$(echo "$WATCH_STATE" | jq -r '.ci_fix_attempts // 0')
   ```

2. If `FIX_ATTEMPTS` >= 2: Pause and report:
   ```bash
   echo "CI has failed after 2 fix attempts. Manual intervention required."
   echo "Failing checks:"
   gh pr checks "$PR_NUMBER" 2>&1 | grep -i "fail\|error" || true
   echo ""
   echo "PR: $PR_URL"
   "$SHIP_STATE" watch-cleanup
   # STOP - unresolvable failure
   ```

3. If `FIX_ATTEMPTS` < 2: Attempt a fix:
   - Get the failing run ID: `gh pr checks "$PR_NUMBER" --json name,state,detailsUrl --jq '.[] | select(.state == "FAILURE") | .detailsUrl' 2>/dev/null`
   - Extract the run ID from the URL and read the failure log: `gh run view <RUN_ID> --log-failed 2>/dev/null`
   - Scope the fix to files in the PR diff: `gh pr diff "$PR_NUMBER" --name-only 2>/dev/null`
   - Attempt to fix the issue based on the failure log, restricted to the PR's changed files
   - If a fix is made, commit and push:
     ```bash
     git add -u
     git commit -m "fix: address CI failure (watch mode attempt $((FIX_ATTEMPTS + 1)))

     Assisted-By: 🤖 Claude Code"
     REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
     git push "$REMOTE" "$(git branch --show-current)"
     ```
   - Update fix attempts: `"$SHIP_STATE" watch-update ci_fix_attempts "$((FIX_ATTEMPTS + 1))"`
   - Continue the loop (schedule next poll)

#### (f) CI Pending

When `CI_STATUS` is `"pending"`: No action needed. Schedule next poll.

#### Schedule Next Poll

At the end of each iteration (unless the loop exited), wait for the configured interval before the next iteration:

```bash
sleep "$WATCH_INTERVAL"
# Then go back to LOOP
```

The watch loop continues until one of the exit conditions is met: success, timeout, PR closed/merged, or unresolvable failure.
