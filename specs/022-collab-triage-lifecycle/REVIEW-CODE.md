# Code Review: Collab Triage Lifecycle

**Spec:** specs/022-collab-triage-lifecycle/spec.md
**Date:** 2026-06-02
**Reviewer:** Claude (speckit.spex-gates.review-code + deep-review)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 18/18 (100%)
- Error Handling / Edge Cases: 4/4 (100%)
- Non-Functional: N/A (workflow orchestration, no perf requirements)

## Detailed Review

### Functional Requirements

#### FR-001: triage-spec and triage-impl as recognized flow state phases
**Implementation:** spex/scripts/spex-flow-state.sh:124-125 (gate cases), :74-85 (create fields)
**Status:** Compliant
**Notes:** Both phases tracked via `triage_spec_passed` and `triage_impl_passed` boolean fields.

#### FR-002: Only activate when spex-collab is enabled
**Implementation:** spex/scripts/spex-flow-state.sh:67-71, spex/scripts/spex-ship-statusline.sh:174-178
**Status:** Compliant
**Notes:** Registry check gates both creation and rendering.

#### FR-003: After spec PR, transition to triage-spec with suggestion
**Implementation:** spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md:313-330
**Status:** Compliant

#### FR-004: After implementation push, transition to triage-impl with suggestion
**Implementation:** spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md:334-361
**Status:** Compliant

#### FR-005: Suggestion includes delay notice and /loop command
**Implementation:** phase-manager.md:323-325
**Status:** Compliant
**Notes:** "Bot reviewers typically need 1-2 minutes to post comments" + `/loop` command.

#### FR-006: Loop interval from collab-config.yml, default "5m"
**Implementation:** phase-manager.md:317-318
**Status:** Compliant
**Notes:** Double fallback: `yq -r '.triage.loop_interval // "5m"' ... || echo "5m"`.

#### FR-007: Triage completion via gate in flow state
**Implementation:** spex-flow-state.sh:124-125
**Status:** Compliant

#### FR-008: Read triage state and count comments after triage-spec
**Implementation:** phase-manager.md:380-388
**Status:** Compliant

#### FR-009: Compare against split_threshold (default 100)
**Implementation:** phase-manager.md:392-394
**Status:** Compliant

#### FR-010: Below threshold, recommend same-PR continuation
**Implementation:** phase-manager.md:398-411
**Status:** Compliant

#### FR-011: Above threshold, recommend split with user choice
**Implementation:** phase-manager.md:439-455
**Status:** Compliant
**Notes:** Three options via AskUserQuestion, not forced.

#### FR-012: Status line T badge with visual pattern
**Implementation:** spex-ship-statusline.sh:173-193
**Status:** Compliant
**Notes:** Renders after R badge. Uses same pattern as C/S/P/R gates.

#### FR-013: T badge only when spex-collab enabled
**Implementation:** spex-ship-statusline.sh:174-178
**Status:** Compliant

#### FR-014: gate triage-spec and gate triage-impl actions
**Implementation:** spex-flow-state.sh:124-125
**Status:** Compliant

#### FR-015: Deep review suggestion before triage-impl
**Implementation:** phase-manager.md:340-348
**Status:** Compliant

#### FR-016: Config template includes triage entries
**Implementation:** config-template.yml:18-19
**Status:** Compliant

#### FR-017: Existing triage command NOT modified
**Status:** Compliant
**Notes:** git diff confirms zero changes to speckit.spex-collab.triage.md.

#### FR-018: Existing phase-split NOT modified
**Status:** Compliant
**Notes:** git diff confirms zero changes to speckit.spex-collab.phase-split.md.

### Edge Cases

#### Missing triage state file at gate check
**Implementation:** phase-manager.md:382-387
**Status:** Compliant
**Notes:** Falls back to COMMENT_COUNT=0, recommends same-PR.

#### spex-collab disabled mid-workflow
**Status:** Compliant
**Notes:** All triage rendering/creation is gated on registry check.

