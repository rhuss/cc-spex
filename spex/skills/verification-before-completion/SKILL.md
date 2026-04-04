---
name: verification-before-completion
description: Extended verification including tests AND spec compliance - runs tests, validates spec compliance, checks for drift, blocks completion on failures
---

# Verification Before Completion (Spec-Aware)

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

Verify implementation is complete by running tests AND validating spec compliance.

**Key Additions from Standard Verification:**
- Step 1: Run tests (existing behavior)
- **Step 2: Code hygiene review** (mechanical defect detection)
- **Step 3: Validate spec compliance** (spec-driven)
- **Step 4: Check for spec drift** (spec-driven)
- Blocks completion if tests, code hygiene, OR spec compliance fails

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. CHECK SPEC: Does implementation match spec?
   - If NO: State actual compliance with evidence
   - If YES: State compliance score WITH evidence
6. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## When to Use

- After implementation and code review
- Before claiming work is complete
- Before committing/merging/deploying
- As final gate in `/speckit-implement` (via superpowers trait overlay)

## Spec Selection

If a spec path is provided as an argument, use it directly.

Otherwise, attempt branch-based resolution:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
```

If this succeeds (outputs JSON with `FEATURE_SPEC`), use the resolved spec path. Parse the JSON to extract `FEATURE_SPEC` and `FEATURE_DIR`.

If this fails (not on a feature branch, no matching spec directory), fall back to interactive selection:

```bash
fd -t f "spec.md" specs/ 2>/dev/null | head -20
```

**If specs found:** Present list and ask user to select one using AskUserQuestion.

**If no specs found:** Inform user:
```
No specs found in specs/ directory.

Verification requires a spec to validate against.
Use `spex:brainstorm` or `/speckit-specify` to create one first.
```

## The Process

### 1. Run Tests

**Execute all tests:**
```bash
# Run full test suite
npm test  # or pytest, go test, etc.
```

**Check results:**
- All tests passing?
- No flaky tests?
- Coverage adequate?

**If tests fail:**
- STOP: Fix tests before proceeding
- Do not skip this step
- Do not claim completion

### 2. Code Hygiene Review

**Before checking spec compliance, review every changed file for mechanical defects.
These are craft-level issues that no spec describes but that cause real bugs.**

**For each function you wrote or modified, check:**

#### Dead Code and Logic
- [ ] Every conditional branch produces a **different** outcome (no branches that do the same thing)
- [ ] Every parameter is **actually used** to change behavior (no unused parameters)
- [ ] Every exported function has **at least one caller** outside tests (no orphaned API surface)
- [ ] No variables assigned but never read

#### Copy and Mutation Safety
- [ ] When copying a data structure, verify whether **nested references are shared**
- [ ] If the copy is later mutated, confirm the original is **not affected**
- [ ] If a function receives a pointer/reference, verify whether it is expected to **mutate or read-only**

#### Cleanup and Consistency
- [ ] When removing/disabling something, verify **all references** to it are also cleaned up (no orphaned entries, dangling references, stale indices)
- [ ] When adding to a collection, verify **duplicates are handled** (deduplicate or reject)
- [ ] When deriving a value from an identifier, verify the **derivation uses the correct source** (e.g., a display name vs an internal ID vs a type name are different things)

#### Unnecessary Operations
- [ ] No sorting/ordering when the result doesn't depend on order (counting, summing, existence checks)
- [ ] No intermediate data structures that serve no purpose (building a list just to iterate it once)

**If any issue found:** Fix before proceeding. These are not style nits; they are latent bugs.

### 3. Validate Spec Compliance

**Load spec:**
```bash
cat specs/features/[feature-name].md
```

**Check each requirement:**

```markdown
Functional Requirement 1: [From spec]
  IMPLEMENTED / MISSING
  TESTED / UNTESTED
  MATCHES SPEC / DEVIATION

Functional Requirement 2: [From spec]
  ...
```

**Verify:**
- All requirements implemented
- All requirements tested
- All behavior matches spec
- No missing features
- No extra features (or documented)

**Calculate compliance:**
```
Spec Compliance: X/X requirements = XX%
```

**If compliance < 100%:**
- STOP: Use `spex:evolve` to reconcile
- Document all deviations
- Do not proceed until resolved

### 4. Check for Spec Drift

**Compare:**
- What spec says NOW
- What code does NOW
- Any divergence?

**Common drift sources:**
- Spec updated but code not
- Code changed but spec not
- Undocumented additions
- Forgotten requirements

**If drift detected:**
- Document each instance
- Use `spex:evolve` to reconcile
- Do not proceed with drift

### 5. Verify Success Criteria

**From spec, check each criterion:**

```markdown
Success Criteria (from spec):
- [ ] Criterion 1: [Description]
      Status: Met / Not met
      Evidence: [How verified]

