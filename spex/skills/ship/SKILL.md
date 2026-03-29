---
name: ship
description: Autonomous full-cycle workflow - chains specify through verify with configurable oversight levels, auto-fix, and optional PR creation
argument-hint: "[brainstorm-file] [--ask cautious|balanced|autopilot] [--resume] [--start-from <stage>] [--create-pr] [--no-external] [--[no-]coderabbit] [--[no-]copilot]"
---

# Autonomous Full-Cycle Workflow (spex:ship)

## Overview

This skill chains the entire spex workflow autonomously: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, and verify. Point it at a brainstorm document and choose an oversight level to control how much human oversight the pipeline requires.

**This skill requires both `superpowers` and `deep-review` traits to be enabled.**

## Prerequisites

### Trait Validation

Check that required traits are enabled:

```bash
SUPERPOWERS=$(jq -r '.traits.superpowers // false' .specify/spex-traits.json 2>/dev/null)
DEEP_REVIEW=$(jq -r '.traits["deep-review"] // false' .specify/spex-traits.json 2>/dev/null)

if [ "$SUPERPOWERS" != "true" ] || [ "$DEEP_REVIEW" != "true" ]; then
  echo "ERROR: spex:ship requires both superpowers and deep-review traits."
  echo ""
  echo "Enable them with:"
  echo "  /spex:traits enable superpowers deep-review"
  echo ""
  echo "Missing traits:"
  [ "$SUPERPOWERS" != "true" ] && echo "  - superpowers"
  [ "$DEEP_REVIEW" != "true" ] && echo "  - deep-review"
fi
```

If either trait is missing, **STOP** with the error message above. Do not proceed.

### Dirty Worktree Check

Before starting the pipeline, verify the working tree is clean:

```bash
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "ERROR: Working tree has uncommitted changes."
  echo ""
  echo "Please commit or stash your changes before running spex:ship:"
  echo "  git stash"
  echo "  # or"
  echo "  git add -A && git commit -m 'WIP: save before ship'"
fi
```

If the worktree is dirty, **STOP** with the error message. Do not proceed.

### External Tool Auth Validation

If `--coderabbit` is explicitly set (not just inherited from config defaults), validate authentication at startup:

```bash
# Only check if --coderabbit was explicitly passed as a flag
which coderabbit >/dev/null 2>&1 && coderabbit auth status 2>&1 || echo "CODERABBIT_AUTH_FAILED"
```

If auth check fails when CodeRabbit was explicitly requested, **STOP** with:
```
ERROR: CodeRabbit authentication failed.
You explicitly requested CodeRabbit with --coderabbit, but auth is not configured.
Run without --coderabbit or configure CodeRabbit authentication first.
```

If CodeRabbit is only enabled via config defaults (not explicit flag), skip auth validation and let the deep-review stage handle missing tools gracefully.

## Argument Parsing

Parse the invocation arguments. The skill accepts:

### Positional Argument

