---
description: "Present phase split proposal before implementation begins"
---

# Phase Split Proposal

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `mode` is `"ship"` or `status` is `"running"`, skip the phase split entirely and return immediately without prompting.

```bash
if [ -f ".specify/.spex-state" ]; then
  MODE=$(jq -r '.mode // empty' .specify/.spex-state 2>/dev/null)
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  if [ "$MODE" = "ship" ] || [ "$STATUS" = "running" ]; then
    echo "Ship mode active, skipping phase split"
  fi
fi
```

If ship mode is detected, return immediately. Do not display any proposal or prompt the user.

## Extension Enabled Check

Verify spex-collab is active:

```bash
if [ ! -f ".specify/extensions/spex-collab/extension.yml" ]; then
  echo "spex-collab extension not found, skipping"
fi
```

If the extension is not found, return without action.

## Check for Existing Phase Plan

If `.specify/.spex-state` already has a `collab.phase_plan` with entries, a phase plan was previously confirmed:

```bash
EXISTING_PLAN=$(jq -r '.collab.phase_plan // empty' .specify/.spex-state 2>/dev/null)
```

If a phase plan exists and has entries:
- Display: "A phase plan already exists from a previous session."
- Show the existing plan as a table
- Ask: "Use existing plan, or create a new one?"
- If user chooses existing: return (implementation proceeds with saved plan)
- If user chooses new: continue with detection below

## Resolve Spec Directory and Read Tasks

```bash
PREREQ=$(.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQ" | jq -r '.FEATURE_DIR')
```

Read `tasks.md` from FEATURE_DIR.

## Estimate File Count

Estimate how many files the feature will touch. This determines whether to propose multi-phase splitting or silently default to single phase.

### Parse File Paths from plan.md

If `plan.md` exists in FEATURE_DIR, extract file path references:

```bash
PLAN_FILE="${FEATURE_DIR}/plan.md"
ESTIMATED_FILES=0
ESTIMATION_SOURCE="heuristic"

if [ -f "$PLAN_FILE" ]; then
  # Extract file paths: match patterns like src/foo/bar.sh, `path/to/file.md`, ./relative/path.yml
  # Filter: must contain a directory separator (/), have a file extension (1-10 chars)
  # Exclude: URLs (http/https), version-like patterns (v1.5)
  FILE_PATHS=$(grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,10}' "$PLAN_FILE" 2>/dev/null | \
    grep '/' | \
    grep -vE '^https?://' | \
    grep -vE '^//' | \
    grep -v '^v[0-9]' | \
    sort -u)
  FILE_COUNT=$(echo "$FILE_PATHS" | grep -c '.' 2>/dev/null || echo "0")

  if [ "$FILE_COUNT" -ge 5 ]; then
    ESTIMATED_FILES=$FILE_COUNT
    ESTIMATION_SOURCE="plan.md"
  fi
fi
```

### Fall Back to Task-Count Heuristic

If fewer than 5 unique file paths were found in plan.md (or plan.md does not exist), use the task-count heuristic:

```bash
if [ "$ESTIMATED_FILES" -eq 0 ]; then
  # Count all task lines (completed or not) in tasks.md
  TASK_COUNT=$(grep -cE '^[[:space:]]*- \[([ Xx])\] T[0-9]+' "${FEATURE_DIR}/tasks.md" 2>/dev/null || echo "0")
  # Estimate: each task touches ~1.5 files on average
  ESTIMATED_FILES=$(echo "$TASK_COUNT * 1.5" | bc 2>/dev/null || echo "$((TASK_COUNT + TASK_COUNT / 2))")
  # Round to integer
  ESTIMATED_FILES=$(printf "%.0f" "$ESTIMATED_FILES" 2>/dev/null || echo "$ESTIMATED_FILES")
  ESTIMATION_SOURCE="heuristic"
fi
```

## Threshold Gate

Read the file threshold from collab-config.yml and compare against the estimated file count. When the estimate is at or below the threshold, silently default to single-phase mode without prompting the user.

```bash
# Read configurable threshold (default: 20)
FILE_THRESHOLD=20
COLLAB_CONFIG=".specify/extensions/spex-collab/collab-config.yml"
if [ -f "$COLLAB_CONFIG" ]; then
  CONFIGURED_THRESHOLD=$(yq -r '.phases.file_threshold // 20' "$COLLAB_CONFIG" 2>/dev/null)
  if [ -n "$CONFIGURED_THRESHOLD" ] && [ "$CONFIGURED_THRESHOLD" != "null" ]; then
    FILE_THRESHOLD=$CONFIGURED_THRESHOLD
  fi
fi
```

### Below Threshold: Silent Single Phase

If the estimated file count is at or below the threshold, skip the phase split entirely and default to single-phase mode:

