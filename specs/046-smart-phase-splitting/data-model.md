# Data Model: Smart Phase Splitting

## Entities

### Phase Plan (in `.spex-state`)

The existing `collab.phase_plan` structure in `.spex-state`. No schema changes needed.

```json
{
  "collab": {
    "phase_plan": [
      {"phase": 1, "name": "Full Implementation", "tasks": ["T001", "T002", "..."]}
    ],
    "completed_phases": [],
    "current_phase": null,
    "pr_base_branch": "main"
  }
}
```

**Single-phase indicator**: When `phase_plan` has exactly one entry, the system is in single-phase mode. No new field needed.

### File Estimate (transient, not persisted)

Computed during phase-split execution, used for threshold comparison and merge decisions. Not stored in `.spex-state` or any file.

| Attribute | Type | Description |
|-----------|------|-------------|
| source | string | `"plan.md"` or `"heuristic"` |
| count | integer | Total estimated file count |
| paths | string[] | Deduplicated file paths (when source is plan.md) |

### Collab Config (in `collab-config.yml`)

New `phases` section added to the existing config:

```yaml
phases:
  file_threshold: 20    # minimum estimated files to propose multi-phase split
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| phases.file_threshold | integer | 20 | Estimated file count below which phase splitting is skipped |

## State Transitions

### Phase-Split Decision Flow

```
START
  │
  ├─ Ship mode? ──yes──> SKIP (existing behavior)
  │
  ├─ Existing plan? ──yes──> SHOW existing plan
  │
  ├─ Estimate files
  │   ├─ plan.md has 5+ paths? ──yes──> use plan.md count
  │   └─ fewer than 5 paths? ──yes──> use tasks * 1.5
  │
  ├─ count <= threshold? ──yes──> SINGLE PHASE (silent, no prompt)
  │
  ├─ count > threshold
  │   ├─ Parse phases from tasks.md
  │   ├─ Merge adjacent small phases (< 10 files each)
  │   ├─ Only one phase after merge? ──yes──> SINGLE PHASE (silent)
  │   └─ Multiple phases ──> SHOW proposal (confirm/adjust/single)
  │
  └─ Persist phase plan to .spex-state
```

### Phase-Manager Invocation Flow

```
Single-phase mode (phase_plan length == 1):
  Implementation runs all tasks
  Phase-manager called once at end
  → Review gate + PR offer

Multi-phase mode (phase_plan length > 1):
  Per-phase: implement → phase-manager
  → Review gate + REVIEWERS.md update + PR offer per phase
  (unchanged from current behavior)
```
