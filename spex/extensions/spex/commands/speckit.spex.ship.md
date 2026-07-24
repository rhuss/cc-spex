---
description: "Autonomous full-cycle workflow: specify through verify with configurable oversight levels, auto-fix, and optional PR creation"
---

# Autonomous Full-Cycle Workflow (speckit-spex-ship)

Codex projects must run `spex:init` first. Ship resumes from validated
WorkflowState and reports ordered ProgressEvents; visible progress never
overrides durable feature/worktree authority.

## CONTINUOUS EXECUTION RULE (READ THIS FIRST)

**This pipeline runs ALL stages without stopping.** After completing any stage, you MUST immediately begin the next stage. There are no natural stopping points between stages.

- Do NOT say "Ready for the next stage" and wait.
- Do NOT say "Shall I proceed?" and wait.
- Do NOT say "Proceeding to..." and wait.
- Do NOT treat a stage completion as a task completion.
- Do NOT output a summary and stop.

The pipeline is ONE continuous task. It starts at the first stage and runs through the last stage. The ONLY reasons to yield to the user are:
1. A genuine authority boundary exists (a product choice, permission, destructive/external action, secret, or scope expansion that the agent cannot authorize).
2. `ask` is `always` and the user explicitly requested review-time judgment.
3. A durable terminal recovery state (`failed_budget`, `failed_nonconvergent`, or `failed_validation`) has been reached and its evidence report is ready.
4. Stage 7 completes and presents the completion prompt.

Test failures, syntax errors, security findings, infeasible approaches, delegated-agent returns, and exhaustion of ordinary correction retries are **not** by themselves pause reasons. Route recoverable findings into the bounded recovery lifecycle below.

### Continuation Invariant

Stage completion, delegated/subagent return, context compression or automatic
conversation compaction, ordinary retry exhaustion, and discovery of a
recoverable finding all mean **continue this same ship run**. After any of
these events, re-resolve durable WorkflowState and perform its next action.
Never translate an agent summary, a shortened context window, or the end of a
stage into a final response. Ship may end only when WorkflowState is
`completed`, a durable terminal failure report has been persisted, or a
`paused_authority` boundary requires user authority.

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

Locate the script from the checkout where ship was invoked. Do not export or
persist a CWD-derived state path:
```bash
SHIP_STATE=".specify/extensions/spex/scripts/spex-ship-state.sh"
[ -x "$SHIP_STATE" ] || { echo "ERROR: WorkflowState authority is unavailable: $SHIP_STATE" >&2; exit 1; }
SHIP_STATE="$(cd "$(dirname "$SHIP_STATE")" && pwd -P)/$(basename "$SHIP_STATE")"
```

Define one authority refresh routine and call it before every spec lookup, state
mutation, stage transition, and continuation after delegated work:

