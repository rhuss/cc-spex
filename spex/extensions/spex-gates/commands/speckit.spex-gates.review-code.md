---
description: "Review code against spec compliance with deviation tracking and evolution triggers"
---

# Code Review Against Specification

## Ship Pipeline Guard

If `.specify/.spex-state` exists and its `status` is `running`, this command is part of an autonomous pipeline. Check the `ask` field:
- If `ask` is `"smart"` or `"never"`: suppress all user prompts (do NOT use AskUserQuestion), complete the review autonomously, and return immediately so the pipeline can advance.
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

In autonomous mode: do NOT output a completion summary, do NOT ask "Shall I proceed?", do NOT suggest next steps. Complete the review and return.

## Flow Status Update (before review starts)

If review-code is running, implementation is by definition done. Mark it immediately so the status line shows `impl ✓` during the review:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1; then
  jq '.implemented = true | .running = "review-code"' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi
```

## IMPORTANT: Deep Review Extension Check

**Before starting any review work**, check if the `spex-deep-review` extension is enabled:

```bash
# Check via extensions registry
jq -r '.extensions["spex-deep-review"].enabled // false' .specify/extensions/.registry 2>/dev/null
```

If deep review is enabled, this command MUST invoke `speckit.spex-deep-review.review` after spec compliance passes (>= 95%). Do NOT produce only a basic compliance review when deep-review is active. The deep review dispatches 5 specialized agents, runs a fix loop, and generates a Deep Review Report. See step 9a below for details.

## Overview

Review code implementation against specification to ensure compliance.

**Key Difference from Standard Code Review:**
- Primary focus: **Does code match spec?**
- Secondary focus: Code quality, patterns, best practices
- Output: **Compliance score** + deviation list
- Triggers: **Spec evolution** if mismatches found

## When to Use

- After implementation complete (called via spex-gates hook on after_implement)
- Before merging/deploying code
- When validating existing code against spec
- As part of verification workflow

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

Code review against spec requires a spec to compare against.
Use `speckit-spex-brainstorm` or `/speckit-specify` to create one first.
```

## The Process

### 1. Load Spec and Code

**Read specification:**
```bash
cat specs/features/[feature-name].md
```

**Identify implementation files:**
```bash
# From implementation plan or code exploration
ls -la [implementation-files]
```

### 2. Review Functional Requirements

**For each functional requirement in spec:**

1. **Find implementation** in code
2. **Compare behavior**: Does code do what spec says?
3. **Check completeness**: All aspects implemented?
4. **Note deviations**: Any differences?

**Create compliance matrix:**
```
Requirement 1: [Spec text]
  Implementation: [file:line]
  Status: Compliant | Deviation | Missing
  Notes: [If deviation, explain]

Requirement 2: [Spec text]
  ...
```

### 3. Review Error Handling

**For each error case in spec:**

1. **Find error handling** in code
2. **Check error response**: Matches spec?
3. **Verify error codes**: Correct HTTP status / error codes?
4. **Test error messages**: Clear and helpful?

**Error handling compliance:**
```
Error Case 1: [From spec]
  Implemented: Yes/No
  Location: [file:line]
  Response: [What code returns]
  Spec Expected: [What spec says]
  Status: Compliant / Deviation
```

### 4. Review Edge Cases

**For each edge case in spec:**

1. **Find handling** in code
2. **Check behavior**: Matches spec?
3. **Verify tests**: Edge case tested?

### 5. Check for Extra Features

**Identify code features NOT in spec:**

- Functions/endpoints not mentioned in spec
- Behavior beyond spec requirements
- Additional error handling
- Extra validations

**For each extra feature:**
- Document what it does
- Assess: Helpful addition or scope creep?
- Note for potential spec update

### 6. Calculate Compliance Score

**Formula:**
```
Compliance % = (Compliant Requirements / Total Requirements) x 100
```

**Include:**
- Functional requirements
- Error cases
- Edge cases
- Non-functional requirements

### 7. Generate Report

**Report structure:**

```markdown
# Code Review: [Feature Name]

**Spec:** specs/features/[feature].md
**Date:** YYYY-MM-DD
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: XX%**

- Functional Requirements: X/X (XX%)
- Error Handling: X/X (XX%)
- Edge Cases: X/X (XX%)
- Non-Functional: X/X (XX%)

## Detailed Review

### Functional Requirements

#### Requirement 1: [Spec text]
**Implementation:** src/[file]:line
**Status:** Compliant
**Notes:** Correctly implemented as specified

#### Requirement 2: [Spec text]
**Implementation:** src/[file]:line
**Status:** Deviation
**Issue:** [What differs from spec]
**Impact:** [Minor/Major]
**Recommendation:** [Update spec / Fix code]

### Error Handling

[Similar format for each error case]

### Edge Cases

[Similar format for each edge case]

### Extra Features (Not in Spec)

#### [Feature name]
**Location:** src/[file]:line
**Description:** [What it does]
**Assessment:** [Helpful / Scope creep]
**Recommendation:** [Add to spec / Remove]

## Code Quality Notes

[Secondary observations about code quality, patterns, etc.]

## Recommendations

### Critical (Must Fix)
- [ ] [Issue requiring immediate attention]

### Spec Evolution Candidates
- [ ] [Deviation that might warrant spec update]

### Optional Improvements
- [ ] [Nice-to-have suggestions]

## Conclusion

[Overall assessment]

**Next Steps:**
- If compliance < 100%: Use `speckit-spex-evolve` to reconcile deviations
- If compliance = 100%: Proceed to verification
```