- **brainstorm-file**: Path to a brainstorm document in `brainstorm/`. If omitted, auto-detect (see Brainstorm File Resolution below).

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--ask <level>` | `smart` | One of: `always`, `smart`, `never` |
| `--create-pr` | off | Create a pull request after successful completion |
| `--resume` | off | Resume an interrupted pipeline from state file |
| `--start-from <stage>` | (none) | Start from a specific stage (skips prior stages) |
| `--no-external` | (from config) | Disable all external review tools |
| `--external` | (from config) | Enable all external review tools |
| `--no-coderabbit` | (from config) | Disable CodeRabbit |
| `--coderabbit` | (from config) | Enable CodeRabbit |
| `--no-copilot` | (from config) | Disable Copilot |
| `--copilot` | (from config) | Enable Copilot |

### Flag Resolution

**Oversight level**: Validate that the value is one of `always`, `smart`, `never`. If invalid, fail with:
```
ERROR: Invalid oversight level "X". Must be one of: always, smart, never
```

**External tool flags**: Follow the same resolution pattern as the `review-code` skill:

1. Read config defaults:
   ```bash
   DEFAULT_ENABLED=$(jq -r '.external_tools.enabled // true' .specify/spex-traits.json 2>/dev/null)
   DEFAULT_CODERABBIT=$(jq -r '.external_tools.coderabbit // true' .specify/spex-traits.json 2>/dev/null)
   DEFAULT_COPILOT=$(jq -r '.external_tools.copilot // true' .specify/spex-traits.json 2>/dev/null)
   ```

2. Start with config defaults:
   ```
   coderabbit = DEFAULT_ENABLED && DEFAULT_CODERABBIT
   copilot    = DEFAULT_ENABLED && DEFAULT_COPILOT
   ```

3. Apply CLI flag overrides (flags always win, applied in order):
   - `--external` sets both to true
   - `--no-external` sets both to false
   - `--coderabbit` / `--no-coderabbit` overrides coderabbit only
   - `--copilot` / `--no-copilot` overrides copilot only

4. Track whether `--coderabbit` was explicitly set (for auth validation).

**`--resume` and `--start-from` are mutually exclusive** with each other. If both are provided, fail with:
```
ERROR: Cannot use both --resume and --start-from. Choose one.
```

**`--resume` does not accept a brainstorm file.** If `--resume` is set alongside a brainstorm file, fail with:
```
ERROR: Cannot specify a brainstorm file with --resume. The brainstorm file is read from the state file.
```

**`--start-from` allows a brainstorm file** when starting from `specify` (since it needs one). When starting from any other stage, a brainstorm file argument is ignored.

### Valid Stage Names for --start-from

The following stage names are accepted: `specify`, `clarify`, `review-spec`, `plan`, `review-plan`, `tasks`, `implement`, `deep-review`, `verify`.

If an invalid stage name is provided, fail with:
```
ERROR: Invalid stage "X". Valid stages are: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify
```

## Brainstorm File Resolution

Resolve the brainstorm document to use as input:

**If a path is provided**: Validate it exists.
```bash
[ -f "$BRAINSTORM_FILE" ] || echo "ERROR: Brainstorm file not found: $BRAINSTORM_FILE"
```

**If no path is provided**: Auto-detect the highest-numbered brainstorm file:
```bash
ls -1 brainstorm/[0-9]*.md 2>/dev/null | sort -t/ -k2 -V | tail -1
```

**If no brainstorm files found**: Fail with:
```
ERROR: No brainstorm files found in brainstorm/ directory.

Available files:
$(ls brainstorm/ 2>/dev/null || echo "  (directory does not exist)")

