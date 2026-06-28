# Data Model: Focused Interactive Smoke Test

## Entities

### Smoke Test Scenario (runtime, parsed from spec)

| Field | Type | Description |
|-------|------|-------------|
| number | Integer | Position in the numbered list (1-based) |
| instruction | String | Prose description from the `## Smoke Test` section |
| verdict | Enum: pass/fail/skip | Set by human during interactive review |
| notes | String (optional) | Reviewer's notes or observations |
| evidence | String (optional) | Captured output, screenshots, or command results |
| retry | Object (optional) | Contains `fix_applied`, `retry_verdict`, `retry_notes` if retried after failure |

### SMOKE-TEST.md Report (persisted file)

| Field | Type | Description |
|-------|------|-------------|
| feature_name | String | From spec title |
| date | Date | Report generation date |
| spec_path | String | Relative path to spec.md |
| result_summary | String | "N passed, M skipped, K failed (out of TOTAL)" |
| scenarios | List[Scenario] | One entry per scenario with evidence and verdict |

## State Transitions

### Scenario Lifecycle

```
[parsed] → [executing] → [evidence_collected] → [verdict_given]
                                                       ↓
                                              [fail] → [investigating] → [fix_applied] → [retrying] → [retry_verdict]
                                              [pass] → (done)
                                              [skip] → (done)
```

## Relationships

- A spec has 0 or 1 `## Smoke Test` sections
- A `## Smoke Test` section has 1-5 scenarios (warns if >5)
- Each scenario produces exactly one verdict (with optional retry)
- All scenarios together produce one SMOKE-TEST.md report
