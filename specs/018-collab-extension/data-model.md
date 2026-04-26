# Data Model: spex-collab Extension

**Date**: 2026-04-26

## Entities

### REVIEWERS.md

A Markdown file generated in the spec directory (`specs/<feature>/REVIEWERS.md`).

**Lifecycle**:
1. Created after `after_tasks` hook fires (spec PR content)
2. Updated after each implementation phase completes (code PR content appended)
3. Regenerated on re-run (spec sections replaced, code sections preserved)

**Structure**:

| Section | When Created | Behavior on Re-run |
|---------|-------------|-------------------|
| Feature Overview | after_tasks | Regenerated |
| Scope Boundaries | after_tasks | Regenerated |
| Key Decisions | after_tasks | Regenerated |
| Areas Needing Attention | after_tasks | Regenerated |
| Open Questions | after_tasks | Regenerated |
| Review Checklist | after_tasks | Regenerated |
| Phase N sections | after each phase | Appended (never overwritten) |

**Identity**: One per feature, identified by spec directory path.

### Phase Plan (in `.spex-state`)

Stored under the `collab` namespace in `.specify/.spex-state`.

**Fields**:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `collab.phase_plan` | array of objects | `[]` | Confirmed phase groupings |
| `collab.phase_plan[].phase` | integer | - | Phase number (1-based) |
| `collab.phase_plan[].name` | string | - | Phase display name |
| `collab.phase_plan[].tasks` | array of strings | - | Task IDs in this phase |
| `collab.completed_phases` | array of integers | `[]` | Phase numbers completed |
| `collab.current_phase` | integer or null | `null` | Phase in progress |
| `collab.pr_base_branch` | string | `"main"` | PR target branch |

**Lifecycle**:
1. Created by `phase-split` command (before_implement hook)
2. Updated by `phase-manager` command (after each phase)
3. Read on session resume to skip completed phases

**State transitions**:
```
[phase-split] → phase_plan populated, current_phase = null
[phase starts] → current_phase = N
[phase completes + PR created] → completed_phases += [N], current_phase = null
[phase completes, PR declined] → completed_phases += [N], current_phase = null
[all phases done] → current_phase = null, completed_phases = [1..N]
```

### Extension Configuration

Stored in `.specify/extensions/spex-collab/collab-config.yml`.

**Fields**:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pr_base_branch` | string | `"main"` | Default target branch for PRs |
| `auto_generate_reviewers` | boolean | `true` | Generate REVIEWERS.md automatically |

## Relationships

```
spec.md ──────────┐
plan.md ──────────┤
REVIEW-SPEC.md ───┤──→ REVIEWERS.md (spec sections)
                  │
REVIEW-CODE.md ───┤──→ REVIEWERS.md (code phase sections)
git diff ─────────┘

tasks.md ──→ Phase Plan ──→ .spex-state (collab namespace)
```

## Validation Rules

- Phase numbers are 1-based, sequential, no gaps
- `completed_phases` is always sorted ascending
- `current_phase` is either null or a valid phase number from `phase_plan`
- Completed phases in `phase_plan` are immutable (cannot be re-grouped). Remaining (not-yet-started) phases can be re-grouped by the user via the phase-split command
- REVIEWERS.md phase sections are identified by `## Phase N:` headings
