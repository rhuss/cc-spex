# Data Model: Flow Status Line

## State File (`.specify/.spex-state`)

JSON file tracking active workflow mode. Renamed from `.spex-ship-phase`.

### Ship Mode Schema

```json
{
  "mode": "ship",
  "stage": "specify|clarify|review-spec|plan|tasks|review-plan|implement|review-code|stamp|done",
  "stage_index": 0,
  "total_stages": 9,
  "ask": "always|smart|never",
  "started_at": "2026-04-07T10:30:00Z",
  "retries": 0,
  "status": "running|paused|failed|completed",
  "brainstorm_file": "brainstorm/NNN-feature.md",
  "feature_branch": "NNN-feature-name"
}
```

**Changes from current**: Added `"mode": "ship"` field. All other fields unchanged.

### Flow Mode Schema

```json
{
  "mode": "flow",
  "started_at": "2026-04-07T10:30:00Z",
  "feature_branch": "015-flow-status-line",
  "spec_dir": "specs/015-flow-status-line",
  "brainstorm_file": "brainstorm/015-feature.md",
  "implemented": false
}
```

**Fields**:
- `mode` (required): Always `"flow"`
- `started_at` (required): ISO 8601 timestamp of flow activation
- `feature_branch` (required): Current branch name
- `spec_dir` (required): Relative path to spec directory from repo root
- `brainstorm_file` (optional): Path to originating brainstorm file
- `implemented` (optional): Set to `true` by speckit-implement on completion. Absent or `false` means not yet implemented.

### State Transitions

```
[no file] --specify--> flow (mode=flow)
flow      --ship-->    ship (mode=ship, overwrites)
flow      --stamp-->   [no file] (deleted after celebration)
ship      --done-->    [no file] (deleted, existing behavior)
```

## Milestone Artifacts

Detected by file existence in `spec_dir`:

| Milestone | Artifact | Detection |
|-----------|----------|-----------|
| specify | `spec.md` | File exists |
| plan | `plan.md` | File exists |
| tasks | `tasks.md` | File exists |
| implement | n/a | `"implemented": true` in state file |

## Review Artifacts

Detected by file existence in `spec_dir`:

| Review | Artifact | Producer |
|--------|----------|----------|
| spec review | `REVIEW-SPEC.md` | `/spex:review-spec` |
| plan review | `REVIEW-PLAN.md` | `/spex:review-plan` |
| code review | `REVIEW-CODE.md` | `/spex:review-code` |

**Transition**: During migration, `REVIEWERS.md` is accepted as fallback for plan review validation in ship pipeline.

## Traits Configuration (`.specify/spex-traits.json`)

Read-only from status line perspective. Existing schema:

```json
{
  "version": 1,
  "traits": {
    "superpowers": true,
    "deep-review": true,
    "teams": false,
    "worktrees": true
  }
}
```

Status line reads `traits` object, filters for `true` values, displays names.