Create a brainstorm document first with /spex:brainstorm
```

## State File Management

The pipeline tracks its progress in `.specify/.spex-ship-phase` as JSON.

### Writing State

At each stage transition, write the state file:

```bash
# Write to temp file first, then atomic rename
cat > .specify/.spex-ship-phase.tmp << 'STATEEOF'
{
  "stage": "<current-stage-name>",
  "stage_index": <0-8>,
  "total_stages": 9,
  "ask": "<cautious|balanced|autopilot>",
  "started_at": "<ISO-8601 timestamp from pipeline start>",
  "retries": <0-2>,
  "status": "<running|paused|completed|failed>",
  "brainstorm_file": "<path-to-brainstorm-doc>",
  "feature_branch": "<branch-name-or-null>"
}
STATEEOF
mv .specify/.spex-ship-phase.tmp .specify/.spex-ship-phase
```

Write the state file:
- **Before each stage begins**: Set `stage` to the new stage name, `stage_index` to its position, `status` to `running`, `retries` to 0.
- **When pausing for user input**: Set `status` to `paused`.
- **When resuming**: Set `status` back to `running`.
- **On completion**: Set `status` to `completed`, then delete the state file.
- **On failure**: Set `status` to `failed`, leave the state file in place.

The `feature_branch` field is set after the specify stage completes (it may be null during the specify stage itself).

### Cleanup

On successful completion, remove the state file:
```bash
rm -f .specify/.spex-ship-phase
```

On failure or interruption, leave the state file in place so `--resume` can use it.

## Resume Logic

When `--resume` is set:

1. Read the state file:
   ```bash
   if [ ! -f .specify/.spex-ship-phase ]; then
     echo "ERROR: No interrupted pipeline found."
     echo "Start a new pipeline with: /spex:ship <brainstorm-file>"
     exit 1
   fi
   STATE=$(cat .specify/.spex-ship-phase)
   ```

2. Extract the last stage and its index:
   ```bash
   LAST_STAGE=$(echo "$STATE" | jq -r '.stage')
   LAST_INDEX=$(echo "$STATE" | jq -r '.stage_index')
   AUTONOMY=$(echo "$STATE" | jq -r '.ask')
   BRAINSTORM=$(echo "$STATE" | jq -r '.brainstorm_file')
   ```

3. Check the `status` field to determine resume behavior:
   - If `status` is `"paused"` or `"failed"`: resume from `LAST_INDEX` (retry the same stage).
   - If `status` is `"running"`: resume from `LAST_INDEX` (the stage was interrupted mid-execution).
   - If `status` is `"completed"`: report that the pipeline already completed and clean up the state file.

4. If the calculated resume index is >= 9, the pipeline was already complete. Report this and clean up.

5. Reset `retries` to 0 in the state file before resuming (so the resumed stage gets fresh retry attempts).

6. Re-validate values from the state file before proceeding:
   - Validate `ask` is one of `always`, `smart`, `never`
   - Validate `brainstorm_file` exists (if resuming the specify stage)
   - Validate `stage_index` is in range 0-8

7. Update the state file with `status: running` before proceeding.

## Start-From Logic

When `--start-from <stage>` is set:

1. Map the stage name to its index (0-8).

2. Verify that expected artifacts exist for stages that depend on prior output:
   - Stages `clarify` and later need `spec.md` to exist
   - Stages `plan` and later need `spec.md`
   - Stages `review-plan` and later need `plan.md`
   - Stages `implement` and later need `tasks.md`

3. If expected artifacts are missing, **warn** (do not fail):
   ```
   WARNING: Starting from stage "implement" but tasks.md was not found.
   The implement stage may fail if required artifacts are missing.
   Proceeding anyway...
   ```

4. Create a fresh state file with the starting stage and begin execution.

5. The brainstorm file is not needed when starting from a stage after `specify`. If starting from `specify`, a brainstorm file is required (auto-detect or fail).

## Pipeline Stages

The pipeline executes 9 stages in fixed order:

| Index | Stage | Invocation | Description |
|-------|-------|------------|-------------|
| 0 | `specify` | `/speckit.specify` | Generate spec from brainstorm |
| 1 | `clarify` | `/speckit.clarify` | Resolve spec ambiguities |
| 2 | `review-spec` | `{Skill: spex:review-spec}` | Validate spec quality |
| 3 | `plan` | `/speckit.plan` | Generate implementation plan |
| 4 | `review-plan` | `{Skill: spex:review-plan}` | Validate plan and tasks |
| 5 | `tasks` | `/speckit.tasks` | Generate task breakdown |
| 6 | `implement` | `/speckit.implement` | Execute implementation |
| 7 | `deep-review` | `{Skill: spex:deep-review}` | Multi-perspective code review |
| 8 | `verify` | `{Skill: spex:verification-before-completion}` | Final verification |

### Stage 0: Specify

1. Read the brainstorm document content.
2. Update state file: `stage: "specify"`, `stage_index: 0`, `status: "running"`.
3. Invoke `/speckit.specify` passing the brainstorm content as the feature description.
   - The brainstorm content provides the problem statement, approaches considered, and decisions made.
   - Pass it as the user input to the specify command.
4. After specify completes, extract the feature branch name from the git branch:
   ```bash
   FEATURE_BRANCH=$(git branch --show-current)
   ```
5. Update state file with `feature_branch`.
6. Proceed to Stage 1.

**Worktree integration**: If the `worktrees` trait is enabled, the specify command's overlay will create a worktree automatically. The session will be in the worktree after this stage. All subsequent stages run inside the worktree without any special handling by ship.

### Stage 1: Clarify

1. Update state file: `stage: "clarify"`, `stage_index: 1`.
2. Invoke `/speckit.clarify` on the generated spec.
3. The clarify command will ask up to 5 questions to resolve ambiguities.
4. **Oversight interaction**: In `never` mode, accept recommended answers automatically. In `smart` mode, accept recommended answers. In `always` mode, present each question to the user.
5. After clarification completes, proceed to Stage 2.

### Stage 2: Review Spec

1. Update state file: `stage: "review-spec"`, `stage_index: 2`.
2. Invoke `{Skill: spex:review-spec}` to validate spec quality.
3. Capture the review findings and overall assessment.
4. Apply **Oversight Decision Logic** (see below) to handle findings.
5. After findings are resolved (or pipeline pauses), proceed to Stage 3.

### Stage 3: Plan

1. Update state file: `stage: "plan"`, `stage_index: 3`.
2. Invoke `/speckit.plan` to generate the implementation plan.
3. This produces `plan.md`, `research.md`, `data-model.md`, and other artifacts.
4. After plan generation completes, proceed to Stage 4.

### Stage 4: Review Plan

1. Update state file: `stage: "review-plan"`, `stage_index: 4`.
2. Invoke `{Skill: spex:review-plan}` to validate plan coverage and task quality.
3. This generates `REVIEWERS.md`.
4. Capture findings and apply **Oversight Decision Logic**.
5. After findings are resolved, proceed to Stage 5.

### Stage 5: Tasks

1. Update state file: `stage: "tasks"`, `stage_index: 5`.
2. Invoke `/speckit.tasks` to generate the task breakdown.
3. This produces `tasks.md`.
4. After task generation completes, proceed to Stage 6.

### Stage 6: Implement

1. Update state file: `stage: "implement"`, `stage_index: 6`.
2. Invoke `/speckit.implement` to execute the implementation plan.
3. This is typically the longest stage. Implementation follows the task plan.
4. After implementation completes, proceed to Stage 7.

### Stage 7: Deep Review

1. Update state file: `stage: "deep-review"`, `stage_index: 7`.
2. Invoke `{Skill: spex:deep-review}` with the resolved external tool settings:
   - Pass `coderabbit: true/false` and `copilot: true/false` from flag resolution.
   - Pass spec path and feature directory.
   - Pass invocation context as `superpowers`.
3. The deep-review skill dispatches 5 review agents and runs the autonomous fix loop.
4. Apply **Oversight Decision Logic** to any remaining findings after the fix loop.
5. After findings are resolved, proceed to Stage 8.

### Stage 8: Verify

1. Update state file: `stage: "verify"`, `stage_index: 8`.
2. Invoke `{Skill: spex:verification-before-completion}` for final verification.
3. This runs tests, validates spec compliance, and checks for drift.
4. If verification passes, proceed to Pipeline Completion.
5. If verification fails, apply **Oversight Decision Logic**.

## Oversight Decision Logic

After each review stage (review-spec, review-plan, deep-review, verify), evaluate the findings:

### Finding Classification

Classify each finding into one of three categories:

**Unambiguous** (auto-fixable in `smart` and `never`):
- Formatting issues (indentation, whitespace, line length)
- Style violations (naming conventions, import ordering)
- Typos in comments or documentation
- Missing imports or unused variables
- Minor spec wording improvements

**Ambiguous** (requires judgment, pauses in `smart`):
- Architecture or design changes
- API contract modifications
- Requirement interpretation questions
- Performance vs. readability trade-offs
- Missing functionality that could be intentional
- Unclear whether a finding is a bug or a feature

**Blocker** (always pauses, even in `never`):
- Compilation errors or syntax errors
- Missing critical dependencies
- Failing tests that cannot be auto-resolved
- Contradictory requirements
- Security vulnerabilities
- Data loss risks

### Oversight Rules

| Oversight Level | Unambiguous | Ambiguous | Blocker |
|----------------|-------------|-----------|---------|
| `always` | Pause | Pause | Pause |
| `smart` | Auto-fix | Pause | Pause |
| `never` | Auto-fix | Auto-fix | Pause |

### Applying the Rules

1. After a review stage completes, collect all findings.
2. Classify each finding using the categories above.
3. Based on the oversight level:
   - **Auto-fix**: Apply the fix, increment retry count, re-run the review stage.
   - **Pause**: Present findings to user (see Pause and Resume below).
4. If no findings need attention, proceed to the next stage.

## Auto-Fix and Re-Run

When auto-fixing findings:

1. Apply fixes for all findings classified as auto-fixable under the current oversight level.
2. Increment `retries` in the state file.
3. Re-run the same review stage to verify fixes.
4. If new findings appear, classify and handle them.
5. **Max 2 retry cycles per stage.** After 2 retries with remaining findings, pause regardless of oversight level:

```
Pipeline paused after 2 fix cycles for stage "deep-review".
Remaining findings could not be auto-resolved.

