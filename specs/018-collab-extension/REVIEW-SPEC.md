# Spec Review: spex-collab Extension

**Spec:** specs/018-collab-extension/spec.md
**Date:** 2026-04-26
**Reviewer:** Claude (speckit-spex-gates-review-spec)

## Overall Assessment

**Status:** NEEDS WORK

**Summary:** The spec clearly defines what spex-collab does and why. Two issues need attention before implementation: the REVIEWERS.md content structure needs more specificity for the code PR variant, and the hook integration mechanism is underspecified.

## Completeness: 4/5

### Structure
- All required sections present
- User scenarios well-defined with acceptance criteria
- Edge cases covered

### Coverage
- Functional requirements are comprehensive (11 items)
- Success criteria defined
- Assumptions documented

**Issues:**
- Missing: how spex-collab hooks into the spec-kit lifecycle. It needs `after_tasks` (for REVIEWERS.md generation) and `before_implement` / custom phase hooks. The extension.yml manifest should be specified.
- Missing: explicit REVIEWERS.md content template for code PRs (FR-005 lists what to include but not the structure).
- The "minimal REVIEWERS.md when disabled" behavior (FR-006) lacks detail on who generates it. If the extension is disabled, its hooks don't fire. This needs a different mechanism.

## Clarity: 4/5

### Language Quality
- Requirements use MUST consistently
- No ambiguous language detected
- Scenarios are specific

**Ambiguities Found:**
1. FR-008: "present a PR split proposal based on task phases" - how are task phases detected? The assumption says `[P]` markers or sequential grouping, but spec-kit's actual phase format should be confirmed.
2. FR-010: "wait for user signal before starting the next phase" - what form does this signal take? A prompt? A slash command? Resuming the conversation?

## Implementability: 3/5

### Plan Generation
- Can generate an implementation plan from this
- Scope is manageable (single extension)

**Issues:**
- The "disabled but still generates minimal REVIEWERS.md" behavior (FR-006) contradicts extension mechanics. When disabled, extension hooks don't fire. Options: (a) make this a spex-gates feature instead, (b) use a separate mechanism outside the extension, or (c) drop this requirement and only generate REVIEWERS.md when enabled.
- The phase-based pausing mechanism needs architectural clarity. How does the extension intercept `/speckit-implement` mid-execution to pause between phases? This is the most complex part and needs more design thought. Options: (a) the extension provides its own implement wrapper command, (b) it hooks into spec-kit phase boundaries, (c) it modifies the implement command's behavior via a hook.

## Testability: 4/5

### Verification
- Acceptance scenarios are testable
- Success criteria SC-001 is subjective ("within 30 minutes") but reasonable as a guideline
- SC-003 (zero overhead in ship mode) is directly verifiable

**Issues:**
- SC-001 is hard to measure objectively. Consider rephrasing as "REVIEWERS.md covers all spec sections with actionable review guidance."

## Constitution Alignment

- Follows extension architecture principles (Section II)
- Follows extension composability (Section III, independent of other extensions)
- Follows naming discipline (Section V, `spex-collab` prefix)
- Follows quality gate principles (Section IV, gates as tools not bureaucracy)

**Violations:** None

## Recommendations

### Critical (Must Fix Before Implementation)
- [ ] Specify how the "disabled but minimal REVIEWERS.md" behavior works mechanically (FR-006). Choose: spex-gates responsibility, or drop the requirement.
- [ ] Define the phase-pause mechanism: does spex-collab wrap `/speckit-implement`, hook into it, or provide its own command?

### Important (Should Fix)
- [ ] Add the extension.yml manifest outline (hooks, commands, dependencies)
- [ ] Specify the user signal mechanism for resuming after a phase PR (FR-010)
- [ ] Define the REVIEWERS.md content template for code PRs with concrete sections

### Optional (Nice to Have)
- [ ] Rephrase SC-001 to be more objectively measurable

## Conclusion

The spec captures the right problem and the right solution. The two P1 user stories (REVIEWERS.md generation and phase-based PR splitting) are clearly motivated. The main gaps are in the integration mechanism: how the extension hooks into spec-kit's lifecycle for phase pausing, and how the "disabled but still generates" behavior works. Fixing the two critical items will make this ready for planning.

**Ready for implementation:** After fixes

**Next steps:**
1. Resolve the two critical items
2. Re-review
3. Proceed with `/speckit-plan`