```bash
resolve_feature_context() {
  RESOLVED_STATE=$(env -u SHIP_STATE_FILE "$SHIP_STATE" resolve) || {
    echo "ERROR: WorkflowState resolution failed; refusing ambiguous or invalid checkout authority." >&2
    exit 1
  }
  echo "$RESOLVED_STATE" | jq -e '
    .schema_version == "2.0.0" and
    (.revision | type == "number") and
    (.context.active_worktree | startswith("/")) and
    (.context.spec_dir | startswith("/")) and
    (.context.state_file | startswith("/")) and
    (.context.feature_branch | test("^[0-9]{3}-[a-z0-9-]+$"))
  ' >/dev/null || { echo "ERROR: Resolver returned invalid FeatureContext." >&2; exit 1; }

  ACTIVE_WORKTREE=$(echo "$RESOLVED_STATE" | jq -r '.context.active_worktree')
  FEATURE_DIR=$(echo "$RESOLVED_STATE" | jq -r '.context.spec_dir')
  STATE_FILE=$(echo "$RESOLVED_STATE" | jq -r '.context.state_file')
  FEATURE_BRANCH=$(echo "$RESOLVED_STATE" | jq -r '.context.feature_branch')
  STATE_REVISION=$(echo "$RESOLVED_STATE" | jq -r '.revision')

  [ -d "$ACTIVE_WORKTREE" ] && [ -f "$FEATURE_DIR/spec.md" ] || {
    echo "ERROR: Validated worktree or specification no longer exists." >&2; exit 1;
  }
  case "$FEATURE_DIR/" in "$ACTIVE_WORKTREE"/*) ;; *)
    echo "ERROR: Specification is outside the validated worktree." >&2; exit 1;;
  esac
  [ "$STATE_FILE" = "$ACTIVE_WORKTREE/.specify/.spex-state" ] || {
    echo "ERROR: State file is outside the validated worktree." >&2; exit 1;
  }
  [ "$(git -C "$ACTIVE_WORKTREE" branch --show-current)" = "$FEATURE_BRANCH" ] || {
    echo "ERROR: Validated feature branch no longer matches its worktree." >&2; exit 1;
  }

  cd "$ACTIVE_WORKTREE" || exit 1
  SHIP_STATE="$ACTIVE_WORKTREE/.specify/extensions/spex/scripts/spex-ship-state.sh"
  [ -x "$SHIP_STATE" ] || { echo "ERROR: Worktree state authority is unavailable." >&2; exit 1; }

  # Re-resolve after changing checkout and reject any cross-checkout disagreement.
  CONFIRMED_STATE=$(env -u SHIP_STATE_FILE "$SHIP_STATE" resolve) || exit 1
  [ "$(echo "$CONFIRMED_STATE" | jq -r '.workflow_id + ":" + (.revision|tostring)')" = \
    "$(echo "$RESOLVED_STATE" | jq -r '.workflow_id + ":" + (.revision|tostring)')" ] || {
    echo "ERROR: Workflow authority changed while restoring the feature worktree." >&2; exit 1;
  }
  RESOLVED_STATE="$CONFIRMED_STATE"
}

advance_stage() {
  resolve_feature_context
  env -u SHIP_STATE_FILE "$SHIP_STATE" advance
}

begin_delegated_stage() {
  resolve_feature_context
  DELEGATED_WORKFLOW_ID=$(echo "$RESOLVED_STATE" | jq -r '.workflow_id')
  DELEGATED_STAGE=$(echo "$RESOLVED_STATE" | jq -r '.stage')
  DELEGATED_WORKTREE="$ACTIVE_WORKTREE"
}

continue_after_delegation() {
  EXPECTED_WORKFLOW_ID="$DELEGATED_WORKFLOW_ID"
  EXPECTED_STAGE="$DELEGATED_STAGE"
  EXPECTED_WORKTREE="$DELEGATED_WORKTREE"
  resolve_feature_context
  [ "$(echo "$RESOLVED_STATE" | jq -r '.workflow_id')" = "$EXPECTED_WORKFLOW_ID" ] &&
  [ "$(echo "$RESOLVED_STATE" | jq -r '.stage')" = "$EXPECTED_STAGE" ] &&
  [ "$ACTIVE_WORKTREE" = "$EXPECTED_WORKTREE" ] || {
    echo "ERROR: Workflow authority changed during delegated work; refusing continuation." >&2
    exit 1
  }
}
```

`SHIP_STATE_FILE`, the apparent CWD, branch-name guesses, and file mtimes are
never mutation authority. A nonzero resolver result is a hard refusal; do not
select a candidate or create a replacement state file.