- [ ] Criterion 2: [Description]
      ...
```

**All criteria must be met.**

If any criterion not met:
- STOP: Criterion not met
- Implement missing piece
- Re-verify

### 6. Generate Verification Report

**Report structure:**

```markdown
# Verification Report: [Feature Name]

**Date:** YYYY-MM-DD
**Spec:** specs/features/[feature].md

## Test Results

**Status:** PASS / FAIL

```
[Test output]
```

**Summary:**
- Total: X tests
- Passed: X
- Failed: X
- Coverage: XX%

## Spec Compliance

**Status:** COMPLIANT / NON-COMPLIANT

**Compliance Score:** XX%

### Requirements Status
- Functional: X/X (XX%)
- Error Cases: X/X (XX%)
- Edge Cases: X/X (XX%)
- Non-Functional: X/X (XX%)

### Deviations
[List any deviations found]

## Spec Drift Check

**Status:** NO DRIFT / DRIFT DETECTED

[Details if drift found]

## Success Criteria

**Status:** ALL MET / INCOMPLETE

- [x] Criterion 1
- [x] Criterion 2
...

## Overall Status

**VERIFIED - Ready for completion**

OR

**NOT VERIFIED - Issues must be resolved**

**Blocking Issues:**
- [Issue 1]
- [Issue 2]

**Next Steps:**
[What needs to be done]
```

### 7. Make Go/No-Go Decision

**All conditions must be true:**
- [x] All tests passing
- [x] Code hygiene review clean (no dead code, no mutation bugs, no orphans)
- [x] Spec compliance 100%
- [x] No spec drift
- [x] All success criteria met

**If ALL true:**
- VERIFIED: Proceed to completion
- Safe to commit/merge/deploy
- **Write verification marker** so the commit gate hook allows the commit:
  ```bash
  touch "${TMPDIR:-/tmp}/.claude-spex-verified-${SESSION_ID}"
  ```
  (The SESSION_ID is available from the hook context. If not, use a stable session identifier.)

**If ANY false:**
- NOT VERIFIED: Block completion
- Fix issues before proceeding
- Re-run verification after fixes

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Spec compliant | Line-by-line requirement check | "Looks complete" |
| Linter clean | Linter output: 0 errors | Partial check |
| Build succeeds | Build command: exit 0 | Linter passing |
| Bug fixed | Test original symptom: passes | Code changed |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!")
- About to commit/push/PR without verification
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**
- **Modified CLAUDE.md without explicit user request** (CLAUDE.md is user-maintained, never auto-update)

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence is not evidence |
| "Just this once" | No exceptions |
| "Tests pass" | Did you check spec compliance? |
| "Spec compliant" | Did you run the tests? |
| "I'm tired" | Exhaustion is not an excuse |
| "Partial check is enough" | Partial proves nothing |

## Verification Checklist

Use TodoWrite to track:

- [ ] Run full test suite
- [ ] Verify all tests passing
- [ ] Code hygiene: check for dead branches and unused parameters
- [ ] Code hygiene: check copy/mutation safety
- [ ] Code hygiene: check cleanup consistency (no orphans)
- [ ] Code hygiene: check for unnecessary operations
- [ ] Code hygiene: verify CLAUDE.md was not modified (revert if auto-modified)
- [ ] Load specification
- [ ] Validate spec compliance for all requirements
- [ ] Check for spec drift
- [ ] Verify all success criteria met
- [ ] Generate verification report
- [ ] Make go/no-go decision
- [ ] If not verified: Document blocking issues
- [ ] If verified: Proceed to completion

## Example: Verification PASS

```
You: Running verification before completion...

Step 1: Running tests...

$ npm test

All tests passing (24/24)
Coverage: 95%

Step 2: Validating spec compliance...

Reading spec: specs/features/user-profile-api.md

Checking requirements:
COMPLIANT: Functional Requirement 1: PUT endpoint - Implemented & tested
COMPLIANT: Functional Requirement 2: Validation - Implemented & tested
COMPLIANT: Functional Requirement 3: Auth - Implemented & tested
COMPLIANT: Functional Requirement 4: Authorization - Implemented & tested
COMPLIANT: Functional Requirement 5: Response format - Implemented & tested
COMPLIANT: Functional Requirement 6: Partial updates - Implemented & tested

