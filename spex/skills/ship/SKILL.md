---
name: ship
description: Autonomous full-cycle workflow - chains specify through verify with configurable oversight levels, auto-fix, and optional PR creation
argument-hint: "[brainstorm-file] [--ask always|smart|never] [--resume] [--start-from <stage>] [--create-pr] [--no-external] [--[no-]coderabbit] [--[no-]copilot]"
---

# Autonomous Full-Cycle Workflow (spex:ship)

## CONTINUOUS EXECUTION RULE (READ THIS FIRST)

**This pipeline runs ALL stages without stopping.** After completing any stage, you MUST immediately begin the next stage. There are no natural stopping points between stages.

- Do NOT say "Ready for the next stage" and wait.
- Do NOT say "Shall I proceed?" and wait.
- Do NOT say "Proceeding to..." and wait.
- Do NOT treat a stage completion as a task completion.
- Do NOT output a summary and stop.

The pipeline is ONE continuous task. It starts at the first stage and runs through the last stage. The ONLY reasons to pause are:
1. `ask` is `always` AND a review stage has findings requiring user input.
2. A blocker error occurs (test failure, syntax error, security issue).
3. All 9 stages have completed.

**After every stage: update the state file, then immediately start the next stage.** No waiting, no confirmation, no stopping.

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

The following stage names are accepted: `specify`, `clarify`, `review-spec`, `plan`, `tasks`, `review-plan`, `implement`, `review-code`, `verify`.

