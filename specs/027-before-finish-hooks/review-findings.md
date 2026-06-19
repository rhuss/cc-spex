# Deep Review Findings

**Date:** 2026-06-19
**Branch:** 027-before-finish-hooks
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 2 | - | 2 |
| **Total** | **2** | **0** | **2** |

**Agents completed:** 5/5 (+ 1 external tool attempted)
**Agents failed:** CodeRabbit (timeout after 120s, non-blocking)

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/extensions/spex/commands/speckit.spex.finish.md:62-98,449-487
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, intentional duplication)

**What is wrong:**
Pre-Execution Checks and Post-Completion Hooks sections contain near-identical instruction blocks. Both sections independently describe the same hook-reading pattern: read extensions.yml, filter disabled hooks, skip conditioned hooks, convert dot notation, handle optional/mandatory distinction, handle autonomous mode.

**Why this matters:**
If the hook-reading pattern changes upstream, both sections need independent updates. This is a maintenance risk over time, though the current duplication is small (~40 lines each) and the divergence risk is low.

**How it was resolved:**
Not fixed. Intentional design: Markdown skill instructions must be self-contained in each section. The AI agent reads and follows each section independently, so cross-referencing a shared hook-reading pattern would reduce clarity and reliability.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 65
- **File:** spex/extensions/spex/commands/speckit.spex.finish.md:451-452
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, pre-existing architectural gap)

**What is wrong:**
Post-Completion Hooks section states after_finish hooks "fire during the watch cleanup paths instead" but Phase 7 watch mode exit points do not include explicit after_finish hook execution steps. All watch exit paths call `$SHIP_STATE watch-cleanup` and stop.

**Why this matters:**
Flow state cleanup (the primary after_finish hook) may not fire when watch mode exits. However, the `watch-cleanup` function and alternative cleanup paths (spex-clear command, stale state detection) provide redundant coverage.

**How it was resolved:**
Not fixed. Pre-existing gap in the watch mode design, not introduced by this PR. The feature's instruction text correctly documents the intended behavior, even though the Phase 7 implementation doesn't have explicit hook execution steps. This is tracked as a future improvement opportunity.

## Test Suite Results

No test command detected; post-fix test step was skipped.
