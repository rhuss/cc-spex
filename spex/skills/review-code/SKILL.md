---
name: review-code
description: Review code against spec compliance - checks implementation matches spec requirements, identifies deviations, reports compliance score, triggers evolution if needed
---

# Code Review Against Specification

## Overview

Review code implementation against specification to ensure compliance.

**Key Difference from Standard Code Review:**
- Primary focus: **Does code match spec?**
- Secondary focus: Code quality, patterns, best practices
- Output: **Compliance score** + deviation list
- Triggers: **Spec evolution** if mismatches found

## When to Use

- After implementation complete (called via superpowers trait overlay on `/speckit.implement`)
- Before merging/deploying code
- When validating existing code against spec
- As part of verification workflow

## Spec Selection

If no spec is specified, discover available specs:

```bash
# List all specs in the project
fd -t f "spec.md" specs/ 2>/dev/null | head -20
```

**If specs found:** Present list and ask user to select one using AskUserQuestion.

Example:
```
Found 2 specs in this project:
1. specs/0001-user-auth/spec.md
2. specs/0002-api-gateway/spec.md

Which spec should I review code against?
```

**If no specs found:** Inform user:
```
No specs found in specs/ directory.

Code review against spec requires a spec to compare against.
Use `spex:brainstorm` or `/speckit.specify` to create one first.
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
  Status: ✓ Compliant | ✗ Deviation | ? Missing
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
  Status: ✓ / ✗
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
Compliance % = (Compliant Requirements / Total Requirements) × 100
```

**Include:**
- Functional requirements
- Error cases
- Edge cases
- Non-functional requirements

**Example:**
```
Functional: 8/8 = 100%
Error Cases: 3/4 = 75%
Edge Cases: 2/3 = 67%
Non-Functional: 3/3 = 100%

Overall: 16/18 = 89%
```

### 7. Generate Report

**Report structure:**

```markdown
# Code Review: [Feature Name]

**Spec:** specs/features/[feature].md
**Date:** YYYY-MM-DD
**Reviewer:** Claude (spex:review-code)

## Compliance Summary

**Overall Score: XX%**

- Functional Requirements: X/X (XX%)
- Error Handling: X/X (XX%)
- Edge Cases: X/X (XX%)
- Non-Functional: X/X (XX%)

## Detailed Review

### Functional Requirements

#### ✓ Requirement 1: [Spec text]
**Implementation:** src/[file]:line
**Status:** Compliant
**Notes:** Correctly implemented as specified

#### ✗ Requirement 2: [Spec text]
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
- If compliance < 100%: Use `spex:evolve` to reconcile deviations
- If compliance = 100%: Proceed to verification
```

### 8. Deep Review Enhancement (if trait enabled)

**First, parse flags from the invocation arguments:**

When `/spex:review-code` is invoked with arguments, extract flags before treating the remainder as hint text:

- `--no-external`: disable all external tools
- `--no-coderabbit`: disable CodeRabbit only
- `--no-copilot`: disable Copilot only
- `--external`: enable all external tools
- `--coderabbit`: enable CodeRabbit only
- `--copilot`: enable Copilot only

Flags are consumed and removed from the argument string. The remaining text (if any) becomes the hint text.

Example: `/spex:review-code --no-copilot check mutation safety` results in:
- Flags: copilot disabled
- Hint text: "check mutation safety"

**Resolve external tool settings (defaults + flag overrides):**

```bash
# 1. Read defaults from config (all default to true if key is missing)
DEFAULT_ENABLED=$(jq -r '.external_tools.enabled // true' .specify/spex-traits.json 2>/dev/null)
DEFAULT_CODERABBIT=$(jq -r '.external_tools.coderabbit // true' .specify/spex-traits.json 2>/dev/null)
DEFAULT_COPILOT=$(jq -r '.external_tools.copilot // true' .specify/spex-traits.json 2>/dev/null)

# 2. If global "enabled" is false, individual tools default to false too
#    (unless individually overridden to true in config)
```

```
Resolution logic:

1. Start with config defaults:
   coderabbit = DEFAULT_ENABLED && DEFAULT_CODERABBIT
   copilot    = DEFAULT_ENABLED && DEFAULT_COPILOT

2. Apply flag overrides (flags always win over defaults):
   --external       → coderabbit = true,  copilot = true
   --no-external    → coderabbit = false, copilot = false
   --coderabbit     → coderabbit = true
   --no-coderabbit  → coderabbit = false
   --copilot        → copilot = true
   --no-copilot     → copilot = false

3. Flags are applied in order. Later flags override earlier ones:
   --external --no-copilot → coderabbit = true, copilot = false
   --no-external --coderabbit → coderabbit = true, copilot = false
```

