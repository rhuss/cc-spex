---
name: review-spec
description: Review specifications for soundness, completeness, and implementability - validates structure, identifies ambiguities, checks for gaps before implementation
---

# Reviewing Specifications for Soundness

## Overview

Validate specification quality before implementation begins.

A poor spec leads to confusion, rework, and spec/code drift. A sound spec enables smooth implementation.

This skill checks: completeness, clarity, implementability, and testability.

## When to Use

- After spec creation (before implementation)
- Before generating implementation plan
- When spec seems unclear or incomplete
- Periodically for important specs

## Prerequisites

Ensure spec-kit is initialized:

{Skill: spec-kit}

If spec-kit prompts for restart, pause this workflow and resume after restart.

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

**If specs found:** Present list and ask user to select one using AskUserQuestion.

**If no specs found:** Inform user:
```
No specs found in specs/ directory.

To create a spec first:
- Use `spex:brainstorm` to refine ideas into a spec
- Use `/speckit-specify` to create a spec from clear requirements

Cannot review without a spec to review.
```

## spec-kit Integration

This skill can use `/speckit-*` slash commands when available:

- `/speckit-clarify` - Find underspecified areas in the spec
- `/speckit-analyze` - Cross-artifact consistency check (if plan/tasks exist)

**If `/speckit-*` commands are available:**
Use them to assist with review, but always perform manual review as well.

**If `/speckit-*` commands are not available:**
Proceed with manual review only. This is acceptable.

## Review Dimensions

### 1. Completeness
- All sections filled
- No TBD or placeholder text
- All requirements defined
- Success criteria specified

### 2. Clarity
- No ambiguous language
- Concrete, specific requirements
- Edge cases explicitly defined
- Error handling specified

### 3. Implementability
- Can generate implementation plan
- Dependencies identified
- Constraints realistic
- Scope manageable

### 4. Testability
- Success criteria measurable
- Requirements verifiable
- Acceptance criteria clear

## The Process

### 1. Load and Read Spec

**Read the spec:**

```bash
cat specs/[feature-name]/spec.md
```

Read thoroughly, take notes on issues.

### 2. Check Structure

**Required sections (should exist):**
- [ ] Purpose/Overview
- [ ] Functional Requirements
- [ ] Success Criteria
- [ ] Error Handling

**Recommended sections:**
- [ ] Non-Functional Requirements
- [ ] Edge Cases
- [ ] Dependencies
- [ ] Constraints
- [ ] Out of Scope

**If sections missing:**
- Note which ones
- Assess if truly needed for this spec
- Recommend additions

### 3. Review Completeness

**For each section, check:**

**Purpose:**
- [ ] Clearly states why feature exists
- [ ] Describes problem being solved
- [ ] Avoids implementation details

**Functional Requirements:**
- [ ] Numbered/listed clearly
- [ ] Each requirement is specific
- [ ] No "TBD" or placeholders
- [ ] All aspects covered

**Success Criteria:**
- [ ] Measurable outcomes defined
- [ ] Clear completion indicators
- [ ] Testable assertions

**Error Handling:**
- [ ] All error cases identified
- [ ] Handling approach specified
- [ ] Error messages/codes defined

**Edge Cases:**
- [ ] Boundary conditions listed
- [ ] Expected behavior specified
- [ ] Not marked as "TBD"

### 4. Check for Ambiguities

**Red flag words/phrases:**
- "should" (vs "must")
- "might", "could", "probably"
- "fast", "slow" (without metrics)
- "user-friendly" (vague)
- "handle appropriately" (non-specific)
- "etc." (incomplete list)
- "similar to..." (unclear)

**For each ambiguity:**
- Identify the vague requirement
- Note what's unclear
- Suggest specific alternative

### 5. Validate Implementability

**Ask:**
- Can I generate an implementation plan from this?
- Are file locations/components identifiable?
- Are dependencies clear?
- Is scope reasonable?

**Check for:**
- Unknown dependencies
- Unrealistic constraints
- Scope too large
- Conflicting requirements

### 6. Assess Testability

**For each requirement:**
- How will this be tested?
- Is the outcome verifiable?
- Can success be measured?

**For success criteria:**
- Are they specific enough to test?
- Can they be automated?
- Are they objective (not subjective)?

### 7. Check Against Constitution

**If constitution exists:**

```bash
if [ -f ".specify/memory/constitution.md" ]; then
  cat .specify/memory/constitution.md
else
  echo "no-constitution"
fi
```

