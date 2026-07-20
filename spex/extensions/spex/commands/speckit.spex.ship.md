---
description: "Autonomous full-cycle workflow: specify through verify with configurable oversight levels, auto-fix, and optional PR creation"
---

# Autonomous Full-Cycle Workflow (speckit-spex-ship)

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
3. Stage 7 (review-code) completes: the pipeline is done and presents a completion prompt for the user to decide how to proceed (submit PR, merge directly, or stop).

**After every stage: update the state file, then immediately start the next stage.** No waiting, no confirmation, no stopping.

## Overview

This skill chains the entire spex workflow autonomously: specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, and verify. Point it at a brainstorm document and choose an oversight level to control how much human oversight the pipeline requires.

**This skill requires both `spex-gates` and `spex-deep-review` extensions to be enabled.**

## Prerequisites

### Extension Validation

Check that required extensions are enabled:

```bash
# Check for enabled extensions
GATES=$(specify extension list 2>/dev/null | grep -c 'spex-gates.*enabled' || echo 0)
DEEP_REVIEW=$(specify extension list 2>/dev/null | grep -c 'spex-deep-review.*enabled' || echo 0)

if [ "$GATES" = "0" ] || [ "$DEEP_REVIEW" = "0" ]; then
  echo "ERROR: speckit-spex-ship requires both spex-gates and spex-deep-review extensions."
  echo ""
  echo "Enable them with:"
  echo "  specify extension enable spex-gates && specify extension enable spex-deep-review"
  echo ""
  echo "Missing extensions:"
  [ "$GATES" = "0" ] && echo "  - spex-gates"
  [ "$DEEP_REVIEW" = "0" ] && echo "  - spex-deep-review"
fi
```

If either extension is missing, **STOP** with the error message above. Do not proceed.

### Dirty Worktree Check

Before starting the pipeline, check for uncommitted changes that are NOT spex configuration files:

```bash
# Filter out spex-generated files from dirty check
DIRTY=$(git status --porcelain 2>/dev/null | grep -v -E '^.{2} \.claude/(commands/speckit\.|settings)' | grep -v -E '^.{2} \.specify/(extensions/|\.spex-)' || true)
if [ -n "$DIRTY" ]; then
  echo "Working tree has uncommitted non-spex changes:"
  echo "$DIRTY"
fi
```

If there are dirty non-spex files, commit them automatically with a "WIP: save before ship" message, then proceed. Do NOT stop or ask the user. Spex config files (`.claude/skills/speckit-*`, `.claude/settings.*`, `.specify/extensions/`) are expected to be dirty after init and should be ignored.

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
| `--resume` | off | Resume an interrupted pipeline from state file |
| `--start-from <stage>` | (none) | Start from a specific stage (skips prior stages) |
| `--no-external` | (from config) | Disable all external review tools |
| `--external` | (from config) | Enable all external review tools |
| `--no-coderabbit` | (from config) | Disable CodeRabbit |
| `--coderabbit` | (from config) | Enable CodeRabbit |
| `--no-copilot` | (from config) | Disable Copilot |
| `--copilot` | (from config) | Enable Copilot |
| `--no-codex` | (from config) | Disable Codex |
| `--codex` | (from config) | Enable Codex |

### Flag Resolution

**Oversight level**: Validate that the value is one of `always`, `smart`, `never`. If invalid, fail with:
```
ERROR: Invalid oversight level "X". Must be one of: always, smart, never
```

**External tool flags**: Follow the same resolution pattern as the `review-code` skill:

1. Read config defaults from deep-review extension config:
   ```bash
   DEEP_REVIEW_CONFIG=".specify/extensions/spex-deep-review/deep-review-config.yml"
   DEFAULT_CODERABBIT=$(yq -r '.external_tools.coderabbit // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
   DEFAULT_CODERABBIT=${DEFAULT_CODERABBIT:-true}
   DEFAULT_COPILOT=$(yq -r '.external_tools.copilot // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
   DEFAULT_COPILOT=${DEFAULT_COPILOT:-true}
   DEFAULT_CODEX=$(yq -r '.external_tools.codex // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
   DEFAULT_CODEX=${DEFAULT_CODEX:-true}
   ```

