# Data Model: Guided Smoke Test

## Smoke Test State (extension of .specify/.spex-state)

### Fields added to state file

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| smoke_test_completed | boolean | no | Whether all scenarios passed/were confirmed |
| smoke_test_at | ISO 8601 string | no | When the smoke test was run |
| smoke_test_scenarios | integer | no | Number of scenarios completed (passed + skipped) |
| smoke_test_total | integer | no | Total number of scenarios found in spec |
| smoke_test_skipped | integer | no | Number of scenarios the user skipped |

### State Transitions

```
No smoke test run:
    → smoke_test_completed: absent

Smoke test started:
    → smoke_test_at: <timestamp>, smoke_test_completed: false

All scenarios confirmed (passed or skipped):
    → smoke_test_completed: true, smoke_test_scenarios: N, smoke_test_total: N

User exits early:
    → smoke_test_completed: false, smoke_test_scenarios: <completed>, smoke_test_total: <total>
```

## Parsed Scenario Structure (in-memory only, not persisted)

Each acceptance scenario parsed from spec.md is represented as:

| Field | Type | Description |
|-------|------|-------------|
| index | integer | 1-based position within the user story |
| story | string | User story title (e.g., "User Story 1 - Interactive Smoke Test...") |
| given | string | Precondition text (from **Given** clause) |
| when | string | Action text (from **When** clause) |
| then | string | Expected outcome text (from **Then** clause) |
| status | string | One of: `pending`, `passed`, `failed`, `skipped` |

## Ship Pipeline Stage Map (updated)

| Index | Stage | Description |
|-------|-------|-------------|
| 0 | specify | Generate spec from brainstorm |
| 1 | clarify | Resolve spec ambiguities |
| 2 | review-spec | Validate spec quality |
| 3 | plan | Generate implementation plan |
| 4 | tasks | Generate task breakdown |
| 5 | review-plan | Validate plan and task quality |
| 6 | implement | Execute implementation |
| 7 | review-code | Spec compliance + code review + deep review |
| 8 | smoke-test | Interactive smoke test (always pauses) → PIPELINE STOPS |

Finish is no longer a pipeline stage. The user runs `/speckit-spex-finish` manually after the pipeline stops.