**Validate:**
- Does spec follow project principles?
- Are patterns consistent?
- Does error handling match standards?
- Are architectural decisions aligned?

**Note any violations with reasoning.**

### 8. Run Cross-Artifact Consistency Check (Optional)

**If plan or tasks exist and `/speckit-analyze` is available:**

Invoke `/speckit-analyze` to check consistency between:
- spec.md (requirements)
- plan.md (implementation approach)
- tasks.md (task list)

**Report any mismatches or gaps found.**

### 9. Generate Review Report

**Write the review report to `REVIEW-SPEC.md` in the spec directory** (e.g., `specs/[feature-name]/REVIEW-SPEC.md`). This enables artifact-based detection by the status line.

**Report structure:**

```markdown
# Spec Review: [Feature Name]

**Spec:** specs/features/[feature].md
**Date:** YYYY-MM-DD
**Reviewer:** Claude (spex:review-spec)

## Overall Assessment

**Status:** ✅ SOUND / ⚠️ NEEDS WORK / ❌ MAJOR ISSUES

**Summary:** [1-2 sentence overall assessment]

## Completeness: [Score/5]

### Structure
- [✓/✗] All required sections present
- [✓/✗] Recommended sections included
- [✓/✗] No placeholder text

### Coverage
- [✓/✗] All functional requirements defined
- [✓/✗] Error cases identified
- [✓/✗] Edge cases covered
- [✓/✗] Success criteria specified

**Issues:**
- [List any completeness issues]

## Clarity: [Score/5]

### Language Quality
- [✓/✗] No ambiguous language
- [✓/✗] Requirements are specific
- [✓/✗] No vague terms

**Ambiguities Found:**
1. [Quote ambiguous text]
   - Issue: [What's unclear]
   - Suggestion: [Specific alternative]

## Implementability: [Score/5]

### Plan Generation
- [✓/✗] Can generate implementation plan
- [✓/✗] Dependencies identified
- [✓/✗] Constraints realistic
- [✓/✗] Scope manageable

**Issues:**
- [List any implementability issues]

## Testability: [Score/5]

### Verification
- [✓/✗] Success criteria measurable
- [✓/✗] Requirements verifiable
- [✓/✗] Acceptance criteria clear

**Issues:**
- [List any testability issues]

## Constitution Alignment

[If constitution exists]

- [✓/✗] Follows project principles
- [✓/✗] Patterns consistent
- [✓/✗] Error handling aligned

**Violations:**
- [List any violations]

## Recommendations

### Critical (Must Fix Before Implementation)
- [ ] [Critical issue 1]
- [ ] [Critical issue 2]

### Important (Should Fix)
- [ ] [Important issue 1]

### Optional (Nice to Have)
- [ ] [Optional improvement 1]

## Conclusion

[Final assessment and recommendation]

**Ready for implementation:** Yes / No / After fixes

**Next steps:**
[What should be done]
```

### 10. Make Recommendation

**If sound (minor issues only):**
- ✅ Ready for implementation
- Proceed with `/speckit-implement`

**If needs work (important issues):**
- ⚠️ Fix issues before implementing
- Update spec, re-review

**If major issues:**
- ❌ Not ready for implementation
- Significant rework needed
- May need re-brainstorming

## Review Checklist

Use TodoWrite to track:

- [ ] Load and read spec thoroughly
- [ ] Check structure (all sections present)
- [ ] Review completeness (no TBD, all covered)
- [ ] Identify ambiguities (vague language)
- [ ] Validate implementability (can plan from this)
- [ ] Assess testability (can verify requirements)
- [ ] Check constitution alignment (if exists)
- [ ] Run `/speckit-analyze` for cross-artifact consistency (if available)
- [ ] Generate review report
- [ ] Make recommendation (ready/needs work/major issues)

## Example: Sound Spec