2. Start with config defaults:
   ```
   coderabbit = DEFAULT_CODERABBIT
   copilot    = DEFAULT_COPILOT
   codex      = DEFAULT_CODEX
   ```

3. Apply CLI flag overrides (flags always win, applied in order):
   - `--external` sets all to true
   - `--no-external` sets all to false
   - `--coderabbit` / `--no-coderabbit` overrides coderabbit only
   - `--copilot` / `--no-copilot` overrides copilot only
   - `--codex` / `--no-codex` overrides codex only

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

The following stage names are accepted: `specify`, `clarify`, `review-spec`, `plan`, `tasks`, `review-plan`, `implement`, `review-code`.

If an invalid stage name is provided, fail with:
```
ERROR: Invalid stage "X". Valid stages are: specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code
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

Create a brainstorm document first with /speckit-spex-brainstorm
```

## State File Management

The pipeline tracks its progress in `.specify/.spex-state` as JSON. **All state file operations use the `spex-ship-state.sh` script. Never write the state file directly.**

Locate the script and set the absolute state file path:
```bash
SHIP_STATE=".specify/extensions/spex/scripts/spex-ship-state.sh"
# Use absolute path so state file location survives CWD changes (e.g., worktree switches)
export SHIP_STATE_FILE="$(pwd -P)/.specify/.spex-state"
```

**IMPORTANT:** Both `SHIP_STATE` (script path) and `SHIP_STATE_FILE` (absolute state file path) must be set before any state operations. The `SHIP_STATE_FILE` env var ensures the state script and statusline script always reference the same file, even when CWD changes during worktree creation.

### Available Commands

| Command | What it does |
|---------|-------------|
| `spex-ship-state.sh create <brainstorm> [--ask <level>] [--start-from <stage>]` | Create state file at pipeline start |
| `spex-ship-state.sh advance` | Advance to the next stage (auto-cleans up after stage 7) |
| `spex-ship-state.sh status` | Show current stage and status |
| `spex-ship-state.sh pause` | Set status to paused |
| `spex-ship-state.sh fail` | Set status to failed |
| `spex-ship-state.sh cleanup` | Remove state file (pipeline done) |

### Stage Transitions

**After every stage completes**, run:
```bash
SHIP_STATE_FILE="$SHIP_STATE_FILE" "$SHIP_STATE" advance
```

This advances `stage` and `stage_index` to the next stage with `status: running`. After the final stage (verify), `advance` automatically removes the state file and outputs `PIPELINE_COMPLETE`.

**Do NOT manually write JSON to the state file. Always use the script.**

### CWD Recovery After Subagents (Worktree Pipelines)

When the pipeline runs in a worktree, the shell CWD may be reset to the main repo directory after a subagent returns (Stages 2, 5, 6, 7 all use subagents). **After every subagent returns**, recover CWD using the worktree recovery script:

```bash
WORKTREE_CWD=".specify/extensions/spex/scripts/spex-worktree-cwd.sh"
RECOVERY_DIR=$("$WORKTREE_CWD")
[ -n "$RECOVERY_DIR" ] && cd "$RECOVERY_DIR"
```

The script uses `SHIP_STATE_FILE` (set as an absolute path during initialization) to find the worktree root. It is safe to call unconditionally; it outputs nothing when CWD is already correct or when not in a worktree.

## Ship Pipeline Guard

The `.specify/.spex-state` file serves as a signal to sub-commands running inside the pipeline. When this file exists with `status: running`, each `/speckit-*` command MUST:

- Complete its work normally
- Do NOT output a completion summary
- Do NOT ask "Shall I proceed?" or similar
- Do NOT prompt the user interactively (unless `ask` is `always`)
- Return immediately so the pipeline can advance

### speckit-specify guard

When `.specify/.spex-state` exists with `status: running`:
- Complete the specification work normally
- Do NOT ask "Shall I proceed?" after spec creation
- Return immediately so the pipeline can advance