### 8. Deep Review Enhancement (if extension enabled)

**First, parse flags from the invocation arguments:**

When this command is invoked with arguments, extract flags before treating the remainder as hint text:

- `--no-external`: disable all external tools
- `--no-coderabbit`: disable CodeRabbit only
- `--no-copilot`: disable Copilot only
- `--external`: enable all external tools
- `--coderabbit`: enable CodeRabbit only
- `--copilot`: enable Copilot only

Flags are consumed and removed from the argument string. The remaining text (if any) becomes the hint text.

**Resolve external tool settings (defaults + flag overrides):**

```bash
# 1. Read defaults from deep-review extension config (all default to true if key is missing)
DEEP_REVIEW_CONFIG=".specify/extensions/spex-deep-review/deep-review-config.yml"
DEFAULT_CODERABBIT=$(yq -r '.external_tools.coderabbit // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)
DEFAULT_COPILOT=$(yq -r '.external_tools.copilot // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)

# 2. If config file is missing, default all tools to true
```

```
Resolution logic:

1. Start with config defaults:
   coderabbit = DEFAULT_CODERABBIT
   copilot    = DEFAULT_COPILOT

2. Apply flag overrides (flags always win over defaults):
   --external       -> coderabbit = true,  copilot = true
   --no-external    -> coderabbit = false, copilot = false
   --coderabbit     -> coderabbit = true
   --no-coderabbit  -> coderabbit = false
   --copilot        -> copilot = true
   --no-copilot     -> copilot = false

3. Flags are applied in order. Later flags override earlier ones:
   --external --no-copilot -> coderabbit = true, copilot = false
   --no-external --coderabbit -> coderabbit = true, copilot = false
```

**After spec compliance is calculated, check for deep review:**

**If deep review is enabled AND spec compliance >= 95% (or no spec exists):**
- Invoke `speckit.spex-deep-review.review` with:
  - Stage 1 compliance score (or null if no spec)
  - Invocation context: `quality-gate` if called from hook, `manual` if called directly
  - Hint text: remaining argument text after flag extraction
  - External tool settings: `{coderabbit: true/false, copilot: true/false}` (resolved from defaults + flags)
  - Spec path and feature directory
- Wait for deep review to complete before proceeding

**If deep review is enabled AND spec compliance < 95%:**
- Do NOT invoke deep review
- Report the compliance score and non-compliant requirements
- Instruct the user to fix spec compliance issues first

**If deep review is NOT enabled:**
- Continue with standard review behavior (steps 9b below)

### 9b. Trigger Evolution if Needed

**If deviations found (standard review path, no deep-review):**
- Present review results to user
- Recommend using `speckit-spex-evolve`
- Don't proceed to verification until resolved

**If 100% compliant (standard review path):**
- Approve for verification
- Proceed to `speckit.spex-gates.stamp`

## Assessment Criteria

### Compliant
- Code does exactly what spec says
- No deviations in behavior
- All aspects covered

### Minor Deviation
- Small differences (naming, details)
- Non-breaking additions
- Better error messages than spec
- Typically: Update spec

### Major Deviation
- Different behavior than spec
- Missing functionality
- Wrong error handling
- Typically: Fix code or evolve spec

### Missing
- Spec requires it, code doesn't have it
- Critical gap
- Must fix code

## Anti-Rationalization: What You Must NOT Do

**DO NOT skip checking ANY requirement.** Each spec requirement must be verified against code. Not "spot checking." Not "seems fine." Every. Single. One.

**DO NOT assume compliance.** "It looks right" is not compliance. "I think it matches" is not compliance. Show the code location. Compare the behavior. Document the status.

**DO NOT hide deviations.** A deviation is not a failure; it's information. Hiding deviations breaks the feedback loop. Report every deviation, even minor ones.

**DO NOT proceed with deviations unresolved.** 89% compliance is NOT ready for verification. 99% compliance is NOT ready for verification. Only 100% compliance proceeds to verification.

**DO NOT rationalize scope creep.** "But this feature is useful!" is not justification for unspecified code. Either add it to the spec (via evolution) or remove it. Undocumented features are invisible bugs.

**DO NOT conflate code quality with spec compliance.** Code can be beautiful AND non-compliant. Code can be ugly AND compliant. Check both, report both, but never confuse them.

## Remember

**Spec compliance is primary concern.**

This is not just code quality review; it's **spec validation**.

- Does code match spec? (Most important)
- Is code quality good? (Secondary)
- Any improvements? (Tertiary)

**100% compliance is the goal.**

- < 90%: Significant issues, fix before proceeding
- 90-99%: Minor deviations, likely spec updates
- 100%: Perfect compliance, ready for verification

**Deviations trigger evolution.**

- Don't force-fit wrong spec
- Don't ignore deviations
- Use `speckit-spex-evolve` to reconcile

**The code and spec must tell the same story.**

**Evidence before assertions. Always.**

## Update Flow State

After the review completes, mark the review-code gate as passed in the flow state:

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ] && jq -e '.mode == "flow"' "$STATE_FILE" >/dev/null 2>&1; then
  jq '.review_code_passed = true | .implemented = true | .running = ""' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi
```

This updates the status line to show both `impl ✓` and `R ✓`. If code review passed, implementation is by definition complete.