Visible progress is presentation metadata, not workflow authority. A native
task-progress view, status line, transcript line, or remembered stage may lag,
disappear after interruption, or belong to an earlier process. Never use any
of them to select a state file, stage, revision, worktree, or resume action.

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
advance_stage
```

This advances `stage` and `stage_index` to the next stage with `status: running`. After the final stage (verify), `advance` automatically removes the state file and outputs `PIPELINE_COMPLETE`.

**Do NOT manually write JSON to the state file. Always use the script.**

### Authority Recovery After Subagents (Worktree Pipelines)

When a subagent returns, the host may reset the apparent CWD to the main
checkout. **After every subagent returns**, discard all remembered paths and
re-resolve durable authority:

```bash
resolve_feature_context
```

Do not use a persisted environment variable or previously remembered worktree
path as a fallback. If resolution is ambiguous or identity validation fails,
stop before reading artifacts, advancing state, or applying delegated output.

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

1. Resolve and validate durable authority from the invocation checkout. Never
   probe `.specify/.spex-state` directly:
   ```bash
   resolve_feature_context
   STATE="$RESOLVED_STATE"
   ```

2. Extract the validated stage and map its name to the fixed pipeline index:
   ```bash
   LAST_STAGE=$(echo "$STATE" | jq -r '.stage')
   case "$LAST_STAGE" in
     specify) LAST_INDEX=0 ;; clarify) LAST_INDEX=1 ;; review-spec) LAST_INDEX=2 ;;
     plan) LAST_INDEX=3 ;; tasks) LAST_INDEX=4 ;; review-plan) LAST_INDEX=5 ;;
     implement) LAST_INDEX=6 ;; review-code) LAST_INDEX=7 ;;
     *) echo "ERROR: Invalid stage in resolved WorkflowState: $LAST_STAGE" >&2; exit 1 ;;
   esac
   ```

3. Reconcile the visible presentation with the validated durable state before
   deciding what work to run. The active harness may provide its last
   presented `VISIBLE_PROGRESS_SEQUENCE` and `VISIBLE_PROGRESS_STAGE`; both are
   optional, untrusted presentation inputs. Compare them only after
   `resolve_feature_context` succeeds:

   ```bash
   DURABLE_PROGRESS_SEQUENCE=$(echo "$STATE" | jq -r '.revision')
   DURABLE_PROGRESS_STAGE=$(echo "$STATE" | jq -r '.stage')
   PROGRESS_DISCREPANCY=""

   case "${VISIBLE_PROGRESS_SEQUENCE:-}" in
     ""|*[!0-9]*)
       [ -z "${VISIBLE_PROGRESS_SEQUENCE:-}" ] ||
         PROGRESS_DISCREPANCY="visible sequence is invalid"
       ;;
     *)
       [ "$VISIBLE_PROGRESS_SEQUENCE" = "$DURABLE_PROGRESS_SEQUENCE" ] ||
         PROGRESS_DISCREPANCY="visible sequence $VISIBLE_PROGRESS_SEQUENCE differs from durable sequence $DURABLE_PROGRESS_SEQUENCE"
       ;;
   esac
   if [ -n "${VISIBLE_PROGRESS_STAGE:-}" ] &&
      [ "$VISIBLE_PROGRESS_STAGE" != "$DURABLE_PROGRESS_STAGE" ]; then
     PROGRESS_DISCREPANCY="${PROGRESS_DISCREPANCY:+$PROGRESS_DISCREPANCY; }visible stage $VISIBLE_PROGRESS_STAGE differs from durable stage $DURABLE_PROGRESS_STAGE"
   fi
   ```

   If `PROGRESS_DISCREPANCY` is nonempty, emit one concise reconciliation
   update before any stage output:

   ```text
   Progress reconciled: <discrepancy>. Durable WorkflowState is authoritative; resuming sequence <revision> at <stage>.
   ```

   Then replace the harness presentation with `DURABLE_PROGRESS_SEQUENCE` and
   `DURABLE_PROGRESS_STAGE`. In Codex, update native task progress when that
   surface is available and always emit the transcript update; when it is not
   available, emit the same transcript update with the adapter's explicit
   degradation. If no visible snapshot exists, initialize presentation from
   the durable values without claiming a discrepancy. This operation changes
   presentation only: it MUST NOT write WorkflowState, append a transition,
   change revision, or infer a stage from visible progress.

4. Check the validated `status` field to determine resume behavior:
   - If `status` is `"paused_authority"`, run
     `env -u SHIP_STATE_FILE "$SHIP_STATE" resume --expected-revision "$STATE_REVISION"`,
     then call `resolve_feature_context` again. Recompute `STATE`,
     `DURABLE_PROGRESS_SEQUENCE`, `DURABLE_PROGRESS_STAGE`, and `LAST_INDEX`
     from that newly resolved state, reconcile presentation again, and resume
     the resulting durable stage.
   - If `status` is `"running"`: resume from `LAST_INDEX` (the stage was interrupted mid-execution) without rewriting state.
   - If `status` is a failure state, refuse automatic resume and report its validated `resume_point`.
   - If `status` is `"completed"`: report that the pipeline already completed and clean up the state file.

5. Before invoking the resumed stage, call `resolve_feature_context` once more.
   If its workflow ID, revision, or stage differs from the state used for the
   reconciliation update, discard the pending stage invocation and repeat
   steps 2–4 with the newly resolved state. Use only its `context.spec_dir` for
   artifact discovery and its revision for subsequent mutation. Never edit
   retry/status fields directly.

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

If a stage fails or is interrupted, the pipeline MUST NOT silently proceed to the next stage. It must retry ordinary corrections, enter bounded recovery, record an evidenced terminal state, or pause at a genuine authority boundary.

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
4. After specify completes (including all its hooks), discard the apparent CWD
   and call `resolve_feature_context`. The resolver output is the only accepted
   feature branch, worktree, spec directory, and state location.

5. **Worktree integration:** If the `spex-worktrees` extension is enabled, the
   `after_specify` hook must return only after its two-phase state transfer is
   committed. Resolve that transferred authority rather than searching Git
   worktree output by branch name.
   ```bash
   WORKTREE_ENABLED=$(jq -r '.extensions["spex-worktrees"].enabled // false' .specify/extensions/.registry 2>/dev/null)
   ```
   If resolution fails because no transferred feature candidate exists, invoke
   `/speckit-spex-worktrees-manage` once. After it returns, call
   `resolve_feature_context`; if it still fails or reports competing candidates,
   stop. Never fall back to `git worktree list`, branch matching, timestamps, or
   the prior CWD.

   If worktrees are not enabled, still call `resolve_feature_context`; the
   validated active checkout may equal the invocation checkout, but apparent
   CWD alone is never sufficient authority.

6. Run `advance_stage` to move to Stage 1, then **immediately** begin it (do not stop).

### Stage 1: Clarify (ALWAYS runs, even if the spec "looks clear")

Do NOT skip this stage. Clarify may uncover ambiguities that are not obvious from reading the spec.

1. Read the `ask` level from the state file (default: `smart`).
3. **BEFORE invoking clarify**, determine the interaction mode:
   - If `ask` is `smart` or `never`: You are the decision-maker. Do NOT prompt the user interactively. When the clarify process identifies ambiguities, YOU select the recommended option for each question. If no recommendation exists, use your best judgment based on the spec context. Answer all questions yourself, then encode the answers into the spec.
   - If `ask` is `always`: Present each question to the user interactively.

4. Invoke `/speckit-clarify` on the generated spec. **The clarify command will try to present interactive questions. In `smart` and `never` modes, this is overridden: answer every question yourself with the recommended option. Do NOT wait for user input. Do NOT display questions with "You can reply with..." prompts. Process all questions in a single pass and update the spec.**
5. After clarification completes, run `advance_stage` then **immediately** begin Stage 2 (do not stop).

### Stage 2: Review Spec (Forked Subagent)

Do NOT skip this stage. Review-spec validates structural quality, not just ambiguities. This stage runs in an isolated subagent for clean context separation between generation and review.

1. Resolve validated workflow authority, consume its spec directory, and
   snapshot delegated-stage identity:
   ```bash
   begin_delegated_stage
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

