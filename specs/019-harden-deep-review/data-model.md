# Data Model: Harden Deep Review Process

## Entities

### Test Command Configuration

Added to `deep-review-config.yml`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `test_command` | string | (empty) | Override auto-detected test command. When set, skips auto-detection. |
| `test_timeout_seconds` | integer | 300 | Maximum seconds for test suite execution before timeout. |

### Test Suite Finding

Extension of the existing finding schema for test-originated findings:

| Field | Value | Notes |
|-------|-------|-------|
| `source_agent` | `"test-suite"` | Distinguishes from review agent findings |
| `category` | `"regression"` | Enables separate tracking in summary table |
| `confidence` | `95` | High confidence (test failures are objective) |
| `severity` | `"Critical"` | All test failures are Critical |
| `round_found` | N | The fix round that introduced the regression |

### Review Hints File

| Attribute | Value |
|-----------|-------|
| Path | `.specify/review-hints.md` |
| Format | Plain markdown (flat file) |
| Required | No (opt-in) |
| Injection target | Common preamble item 10, before agent-specific prompts |

## Relationships

- Test Command Configuration is read by the fix loop (Step 7) in `speckit.spex-deep-review.run.md`
- Test Suite Findings enter the standard finding schema and are processed by the merge/dedup logic (Step 5) and gate check (Step 6)
- Review Hints content is injected into every review agent dispatch (Step 3)

## State Transitions

No new state machines. Test suite execution is a synchronous step within the existing fix loop round.

```
Fix Round N:
  Apply fixes -> Stage changes -> Run test suite -> Re-dispatch agents -> Gate check
                                  ^^^^^^^^^^^^^^^
                                  NEW STEP
```