```bash
if [ "$ESTIMATED_FILES" -le "$FILE_THRESHOLD" ]; then
  echo "Estimated files ($ESTIMATED_FILES, source: $ESTIMATION_SOURCE) at or below threshold ($FILE_THRESHOLD). Defaulting to single phase."
  # Fall through to single-phase setup (persisting a single "Full Implementation" phase plan)
fi
```

When below threshold:
1. Do NOT show any phase split prompt or proposal
2. Collect all task IDs from tasks.md into a single phase named "Full Implementation"
3. Persist the single-phase plan to `.spex-state` (see "Persist Phase Plan" section below)
4. Output single-phase implementation instructions (see "Single-Phase Implementation Instructions" section below)
5. Return immediately (skip "Detect Task Phases", "Present Phase Split Proposal", and merge logic)

### Above Threshold: Continue to Phase Detection

If the estimated file count exceeds the threshold, continue to the phase detection and merge logic below:

```bash
if [ "$ESTIMATED_FILES" -gt "$FILE_THRESHOLD" ]; then
  echo "Estimated files ($ESTIMATED_FILES, source: $ESTIMATION_SOURCE) exceeds threshold ($FILE_THRESHOLD). Proposing phase split."
  # Continue to Detect Task Phases
fi
```

## Detect Task Phases

Parse tasks.md for heading-based groupings. Look for these patterns:

1. `## Phase N:` headings (e.g., `## Phase 1: Setup`)
2. `## USN` or `## US1:` headings (user story groupings)
3. Any `## ` heading that contains task items (`- [ ] T###`) below it

For each heading group:
- Record the phase name (heading text)
- Collect all task IDs (lines matching `- [ ] T[0-9]+` or `- [X] T[0-9]+`)
- Count total tasks and completed tasks

If no phase-like headings are found, treat all tasks as a single phase named "Full Implementation".

## Merge Adjacent Small Phases