If an invalid stage name is provided, fail with:
```
ERROR: Invalid stage "X". Valid stages are: specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code, verify
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

The state file is created during Pipeline Initialization (see above). At each stage transition, update it by running:

```bash
cat > .specify/.spex-ship-phase << STATEEOF
{
  "stage": "<current-stage-name>",
  "stage_index": <0-8>,
  "total_stages": 9,
  "ask": "<ask-level>",
  "started_at": "<original-started_at-value>",
  "retries": <0-2>,
  "status": "<running|paused|completed|failed>",
  "brainstorm_file": "<brainstorm-path>",
  "feature_branch": "$(git branch --show-current)"
}
STATEEOF
```

Update the state file at each transition:
- **When a stage finishes and the next stage begins**: Set `stage` to the NEXT stage name, `stage_index` to the NEXT stage's index, `status` to `running`, `retries` to 0. **Do NOT set status to `completed` for individual stages.** Simply advance to the next stage.
- **When pausing for user input**: Set `status` to `paused`.
- **When resuming**: Set `status` back to `running`.
- **When ALL 9 stages have finished** (pipeline done): Set `status` to `completed`, then delete the state file.
- **On failure**: Set `status` to `failed`, leave the state file in place.

**IMPORTANT:** The `completed` status means the ENTIRE PIPELINE is done, not that a single stage finished. When stage 1 (clarify) finishes, you write stage 2 (review-spec) with status `running`. You never write stage 1 with status `completed`.

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
   - Stages `tasks` and later need `plan.md`
   - Stages `review-plan` and later need `plan.md` and `tasks.md`
   - Stages `implement` and later need `tasks.md`

3. If expected artifacts are missing, **warn** (do not fail):
   ```
   WARNING: Starting from stage "implement" but tasks.md was not found.
   The implement stage may fail if required artifacts are missing.
   Proceeding anyway...
   ```

4. Create a fresh state file with the starting stage and begin execution.

5. The brainstorm file is not needed when starting from a stage after `specify`. If starting from `specify`, a brainstorm file is required (auto-detect or fail).

## Pipeline Discipline (MANDATORY)

**These rules are non-negotiable. They override any judgment about efficiency or convenience.**

### Rule 1: Every stage runs, in order, no exceptions

When starting a fresh pipeline (no `--start-from`, no `--resume`), you MUST execute ALL 9 stages in sequence: specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code, verify.

You MUST NOT:
- Skip a stage because its output artifact already exists
- Skip a stage because you believe its output would be trivial
- Skip a stage because a previous conversation already produced its artifact
- Merge two stages into one (e.g., running plan and tasks together)
- Reorder stages for any reason

### Rule 2: Fresh start means fresh artifacts

When running from stage 0 (specify), the pipeline creates all artifacts from scratch. If `spec.md`, `plan.md`, or `tasks.md` already exist from a prior run, they are overwritten by the new pipeline run. Do NOT reuse artifacts from previous runs unless resuming with `--resume` or explicitly starting later with `--start-from`.

### Rule 3: Only `--start-from` and `--resume` allow skipping

These are the ONLY two mechanisms for starting at a stage other than specify:
- `--start-from <stage>`: User's explicit choice to skip prior stages. The user takes responsibility for ensuring prior artifacts exist and are valid.
- `--resume`: Continues from where a previous run was interrupted, using the state file.

If neither flag is set, the pipeline starts at stage 0 and runs through stage 8. No automatic detection of "oh, we can skip ahead because artifacts exist."

### Rule 4: Stage gate validation

Before executing each stage, verify that:
1. The previous stage's state file entry shows it completed (stage_index is one less than current, or this is the first stage)
2. The state file status was updated to `running` for the current stage

If a stage fails or is interrupted, the pipeline MUST NOT silently proceed to the next stage. It must either pause (for findings), fail (for errors), or retry (within the 2-retry limit).

### Rule 5: No implicit intelligence

Do NOT apply "smart" behavior to the pipeline flow itself:
- Do NOT decide that a brainstorm file is "clear enough" to skip clarify
- Do NOT decide that a spec is "simple enough" to skip review-spec
- Do NOT decide that implementation is "straightforward enough" to skip review-code
- Do NOT skip verify because all prior reviews passed

The `--ask` flag controls oversight within review stages (how findings are handled). It does NOT control which stages run. ALL stages run regardless of the ask level.

## Pipeline Initialization (BLOCKING - DO THIS FIRST)

**You MUST complete these steps before invoking ANY speckit command or skill.** Do not skip ahead to stage execution.

### Step 1: Create the state file

Run this Bash command immediately. Replace the placeholder values with resolved arguments:

```bash
cat > .specify/.spex-ship-phase << STATEEOF
{
  "stage": "$([ -n "$START_FROM" ] && echo "$START_FROM" || echo "specify")",
  "stage_index": $([ -n "$START_FROM_INDEX" ] && echo "$START_FROM_INDEX" || echo "0"),
  "total_stages": 9,
  "ask": "${ASK_LEVEL:-smart}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "retries": 0,
  "status": "running",
  "brainstorm_file": "${BRAINSTORM_FILE}",
  "feature_branch": "$(git branch --show-current)"
}
STATEEOF
```

### Step 2: Verify the state file exists

```bash
[ -f .specify/.spex-ship-phase ] && echo "STATE_FILE_OK" || echo "STATE_FILE_MISSING"
```

If `STATE_FILE_MISSING`: **STOP**. Something went wrong. Do not proceed to any pipeline stage.

### Step 3: Announce pipeline start

Output a brief status message confirming the pipeline configuration before running any stage:

```
## spex:ship starting

