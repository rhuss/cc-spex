---
description: "Verify + walkthrough + squash + merge/keep (land the code on main)"
argument-hint: "[--auto] [--no-verify] [--no-walkthrough] [--skip-archive]"
---

# Finish - Verify, Walkthrough, Squash, and Land the Code

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:

```bash
AUTONOMOUS_MODE=false
if [ "$AUTO_MODE" = "true" ]; then
  AUTONOMOUS_MODE=true
elif [ -f ".specify/.spex-state" ]; then
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

- If `--auto` is passed, set `AUTO_MODE=true`. This suppresses all interactive prompts and uses defaults (same behavior as the ship pipeline's autonomous mode).
- If `--no-verify` is passed, set `SKIP_VERIFY=true`. This skips the verification phase (Phase 0) and prints a one-line note.
- If `--no-walkthrough` is passed, set `SKIP_WALKTHROUGH=true`. This bypasses the walkthrough gate unconditionally.
- If `--skip-archive` is passed, set `SKIP_ARCHIVE=true`. This skips the archive step when spex-detach is enabled.

```bash
AUTO_MODE=false
SKIP_VERIFY=false
SKIP_WALKTHROUGH=false
SKIP_ARCHIVE=false
for arg in "$@"; do
  case "$arg" in
    --auto) AUTO_MODE=true ;;
    --no-verify) SKIP_VERIFY=true ;;
    --no-walkthrough) SKIP_WALKTHROUGH=true ;;
    --skip-archive) SKIP_ARCHIVE=true ;;
  esac
done

# --auto always means unattended, even without ship state (the guard above
# may have run before AUTO_MODE was set).
[ "$AUTO_MODE" = true ] && AUTONOMOUS_MODE=true
```

## Phase 0: Verification

Verification is the first phase. It runs before the `before_finish` extension hooks (for example, the detach archive hook), the walkthrough gate, squash, archive, and any merge, PR, or keep action, so nothing acts on unverified code.

### Step 1: Resolve the feature directory

Resolve `FEATURE_DIR` once. Phase 1 and every later phase reuse this value instead of re-deriving it.

```bash
FEATURE_DIR=$(jq -r '.spec_dir // empty' .specify/.spex-state 2>/dev/null)
[ -n "$FEATURE_DIR" ] || FEATURE_DIR=$(jq -r '.feature_directory // empty' .specify/feature.json 2>/dev/null)
[ -n "$FEATURE_DIR" ] || FEATURE_DIR="specs/$(git rev-parse --abbrev-ref HEAD)"
FEATURE_DIR="${FEATURE_DIR%/}"

RECORD=".specify/extensions/spex/scripts/spex-verify-record.sh"
[ -f "$RECORD" ] || RECORD="spex/scripts/spex-verify-record.sh"

# Verify belongs to spex-gates, which may be disabled or not installed.
GATES_ENABLED=$(jq -r '.extensions["spex-gates"].enabled // false' .specify/extensions/.registry 2>/dev/null)
[ "$GATES_ENABLED" = "true" ] || GATES_ENABLED=false
```

### Step 2: Apply the verification table

Evaluate the rows top to bottom; the first matching row wins. Print the exact output shown.

| Condition | Output (exact first line) | Result |
|---|---|---|
| `SKIP_VERIFY` is true (`--no-verify`) | `Verification skipped (--no-verify).` | `VERIFY_RESULT=skipped-flag`, continue |
| `GATES_ENABLED` is not `true` (the `spex-gates` entry in `.specify/extensions/.registry` is missing or disabled) | `Verification skipped: spex-gates is not enabled.` | `VERIFY_RESULT=skipped-no-gates`, continue |
| `sh "$RECORD" check --feature "$FEATURE_DIR"` exits 0 (a pass is recorded for the current code state) | `Verification already passed for this code.` | `VERIFY_RESULT=already-verified`, continue (verify is not re-run) |
| `$FEATURE_DIR/spec.md` does not exist (`[ ! -f "$FEATURE_DIR/spec.md" ]`) and `AUTONOMOUS_MODE` is true | `Finish stopped: no spec found for verification.` then `Run /speckit-spex-finish --no-verify to land without verification.` | `VERIFY_RESULT=no-spec`, **stop** |
| `$FEATURE_DIR/spec.md` does not exist and the run is interactive | Invoke `/speckit-spex-gates-verify --embedded` without a spec path, so verify resolves the spec through its normal selection (including its picker); then apply the result rows below. If verify reports `NO_SPEC`, print the no-spec stop message from the row above and **stop**. | see the result rows |
| Invoke `/speckit-spex-gates-verify --embedded "$FEATURE_DIR/spec.md"` (append `--auto` when `AUTONOMOUS_MODE` is true); its gate result is PASS | `Verification passed.` | `VERIFY_RESULT=passed`, continue; set `VERIFY_RECORDED=false` when its result block has `warning: pass not recorded`, else `VERIFY_RECORDED=true` |
| Verify reports one or more failing gates (`VERIFY_RESULT` status `FAIL`) | the gate-failure stop message below | `VERIFY_RESULT=failed`, **stop** |
| Verify did not complete (status `ERROR`, it was interrupted, or it produced no clear PASS or FAIL); a verify `NO_SPEC` result uses the no-spec row above | `Finish stopped: verification did not complete.` then the error on one line, then `To land without verification: /speckit-spex-finish --no-verify` | `VERIFY_RESULT=incomplete`, **stop** |

Pass the spec path explicitly, as shown, so verify checks and records exactly the `FEATURE_DIR` that finish resolved. When verify selected the spec itself (interactive row above), set `FEATURE_DIR` to the `feature` that verify reports in its `VERIFY_RESULT` block, so later phases use the verified spec. Pass `--auto` to verify whenever `AUTONOMOUS_MODE` is true, so verify also runs without prompts (it would otherwise detect unattended mode only from `.specify/.spex-state`, not from finish's own `--auto`). `--embedded` keeps `.specify/.spex-state` in place and suppresses verify's completion banner; finish owns state cleanup (Phase 6). Verify records the pass for the current code state itself; finish never writes the record.

**Gate-failure stop message** (exact shape; one line per failing gate, using the gate names verify reports: `closeout`, `tests`, `code hygiene`, `spec compliance`, `spec drift`, `success criteria`):

```text
Finish stopped: verification did not pass.
  - <gate name>: <one-line reason>
  - <gate name>: <one-line reason>