#### Manual triage without flow state in triage phase
**Status:** Compliant
**Notes:** Triage command unchanged (FR-017), no flow state side effects.

#### PR with no review comments
**Status:** Compliant
**Notes:** 0 < any threshold, recommends same-PR.

### Extra Features (Not in Spec)

None found. All changes are additive implementations of specified requirements.

## Code Quality Notes

- Shell scripts follow established patterns (set -euo pipefail, jq for JSON, heredocs for templates)
- Double-fallback config reads (`yq ... // default ... || echo default`) are defensive and correct
- Statusline rendering extends the existing gate badge pattern cleanly
- Documentation updates in help.md and README.md are accurate and well-structured

---

## Deep Review Report

**Date:** 2026-06-02
**Branch:** 022-collab-triage-lifecycle
**Rounds:** 0 (no fix loop needed)
**Gate Outcome:** PASS
**Invocation:** quality-gate

### Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 3 | - | 3 |
| **Total** | **3** | **0** | **3** |

**Agents completed:** 5/5 (+ 0 external tools)
**External tools:** CodeRabbit skipped (disabled), Copilot skipped (disabled)

### Review Agents

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     0 |     0 |         0 | completed |
| Architecture & Idioms   |     2 |     0 |         2 | completed |
| Security                |     0 |     0 |         0 | completed |
| Production Readiness    |     1 |     0 |         1 | completed |
| Test Quality            |     0 |     0 |         0 | completed |
| CodeRabbit (external)   |     - |     - |         - | skipped (disabled via --no-external) |
| Copilot (external)      |     - |     - |         - | skipped (disabled via --no-external) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |     3 |     0 |         3 |           |

### Findings

#### FINDING-1
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/scripts/spex-ship-statusline.sh:138,175
- **Category:** architecture
- **Source:** architecture-agent

**What is wrong:**
The `collab_registry` variable is declared twice in `render_flow()`, once at line 138 (inside the `all_done` block) and again at line 175 (for the T badge block). Both use the identical value `.specify/extensions/.registry`.

**Why this matters:**
Minor code duplication within the same function. If the registry path changes, both declarations would need updating.

**How it was resolved:**
Not fixed. Minor issue, does not affect functionality. Could be refactored to a single declaration at function scope.

#### FINDING-2
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/scripts/spex-flow-state.sh:74-96
- **Category:** architecture
- **Source:** architecture-agent

**What is wrong:**
The `do_create()` function has two nearly identical heredoc templates (collab-enabled vs collab-disabled), differing only by the presence of `triage_spec_passed` and `triage_impl_passed` fields. This duplicates 6 common lines.

**Why this matters:**
Minor maintenance burden. If base flow state fields change, both heredocs need updating. However, heredocs are the established pattern in this codebase.

**How it was resolved:**
Not fixed. Follows existing codebase convention. The duplication is small and the alternative (building JSON with jq) would be less readable.

#### FINDING-3
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/scripts/spex-ship-statusline.sh:176
- **Category:** production-readiness
- **Source:** production-readiness-agent

**What is wrong:**
The registry file is read twice in `render_flow()`: once at line 176 (collab detection for T badge) and once in `read_extensions()` at line 84. Both invoke `jq` on the same file.

**Why this matters:**
Negligible performance impact. The status line script runs briefly and the registry file is small (< 1KB typically). The extra file read adds < 1ms.

**How it was resolved:**
Not fixed. Performance impact is negligible for a status line script that runs periodically.

### Post-Fix Spec Coverage

No code was removed during this review. Spec coverage check skipped (not applicable).

All 18 functional requirements verified as compliant during Stage 1 spec compliance check.

## Recommendations

### Optional Improvements
- [ ] Consider extracting `collab_registry` to function scope in statusline to avoid double declaration
- [ ] Consider building flow state JSON with `jq` in `do_create()` to reduce heredoc duplication

## Conclusion

All 18 functional requirements are 100% compliant. All 4 edge cases are properly handled. No extra features beyond spec. Code follows established patterns. The implementation is clean, additive, and well-integrated with the existing codebase.

**Gate: PASS**