- **Brainstorm**: <file>
- **Starting stage**: <stage> (<index>/9)
- **Oversight**: <ask-level>
- **State file**: .specify/.spex-ship-phase (created)
```

Only after all three steps complete successfully, proceed to Pipeline Stages below.

## Pipeline Stages

The pipeline executes 9 stages in fixed order:

| Index | Stage | Invocation | Description |
|-------|-------|------------|-------------|
| 0 | `specify` | `/speckit.specify` | Generate spec from brainstorm |
| 1 | `clarify` | `/speckit.clarify` | Resolve spec ambiguities |
| 2 | `review-spec` | `{Skill: spex:review-spec}` | Validate spec quality |
| 3 | `plan` | `/speckit.plan` | Generate implementation plan |
| 4 | `tasks` | `/speckit.tasks` | Generate task breakdown |
| 5 | `review-plan` | `{Skill: spex:review-plan}` | Validate plan, tasks, and generate REVIEWERS.md |
| 6 | `implement` | `/speckit.implement` | Execute implementation |
| 7 | `review-code` | `{Skill: spex:review-code}` | Spec compliance + code review + deep review + REVIEWERS.md update |
| 8 | `verify` | `{Skill: spex:verification-before-completion}` | Final verification |

### Suppressing trait overlay gates

When running inside the ship pipeline, **no `/speckit.*` command may pause for user input unless the `ask` level is `always`**. This overrides any instruction in the speckit command prompts themselves. Specifically:

- **`speckit.specify`**: Do not ask "Shall I proceed?" after spec creation. Proceed to the next stage.
- **`speckit.clarify`**: Do not present questions interactively in `smart` or `never` mode. Auto-select recommended answers.
- **`speckit.plan`**: Do not ask for confirmation before or after planning. Proceed to the next stage.
- **`speckit.tasks`**: Do not ask for confirmation. Proceed to the next stage.
- **`speckit.implement`**: Do not pause at trait overlay gates. Proceed to the next stage.

Trait overlays (e.g., `superpowers` adding review after specify) may run their reviews, but their results are informational. Do NOT pause or ask the user before proceeding. The ship pipeline's own stage gate logic handles all oversight decisions.

**This is a hard override. If a speckit command prompt says "present to user" or "wait for answer", and `ask` is `smart` or `never`, you answer it yourself and continue.**

### Stage 0: Specify (ALWAYS runs unless --start-from or --resume skips it)

**Even if spec.md already exists**, this stage re-creates it from the brainstorm document. A fresh pipeline means fresh artifacts.

1. Read the brainstorm document content.
2. Update state file: `stage: "specify"`, `stage_index: 0`, `status: "running"`.
3. Invoke `/speckit.specify` passing the brainstorm content as the feature description.
   - The brainstorm content provides the problem statement, approaches considered, and decisions made.
   - Pass it as the user input to the specify command.
   - **Do not pause** after specify completes, even if a trait overlay runs a review or asks for confirmation. Proceed directly to step 4.
4. After specify completes, extract the feature branch name from the git branch:
   ```bash
   FEATURE_BRANCH=$(git branch --show-current)
   ```
5. Update state file with `feature_branch`.
6. **Immediately** begin Stage 1 (do not stop).

**Worktree compatibility:** The `worktrees` trait is NOT recommended with `spex:ship`. The worktrees overlay creates a sibling worktree during specify, which requires restarting the Claude Code session in the new directory, breaking the autonomous pipeline. Ship works best by creating a feature branch in-place. If you want main isolation, create a worktree manually before starting ship:
```bash
git worktree add ../project-wip main
cd ../project-wip && claude
# then: /spex:ship brainstorm/NNN-feature.md
```

### Stage 1: Clarify (ALWAYS runs, even if the spec "looks clear")

Do NOT skip this stage. Clarify may uncover ambiguities that are not obvious from reading the spec.

1. Update state file: `stage: "clarify"`, `stage_index: 1`.
2. Read the `ask` level from the state file (default: `smart`).
3. **BEFORE invoking clarify**, determine the interaction mode:
   - If `ask` is `smart` or `never`: You are the decision-maker. Do NOT use `AskUserQuestion` or present options to the user. When the clarify process identifies ambiguities, YOU select the recommended option for each question. If no recommendation exists, use your best judgment based on the spec context. Answer all questions yourself, then encode the answers into the spec.
   - If `ask` is `always`: Present each question to the user interactively.

4. Invoke `/speckit.clarify` on the generated spec. **The clarify command will try to present interactive questions. In `smart` and `never` modes, this is overridden: answer every question yourself with the recommended option. Do NOT wait for user input. Do NOT display questions with "You can reply with..." prompts. Process all questions in a single pass and update the spec.**
5. After clarification completes, **immediately** begin Stage 2 (do not stop).

### Stage 2: Review Spec (ALWAYS runs, even if spec passed clarify without changes)

Do NOT skip this stage. Review-spec validates structural quality, not just ambiguities.

1. Update state file: `stage: "review-spec"`, `stage_index: 2`.
2. Invoke `{Skill: spex:review-spec}` to validate spec quality.
3. Capture the review findings and overall assessment.
4. Apply **Oversight Decision Logic** (see below) to handle findings.
5. After findings are resolved (or pipeline pauses), **immediately** begin Stage 3 (do not stop).

### Stage 3: Plan

1. Update state file: `stage: "plan"`, `stage_index: 3`.
2. Invoke `/speckit.plan` to generate the implementation plan.
3. This produces `plan.md`, `research.md`, `data-model.md`, and other artifacts.
4. After plan generation completes, **immediately** begin Stage 4 (do not stop).

### Stage 4: Tasks

1. Update state file: `stage: "tasks"`, `stage_index: 4`.
2. Invoke `/speckit.tasks` to generate the task breakdown.
3. This produces `tasks.md`.
4. After task generation completes, **immediately** begin Stage 5 (do not stop).

### Stage 5: Review Plan

1. Update state file: `stage: "review-plan"`, `stage_index: 5`.
2. Invoke `{Skill: spex:review-plan}` to validate plan coverage and task quality.
3. This requires both `plan.md` and `tasks.md` (generated in stages 3 and 4).
4. This generates `REVIEWERS.md`.
5. Capture findings and apply **Oversight Decision Logic**.
6. After findings are resolved, **immediately** begin Stage 6 (do not stop).

### Stage 6: Implement

1. Update state file: `stage: "implement"`, `stage_index: 6`.
2. Invoke `/speckit.implement` to execute the implementation plan.
3. This is typically the longest stage. Implementation follows the task plan.
4. After implementation completes, **immediately** begin Stage 7 (do not stop).

### Stage 7: Review Code

1. Update state file: `stage: "review-code"`, `stage_index: 7`.
2. Invoke `{Skill: spex:review-code}`.
3. This skill runs the full review chain:
   a. Spec compliance check (compliance score and deviation list)
   b. Code Review Guide appended to REVIEWERS.md
   c. Deep review (if trait enabled): 5 review agents, fix loop, Deep Review Report appended to REVIEWERS.md
4. Apply **Oversight Decision Logic** to any remaining findings.
5. After findings are resolved, **immediately** begin Stage 8 (do not stop).

### Stage 8: Verify

1. Update state file: `stage: "verify"`, `stage_index: 8`.
2. Invoke `{Skill: spex:verification-before-completion}` for final verification.
3. This runs tests, validates spec compliance, and checks for drift.
4. If verification passes, **immediately** proceed to Pipeline Completion (do not stop).
5. If verification fails, apply **Oversight Decision Logic**.

## Oversight Decision Logic

After each review stage (review-spec, review-plan, review-code, verify), evaluate the findings:

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
Pipeline paused after 2 fix cycles for stage "review-code".
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
  4. tasks      - tasks.md generated
  5. review-plan - plan validated, REVIEWERS.md generated
  6. implement  - code implemented
  7. review-code - code reviewed, REVIEWERS.md updated
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
- `/speckit.tasks` (Stage 4)
- `{Skill: spex:review-plan}` (Stage 5)
- `/speckit.implement` (Stage 6)
- `{Skill: spex:review-code}` (Stage 7)
- `{Skill: spex:verification-before-completion}` (Stage 8)

**Required traits:** `superpowers`, `deep-review`
**Not recommended:** `worktrees` trait (creates a session restart mid-pipeline; use manual worktree setup instead)
