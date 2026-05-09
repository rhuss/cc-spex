---
description: "Reconcile revised tasks against existing implementation, mark completed tasks, and produce an actionable delta for re-implementation"
argument-hint: ""
---

# Reconcile Implementation with Revised Spec

After a spec revision changes the task list, this command scans the existing codebase to determine which tasks are already satisfied, which need rework, and which are new. It produces a reconciled `tasks.md` where `/speckit-implement` can pick up only the delta.

## Ship Pipeline Guard

If `.specify/.spex-state` exists with `mode: "ship"`, return immediately.

## Resolve Context

```bash
PREREQ=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQ" | jq -r '.FEATURE_DIR')
BRANCH=$(git branch --show-current)
```

Verify required artifacts:
```bash
[ -f "${FEATURE_DIR}/spec.md" ] || { echo "ERROR: No spec.md"; exit 1; }
[ -f "${FEATURE_DIR}/tasks.md" ] || { echo "ERROR: No tasks.md"; exit 1; }
[ -f "${FEATURE_DIR}/plan.md" ] || { echo "ERROR: No plan.md"; exit 1; }
```

## Detect Existing Implementation

Check whether implementation work already exists on this branch:

```bash
# Count non-spec commits on the feature branch
IMPL_FILES=$(git diff --name-only main...HEAD 2>/dev/null | grep -v '^specs/' | grep -v '^brainstorm/' | grep -v '^\.' | head -50)
IMPL_FILE_COUNT=$(echo "$IMPL_FILES" | grep -c . 2>/dev/null || echo 0)
```

If no implementation files are found (`IMPL_FILE_COUNT` is 0):
```
No implementation files detected on this branch.
Nothing to reconcile. Run /speckit-implement to start fresh.
```
Return.

## Read Artifacts

1. **tasks.md**: Parse the full task list. Extract each task's:
   - ID (e.g., `T01`, `1.1`)
   - Status (`[ ]` or `[X]`)
   - Description
   - File paths mentioned in the task
   - Phase assignment
   - Parallel marker `[P]` if present

2. **plan.md**: Read for architecture context, file structure, and module organization to understand what each task produces.

3. **spec.md**: Read for requirements to understand what "satisfied" means for each task.

## Analyze Each Task Against Existing Code

For each task in tasks.md that is currently `[ ]` (not yet marked complete):

### Step 1: Identify Expected Output

From the task description and plan context, determine what the task should produce:
- Files to create or modify (extract paths from the task description)
- Functions, classes, or exports to add
- Tests to write
- Configuration changes

### Step 2: Check Against Existing Code

For each expected output:

```bash
# Check if mentioned files exist
for FILE in <expected_files>; do
  [ -f "$FILE" ] && echo "EXISTS: $FILE" || echo "MISSING: $FILE"
done
```

For files that exist, read them and assess whether the task's intent is satisfied:
- Does the file contain the expected functions/classes?
- Does the implementation match the spec requirements referenced by the task?
- Are the tests present and covering the expected behavior?

### Step 3: Classify the Task

Assign each task one of three statuses:

- **DONE**: The existing code fully satisfies this task. All expected files exist, functions are implemented, tests cover the behavior. Mark as `[X]`.

- **REWORK**: The existing code partially covers this task, but the spec revision changed requirements that affect it. The code exists but needs modification. Mark as `[ ]` and add a `<!-- REWORK: description of what needs to change -->` comment.

- **NEW**: No existing code addresses this task. It was added by the spec revision. Keep as `[ ]`.

## Present Reconciliation Report

After analyzing all tasks, present the findings:

```
## Reconciliation Report

**Tasks analyzed**: N total

| Status  | Count | Tasks |
|---------|-------|-------|
| DONE    | X     | T01, T03, T05, ... |
| REWORK  | Y     | T04, T08, ...      |
| NEW     | Z     | T12, T13, ...      |

### DONE (will be marked [X])

These tasks are fully satisfied by existing code:
- T01: Create events.py module — exists at agent_eval/events.py
- T03: Add EventType enum — exists in events.py with all required types
...

### REWORK (need modification)

These tasks have existing code that needs updating for the revised spec:
- T04: Parse tool results — exists but needs 50K cap (was unlimited)
  Files: agent_eval/events.py:parse_tool_result()
- T08: Template variable — exists as {{ stdout }}, needs rename to {{ conversation }}
  Files: agent_eval/judges/llm.py
...

### NEW (no existing code)

These tasks were added by the spec revision:
- T12: Subagent transcript merging
- T13: Deduplication by message ID
...
```

Use AskUserQuestion (`multiSelect: false`, header: "Reconcile"):

**"Apply this reconciliation to tasks.md?"**

- "Apply all": "Mark DONE tasks as [X], add REWORK comments, keep NEW as [ ]"
- "Review individually": "Go through each DONE/REWORK classification for confirmation"
- "Cancel": "Leave tasks.md unchanged"

### If "Review individually"

For each task classified as DONE, ask for confirmation:

Use AskUserQuestion (`multiSelect: true`, header: "Confirm"):

**"Which DONE classifications are correct? Unselected tasks will remain [ ]."**

Options: one per DONE task (label: task ID, description: evidence summary)

Then for each REWORK task, show the rework description and ask if it's accurate.

## Apply to tasks.md

Update `${FEATURE_DIR}/tasks.md`:

1. Mark confirmed DONE tasks as `[X]`
2. For REWORK tasks, keep as `[ ]` and append a rework hint comment after the task line:
   ```markdown
   - [ ] T04 [core] Implement tool result parsing with size cap `agent_eval/events.py`
     <!-- REWORK: Add 50K char cap to parse_tool_result(), was unlimited. See spec §3.4 -->
   ```
3. NEW tasks remain as `[ ]` (no annotation needed)

## Update REVIEWERS.md

Append a reconciliation note to the revision history in REVIEWERS.md:

```markdown
### Reconciliation (YYYY-MM-DD)

**Existing implementation scanned**: N files on branch
**Task reconciliation**: X DONE, Y REWORK, Z NEW out of T total
**Delta for re-implementation**: Y + Z = D tasks remaining
```

## Suggest Next Step

```
## Reconciliation Complete

tasks.md updated: X tasks marked [X], Y marked for rework, Z new
Delta: D tasks remaining for /speckit-implement

Next step:
  /speckit-implement    Run implementation for remaining [ ] tasks
```

If the delta is 0 (all tasks satisfied):
```
All tasks are satisfied by existing code. No re-implementation needed.

Next step:
  /speckit-spex-gates-review-code    Verify compliance with revised spec
```
