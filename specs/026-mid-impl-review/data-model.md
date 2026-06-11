# Data Model: Mid-Implementation Review Checkpoints

## Checkpoint State (extension of .specify/.spex-state)

### Fields added to state file

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| checkpoint_1_findings | integer | no | Findings count from 1/3 checkpoint |
| checkpoint_1_fixed | integer | no | Fixed count from 1/3 checkpoint |
| checkpoint_2_findings | integer | no | Findings count from 2/3 checkpoint |
| checkpoint_2_fixed | integer | no | Fixed count from 2/3 checkpoint |

These fields are written by the implementing subagent after each checkpoint completes. They are read by the deep review statistics reporter for the layer comparison.

## Agent Statistics (in-memory, output to console)

### Per-Agent Row

| Field | Type | Description |
|-------|------|-------------|
| agent_name | string | One of: Correctness, Architecture & Idioms, Security, Production Readiness, Test Quality |
| found | integer | Total findings reported by this agent |
| fixed | integer | Findings successfully fixed in the fix loop |
| remaining | integer | found - fixed |

### Layer Comparison Row (ship mode only)

| Field | Type | Description |
|-------|------|-------------|
| layer_name | string | One of: "Checkpoint 1/3", "Checkpoint 2/3", "Final review" |
| findings | integer | Total findings for this layer |
| fixed | integer | Fixed findings for this layer |
| unique | integer | Findings only caught by this layer (not by any other) |

### Unique Finding Calculation

A finding is "unique" to a layer when no other layer reported a finding at the same file path with overlapping line ranges. The comparison uses:
- File path (exact match)
- Line range overlap (if line numbers available; if not, fall back to finding description substring match)
