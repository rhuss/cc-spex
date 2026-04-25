---
description: "Final verification gate: tests, code hygiene, spec compliance, and drift check"
---

# Verification Before Completion (Spec-Aware)

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:
- If `ask` is `"smart"` or `"never"`: suppress all user prompts (do NOT use AskUserQuestion), complete the verification autonomously, and return immediately so the pipeline can advance.
- If `ask` is `"always"`: prompt the user as normal.

```bash
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  ASK=$(jq -r '.ask // "always"' .specify/.spex-state 2>/dev/null)
  if [ "$STATUS" = "running" ] && [ "$ASK" != "always" ]; then
    echo "AUTONOMOUS_MODE=true"
  else
    echo "AUTONOMOUS_MODE=false"
  fi
else
  echo "AUTONOMOUS_MODE=false"
fi
```

In autonomous mode: do NOT output a completion summary, do NOT ask "Shall I proceed?", do NOT suggest next steps. Complete the verification and return.

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

Verify implementation is complete by running tests AND validating spec compliance.

**Key Steps:**
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
- As final gate in the implementation pipeline (via spex-gates hook)

## Spec Selection

If a spec path is provided as an argument, use it directly.

Otherwise, attempt branch-based resolution:

```bash
.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null
```

If this succeeds (outputs JSON with `FEATURE_SPEC`), use the resolved spec path. Parse the JSON to extract `FEATURE_SPEC` and `FEATURE_DIR`.

If this fails (not on a feature branch, no matching spec directory), fall back to interactive selection:

```bash
find specs/ -name "spec.md" -type f 2>/dev/null | head -20
```

**If specs found:** Present list and ask user to select one using AskUserQuestion (skip in autonomous mode).

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

[Test output]

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

### 8. Completion Celebration

**After all verification passes** (go decision is positive), check if a state file exists:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ]; then
  MODE=$(jq -r '.mode // empty' "$STATE_FILE" 2>/dev/null)
fi
```

**If a state file exists** (flow or ship mode), display a celebration:

1. **Compute stats:**
   ```bash
   FEATURE=$(jq -r '.feature_branch // "unknown"' "$STATE_FILE" 2>/dev/null)
   STARTED=$(jq -r '.started_at // empty' "$STATE_FILE" 2>/dev/null)
   SPEC_DIR=$(jq -r '.spec_dir // empty' "$STATE_FILE" 2>/dev/null)
   # If spec_dir not in state (ship mode), derive from branch
   [ -z "$SPEC_DIR" ] && SPEC_DIR="specs/$FEATURE"
   REVIEW_COUNT=$(ls "$SPEC_DIR"/REVIEW-*.md 2>/dev/null | wc -l | tr -d ' ')
   COMMIT_COUNT=$(git rev-list --count main..HEAD 2>/dev/null || echo "?")
   ```
   - Duration: compute from `started_at` to now (human-readable, e.g., "2h 15m" or "3d 4h")
   - If `started_at` is empty, skip duration

2. **Display celebration banner:**
   ```
   +-------------------------------------------+
   |                                           |
   |   ALL CHECKS PASSED                       |
   |                                           |
   |   Feature:  <feature_branch>              |
   |   Duration: <duration>                    |
   |   Reviews:  <count> passed                |
   |   Commits:  <count>                       |
   |                                           |
   |   <random sign-off message>               |
   |                                           |
   +-------------------------------------------+
   ```

3. **Sign-off message pool** (select one randomly):
   - "Ship it!"
   - "Another one bites the dust."
   - "That's a wrap."
   - "Clean as a whistle."
   - "Nailed it."
   - "Spec met. Code shipped. Coffee earned."
   - "Nothing left to prove."

4. **Remove state file** after displaying:
   ```bash
   rm -f "$STATE_FILE"
   ```

**If no state file exists**, skip the celebration (no-op).

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

## Quality Gates

**This command enforces quality gates:**

1. **All tests must pass**
2. **Code hygiene review clean** (mechanical defects)
3. **100% spec compliance required**
4. **No spec drift allowed**
5. **All success criteria must be met**

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