### speckit-clarify guard

When `.specify/.spex-state` exists with `status: running`:
- If `ask` is `smart` or `never`: Do NOT present clarification questions to the user. Select the recommended answer for each question yourself. Process all questions in a single pass and update the spec.
- Do NOT output a completion summary
- Return immediately so the pipeline can advance

### speckit-plan guard

When `.specify/.spex-state` exists with `status: running`:
- Complete the planning work normally
- Do NOT ask "Shall I proceed?" or "Ready for implementation."
- Return immediately so the pipeline can advance

### speckit-tasks guard

When `.specify/.spex-state` exists with `status: running`:
- Complete the task generation normally
- Do NOT ask "Shall I proceed?" or suggest next steps
- Return immediately so the pipeline can advance

### speckit-implement guard

When `.specify/.spex-state` exists with `status: running`:
- Complete the implementation work normally
- Do NOT output a completion summary
- Do NOT ask "Shall I proceed?" or suggest next steps
- Return immediately so the pipeline can advance

## Resume Logic

When `--resume` is set:

1. Read the state file:
   ```bash
   if [ ! -f .specify/.spex-state ]; then
     echo "ERROR: No interrupted pipeline found."
     echo "Start a new pipeline with: /speckit-spex-ship <brainstorm-file>"
     exit 1
   fi
   STATE=$(cat .specify/.spex-state)
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
   - Validate `stage_index` is in range 0-7

7. Update the state file with `status: running` before proceeding.

## Start-From Logic

When `--start-from <stage>` is set:

1. Map the stage name to its index (0-7).

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

When starting a fresh pipeline (no `--start-from`, no `--resume`), you MUST execute ALL 8 stages in sequence: specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code.

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

If neither flag is set, the pipeline starts at stage 0 and runs through stage 7. No automatic detection of "oh, we can skip ahead because artifacts exist."

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

### Step 1: Locate the state script

```bash
SHIP_STATE=".specify/extensions/spex/scripts/spex-ship-state.sh"
[ -x "$SHIP_STATE" ] && echo "SCRIPT_OK: $SHIP_STATE" || echo "SCRIPT_MISSING"
```

If `SCRIPT_MISSING`: **STOP**. The spex extension may not be installed correctly. Run `specify extension add spex` to install it.

### Step 2: Create the state file

```bash
"$SHIP_STATE" create "<brainstorm-file>" --ask "<ask-level>" --start-from "<start-stage>"
```

The output will confirm: `CREATED stage=<stage> index=<N> ask=<level>`. If it fails, **STOP**.

### Step 3: Announce pipeline start

Output a brief status message confirming the pipeline configuration before running any stage:

```
## speckit-spex-ship starting