COMPLIANT: Error Case 1: Missing JWT - Handled & tested
COMPLIANT: Error Case 2: User not found - Handled & tested
COMPLIANT: Error Case 3: Validation failure - Handled & tested
COMPLIANT: Error Case 4: Authorization failure - Handled & tested

COMPLIANT: Edge Case 1: Empty update - Handled & tested
COMPLIANT: Edge Case 2: Invalid avatar URL - Handled & tested
COMPLIANT: Edge Case 3: Special characters in name - Handled & tested

Spec Compliance: 13/13 = 100%

Step 3: Checking for spec drift...

Comparing spec to implementation...
No drift detected

Step 4: Verifying success criteria...

From spec:
MET: Authenticated users can update their profile
MET: Validation errors return 422 with clear messages
MET: Users cannot update other users' profiles
MET: All edge cases handled gracefully

All criteria met

=== VERIFICATION REPORT ===

Tests: PASS (24/24)
Spec Compliance: 100%
Spec Drift: None
Success Criteria: All met

**OVERALL: VERIFIED**

Implementation is complete and verified. Ready for commit/merge.
```

## Example: Verification FAIL

```
You: Running verification before completion...

Step 1: Running tests...

$ npm test

Tests FAILED (22/24 passing, 2 failing)

Failures:
1. "Should handle database connection errors"
   Error: Connection retry not implemented

2. "Should return 503 when database unavailable"
   Error: Returns 500 instead of 503

**BLOCKING: Tests must pass before proceeding**

Step 2: Validating spec compliance...

Reading spec: specs/features/user-profile-api.md

Checking requirements:
[checks requirements...]

DEVIATION: Non-Functional Requirement 1: Database retry logic
   Status: Not implemented
   Spec says: "3 retry attempts with exponential backoff"
   Code does: Single attempt, no retry

Spec Compliance: 12/13 = 92%

Step 3: Checking success criteria...

From spec:
MET: Authenticated users can update their profile
MET: Validation errors return 422
NOT MET: Handles database failures gracefully (missing retry logic)
MET: Users cannot update other users' profiles

=== VERIFICATION REPORT ===

Tests: FAIL (2 failures)
Spec Compliance: 92% (missing retry logic)
Success Criteria: 3/4 met

**OVERALL: NOT VERIFIED**

**Blocking Issues:**
1. Database retry logic not implemented (from spec)
2. Tests failing for error handling
3. Returns wrong HTTP status (500 vs 503)

**Next Steps:**
1. Implement database retry logic per spec
2. Fix HTTP status code
3. Re-run verification

**DO NOT PROCEED until all issues resolved.**
```

## Common Failure Scenarios

### Scenario: Tests Pass but Spec Compliance Fails

```
Tests: 24/24 passing
Spec Compliance: 85%
BLOCKED

Issue: Tests don't cover all spec requirements

Action: Add tests for uncovered requirements, re-verify
```

### Scenario: Spec Compliant but Tests Fail

```
Tests: 20/24 passing
Spec Compliance: 100%
BLOCKED

Issue: Implementation exists but has bugs

Action: Fix bugs, ensure tests pass, re-verify
```

### Scenario: Both Pass but Drift Detected

```
Tests: 24/24 passing
Spec Compliance: 100%
Spec Drift: Spec updated after implementation
BLOCKED

Issue: Spec changed, code doesn't reflect changes

Action: Update code or revert spec, re-verify
```

## Quality Gates

**This skill enforces quality gates:**

1. **All tests must pass** (from superpowers)
2. **Code hygiene review clean** (mechanical defects)
3. **100% spec compliance required** (spex)
4. **No spec drift allowed** (spex)
5. **All success criteria must be met** (spex)

**No exceptions. No shortcuts.**

These gates exist to prevent:
- Incomplete implementations
- Untested code
- Spec/code divergence
- False claims of completion

## Remember

**Verification is not optional.**

- Don't skip verification "just this once"
- Don't claim completion without verification
- Don't ignore failing gates

**Verification failures are information.**

- Tests failing? Code has bugs
- Spec compliance failing? Missing features
- Drift detected? Synchronization problem
- Criteria not met? Work incomplete

**No shortcuts for verification.**

Run the command. Read the output. Check the spec. THEN claim the result.

**Fix issues, don't rationalize past them.**

**Evidence before assertions. Always.**

This is non-negotiable.
