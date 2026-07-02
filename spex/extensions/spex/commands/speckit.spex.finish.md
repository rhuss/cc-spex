---
description: "Smoke test + squash + merge/keep (land the code on main)"
argument-hint: "[--no-smoke-test]"
---

# Finish - Smoke Test, Squash, and Land the Code

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:

```bash
AUTONOMOUS_MODE=false
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  ASK=$(jq -r '.ask // "always"' .specify/.spex-state 2>/dev/null)
  if [ "$STATUS" = "running" ] && [ "$ASK" != "always" ]; then
    AUTONOMOUS_MODE=true
  fi
fi
```

In autonomous mode: suppress all interactive prompts, UNLESS running inside a worktree (`IN_WORKTREE` is true, detected in Phase 2). When in a worktree, always present the user with the action prompt (Phase 4) regardless of autonomous mode. Never auto-merge or auto-delete a worktree.

## Argument Parsing

Parse the following flags from arguments:

- If `--no-smoke-test` is passed, set `SKIP_SMOKE_TEST=true`. This bypasses the smoke test gate unconditionally.

```bash
SKIP_SMOKE_TEST=false
for arg in "$@"; do
  case "$arg" in
    --no-smoke-test) SKIP_SMOKE_TEST=true ;;
  esac
done
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

    Wait for the result of the hook command before proceeding to Phase 1.
    ```
  - If a mandatory hook fails or is declined by the user, STOP. Output an error message indicating which hook failed and do NOT proceed to Phase 1.
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Step 0: Resolve Plugin Root

Extract the plugin root path from the `<plugin-root>` tag in the `<spex-context>` system reminder. All script references below use this path:

```bash
SHIP_STATE_SCRIPT="<PLUGIN_ROOT>/scripts/spex-ship-state.sh"
FINISH_CONTEXT="<PLUGIN_ROOT>/scripts/spex-finish-context.sh"
```

Replace `<PLUGIN_ROOT>` with the actual path from the system reminder.

## Phase 1: Smoke Test Gate

This phase checks whether a smoke test has been run and is current, then decides whether to run one before proceeding.

### Step 1: Check for `--no-smoke-test` flag

```bash
if [ "$SKIP_SMOKE_TEST" = true ]; then
  echo "Smoke test skipped (--no-smoke-test flag)."
  # Proceed to Phase 2
fi
```

### Step 2: Read smoke test state

```bash
SHIP_STATE_SCRIPT="<PLUGIN_ROOT>/scripts/spex-ship-state.sh"
SMOKE_COMPLETED=false
SMOKE_COMMIT_HASH=""

if [ -f ".specify/.spex-state" ]; then
  SMOKE_COMPLETED=$(jq -r '.smoke_test_completed // false' .specify/.spex-state 2>/dev/null)
  SMOKE_COMMIT_HASH=$(jq -r '.smoke_test_commit_hash // empty' .specify/.spex-state 2>/dev/null)
fi
```

### Step 3: Evaluate smoke test freshness

**If smoke test passed and HEAD matches recorded commit hash:** Skip with message.
```bash
CURRENT_HEAD=$(git rev-parse HEAD)
if [ "$SMOKE_COMPLETED" = "true" ] && [ "$SMOKE_COMMIT_HASH" = "$CURRENT_HEAD" ]; then
  echo "Smoke test previously passed at this commit. Skipping."
  # Proceed to Phase 2
fi
```

**If smoke test passed but HEAD differs from recorded hash:** Warn about staleness.
```bash
if [ "$SMOKE_COMPLETED" = "true" ] && [ "$SMOKE_COMMIT_HASH" != "$CURRENT_HEAD" ]; then
  COMMITS_SINCE=$(git rev-list --count "$SMOKE_COMMIT_HASH"..HEAD 2>/dev/null || echo "unknown")
  echo "WARNING: Smoke test passed at commit ${SMOKE_COMMIT_HASH:0:8} but $COMMITS_SINCE commit(s) added since."
fi
```

Present the user with a choice:
- **"Re-run smoke test"**: Invoke `/speckit-spex-smoke-test`, then record result with current HEAD
- **"Skip and proceed"**: Continue without re-running

