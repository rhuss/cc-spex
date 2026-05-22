# Deep Review Findings

**Date:** 2026-05-22
**Branch:** 019-harden-deep-review
**Rounds:** 0 (no fix loop needed)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 1 | 1 | 0 |
| **Total** | **1** | **1** | **0** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md:306
- **Category:** architecture
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (pre-loop)

**What is wrong:**
The finding schema's `category` field lists allowed values as `correctness|architecture|security|production-readiness|test-quality|external` but the new test-suite findings introduced by this feature use `category: "regression"`, which was not included in the schema's enumeration.

**Why this matters:**
Any downstream tooling or validation that parses the finding schema would not recognize "regression" as a valid category. While the schema is documentation (not enforced programmatically), inconsistency between the schema definition and the actual values used by the test-suite source creates confusion for implementers and reviewers.

**How it was resolved:**
Added `|regression` to the category field in the finding schema at line 306, making the schema consistent with the test-suite finding format defined in Step 7.6.

**External tool analysis (CodeRabbit):**
> The finding schema is missing the "regression" category used by test-suite findings; update the schema's allowed category list (the array/string that currently contains correctness|architecture|security|production-readiness|test-quality|external) to include "regression", and ensure any documentation/validation that enumerates categories and the agent summary table (which references "Test Suite (regression)") is updated to accept and display "regression" as a valid category.

## Post-Fix Spec Coverage

No code was removed during the fix. Spec coverage check skipped.

## Test Suite Results

No test command detected; post-fix test step was skipped. This project is a markdown-driven AI agent skill (no compiled code or test suite).

## Remaining Findings

No remaining findings. All issues resolved.