Fix the issues and rerun /speckit-spex-finish, or reconcile the spec with /speckit-spex-evolve.
To land without verification: /speckit-spex-finish --no-verify
```

**On any stop row**: STOP immediately. Do not run the `before_finish` hooks or any later phase. Nothing is squashed or committed, no branch is switched, no worktree is changed or removed, and `.specify/.spex-state` is left untouched. There is no "continue anyway" option in any mode.

**Unattended mode** (`AUTONOMOUS_MODE` true, from the Ship Pipeline Guard): apply the same table without any prompt. Stop rows still stop; finish never continues to squash or merge after a failed or incomplete verification.

Only `VERIFY_RESULT` values `skipped-flag`, `skipped-no-gates`, `already-verified`, and `passed` let finish continue to the `before_finish` hooks and Phase 1.

The recorded pass is tied to the code state, not the session: it survives `/clear` and new sessions, and any change outside `specs/` and `brainstorm/` (committed or not) invalidates it, so the record check fails and verify runs again. Committing already-verified content (including finish's own commit in Phase 3) keeps it valid.

`--no-verify` combines freely with `--no-walkthrough`, `--auto`, and `--skip-archive`; each skipped phase prints its own note.

## Pre-Execution Checks

**Check for extension hooks (before finish)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_finish` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- Convert hook command names from dot notation to hyphen notation for slash command invocation (e.g., `speckit.spex.walkthrough` becomes `/speckit-spex-walkthrough`)
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

## Phase 1: Walkthrough Gate

This phase checks whether a walkthrough has been run and is current, then decides whether to run one before proceeding. The walkthrough is advisory: a FAIL is recorded but does not hard-block finishing (the reviewer decides).

### Step 1: Check for `--no-walkthrough` flag

```bash
if [ "$SKIP_WALKTHROUGH" = true ]; then
  echo "Walkthrough skipped (--no-walkthrough flag)."
  # Proceed to Phase 2
fi
```

### Step 2: Read runbook status

Use the `FEATURE_DIR` resolved in Phase 0 Step 1 (do not re-derive it).

```bash
STATUS=".specify/extensions/spex/scripts/spex-runbook-status.sh"
[ -f "$STATUS" ] || STATUS="spex/scripts/spex-runbook-status.sh"

SHOW=$("$STATUS" show "$FEATURE_DIR")
WT_STATUS=$(printf '%s' "$SHOW" | jq -r '.status // "missing"')
WT_EXISTS=$(printf '%s' "$SHOW" | jq -r '.exists')
WT_CURRENT=$(printf '%s' "$SHOW" | jq -r '.current')
WT_TESTED_AT=$(printf '%s' "$SHOW" | jq -r '.tested_at // empty')
```

When `WT_EXISTS` is `false` and `WT_STATUS` is not `not_testable`, treat the runbook as **missing**.

### Step 3: Apply the finish gate (FR-033, FR-033a)