```
# Spec Review: User Profile Update API

**Spec:** specs/features/user-profile-api.md
**Status:** ✅ SOUND

## Overall Assessment

Specification is well-written, complete, and ready for implementation.
Minor suggestions for improvement but no blocking issues.

## Completeness: 5/5

✓ All required sections present
✓ All functional requirements clearly defined (6 requirements)
✓ All error cases identified (4 cases)
✓ All edge cases covered (3 cases)
✓ Success criteria specified and measurable

## Clarity: 4.5/5

✓ Requirements are specific and unambiguous
✓ Error handling clearly defined
⚠️ One minor ambiguity (see below)

**Ambiguities Found:**
1. "Response should be fast"
   - Issue: "Fast" is subjective
   - Suggestion: Specify "Response time < 200ms" or remove

## Implementability: 5/5

✓ Can generate detailed implementation plan
✓ All dependencies identified (JWT auth, database)
✓ Constraints are realistic
✓ Scope is manageable (single endpoint)

## Testability: 5/5

✓ All success criteria measurable
✓ Each requirement verifiable through tests
✓ Clear acceptance criteria

## Constitution Alignment

✓ Follows RESTful conventions (from constitution)
✓ Error handling matches project patterns
✓ Auth requirements aligned with standards

## Recommendations

### Important (Should Fix)
- [ ] Clarify "fast" response requirement (specify < 200ms or remove)

### Optional
- [ ] Consider adding rate limiting requirement
- [ ] Specify audit logging if required by project

## Conclusion

Excellent spec, ready for implementation after minor clarification on
performance requirement.

**Ready for implementation:** Yes (after performance clarification)

**Next steps:** Clarify "fast" requirement, then proceed to `/speckit-implement`
```

## Example: Needs Work

```
# Spec Review: Real-time Notifications

**Spec:** specs/features/real-time-notifications.md
**Status:** ⚠️ NEEDS WORK

## Overall Assessment

Specification has good foundation but several important gaps that will
cause confusion during implementation.

## Completeness: 3/5

✓ Purpose clearly stated
✗ Non-functional requirements missing
✗ Error handling incomplete
⚠️ Edge cases partially defined

**Issues:**
- No specification of real-time latency requirements
- Database storage requirements unclear
- Error recovery not defined
- Scalability requirements missing

## Clarity: 3/5

**Ambiguities Found:**
1. "Notifications should appear in real-time"
   - Issue: "Real-time" undefined (< 100ms? < 1s? < 5s?)
   - Suggestion: Specify exact latency requirement

2. "Handle notification delivery failures appropriately"
   - Issue: "Appropriately" is non-specific
   - Suggestion: Define retry logic, fallback, user notification

3. "Support many users"
   - Issue: "Many" is vague
   - Suggestion: Specify target (100? 1000? 10000?)

## Implementability: 2/5

✗ Cannot generate complete implementation plan
✗ Technology stack not specified (WebSocket? SSE? Polling?)
✗ Storage mechanism unclear

**Issues:**
- Is this WebSocket or polling? Spec doesn't say
- Where are notifications stored? For how long?
- What happens when user offline?
- No mention of infrastructure requirements

## Testability: 3/5

⚠️ Some criteria measurable, others vague

**Issues:**
- "Users receive notifications quickly" - not measurable
- "System handles failures" - no specific test criteria

## Recommendations

### Critical (Must Fix Before Implementation)
- [ ] Define exact real-time latency requirement (< Xms)
- [ ] Specify technology (WebSocket vs polling vs SSE)
- [ ] Define notification storage (where, how long)
- [ ] Specify error handling and retry logic
- [ ] Define scalability target (number of users)

### Important (Should Fix)
- [ ] Add detailed error cases
- [ ] Specify offline handling
- [ ] Define notification expiration
- [ ] Add infrastructure requirements

## Conclusion

Spec has good intent but lacks critical technical details needed for
implementation. Requires significant expansion before coding can begin.

**Ready for implementation:** No

**Next steps:**
1. Address all critical issues
2. Re-review spec
3. Then proceed to implementation
```

## Quality Standards

**A sound spec has:**
- All sections complete
- No ambiguous language
- Specific, measurable requirements
- Identified dependencies
- Realistic constraints
- Clear error handling
- Defined edge cases
- Testable success criteria

**A poor spec has:**
- Missing sections
- Vague language
- Unmeasurable requirements
- Unknown dependencies
- Unrealistic constraints
- Unclear error handling
- Ignored edge cases
- Subjective criteria

## Remember

**Reviewing specs saves time in implementation.**

- 1 hour reviewing spec saves 10 hours debugging
- Ambiguities caught early prevent rework
- Complete specs enable smooth TDD
- Sound specs reduce spec/code drift

**Be thorough but not pedantic:**
- Flag real issues, not nitpicks
- Focus on what blocks implementation
- Suggest specific improvements
- Balance perfection with pragmatism

**The goal is implementability, not perfection.**