3. When the subagent returns, capture its summary, then immediately call
   `continue_after_delegation` before interpreting or applying it.
4. Apply **Oversight Decision Logic** (see below) to handle findings.
5. After findings are resolved, run `advance_stage` then **immediately** begin Stage 3 (do not stop).

### Stage 3: Plan

1. Invoke `/speckit-plan` to generate the implementation plan.
2. This produces `plan.md`, `research.md`, `data-model.md`, and other artifacts.
3. After plan generation completes, run `advance_stage` then **immediately** begin Stage 4 (do not stop).

### Stage 4: Tasks

1. Invoke `/speckit-tasks` to generate the task breakdown.
2. This produces `tasks.md`.
3. After task generation completes, run `advance_stage` then **immediately** begin Stage 5 (do not stop).

### Stage 5: Review Plan (Forked Subagent)

This stage runs in an isolated subagent for clean context separation between planning and review.

1. Resolve validated workflow authority, consume its spec directory, and
   snapshot delegated-stage identity:
   ```bash
   begin_delegated_stage
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

3. When the subagent returns, capture its summary, then immediately call
   `continue_after_delegation` before interpreting or applying it.
4. Apply **Oversight Decision Logic** to handle findings.
5. After findings are resolved, run `advance_stage` then **immediately** begin Stage 6 (do not stop).

### Stage 6: Implement (Forked Subagent)

This stage runs in an isolated subagent to prevent context accumulation in the orchestrator.

1. Resolve validated workflow authority, consume its spec directory, and
   snapshot delegated-stage identity:
   ```bash
   begin_delegated_stage
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
      If both attempts fail, return the failing tests and task context to the
      ship orchestrator. This is a recoverable finding, not permission to end
      ship; the orchestrator MUST enter bounded recovery and continue from its
      durable result.
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