- **Brainstorm**: <file>
- **Starting stage**: <stage> (<index>/9)
- **Oversight**: <ask-level>
- **State file**: .specify/.spex-state (created)
```

Only after all three steps complete successfully, proceed to Pipeline Stages below.

## Pipeline Stages

The pipeline executes 8 stages in fixed order:

| Index | Stage | Invocation | Description |
|-------|-------|------------|-------------|
| 0 | `specify` | `/speckit-specify` | Generate spec from brainstorm |
| 1 | `clarify` | `/speckit-clarify` | Resolve spec ambiguities |
| 2 | `review-spec` | `/speckit-spex-gates-review-spec` (Subagent) | Validate spec quality |
| 3 | `plan` | `/speckit-plan` | Generate implementation plan |
| 4 | `tasks` | `/speckit-tasks` | Generate task breakdown |
| 5 | `review-plan` | `/speckit-spex-gates-review-plan` (Subagent) | Validate plan and task quality |
| 6 | `implement` | `/speckit-implement` (Subagent) | Execute implementation |
| 7 | `review-code` | `/speckit-spex-gates-review-code` (Subagent) | Spec compliance + code review + deep review |

### Suppressing extension overlay gates

When running inside the ship pipeline, **no `/speckit-*` command may pause for user input unless the `ask` level is `always`**. This overrides any instruction in the speckit command prompts themselves. Specifically:

- **`speckit-specify`**: Do not ask "Shall I proceed?" after spec creation. Proceed to the next stage.
- **`speckit-clarify`**: Do not present questions interactively in `smart` or `never` mode. Auto-select recommended answers.
- **`speckit-plan`**: Do not ask for confirmation before or after planning. Proceed to the next stage.
- **`speckit-tasks`**: Do not ask for confirmation. Proceed to the next stage.
- **`speckit-implement`**: **SKIP all `after_implement` extension hooks entirely.** Do not execute review-code, deep-review, or any other after_implement hook. The ship pipeline runs review-code as its own Stage 7 with a separate subagent, so running it inside the implement subagent would be a double execution. When the implement subagent reaches step 10 (extension hooks), it must detect pipeline mode and skip.

Extension overlays (e.g., `spex-gates` adding review after specify) may run their reviews, but their results are informational. Do NOT pause or ask the user before proceeding. The ship pipeline's own stage gate logic handles all oversight decisions.

**Exception: `speckit-implement`** does not run its after_implement hooks at all in pipeline mode (see above). The pipeline handles review-code as a separate stage.

**This is a hard override. If a speckit command prompt says "present to user" or "wait for answer", and `ask` is `smart` or `never`, you answer it yourself and continue.**

### Stage 0: Specify (ALWAYS runs unless --start-from or --resume skips it)

**Even if spec.md already exists**, this stage re-creates it from the brainstorm document. A fresh pipeline means fresh artifacts.

1. Read the brainstorm document content.
2. Invoke `/speckit-specify` passing the brainstorm content as the feature description.
   - The brainstorm content provides the problem statement, approaches considered, and decisions made.
   - Pass it as the user input to the specify command.
   - **Do not pause** after specify completes, even if an extension overlay runs a review or asks for confirmation. Proceed directly to step 4.
   - **CRITICAL: Specify triggers `after_specify` hooks (including worktree-manage).** When the last hook returns (you may see a "WORKTREE_CREATED" message or a completion box), you are back in the ship pipeline. Do NOT stop. Immediately proceed to step 4.
4. After specify completes (including all its hooks), extract the feature branch name and handle worktree integration:
   ```bash
   FEATURE_BRANCH=$(git branch --show-current)
   ```

5. **Worktree integration:** If the `spex-worktrees` extension is enabled, check whether the `after_specify` hook already created a worktree. If not, create one now (the hook is optional and may have been skipped).
   ```bash
   WORKTREE_ENABLED=$(jq -r '.extensions["spex-worktrees"].enabled // false' .specify/extensions/.registry 2>/dev/null)
   ```
   If `WORKTREE_ENABLED` is `true`, look for an existing worktree for the feature branch:
   ```bash
   WORKTREE_PATH=$(git worktree list --porcelain | grep -B1 "branch refs/heads/$FEATURE_BRANCH" | head -1 | sed 's/^worktree //')
   ```

   If a worktree path is found and it is not the current directory:
   - Run `cd "$WORKTREE_PATH"` to switch into the worktree.
   - Verify `.specify/.spex-state` exists in the worktree.
   - Log: "Switched to worktree at $WORKTREE_PATH. Main directory remains on default branch."
   - Update `SHIP_STATE` to point to the worktree's copy of the state script (the path is relative, so cd handles this).

   If `WORKTREE_ENABLED` is `true` but NO worktree was found (the hook was skipped), invoke `/speckit-spex-worktrees-manage` to create one. This runs the worktree create action, which commits spec files, switches the main repo to the default branch, and creates a sibling worktree. After it completes, re-detect the worktree path and `cd` into it as above.

   If worktrees are NOT enabled, stay in the current directory (existing behavior).

6. Run `"$SHIP_STATE" advance` to move to Stage 1, then **immediately** begin it (do not stop).

### Stage 1: Clarify (ALWAYS runs, even if the spec "looks clear")

Do NOT skip this stage. Clarify may uncover ambiguities that are not obvious from reading the spec.

1. Read the `ask` level from the state file (default: `smart`).
3. **BEFORE invoking clarify**, determine the interaction mode:
   - If `ask` is `smart` or `never`: You are the decision-maker. Do NOT prompt the user interactively. When the clarify process identifies ambiguities, YOU select the recommended option for each question. If no recommendation exists, use your best judgment based on the spec context. Answer all questions yourself, then encode the answers into the spec.
   - If `ask` is `always`: Present each question to the user interactively.

4. Invoke `/speckit-clarify` on the generated spec. **The clarify command will try to present interactive questions. In `smart` and `never` modes, this is overridden: answer every question yourself with the recommended option. Do NOT wait for user input. Do NOT display questions with "You can reply with..." prompts. Process all questions in a single pass and update the spec.**
5. After clarification completes, run `"$SHIP_STATE" advance` then **immediately** begin Stage 2 (do not stop).

### Stage 2: Review Spec (Forked Subagent)

Do NOT skip this stage. Review-spec validates structural quality, not just ambiguities. This stage runs in an isolated subagent for clean context separation between generation and review.

1. Resolve the spec directory:
   ```bash
   PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
   FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
   ```

2. {harness:spawn-worker}:

   ```
   You are executing the spec review stage of a speckit-spex-ship pipeline.

   Feature directory: <FEATURE_DIR>
   Spec: <FEATURE_DIR>/spec.md

   Invoke /speckit-spex-gates-review-spec to validate spec quality.
   The .specify/.spex-state file exists with status "running", so
   complete the review autonomously and return immediately.

   Report the overall assessment and any findings when done.
   ```

3. When the subagent returns, capture its summary.
4. Apply **Oversight Decision Logic** (see below) to handle findings.
5. After findings are resolved, run `"$SHIP_STATE" advance` then **immediately** begin Stage 3 (do not stop).

### Stage 3: Plan

1. Invoke `/speckit-plan` to generate the implementation plan.
2. This produces `plan.md`, `research.md`, `data-model.md`, and other artifacts.
3. After plan generation completes, run `"$SHIP_STATE" advance` then **immediately** begin Stage 4 (do not stop).

### Stage 4: Tasks

1. Invoke `/speckit-tasks` to generate the task breakdown.
2. This produces `tasks.md`.
3. After task generation completes, run `"$SHIP_STATE" advance` then **immediately** begin Stage 5 (do not stop).

### Stage 5: Review Plan (Forked Subagent)

This stage runs in an isolated subagent for clean context separation between planning and review.

1. Resolve the spec directory:
   ```bash
   PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
   FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
   ```

2. {harness:spawn-worker}:

   ```
   You are executing the plan review stage of a speckit-spex-ship pipeline.

   Feature directory: <FEATURE_DIR>
   Spec: <FEATURE_DIR>/spec.md
   Plan: <FEATURE_DIR>/plan.md
   Tasks: <FEATURE_DIR>/tasks.md

   Invoke /speckit-spex-gates-review-plan to validate plan coverage and task quality.
   Plan validation complete.
   The .specify/.spex-state file exists with status "running", so
   complete the review autonomously and return immediately.

   Report the findings and overall assessment when done.
   ```

3. When the subagent returns, capture its summary.
4. Apply **Oversight Decision Logic** to handle findings.
5. After findings are resolved, run `"$SHIP_STATE" advance` then **immediately** begin Stage 6 (do not stop).

### Stage 6: Implement (Forked Subagent)

This stage runs in an isolated subagent to prevent context accumulation in the orchestrator.

1. Resolve the spec directory for the current branch:
   ```bash
   PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
   FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
   ```

2. Check if spex-teams should handle implementation:
   ```bash
   TEAMS_ENABLED=$(jq -r '.extensions["spex-teams"].enabled // false' .specify/extensions/.registry 2>/dev/null)
   INDEPENDENT_TASKS=$(grep -c '\[P\]' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo 0)
   ```

   Before spawning the subagent, check if per-task test checkpoints are enabled:
   ```bash
   SPEX_CONFIG=".specify/extensions/spex/spex-config.yml"
   TEST_BETWEEN_TASKS=$(yq -r '.implement.test_between_tasks // true' "$SPEX_CONFIG" 2>/dev/null)
   TEST_BETWEEN_TASKS=${TEST_BETWEEN_TASKS:-true}
   ```

   Build the test checkpoint instruction block (only when `TEST_BETWEEN_TASKS` is `true`):

   ```
   TEST_CHECKPOINT_INSTRUCTIONS=""
   if [ "$TEST_BETWEEN_TASKS" = "true" ]; then
     TEST_CHECKPOINT_INSTRUCTIONS="
   IMPORTANT: Per-task test checkpoints are ENABLED. After completing each task
   in tasks.md (before starting the next task), you MUST:

   1. Auto-detect the project's test command using this priority:
      - If a Makefile exists with a 'test' target: run 'make test'
      - If package.json exists with a 'test' script: run 'npm test'
      - If go.mod exists: run 'go test ./...'
      - If pytest is available and Python files exist: run 'pytest'
      - If Cargo.toml exists: run 'cargo test'
      - If none detected: skip checkpoints with a warning ('No test command detected, skipping inter-task checks')

   2. Run the detected test command after each completed task.

   3. If tests PASS: proceed to the next task without interruption.

   4. If tests FAIL: attempt to fix the failure. You get a maximum of 2 fix
      attempts per checkpoint. If the fix succeeds, continue to the next task.
      If both attempts fail, STOP implementation and report the failing tests
      with context about which task introduced the regression.
   "
   fi
   ```

   Check if mid-implementation review checkpoints should be enabled:
   ```bash
   DEEP_REVIEW_ENABLED=$(jq -r '.extensions["spex-deep-review"].enabled // false' .specify/extensions/.registry 2>/dev/null)
   SPEX_CONFIG=".specify/extensions/spex/spex-config.yml"
   REVIEW_CHECKPOINTS=$(yq -r '.implement.review_checkpoints // true' "$SPEX_CONFIG" 2>/dev/null)
   REVIEW_CHECKPOINTS=${REVIEW_CHECKPOINTS:-true}
   TOTAL_TASKS=$(grep -c '^\- \[.\]' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo 0)
   ```

   Build the checkpoint instruction block (only when `DEEP_REVIEW_ENABLED` is `true`, `REVIEW_CHECKPOINTS` is `true`, and `TOTAL_TASKS` >= 3):

   ```
   CHECKPOINT_INSTRUCTIONS=""
   if [ "$DEEP_REVIEW_ENABLED" = "true" ] && [ "$REVIEW_CHECKPOINTS" = "true" ] && [ "$TOTAL_TASKS" -ge 3 ]; then
     CP1=$(( TOTAL_TASKS / 3 ))
     CP2=$(( TOTAL_TASKS * 2 / 3 ))
     CHECKPOINT_INSTRUCTIONS="
   IMPORTANT: Mid-implementation review checkpoints are ENABLED.
   Total tasks: $TOTAL_TASKS. Checkpoint 1 after task $CP1, checkpoint 2 after task $CP2.

   After completing task $CP1 (checkpoint 1/3), pause implementation and {harness:spawn-fresh-worker} with this prompt:

     'You are a correctness review agent for a mid-implementation checkpoint.
     Review the implementation so far against the spec at <SPEC_PATH>.
     Focus ONLY on correctness: does the code match the spec requirements
     for the tasks completed so far? Report findings with file paths and
     line numbers. Do NOT review architecture, security, production readiness,
     or test quality. If you find no issues after careful review, confirm
     with: No correctness issues found.'

   After the review agent returns:
   - If findings exist, fix them (max 2 attempts per finding).
   - Record results: run the spex-ship-state.sh script with:
     checkpoint-record --checkpoint 1 --findings <N> --fixed <N>
     (where N is the count of findings found and fixed respectively)
   - If the review agent times out or fails, skip the checkpoint with a
     warning ('Checkpoint 1/3 skipped: review agent failed'), record
     findings=0 fixed=0, and continue implementation.
   - Then continue to the next task.

   After completing task $CP2 (checkpoint 2/3), repeat the same process:
   spawn a fresh correctness review agent, fix findings, and record results
   with --checkpoint 2.
   "
   fi
   ```

   If `TOTAL_TASKS` < 3 and checkpoints would otherwise be enabled, the checkpoint instructions are simply omitted (no explicit comment needed in the prompt).

   If `TEAMS_ENABLED` is `true` AND `INDEPENDENT_TASKS` >= 2, route to teams implement by spawning a subagent with:

   ```
   You are executing the implementation stage of a speckit-spex-ship pipeline using parallel agent teams.

   Feature directory: <FEATURE_DIR>
   Spec: <FEATURE_DIR>/spec.md
   Plan: <FEATURE_DIR>/plan.md
   Tasks: <FEATURE_DIR>/tasks.md

   Read these files, then invoke /speckit.spex-teams.implement to execute parallel implementation.
   The .specify/.spex-state file exists with status "running", so the
   implement command will run in pipeline mode (no completion summary, no user questions).

   IMPORTANT: SKIP ALL after_implement extension hooks (step 10 of the implement skill).
   Do NOT execute review-code, deep-review, or any other after_implement hook.
   The ship pipeline runs review-code as a separate Stage 7.

   <TEST_CHECKPOINT_INSTRUCTIONS>

   <CHECKPOINT_INSTRUCTIONS>

   When marking tasks complete in tasks.md, use the Edit tool.
   Report a brief summary of completed tasks when done.
   ```

   Otherwise, use standard implement by spawning a subagent with:

   ```
   You are executing the implementation stage of a speckit-spex-ship pipeline.

   Feature directory: <FEATURE_DIR>
   Spec: <FEATURE_DIR>/spec.md
   Plan: <FEATURE_DIR>/plan.md
   Tasks: <FEATURE_DIR>/tasks.md

   Read these files, then invoke /speckit-implement to execute the implementation.
   The .specify/.spex-state file exists with status "running", so the
   implement command will run in pipeline mode (no completion summary, no user questions).

   IMPORTANT: SKIP ALL after_implement extension hooks (step 10 of the implement skill).
   Do NOT execute review-code, deep-review, or any other after_implement hook.
   The ship pipeline runs review-code as a separate Stage 7.

   <TEST_CHECKPOINT_INSTRUCTIONS>

   <CHECKPOINT_INSTRUCTIONS>

   When marking tasks complete in tasks.md, use the Edit tool.
   Report a brief summary of completed tasks when done.
   ```

3. When the subagent returns, capture its summary. Do NOT carry the full implementation context into the orchestrator.
4. After implementation completes, run `"$SHIP_STATE" advance` then **immediately** begin Stage 7 (do not stop).

### Stage 7: Review Code (Forked Subagent)

This stage runs in an isolated subagent so the reviewer has no implementation context, enabling an unbiased review.

1. Resolve the spec directory (same as Stage 6):
   ```bash
   PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
   FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
   ```

2. {harness:spawn-worker}. Pass external tool settings resolved during argument parsing:

   ```
   You are executing the code review stage of a speckit-spex-ship pipeline.

   Feature directory: <FEATURE_DIR>
   Spec: <FEATURE_DIR>/spec.md
   External tools: coderabbit=<true/false>, copilot=<true/false>, codex=<true/false>

   IMPORTANT: Do NOT read plan.md or tasks.md. These are implementation
   artifacts that reveal author intent and would anchor your review.
   Review the code against the spec only.

   Invoke /speckit-spex-gates-review-code to run the full review chain:
   - Spec compliance check
   - Code review validation
   - Deep review (if spex-deep-review extension is enabled): 5 review agents, fix loop,
     Deep Review Report output to console
   - External tools (CodeRabbit, Copilot) if enabled

   Report the compliance score, gate outcome, and a summary of findings when done.
   ```

3. When the subagent returns, capture its summary (compliance score, gate outcome, finding counts).

   **CWD recovery (worktree):** Run the CWD recovery script (see "CWD Recovery After Subagents" above).

4. Apply **Oversight Decision Logic** to any remaining findings reported by the subagent.
5. After findings are resolved, run `"$SHIP_STATE" advance` to mark the pipeline as complete. The advance command at index 7 outputs `PIPELINE_COMPLETE`.

### Post-Pipeline: Completion Prompt (Always Interactive)

After `PIPELINE_COMPLETE`, the pipeline is done. Present the user with a choice of how to proceed. This prompt is **always interactive**, regardless of the `ask` level. It is NOT a pipeline stage (no stage index, no status line entry).

**CRITICAL: Stay on the feature branch.** Do NOT switch to main, do NOT run `git checkout`, do NOT clean up worktrees, and do NOT remove the state file at this point. The user must choose how to proceed first. Branch switching only happens inside `/speckit-spex-finish` if the user selects "Merge directly".

**Do NOT check for smoke test scenarios, do NOT announce smoke test phases, do NOT spawn smoke test subagents.** The smoke test runs inside `/speckit-spex-finish` via the `before_finish` hook. The post-pipeline prompt is ONLY the choice below.

1. Output a one-line summary, then IMMEDIATELY {harness:interactive-choice}:

   Output: `Pipeline complete (8/8 stages passed). Consider running /clear before proceeding to free context.`

   Then present options to the user:
   - header: "Complete"
   - multiSelect: false
   - Options:
     - "Submit PR (Recommended)": "Push branch and create a pull request for team review"
     - "Merge directly": "Run /speckit-spex-finish to smoke test, squash, and merge to main"
     - "Stop here": "Do nothing now. Run /speckit-spex-submit or /speckit-spex-finish later"

   {harness:interactive-choice-must} Do NOT output the options as text and wait for a free-form reply.

2. **If "Submit PR":**

   Invoke `/speckit-spex-submit` directly in the current session.

   After submit completes, output:
   ```
   Pipeline complete. PR created.
   Run `/speckit-spex-finish` after reviews are approved.
   ```

3. **If "Merge directly":**

   Invoke `/speckit-spex-finish` directly in the current session.

   After finish completes, output:
   ```
   Pipeline complete. Code landed on main.
   ```

4. **If "Stop here":**

   Output:
   ```
   Pipeline complete through review.

   When ready:
     /speckit-spex-submit    Push and create PR
     /speckit-spex-finish    Smoke test + squash + merge to main
   ```

5. **STOP.**

## Oversight Decision Logic

After each review stage (review-spec, review-plan, review-code, finish), evaluate the findings:

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

After review-code completes and `PIPELINE_COMPLETE` fires, report the completion summary before the choice prompt:

```
## Pipeline Complete