**After spec compliance is calculated, check for the deep-review trait:**

```bash
# Check if deep-review trait is enabled
jq -r '.traits["deep-review"] // false' .specify/spex-traits.json 2>/dev/null
```

**If `deep-review` is enabled AND spec compliance >= 95% (or no spec exists):**
- Invoke `{Skill: spex:deep-review}` with:
  - Stage 1 compliance score (or null if no spec)
  - Invocation context: `superpowers` if called from quality gate, `manual` if called directly
  - Hint text: remaining argument text after flag extraction
  - External tool settings: `{coderabbit: true/false, copilot: true/false}` (resolved from defaults + flags)
  - Spec path and feature directory
- The deep-review skill handles Stage 2 (multi-perspective review), the fix loop, and `review-findings.md` generation
- Wait for the deep-review skill to complete before proceeding

**If `deep-review` is enabled AND spec compliance < 95%:**
- Do NOT invoke deep review
- Report the compliance score and non-compliant requirements
- Instruct the user to fix spec compliance issues first

**If `deep-review` is NOT enabled:**
- Continue with standard review behavior (steps 8b and 9 below)

### 8b. Trigger Evolution if Needed

**If deviations found (standard review path, no deep-review):**
- Present review results to user
- Recommend using `spex:evolve`
- Don't proceed to verification until resolved

**If 100% compliant (standard review path):**
- Approve for verification
- Proceed to `spex:verification-before-completion`

## Review Checklist

Use TodoWrite to track:

- [ ] Load specification
- [ ] Identify all implementation files
- [ ] Review each functional requirement
- [ ] Review each error case
- [ ] Review each edge case
- [ ] Identify extra features not in spec
- [ ] Calculate compliance score
- [ ] Generate detailed review report
- [ ] Make recommendations
- [ ] Trigger evolution if deviations found

## Example Output

```
# Code Review: User Profile Update API

**Spec:** specs/features/user-profile-api.md
**Date:** 2025-11-10
**Reviewer:** Claude (spex:review-code)

## Compliance Summary

**Overall Score: 94%**

- Functional Requirements: 6/6 (100%)
- Error Handling: 4/4 (100%)
- Edge Cases: 3/3 (100%)
- Non-Functional: 2/3 (67%)

## Detailed Review

### Functional Requirements

#### ✓ Requirement 1: PUT endpoint accepts requests
**Implementation:** src/api/users/profile.ts:12
**Status:** Compliant
**Notes:** Route correctly configured at PUT /api/users/:id/profile

#### ✓ Requirement 2: Validates request body
**Implementation:** src/middleware/validation/profile.ts:5
**Status:** Compliant
**Notes:** All validations match spec (name 2-50, bio max 500, avatar_url URL)

[... all ✓ ...]

### Error Handling

#### ✓ Error: Missing/Invalid JWT
**Implementation:** src/middleware/auth.ts:22
**Status:** Compliant
**Spec Expected:** 401 with "Authentication required"
**Actual:** 401 with "Authentication required" ✓

[... all ✓ ...]

### Non-Functional Requirements

#### ✗ Performance: Response time < 200ms
**Status:** Not Verified
**Issue:** No performance testing implemented
**Impact:** Minor (likely meets requirement but unverified)
**Recommendation:** Add performance test or update spec to remove specific timing

### Extra Features (Not in Spec)

#### Updated timestamp in response
**Location:** src/api/users/profile.ts:45
**Description:** Adds `updated_at` timestamp to response object
**Assessment:** Helpful - standard practice for update endpoints
**Recommendation:** Add to spec (minor addition)

## Recommendations

### Spec Evolution Candidates
- [ ] Add `updated_at` field to response spec (minor addition)
- [ ] Remove specific performance timing or add perf tests

## Conclusion

Code implementation is 94% compliant with spec. All functional requirements and error handling correctly implemented. One non-functional requirement unverified and one helpful feature added beyond spec.

**Next Steps:**
Use `spex:evolve` to update spec with:
1. `updated_at` field (minor addition)
2. Clarify performance requirement (remove specific timing or add test)

After spec evolution, compliance will be 100%.
```

## Assessment Criteria

### Compliant (✓)
- Code does exactly what spec says
- No deviations in behavior
- All aspects covered

### Minor Deviation (⚠)
- Small differences (naming, details)
- Non-breaking additions
- Better error messages than spec
- Typically → Update spec

### Major Deviation (✗)
- Different behavior than spec
- Missing functionality
- Wrong error handling
- Typically → Fix code or evolve spec

### Missing (?)
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
- Use `spex:evolve` to reconcile

**The code and spec must tell the same story.**

**Evidence before assertions. Always.**
