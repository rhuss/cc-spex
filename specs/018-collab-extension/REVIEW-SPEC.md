# Spec Review: spex-collab Extension

**Spec:** specs/018-collab-extension/spec.md
**Date:** 2026-04-26
**Reviewer:** Claude (speckit-spex-gates-review-spec)

## Overall Assessment

**Status:** SOUND

**Summary:** Well-structured specification with clear user stories, testable requirements, and measurable success criteria. A few minor clarifications would strengthen implementability, but nothing blocks planning.

## Completeness: 4/5

### Structure
- All required sections present (User Scenarios, Requirements, Success Criteria)
- Edge cases covered with concrete behavior
- Extension Integration section adds valuable hook contract details

### Coverage
- 12 functional requirements, all with MUST language
- 3 user stories with acceptance scenarios
- 4 edge cases with specified behavior
- 4 success criteria

**Issues:**
- Missing explicit "Out of Scope" section. The ship mode guard implies scope boundaries, but what about other potential features (e.g., reviewer assignment, comment tracking, merge conflict handling)?
- Assumptions section could be stronger. "Task phases in tasks.md are indicated by `[P]` markers or sequential grouping" is the key assumption but the format is not fully specified.

## Clarity: 4/5

### Language Quality
- Consistent use of MUST throughout requirements
- No TBD or placeholder text
- Acceptance scenarios follow Given/When/Then format

**Ambiguities Found:**
1. FR-011: "the extension MUST pause and wait for the user to indicate readiness (e.g., PR merged)"
   - Issue: "indicate readiness" is vague on mechanism. Is this a conversation prompt, a command, a file check?
   - Suggestion: Specify that the user resumes by responding in conversation (the parenthetical at the end hints at this but it should be in the requirement itself).

2. FR-009: "hook into spec-kit's phase system transparently"
   - Issue: The Extension Integration section acknowledges the phase hook may not exist. This creates a dependency on unspecified spec-kit behavior.
   - Suggestion: Already mitigated by the fallback note in Extension Integration. Acceptable as-is since the spec acknowledges the uncertainty.

## Implementability: 4/5

### Plan Generation
- Hook points are clearly defined (after_tasks, before_implement, after_implement_phase)
- Ship mode guard pattern is well-established in the codebase
- REVIEWERS.md content structure is specified for both spec and code PRs

**Issues:**
- The `after_implement_phase` hook does not currently exist in spec-kit. The spec acknowledges this but does not specify what happens if it cannot be added. The fallback note about "managing phase transitions internally" is the right approach but could be more explicit as a requirement.
- The assumption about `review_brief.md` being superseded is a cross-cutting change that affects the brainstorm skill. This dependency should be tracked.

## Testability: 5/5

### Verification
- Each user story has an independent test description
- Acceptance scenarios are concrete and verifiable
- Success criteria include measurable targets (30-minute review, zero overhead)
- Edge cases specify expected behavior, not just "handle gracefully"

**Issues:**
- SC-001 ("reviewer can complete review within 30 minutes") is measurable in principle but hard to automate. This is acceptable for a user-facing quality criterion.

## Constitution Alignment

- **II. Extension Architecture**: Compliant. Extension follows the `spex/extensions/<ext-id>/` pattern with manifest and hooks.
- **III. Extension Composability**: Compliant. Extension operates independently through its own hooks. Does not modify other extensions.
- **IV. Quality Gates**: Compliant. Integrates with existing review gates rather than replacing them.
- **V. Naming Discipline**: Compliant. Uses `speckit-` prefix conventions.
- **VI. Skill Autonomy**: Compliant. Extension commands have clear single purposes.

**Violations:** None

## Recommendations

### Important (Should Fix)
- [ ] Add an explicit "Out of Scope" section listing what spex-collab does NOT do (reviewer assignment, comment tracking, automated merge, CI integration)
- [ ] Clarify FR-011 mechanism: specify that the user resumes by responding in the conversation

### Optional (Nice to Have)
- [ ] Document the `review_brief.md` supersession as a separate follow-up task rather than an assumption
- [ ] Specify the exact phase marker format expected from tasks.md (or state that any grouping format is accepted)

## Conclusion

The spec is sound and ready for planning. The user stories are well-prioritized with P1 stories delivering independent value. The extension integration section shows awareness of spec-kit's current limitations and provides fallbacks. The two "Important" recommendations would strengthen clarity but do not block implementation.

**Ready for implementation:** Yes

**Next steps:** Proceed with `/speckit-clarify` to resolve the minor ambiguities, or go directly to `/speckit-plan` if the current level of detail is sufficient.