When the estimated file count exceeds the threshold (meaning we're proposing a multi-phase split), merge adjacent phases that are too small for meaningful PR review. The per-phase merge minimum is 10 files.

### Distribute Files Across Phases

Since plan.md does not map files to specific phases, distribute the estimated file count proportionally based on each phase's task count. Assign leftover files from rounding to the largest phase to prevent truncation loss:

```bash
TOTAL_TASKS=[total tasks across all phases]
ALLOCATED=0
for each phase:
  PHASE_TASKS=[number of tasks in this phase]
  PHASE_FILES=$(( ESTIMATED_FILES * PHASE_TASKS / TOTAL_TASKS ))
  if [ "$PHASE_FILES" -lt 1 ]; then PHASE_FILES=1; fi
  ALLOCATED=$((ALLOCATED + PHASE_FILES))

# Assign rounding remainder to the phase with the most tasks
REMAINDER=$((ESTIMATED_FILES - ALLOCATED))
if [ "$REMAINDER" -gt 0 ]; then
  largest_phase.estimated_files += REMAINDER
fi
```

### Greedy Forward Merge

Iterate through phases and merge adjacent small phases. After the loop, check the trailing phase and merge it backward if it is too small:

```bash
MERGE_MINIMUM=10  # per-phase merge minimum (internal heuristic, not configurable)

merged_phases=()
current_phase=[first phase]
current_files=[first phase's estimated files]

for each remaining phase:
  if current_files < MERGE_MINIMUM:
    # Merge this phase into current: combine names, tasks, and file estimates
    current_phase.name = current_phase.name + " + " + next_phase.name
    current_phase.tasks = current_phase.tasks + next_phase.tasks
    current_files = current_files + next_phase.estimated_files
  else:
    # Current phase is large enough, finalize it
    merged_phases.append(current_phase)
    current_phase = next_phase
    current_files = next_phase.estimated_files

# Finalize the last phase
merged_phases.append(current_phase)

# Trailing-phase fix: if the last phase is too small, merge it into the previous one
if len(merged_phases) > 1 and merged_phases[-1].estimated_files < MERGE_MINIMUM:
  last = merged_phases.pop()
  merged_phases[-1].name = merged_phases[-1].name + " + " + last.name
  merged_phases[-1].tasks = merged_phases[-1].tasks + last.tasks
  merged_phases[-1].estimated_files += last.estimated_files
```

### Post-Merge Check

After merging, check if only one phase remains:

```bash
if [ ${#merged_phases[@]} -eq 1 ]; then
  # Merging reduced everything to a single phase
  # Treat as single-phase mode (no prompt shown)
  # Fall through to single-phase setup
fi
```

If only one phase remains after merging, silently default to single-phase mode (same behavior as threshold-defaulted single phase). Do NOT show a proposal for a single merged phase.

If multiple phases remain after merging, continue to "Present Phase Split Proposal" below. Re-number the merged phases sequentially (1, 2, 3, ...).

## Present Phase Split Proposal

Display the phases (after merging, if applicable) as a table. Merged phases show combined names joined with " + " and include the aggregate task count:

```
## Proposed PR Split

Estimated files: [ESTIMATED_FILES] (source: [ESTIMATION_SOURCE])

| Phase | Name | Est. Files | Tasks | Completed | Task IDs |
|-------|------|-----------|-------|-----------|----------|
| 1     | Setup + US1 | 12 | 9 | 0 | T001-T009 |
| 2     | US2 - Phase-Based Implementation PRs | 15 | 10 | 0 | T010-T019 |
| 3     | US3 + Polish | 18 | 9 | 0 | T020-T028 |

Each phase becomes a separate PR for focused review.
Phases were merged to ensure each touches at least ~10 files for meaningful review.
```

Note: The "Phases were merged..." line is only shown when merging actually reduced the number of phases from the original tasks.md groupings.

{harness:interactive-choice}:

**Question**: "Does this phase split look right for your PRs?"
**Options**:
- "Confirm as-is" - proceed with this grouping
- "Adjust groupings" - let user merge or split phases
- "Single phase (no split)" - treat everything as one PR

If user selects "Adjust groupings":
- Ask which phases to merge or split
- Only allow adjusting phases that have not been completed yet
- Re-display the updated table and confirm again

If user selects "Single phase":
- Combine all tasks into one phase named "Full Implementation"

## Persist Phase Plan

Store the confirmed plan in `.specify/.spex-state` under the `collab` namespace:

```bash
# Read pr_base_branch from extension config if available
PR_BASE="main"
if [ -f ".specify/extensions/spex-collab/collab-config.yml" ]; then
  CONFIGURED_BASE=$(yq -r '.pr_base_branch // "main"' .specify/extensions/spex-collab/collab-config.yml 2>/dev/null)
  if [ -n "$CONFIGURED_BASE" ] && [ "$CONFIGURED_BASE" != "null" ]; then
    PR_BASE="$CONFIGURED_BASE"
  fi
fi
```

Update `.spex-state` with the phase plan using jq. The `collab` object contains:
- `phase_plan`: array of objects with `phase` (int), `name` (string), `tasks` (string array)
- `completed_phases`: empty array (or preserved from existing state)
- `current_phase`: null
- `pr_base_branch`: from config or "main"

```bash
# Example jq update (adapt phase_plan array to actual confirmed phases)
tmp=$(mktemp) && jq --argjson plan '[...]' --arg base "$PR_BASE" '
  .collab = {
    "phase_plan": $plan,
    "completed_phases": (.collab.completed_phases // []),
    "current_phase": null,
    "pr_base_branch": $base
  }
' .specify/.spex-state > "$tmp" && mv "$tmp" .specify/.spex-state
```

## Report

Output confirmation:
```
Phase plan saved to .specify/.spex-state
[N] phases configured, targeting [base_branch] for PRs
```

## Phase-by-Phase Implementation Instructions

After displaying the report, output explicit per-phase execution instructions. These instructions drive the implementation loop, replacing a single `/speckit-implement` invocation with one invocation per phase:

```
## Implementation Plan

Do NOT run `/speckit-implement` without a phase filter. Instead, implement one phase at a time:
```

For each phase in the confirmed plan, output:

```
### Phase [N]: [Phase Name]
Tasks: [task IDs]
Run: /speckit-implement "Implement ONLY tasks [task IDs] (Phase [N]: [Phase Name]). Stop after these tasks are complete."
Then: /speckit-spex-collab-phase-manager
```

After listing all phases, output:

```
Start with Phase 1. After each `/speckit-implement` + `/speckit-spex-collab-phase-manager` cycle,
proceed to the next phase. The phase-manager will handle code review, REVIEWERS.md updates, and PR creation.
```

**IMPORTANT**: After outputting these instructions, do NOT invoke `/speckit-implement` automatically. The instructions are for the user (or the calling workflow) to follow manually, one phase at a time. This ensures the implementation pauses at each phase boundary for review and PR management.

## Single-Phase Implementation Instructions

When single-phase mode is active (either threshold-defaulted or user-selected "Single phase (no split)"), output instructions that run implementation straight through all tasks with phase-manager called only once at the end:

```
## Implementation Plan (Single Phase)

Run implementation for all tasks at once:

### Full Implementation
Tasks: [all task IDs]
Run: /speckit-implement
Then: /speckit-spex-collab-phase-manager
```

The key difference from multi-phase instructions:
- A single `/speckit-implement` call with NO phase filter (runs all tasks)
- Phase-manager is called exactly once after all tasks complete
- No inter-phase pauses or boundaries during implementation
- Phase-manager handles the final review gate and PR creation offer

**IMPORTANT**: In single-phase mode, implementation MUST run continuously through all tasks without any phase-manager interruption. The phase-manager fires only once at the end to offer the review gate and PR creation.