In autonomous mode: skip the stale smoke test (proceed without re-running).

**If smoke test never run:** Invoke `/speckit-spex-smoke-test` interactively.

After the smoke test completes, record the result with the current commit hash:
```bash
CURRENT_HEAD=$(git rev-parse HEAD)
"$SHIP_STATE_SCRIPT" smoke-test-record \
  --completed true \
  --scenarios "$SCENARIO_COUNT" \
  --total "$TOTAL_COUNT" \
  --skipped "$SKIPPED_COUNT" \
  --commit-hash "$CURRENT_HEAD"
```

If the smoke test fails (any scenario does not pass), STOP. The user must fix issues and re-run `/speckit-spex-finish`.

## Phase 2: Context Detection

Detect the current environment by running the context detection script:

```bash
FINISH_CONTEXT="<PLUGIN_ROOT>/scripts/spex-finish-context.sh"
CTX=$("$FINISH_CONTEXT")
```

Parse the JSON output to extract context variables:

- `IN_WORKTREE`: boolean, whether the current directory is a git worktree
- `CURRENT_BRANCH`: the current branch name
- `DEFAULT_BRANCH`: the default branch (main/master)
- `MAIN_WORKTREE`: path to the main worktree (only set when `IN_WORKTREE` is true)
- `EXISTING_PR_NUMBER`: PR number if one exists for this branch (empty if none)
- `EXISTING_PR_URL`: PR URL if one exists

**If already on the default branch:** Report "You are already on the default branch; no merge needed." Clean up state file (`rm -f .specify/.spex-state`). STOP.

## Phase 3: Squash Commits

Squash all feature branch commits into a single commit with a conventional commit message.

### Step 1: Commit outstanding changes

```bash
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: final changes before finish

Assisted-By: 🤖 Claude Code"
fi
```

### Step 2: Compute merge base and commit count

```bash
MERGE_BASE=$(git merge-base "$DEFAULT_BRANCH" HEAD)
COMMIT_COUNT=$(git rev-list --count "$MERGE_BASE"..HEAD)
```

### Step 3: Single commit — skip squash

If `COMMIT_COUNT` is 1, skip the squash step entirely. The branch already has a single commit.

### Step 4: Generate conventional commit message

Read context to generate the message:
- The spec's feature name and key requirements from `specs/<branch>/spec.md`
- The git diff summary: `git diff --stat "$MERGE_BASE"..HEAD`
- The list of changed files to determine scope

**Type detection heuristic:**
- If spec title contains "fix" or brainstorm was about a bug: `fix`
- If spec involves refactoring existing code: `refactor`
- If spec adds documentation: `docs`
- Default: `feat`

**Scope** is derived from the primary directory of change (e.g., `extensions`, `scripts`, `docs`).

**Message format:**
```
<type>(<scope>): <description>

<body summarizing spec and key changes>

Assisted-By: 🤖 Claude Code
```

### Step 5: Present message to user for approval

Present the generated commit message to the user. They can:
- **Approve as-is**: Proceed with squash
- **Edit**: Modify the message before squashing

In autonomous mode: use the generated message without prompting.

### Step 6: Execute squash

```bash
git reset --soft "$MERGE_BASE"
git commit -m "$COMMIT_MESSAGE"
```

### Step 7: Force-push

```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
git push --force-with-lease "$REMOTE" "$CURRENT_BRANCH"
```

If force-push fails (e.g., branch protection), report the error:
```
ERROR: Force-push failed. Check branch protection settings.
The branch has been squashed locally but the remote was not updated.
```

## Phase 4: Select Action

**Worktree override:** When `IN_WORKTREE` is true, ALWAYS present the prompt below regardless of autonomous mode. Worktrees are never auto-merged or auto-deleted.

If `AUTONOMOUS_MODE` is true AND `IN_WORKTREE` is false: skip the prompt and go directly to **Option A: Merge to default branch**.

Present options to the user (single-select, header: "Finish"):

**"Code is squashed and ready. How would you like to land it?"**

1. **If `EXISTING_PR_NUMBER` is set:** **"Merge PR #${EXISTING_PR_NUMBER}"**: "Merge the pull request via gh"
   **Otherwise:** **"Merge to default branch"**: "Fast-forward merge into the default branch, clean up branch and worktree"