The walkthrough is advisory (FR-033): a recorded FAIL never hard-blocks finishing. Apply the table below using `WT_STATUS`, `WT_CURRENT`, and `AUTONOMOUS_MODE` (from the Ship Pipeline Guard). `--no-walkthrough` has already skipped this phase.

| `show` status | Interactive | Unattended (`AUTONOMOUS_MODE` true) |
|---|---|---|
| `passed`, `current: true` | Print "Walkthrough passed at `$WT_TESTED_AT`." Proceed. | Same. |
| `passed`, `current: false` | List `changed_files` and offer **rerun** (`/speckit-spex-walkthrough`) or **continue**. | Print the status and continue. |
| `in_progress` | Offer **resume** (`/speckit-spex-walkthrough`) or **continue**. | Print the status and continue. |
| `failed` | Show the failed step and offer **continue** or **stop**. | Print the status and continue. |
| `drafted` | Offer **run now** (`/speckit-spex-walkthrough`), **later**, or **skip and mark done**. | Print the status and continue. |
| `stale` | The spec changed after the walkthrough ran (spec 059 FR-031). Show `stale_reason` from `show` and offer **rerun** (`/speckit-spex-walkthrough`, refreshing the steps that touch the changed IDs) or **continue**. | Print the status and the reason, and continue. |
| `not_testable` | Nothing to try by hand. Proceed. | Proceed. |
| `unreadable` | Report it and offer **rerun** or **continue**. | Print the status and continue. |
| missing | Run `/speckit-spex-walkthrough` (full session). | Run `/speckit-spex-walkthrough --draft` (draft only, no prompts). |

**Skip and mark done (drafted row).** When the user picks **skip and mark done**, the walkthrough is consciously dismissed instead of left as an unfinished draft: mark every runbook step as `skipped` so the runbook records the decision (the status line then shows all steps skipped) and the gate resolves.

```bash
RUNBOOK=$(printf '%s' "$SHOW" | jq -r '.path')
STEPS=$(printf '%s' "$SHOW" | jq -r '.steps.total')
i=1
while [ "$i" -le "$STEPS" ]; do
  "$STATUS" step "$RUNBOOK" "$i" skipped >/dev/null
  i=$((i + 1))
done
```

After any walkthrough invocation or skip-and-mark-done marking returns, re-read `"$STATUS" show "$FEATURE_DIR"` so later steps see the updated status, then proceed to Phase 2.

## Phase 2: Context Detection

Detect the current environment by running the context detection script:

```bash
FINISH_CONTEXT=".specify/extensions/spex/scripts/spex-finish-context.sh"
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

### Step 0: Re-check verification before staging

The `before_finish` hooks and the walkthrough (Phase 1) run after Phase 0 and may change code (for example a fix made during the walkthrough). Before anything is staged, confirm the verified pass still covers the current code. Skip this step when `VERIFY_RESULT` is `skipped-flag` or `skipped-no-gates`, and when verify reported PASS with `warning: pass not recorded` (`VERIFY_RECORDED=false`: there is no record to compare against, and verification already ran in this finish).

```bash
RECHECK=skip
if { [ "$VERIFY_RESULT" = passed ] || [ "$VERIFY_RESULT" = already-verified ]; } \
   && [ "${VERIFY_RECORDED:-true}" != false ]; then
  sh "$RECORD" check --feature "$FEATURE_DIR" >/dev/null 2>&1
  case $? in
    0) RECHECK=current ;;
    1) RECHECK=stale ;;
    *) RECHECK=unavailable ;;
  esac
fi
```

- `RECHECK=current` or `skip`: continue to Step 1.
- `RECHECK=unavailable` (the record check itself errored): print `Verification record unavailable; verifying again.` and continue as for `stale`.
- `RECHECK=stale`: print `Code changed after verification; verifying again.` and apply the Phase 0 Step 2 table again from the verify-invocation row onward (the `--no-verify`, spex-gates, and record rows do not apply here). A pass continues to Step 1. Any stop row stops finish with its exact stop message, before anything is staged or committed.

### Step 1: Commit outstanding changes

When Phase 0 passed, found a recorded pass, `--no-verify` was given, or spex-gates is not enabled (`VERIFY_RESULT` is `passed`, `already-verified`, `skipped-flag`, or `skipped-no-gates`), make this commit without stopping to confirm the pre-commit verification reminder. The reminder is advisory context; Phase 0 already settled verification for this run.

```bash
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: final changes before finish

Assisted-By: 🤖 Claude Code"
fi
```

### Step 1.5: Archive (when spex-detach is enabled)

Detect whether spex-detach is enabled:

```bash
# is-enabled checks the extension registry; the extension directory alone
# is not enough, since it stays on disk when the extension is disabled.
DETACH_ENABLED=false
DETACH_SCRIPT=".specify/extensions/spex-detach/scripts/spex-detach.sh"
if [ -x "$DETACH_SCRIPT" ] && "$DETACH_SCRIPT" is-enabled 2>/dev/null; then
  DETACH_ENABLED=true
