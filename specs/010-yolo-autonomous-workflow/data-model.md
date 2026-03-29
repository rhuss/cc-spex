# Data Model: Autonomous Full-Cycle Workflow (spex:yolo)

**Date:** 2026-03-29
**Feature:** 010-yolo-autonomous-workflow

## Entities

### PipelineState

Persisted to `.specify/.spex-yolo-phase` as JSON. Written at each stage transition, read by status line scripts.

| Field | Type | Description |
|-------|------|-------------|
| `stage` | string | Current stage name: `specify`, `clarify`, `review-spec`, `plan`, `review-plan`, `tasks`, `implement`, `deep-review`, `verify` |
| `stage_index` | integer (0-8) | Zero-based index of current stage |
| `total_stages` | integer | Always 9 |
| `autonomy` | string | One of: `cautious`, `balanced`, `autopilot` |
| `started_at` | string (ISO-8601) | Pipeline start timestamp |
| `retries` | integer | Current retry count for active stage (resets per stage) |
| `status` | string | One of: `running`, `paused`, `completed`, `failed` |
| `brainstorm_file` | string | Path to input brainstorm document |
| `feature_branch` | string | Git branch name for this pipeline run |

**Example:**
```json
{
  "stage": "implement",
  "stage_index": 6,
  "total_stages": 9,
  "autonomy": "balanced",
  "started_at": "2026-03-29T10:00:00Z",
  "retries": 0,
  "status": "running",
  "brainstorm_file": "brainstorm/05-yolo-autonomous-workflow.md",
  "feature_branch": "010-yolo-autonomous-workflow"
}
```

### AutonomyLevel

Enum-like value controlling pipeline pause behavior. Not persisted separately (stored in PipelineState).

| Level | Auto-fix Behavior | Pause Behavior |
|-------|-------------------|----------------|
| `cautious` | Never auto-fix | Pause on every finding |
| `balanced` | Auto-fix unambiguous issues (formatting, style, minor) | Pause on ambiguous or architectural issues |
| `autopilot` | Auto-fix everything possible | Only pause on genuine blockers (compilation, missing deps, unresolvable failures) |

### PipelineStage

Ordered sequence of stages. Not persisted as a separate entity; encoded in the skill's logic.

| Index | Stage | Invocation | Produces |
|-------|-------|------------|----------|
| 0 | `specify` | `/speckit.specify` | `spec.md` |
| 1 | `clarify` | `/speckit.clarify` | Updated `spec.md` |
| 2 | `review-spec` | `{Skill: spex:review-spec}` | Review report |
| 3 | `plan` | `/speckit.plan` | `plan.md`, `research.md`, `data-model.md` |
| 4 | `review-plan` | `{Skill: spex:review-plan}` | `REVIEWERS.md` |
| 5 | `tasks` | `/speckit.tasks` | `tasks.md` |
| 6 | `implement` | `/speckit.implement` | Source code |
| 7 | `deep-review` | `{Skill: spex:deep-review}` | Review findings, auto-fixes |
| 8 | `verify` | `{Skill: spex:verification-before-completion}` | Verification report |

### ReviewFinding (referenced, not owned)

Review findings are produced by review-spec, review-plan, review-code, and deep-review stages. The yolo skill does not define a new finding format; it classifies existing findings for autonomy decisions.

**Classification for autonomy:**
- **Unambiguous** (auto-fixable in `balanced`+): formatting, typos, missing imports, style violations, unused variables
- **Ambiguous** (requires judgment in `balanced`): architecture changes, API design, requirement interpretation, performance trade-offs
- **Blocker** (always pauses): compilation errors, missing dependencies, failing tests that can't be auto-resolved, contradictory requirements

## Relationships

```
PipelineState  ──tracks──>  PipelineStage (current)
PipelineState  ──uses──>    AutonomyLevel
PipelineStage  ──produces──> ReviewFinding (for review stages)
PipelineStage  ──may retry──> PipelineStage (same, max 2 cycles)
```

## State Transitions

```
[start] ──validate traits──> specify ──> clarify ──> review-spec ──> plan
    ──> review-plan ──> tasks ──> implement ──> deep-review ──> verify ──> [end]

At any review stage:
  findings? ──autonomy check──> auto-fix ──> re-run (max 2 retries)
                              ──> pause (present to user) ──> user responds ──> resume
                              ──> no findings ──> next stage

On failure (after max retries):
  ──> status: "paused" ──> present findings ──> user guidance ──> resume
```

## Validation Rules

- `stage` must be one of the 9 defined stage names
- `stage_index` must match the stage name's position (0-8)
- `autonomy` must be one of: `cautious`, `balanced`, `autopilot`
- `retries` must be 0, 1, or 2 (max 2 retry cycles)
- `status` transitions: `running` -> `paused` | `completed` | `failed`; `paused` -> `running`
- `brainstorm_file` must exist and be readable at pipeline start
- `feature_branch` is set after specify completes (may be null during specify stage)