[Present remaining findings here]

Please provide guidance on how to proceed.
```

6. Reset `retries` to 0 when moving to the next stage.

## Pause and Resume

### Pausing

When the pipeline pauses (due to findings that need human input):

1. Update state file: `status: "paused"`.
2. Present all findings that triggered the pause, grouped by severity:

```
## Pipeline Paused at Stage: review-spec

### Findings Requiring Your Input

**Ambiguous (need your judgment):**
1. [Finding description with context]
2. [Finding description with context]

**Blockers (must be resolved):**
1. [Finding description with context]

Please review these findings and provide guidance. You can:
- Address specific findings ("fix #1 by doing X")
- Skip findings ("skip #2, it's intentional")
- Provide general guidance ("proceed, these are acceptable")
```

3. Wait for user response.

### Resuming After User Input

After the user responds:

1. Update state file: `status: "running"`.
2. Apply any fixes the user requested.
3. If user said to skip findings, proceed to the next stage.
4. If user provided fixes, apply them and optionally re-run the review.
5. Continue the pipeline from the current stage.

## Pipeline Completion

After all stages complete successfully:

1. Update state file: `status: "completed"`.
2. Calculate elapsed time from `started_at`.
3. Report completion summary:

```
## Pipeline Complete

**Feature branch:** <branch-name>
**Stages completed:** 9/9
**Oversight mode:** <mode>
**Elapsed time:** <duration>

