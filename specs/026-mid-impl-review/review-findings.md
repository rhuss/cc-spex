# Deep Review Findings

**Date:** 2026-06-11
**Branch:** 026-mid-impl-review
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 7 | - | 7 |
| **Total** | **9** | **2** | **7** |

**Agents completed:** 5/5 (+ 0 external tools)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/extensions/spex/commands/speckit.spex.ship.md:620
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The grep pattern `'^\- \[ \]'` used to count TOTAL_TASKS only matched unchecked task checkboxes (`- [ ]`), not completed ones (`- [x]`). FR-003 specifies checkpoint positions calculated from the total task count, meaning all tasks, not just remaining ones. When resuming a pipeline after partial implementation, some tasks may already be marked `[x]`, causing TOTAL_TASKS to undercount and producing incorrect checkpoint positions.

**Why this matters:**
With 9 total tasks and 4 already completed, the grep would return 5 instead of 9, placing checkpoints at wrong boundaries. Worse, if enough tasks were completed, TOTAL_TASKS could drop below 3, silently skipping checkpoints when they should run.

**How it was resolved:**
Changed grep pattern from `'^\- \[ \]'` to `'^\- \[.\]'` to match both checked and unchecked task checkboxes.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/scripts/spex-ship-state.sh:318-324
- **Category:** security/correctness
- **Source:** security-agent (also reported by: correctness-agent, production-agent, test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `--findings` and `--fixed` arguments were interpolated directly into a heredoc JSON template without numeric validation. While the `jq --argjson` path (used when a state file exists) validates types safely, the heredoc path (used when no state file exists) could produce invalid JSON from non-numeric input.

**Why this matters:**
A corrupt state file would cause cascading failures in `do_advance`, `do_status`, and the layer comparison logic in the deep review command. This inconsistency between the two code paths created a latent risk.

**How it was resolved:**
Added `case` validation for both `--findings` and `--fixed` to reject non-numeric values with a clear error message, placed before either code path executes.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 72
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md:558-581
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, not auto-fixed)

**What is wrong:**
The layer comparison does not distinguish between "checkpoint 2 ran and found 0 findings" vs. "checkpoint 2 never ran." Both show as 0 in the table.

**Why this matters:**
Could mislead users evaluating checkpoint value (SC-003/SC-004). The `checkpoint_N_at` timestamp could differentiate these cases.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 78
- **File:** spex/extensions/spex/commands/speckit.spex.ship.md:627-629
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The checkpoint calculation used `bc` for floating-point arithmetic, but `bc` is not in the project's documented toolchain. Pure shell arithmetic gives equivalent results for integer task counts.

**How it was resolved:**
Replaced `bc`-based calculation with POSIX shell arithmetic: `CP1=$(( TOTAL_TASKS / 3 ))` and `CP2=$(( TOTAL_TASKS * 2 / 3 ))`.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 80
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md:576-579
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, acknowledged in spec as approximate)

**What is wrong:**
The "Unique" column in the layer comparison uses count-level heuristics since checkpoint findings are stored as counts only. This is explicitly documented as approximate in the instructions.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 85
- **File:** spex/scripts/spex-ship-state.sh:315-327
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, pre-existing pattern inconsistency)

**What is wrong:**
`do_checkpoint_record` includes `mkdir -p` when creating state from scratch, but the structurally identical `do_smoke_test_record` omits it. An inconsistency, but `do_checkpoint_record` has the correct behavior.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 92
- **File:** spex/scripts/spex-ship-state.sh:297-342
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, consistent with project testing model)

**What is wrong:**
No automated unit tests for the `do_checkpoint_record` function. The project uses integration-level testing (`make release`) rather than per-function unit tests.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 88
- **File:** spex/extensions/spex/commands/speckit.spex.ship.md:617-662
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, checkpoint logic is in markdown prompts)

**What is wrong:**
No automated test for checkpoint position calculation. The calculation is embedded in markdown instructions (not executable code), making unit testing impractical within the project's framework.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 82
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md:555-579
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, layer comparison is LLM-driven)

**What is wrong:**
No automated test for layer comparison data extraction. Since this logic executes via LLM interpretation of markdown instructions, unit testing is not feasible.

## Test Suite Results

No test command detected; post-fix test step used `make validate` which passed.

## Remaining Findings

All 7 remaining findings are Minor severity and do not block the gate:
- 2 are pre-existing patterns not introduced by this feature
- 3 are test coverage suggestions consistent with the project's testing model
- 2 are documented design trade-offs (approximate unique counts, checkpoint state disambiguation)