fi
```

If `DETACH_ENABLED` is true, archive spec artifacts to the sibling specs repo (if configured). With stealth mode, spec files are excluded from git via `.git/info/exclude`, so no clean PR branch is needed.

```bash
DETACH_SCRIPT=".specify/extensions/spex-detach/scripts/spex-detach.sh"
DETACH_CONFIG=".specify/extensions/spex-detach/spex-detach-config.yml"
```

1. **Archive** (copy + commit to sibling repo):
   ```bash
   if [ "$SKIP_ARCHIVE" != "true" ]; then
     ARCHIVE_PATH=$(yq -r '.archive.path // empty' "$DETACH_CONFIG" 2>/dev/null)
     if [ -n "$ARCHIVE_PATH" ] && [ -d "$ARCHIVE_PATH" ]; then
       ARCHIVE_RESULT=$("$DETACH_SCRIPT" archive --include-brainstorm)
       if [ $? -eq 0 ]; then
         echo "Archive: specs copied to sibling repo"
       else
         echo "ERROR: Archive failed. Spec artifacts would be lost (excluded from git, not archived)."
         echo "Fix the archive target or re-run with --skip-archive to continue without archiving."
         # STOP: do not continue without archiving when stealth mode is active
       fi
     else
       echo "WARNING: archive.path not configured or not reachable, skipping archive"
     fi
   fi
   ```

### Step 2: Compute merge base and commit count

```bash
MERGE_BASE=$(git merge-base "$DEFAULT_BRANCH" HEAD)
COMMIT_COUNT=$(git rev-list --count "$MERGE_BASE"..HEAD)
```

### Step 3: Single commit, skip squash

If `COMMIT_COUNT` is 1, skip the squash step entirely. The branch already has a single commit.

### Step 4: Generate conventional commit message

Read context to generate the message:
- The spec's feature name and key requirements from `$FEATURE_DIR/spec.md` (resolved in Phase 0)
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

As in Step 1, finish's own squash commit does not stop to confirm the pre-commit verification reminder when Phase 0 passed, found a recorded pass, `--no-verify` was given, or spex-gates is not enabled. (The user's approval of the message in Step 5 is unchanged.)

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

{harness:interactive-choice} (single-select, header: "Finish"):

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

# Preserve spec artifacts back to the main checkout before removing the worktree.
# In detach mode the spec dir is git-excluded and exists only in the worktree, so
# nothing else copies it back; this guards against losing it (FR-039). No-op when
# detach is off.
PRESERVE=".specify/extensions/spex/scripts/spex-finish-preserve-specs.sh"
[ -f "$PRESERVE" ] || PRESERVE="spex/scripts/spex-finish-preserve-specs.sh"
# Use the Phase 0-resolved FEATURE_DIR (the spec dir finish actually operated on),
# not a re-derived specs/$CURRENT_BRANCH, so preservation never misses the dir when
# the spec directory name differs from the branch name.
"$PRESERVE" "$WORKTREE_PATH" "$MAIN_WORKTREE" "${FEATURE_DIR:-specs/$CURRENT_BRANCH}" || true

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

If merge succeeds, sync local main. **When in a worktree (`IN_WORKTREE` is true):** do NOT run `git checkout` (main is already checked out in the main worktree). Instead, switch to the main worktree first, then pull:

```bash
if [ "$IN_WORKTREE" = true ]; then
  cd "$MAIN_WORKTREE"
  git pull --rebase origin "$DEFAULT_BRANCH" 2>/dev/null || git pull origin "$DEFAULT_BRANCH" 2>/dev/null
else
  git checkout "$DEFAULT_BRANCH" 2>/dev/null
  git pull --rebase origin "$DEFAULT_BRANCH" 2>/dev/null || git pull origin "$DEFAULT_BRANCH" 2>/dev/null
fi
```

Then handle worktree cleanup (same prompt-before-cleanup pattern as Option A, including the spec-preservation step with `spex-finish-preserve-specs.sh` before any `git worktree remove`).

### Option C: Push Clean PR Branch

When `DETACH_PR_BRANCH` is set and the user selected "Push clean PR branch":

```bash
REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
git push "$REMOTE" "$DETACH_PR_BRANCH" 2>&1
PUSH_EXIT=$?
```

If push succeeds:
```
Pushed $DETACH_PR_BRANCH to $REMOTE. You can now create an upstream PR from this branch.
```

If push fails:
```
Push failed. You can push manually: git push <remote> $DETACH_PR_BRANCH
```

```bash
ACTION_TAKEN="push-pr-branch"
```

### Option D: Keep Branch

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
