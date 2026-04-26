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
if [ ! -f "spex/extensions/spex-collab/extension.yml" ]; then
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

## Detect Task Phases

Parse tasks.md for heading-based groupings. Look for these patterns:

1. `## Phase N:` headings (e.g., `## Phase 1: Setup`)
2. `## USN` or `## US1:` headings (user story groupings)
3. Any `## ` heading that contains task items (`- [ ] T###`) below it

For each heading group:
- Record the phase name (heading text)
- Collect all task IDs (lines matching `- [ ] T[0-9]+` or `- [X] T[0-9]+`)
- Count total tasks and completed tasks

If no phase-like headings are found, treat all tasks as a single phase named "All Tasks".

## Present Phase Split Proposal

Display the parsed phases as a table:

```
## Proposed PR Split

| Phase | Name | Tasks | Completed | Task IDs |
|-------|------|-------|-----------|----------|
| 1     | Setup (Extension Scaffold) | 3 | 0 | T001, T002, T003 |
| 2     | US1 - Spec PR with REVIEWERS.md | 6 | 0 | T004-T009 |
| 3     | US2 - Phase-Based Implementation PRs | 10 | 0 | T010-T019 |
| 4     | US3 - Code PR with Updated REVIEWERS.md | 3 | 0 | T020-T022 |
| 5     | Polish & Integration | 6 | 0 | T023-T028 |

Each phase becomes a separate PR for focused review.
```

Use AskUserQuestion to ask:

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
Implementation will pause after each phase for PR creation.
Invoke `/speckit.spex-collab.phase-manager` after each phase to manage PRs.
```