**Feature branch:** <branch-name>
**Stages completed:** 8/8
**Oversight mode:** <mode>
**Elapsed time:** <duration>

All stages passed successfully:
  0. specify     - spec.md created
  1. clarify     - spec clarified
  2. review-spec - spec validated
  3. plan        - plan.md generated
  4. tasks       - tasks.md generated
  5. review-plan - plan validated
  6. implement   - code implemented
  7. review-code - code reviewed
```

Then present the post-pipeline completion prompt (see "Post-Pipeline: Completion Prompt" above).

## Integration

**This skill is invoked by:**
- Users directly via `/speckit-spex-ship`

**This skill invokes (inline):**
- `/speckit-specify` (Stage 0)
- `/speckit-clarify` (Stage 1)
- `/speckit-plan` (Stage 3)
- `/speckit-tasks` (Stage 4)

**This skill invokes (forked subagent for context isolation):**
- `/speckit-spex-gates-review-spec` (Stage 2)
- `/speckit-spex-gates-review-plan` (Stage 5)
- `/speckit-implement` (Stage 6)
- `/speckit-spex-gates-review-code` (Stage 7)

**This skill invokes (post-pipeline completion prompt, interactive):**
- `/speckit-spex-submit` (if user chooses "Submit PR")
- `/speckit-spex-finish` (if user chooses "Merge directly")

**Required extensions:** `spex-gates`, `spex-deep-review`