3. When the subagent returns, capture its summary. Do NOT carry the full implementation context into the orchestrator. Immediately call `continue_after_delegation`; refuse to apply the summary if workflow ID, worktree identity, or expected stage changed while delegated work was running.
4. After implementation completes, run `advance_stage` then **immediately** begin Stage 7 (do not stop).

### Stage 7: Review Code (Forked Subagent)

This stage runs in an isolated subagent so the reviewer has no implementation context, enabling an unbiased review.

1. Resolve validated workflow authority, consume its spec directory, and
   snapshot delegated-stage identity:
   ```bash
   begin_delegated_stage
   ```

2. {harness:spawn-worker}. Do NOT pass external tool settings in the prompt. The deep-review skill reads its own config file (`deep-review-config.yml`) and determines which tools to run. Only pass explicit `--no-*` CLI flags if the user provided them at ship invocation time.

   ```
   You are executing the code review stage of a speckit-spex-ship pipeline.

   Feature directory: <FEATURE_DIR>
   Spec: <FEATURE_DIR>/spec.md

   IMPORTANT: Do NOT read plan.md or tasks.md. These are implementation
   artifacts that reveal author intent and would anchor your review.
   Review the code against the spec only.

   IMPORTANT: Do NOT pass external tool settings (coderabbit, copilot, codex)
   to the review-code or deep-review commands. They read their own config.
   Only pass explicit --no-* flags if the user provided them at ship invocation.
   <If user passed --no-coderabbit: include "--no-coderabbit">
   <If user passed --no-copilot: include "--no-copilot">
   <If user passed --no-codex: include "--no-codex">
   <If user passed --no-external: include "--no-external">

   Invoke /speckit-spex-gates-review-code to run the full review chain:
   - Spec compliance check
   - Code review validation
   - Deep review (if spex-deep-review extension is enabled): 5 review agents, fix loop,
     Deep Review Report output to console
   - External tools as configured in deep-review-config.yml

   Report the compliance score, gate outcome, and a summary of findings when done.
   ```

3. When the subagent returns, capture its summary (compliance score, gate outcome, finding counts), then immediately call `continue_after_delegation`. Refuse to apply results if authority no longer matches the delegated stage.

4. Apply **Oversight Decision Logic** to any remaining findings reported by the subagent.
5. After findings are resolved, run `advance_stage` to mark the pipeline as complete. The advance command at index 7 outputs `PIPELINE_COMPLETE`.

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

After each review stage, classify findings by **authority**, not by difficulty:

### Finding Classification

**Routine correction**: A local, reversible fix within the accepted spec and
security boundary. Apply it and rerun the affected check (maximum two ordinary
correction cycles before recovery routing).

**Recoverable finding**: The current approach remains infeasible after ordinary
correction, but in-scope research, artifact revision, or an alternative
implementation may resolve it. This includes compilation/test failures,
missing local dependencies, security defects, feasibility conflicts, and
incorrect architecture. Start or continue a bounded RecoveryEpisode.

**Authority boundary**: Progress requires a product/requirement choice with no
authorized default, new credentials or permission, destructive or external
side effects, or a scope expansion. Only this category may transition to
`paused_authority`. Difficulty, uncertainty, retry exhaustion, or a subagent
failure alone never qualifies.

### Oversight Rules

| Oversight Level | Routine correction | Recoverable finding | Authority boundary |
|----------------|--------------------|---------------------|--------------------|
| `always` | Apply; ask only where explicitly requested | Bounded recovery | Pause with evidence |
| `smart` | Apply | Bounded recovery | Pause with evidence |
| `never` | Apply | Bounded recovery | Pause with evidence |

### Applying the Rules

1. Collect findings and evidence, normalize the finding description, and
   identify affected artifacts and gates.
2. Apply routine corrections and rerun the affected check up to two times.
3. Route anything still recoverable into the durable lifecycle below. Do not
   ask for routine confirmation before continuing.
4. Pause only after writing an `authority_required` recovery completion with an
   exact resume point and residual risk.
5. If no findings remain, proceed immediately.

## Bounded Autonomous Recovery

After ordinary correction is exhausted, resolve current authority and start an
episode using CAS:

```bash
resolve_feature_context
RECOVERY_STATE=$(env -u SHIP_STATE_FILE "$SHIP_STATE" recovery-start \
  --expected-revision "$STATE_REVISION" \
  --objective "<specific recovery objective>" \
  --origin-stage "$(echo "$RESOLVED_STATE" | jq -r '.stage')" \
  --finding "<normalized finding with relevant constraint>" \
  --affected-artifact "<artifact>" \
  --affected-gate "<gate>") || exit 1
```

