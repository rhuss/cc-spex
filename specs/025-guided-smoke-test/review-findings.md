# Deep Review Findings

**Date:** 2026-06-11
**Branch:** 025-guided-smoke-test
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** manual

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 1 | 0 |
| Minor | 1 | 1 | 0 |
| **Total** | **2** | **2** | **0** |

**Agents completed:** 5/5 (+ 0 external tools)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/scripts/spex-ship-statusline.sh:192
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The jq expression `.smoke_test_completed // empty` uses the alternative operator (`//`),
which treats JSON `false` as falsy and returns `empty` instead of `"false"`. This means
when `smoke_test_completed` is `false` (partial completion), the statusline never enters
the `elif [ "$smoke_completed" = "false" ]` branch, so the "ST N/M" partial progress
indicator is never displayed.

**Why this matters:**
Users who partially complete a smoke test (e.g., exiting early after 2 of 5 scenarios)
would see no smoke test indicator at all in the statusline, losing visibility into
their progress. The feature spec explicitly requires partial completion to be visible
(User Story 4, Acceptance Scenario 2).

**How it was resolved:**
Changed `jq -r '.smoke_test_completed // empty'` to `jq -r '.smoke_test_completed | tostring'`.
The `tostring` filter correctly maps: `true` -> `"true"`, `false` -> `"false"`, `null` -> `"null"`.
This distinguishes all three states (completed, partial, absent).

### FINDING-2
- **Severity:** Minor
- **Confidence:** 80
- **File:** spex/scripts/spex-ship-state.sh:1-15
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The header comment block documenting available commands was missing the
`smoke-test-record` subcommand, making the usage documentation incomplete.

**Why this matters:**
Developers reading the script header to understand available commands would not
know about `smoke-test-record` without reading the full source. The usage block
is the primary discoverability mechanism.

**How it was resolved:**
Added `smoke-test-record` with its flags to the usage comment block.

## Post-Fix Spec Coverage

All spec requirements verified after fix loop. No code was removed during fixes.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 | smoke-test.md Step 1 | OK |
| FR-002 | smoke-test.md Step 3 | OK |
| FR-003 | smoke-test.md Step 2 | OK |
| FR-004 | smoke-test.md Step 2 | OK |
| FR-005 | smoke-test.md Step 3f | OK |
| FR-006 | smoke-test.md Step 3e | OK |
| FR-007 | spex-ship-state.sh:do_smoke_test_record | OK |
| FR-008 | verify.md Step 0 | OK |
| FR-009 | verify.md Step 0 | OK |
| FR-010 | ship.md Stage 8, spex-ship-state.sh:STAGES | OK |
| FR-011 | ship.md Stage 8, smoke-test.md | OK |
| FR-012 | ship.md Stage 8 | OK |
| FR-013 | smoke-test.md Step 1 | OK |
| FR-014 | smoke-test.md Step 2 | OK |
| FR-015 | smoke-test.md Step 2 | OK |

## Remaining Findings

None. All findings resolved.