All stages passed successfully:
  0. specify    - spec.md created
  1. clarify    - spec clarified
  2. review-spec - spec validated
  3. plan       - plan.md generated
  4. review-plan - plan validated, REVIEWERS.md generated
  5. tasks      - tasks.md generated
  6. implement  - code implemented
  7. deep-review - code reviewed
  8. verify     - verification passed
```

4. Clean up: `rm -f .specify/.spex-ship-phase`

### PR Creation (if --create-pr)

If `--create-pr` is set and all stages passed:

1. Determine the remote target:
   ```bash
   REMOTE=$(git remote | grep -x upstream 2>/dev/null || echo origin)
   ```

2. Push the feature branch:
   ```bash
   git push -u "$REMOTE" "$(git branch --show-current)"
   ```

3. Create the PR. Identify the spec directory from the feature branch:
   ```bash
   BRANCH=$(git branch --show-current)
   SPEC_DIR="specs/${BRANCH}"
   FEATURE_NAME=$(head -1 "$SPEC_DIR/spec.md" | sed 's/^# Feature Specification: //')

   gh pr create \
     --title "$FEATURE_NAME" \
     --body "$(cat <<PREOF
   ## Summary

   Autonomous pipeline implementation of $FEATURE_NAME.

   See \`$SPEC_DIR/REVIEWERS.md\` for detailed review guidance.

   ## Artifacts

   - Spec: \`$SPEC_DIR/spec.md\`
   - Plan: \`$SPEC_DIR/plan.md\`
   - Tasks: \`$SPEC_DIR/tasks.md\`
   - Review Guide: \`$SPEC_DIR/REVIEWERS.md\`

   Generated by \`/spex:ship\` in $AUTONOMY mode.

   Assisted-By: Claude Code
   PREOF
   )"
   ```

4. Report the PR URL.

### No PR (default)

If `--create-pr` is not set:

```
Pipeline complete. No PR created (use --create-pr to auto-create).

Next steps:
  - Review changes: git diff main...HEAD
  - Create PR manually: gh pr create
  - Run additional reviews: /spex:review-code
```

## Integration

**This skill is invoked by:**
- Users directly via `/spex:ship`

**This skill invokes:**
- `/speckit.specify` (Stage 0)
- `/speckit.clarify` (Stage 1)
- `{Skill: spex:review-spec}` (Stage 2)
- `/speckit.plan` (Stage 3)
- `{Skill: spex:review-plan}` (Stage 4)
- `/speckit.tasks` (Stage 5)
- `/speckit.implement` (Stage 6)
- `{Skill: spex:deep-review}` (Stage 7)
- `{Skill: spex:verification-before-completion}` (Stage 8)

**Required traits:** `superpowers`, `deep-review`
**Optional trait integration:** `worktrees` (handled by specify overlay, no ship-specific logic)