Defaults are three attempts and 1,800 elapsed seconds. Never reset either bound
after interruption. For each attempt:

1. Re-resolve FeatureContext and confirm the same episode/revision.
2. Research or implement one materially different in-scope remedy.
3. Hash every artifact input used by the remedy.
4. Run focused verification and collect concrete evidence.
5. Persist the attempt before deciding whether to continue:

```bash
resolve_feature_context
RECOVERY_STATE=$(env -u SHIP_STATE_FILE "$SHIP_STATE" recovery-record \
  --expected-revision "$STATE_REVISION" \
  --remedy "<remedy attempted>" \
  --input-hash "<path>=sha256:<digest>" \
  --result "<normalized verification result>" \
  --evidence "<test, inspection, or research evidence>" \
  --outcome "<accepted|rejected|failed>") || exit 1
```

Equivalent findings/remedies and A→B→A result oscillation terminate as
`failed_nonconvergent` before another attempt is appended. Deadline or attempt
exhaustion terminates as `failed_budget`. Do not restart an episode to evade a
terminal state.

### Accepted Recovery: Invalidate and Rewind

When a remedy is accepted, determine the earliest affected stage from durable
artifact identity, not the current stage:

| Earliest affected input | Rewind stage | Invalidate/rebuild |
|-------------------------|--------------|--------------------|
| `spec.md` or requirement contract | `specify` | spec review, plan/research/data model/contracts, tasks, implementation and later gates |
| plan/research/data model/contract | `plan` | plan gate, tasks, implementation and later gates |
| `tasks.md` | `tasks` | task-dependent implementation and code gates |
| source/test implementation | `implement` | implementation result and code gates |

Persist completion before continuing:

```bash
resolve_feature_context
RECOVERY_STATE=$(env -u SHIP_STATE_FILE "$SHIP_STATE" recovery-complete \
  --expected-revision "$STATE_REVISION" \
  --outcome accepted \
  --rewind-stage "<earliest-stage>" \
  --resume-action "<exact gates/artifacts to rebuild>" \
  --resume-artifact "<earliest affected artifact>") || exit 1
```

The completion removes affected entries from `completed_gates`, preserves the
episode evidence, and rewinds WorkflowState. Delete or overwrite stale derived
artifacts only as part of rerunning their owning stage; never treat them as
valid input after rewind. Call `resolve_feature_context` and continue at the
persisted `resume_point` without asking the user.

## Pause and Resume

### Pausing at a Genuine Authority Boundary

Before pausing, persist the boundary through the recovery authority:

```bash
resolve_feature_context
env -u SHIP_STATE_FILE "$SHIP_STATE" recovery-complete \
  --expected-revision "$STATE_REVISION" \
  --outcome authority_required \
  --resume-stage "<stage>" \
  --resume-action "<specific user decision or authority needed>" \
  --resume-artifact "<artifact>" \
  --residual-risk "<consequence of proceeding without authority>"
```

Then present the objective, evidence already gathered, the exact choice or
permission required, residual risk, affected artifacts, and resume action:

```
## Pipeline Paused at Stage: review-spec

### Findings Requiring Your Input

**Authority required:** <specific decision/permission>
**Evidence:** <what was tried or established>
**Residual risk:** <why the agent cannot safely choose>
**Resume:** <exact persisted resume action>

Please provide the required decision or authority.
```

Wait for user response. Do not use this path for mere retry exhaustion.

### Resuming After User Input

After the user responds:

1. Re-resolve WorkflowState and verify it is `paused_authority`.
2. Resume with `env -u SHIP_STATE_FILE "$SHIP_STATE" resume --expected-revision "$STATE_REVISION"`.
3. Apply the authorized decision and continue from the persisted resume point.

### Terminal Recovery Report

For `budget_exhausted`, `nonconvergent`, or unrecoverable validation failure,
call `recovery-complete` with the terminal outcome, exact resume stage/action,
resume artifact, and residual risk. Report:

- objective and terminal reason;
- every attempted action and its evidence;
- affected artifacts and invalidated gates;
- residual blocker/risk;
- exact persisted resume point.

Terminal state remains durable and resolvable after interruption. Do not imply
that work completed, discard evidence, or replace the exact resume action with
generic advice.

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