2. **"Keep branch as-is"**: "Leave branch for manual handling later"

## Phase 5: Execute Action

### Option A: Merge to Default Branch (no PR)

**If in a worktree (`IN_WORKTREE` is true):**

Use `MAIN_WORKTREE` and `REPO_ROOT` (as `WORKTREE_PATH`) from the Phase 2 context detection output.

```bash
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
cd "$WORKTREE_PATH"
UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -v -E '^\?\? \.specify/' || true)
if [ -n "$UNCOMMITTED" ]; then
  echo "WARNING: Worktree has uncommitted changes that would be lost:"
  echo "$UNCOMMITTED"
  git add -A
  git commit -m "chore: rescue uncommitted files before worktree removal

Assisted-By: 🤖 Claude Code"
  cd "$MAIN_WORKTREE"
  git merge --ff-only "$CURRENT_BRANCH" 2>&1 || git merge "$CURRENT_BRANCH" -m "Merge rescued commit from '$CURRENT_BRANCH'

Assisted-By: 🤖 Claude Code" 2>&1
fi
cd "$MAIN_WORKTREE"
```

Then clean up state files in BOTH locations:
```bash
rm -f "$WORKTREE_PATH/.specify/.spex-state"
rm -f "$MAIN_WORKTREE/.specify/.spex-state"
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

### Option B: Merge PR

When `EXISTING_PR_NUMBER` is set and the user selected "Merge PR #...":

```bash
MERGE_OUTPUT=$(gh pr merge "$EXISTING_PR_NUMBER" --squash --delete-branch 2>&1)
MERGE_EXIT=$?
```

**IMPORTANT**: `gh pr merge --squash` can succeed server-side (PR merged on GitHub) but return a non-zero exit code because the local fast-forward failed (e.g., local main has diverged due to brainstorm commits). Always check the actual PR state before assuming failure:

```bash
if [ "$MERGE_EXIT" -ne 0 ]; then
  # Check if the PR was actually merged despite the non-zero exit
  PR_STATE=$(gh pr view "$EXISTING_PR_NUMBER" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")
  if [ "$PR_STATE" = "MERGED" ]; then
    echo "PR #$EXISTING_PR_NUMBER merged successfully on GitHub."
    echo "Local sync: pulling latest main..."
    git checkout "$DEFAULT_BRANCH" 2>/dev/null
    git pull --rebase origin "$DEFAULT_BRANCH" 2>/dev/null || git pull origin "$DEFAULT_BRANCH" 2>/dev/null
    MERGE_EXIT=0
  fi
fi
```

If the PR is genuinely not merged (`PR_STATE` is not `MERGED`):
```
PR merge failed. This may be due to:
- Required reviews not yet approved
- Required CI checks not passing
- Branch protection rules

The branch is squashed and force-pushed. An upstream maintainer can merge it,
or you can wait for required checks and re-run /speckit-spex-finish.
```

```bash
ACTION_TAKEN="pr-merge"
```

If merge succeeds (either directly or detected via state check), sync local main and handle worktree cleanup (same prompt-before-cleanup pattern as Option A).

### Option C: Keep Branch

```bash
ACTION_TAKEN="keep"
```

Report based on context:

If in a worktree:
```
Branch <branch> is squashed and ready. Nothing was merged.

When ready to land:
  /speckit-spex-finish    Run again to merge
```

If NOT in a worktree:
```
Branch <branch> is squashed and ready. Nothing was merged.

When ready to land:
  /speckit-spex-finish    Run again to merge
```

## Phase 6: State and Status Line Cleanup

After executing any option, handle the state file. Skip if already cleaned during worktree removal (Option A sets `STATE_CLEANED=true`):

```bash
if [ "${STATE_CLEANED:-false}" != "true" ]; then
  rm -f .specify/.spex-state
  if [ -n "${SHIP_STATE_FILE:-}" ] && [ -f "$SHIP_STATE_FILE" ]; then
    rm -f "$SHIP_STATE_FILE"
  fi
fi
```

This removes the state file, which dismisses the status line.

## Post-Completion Hooks

**Check for extension hooks (after finish)**:

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
