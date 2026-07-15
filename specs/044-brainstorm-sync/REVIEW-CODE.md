# Code Review: Brainstorm Directory Sync

**Spec:** specs/044-brainstorm-sync/spec.md
**Date:** 2026-07-15
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 16/16 (100%)
- Error Handling: 5/5 (100%)
- Edge Cases: 5/5 (100%)
- Non-Functional: N/A (skill markdown, no runtime NFRs)

## Detailed Review

### Functional Requirements

#### FR-001: Scan all .md files excluding overview and inbox
**Implementation:** speckit.spex.brainstorm.md:484-493 (Sync Step 1)
**Status:** Compliant
**Notes:** Correctly excludes `00-overview.md`, `idea-inbox.md`, and `brainstorm/attic/` files

#### FR-002: Parse Status field from header metadata
**Implementation:** speckit.spex.brainstorm.md:489-493
**Status:** Compliant
**Notes:** Uses regex on first 20 lines, extracts first word, normalizes to lowercase, defaults to `active`

#### FR-003: Cross-reference via slug token matching
**Implementation:** speckit.spex.brainstorm.md:504-520
**Status:** Compliant
**Notes:** Split on hyphens, >= 2 shared tokens or substring match. Tie-breaking added during review.

#### FR-004: Check overview Spec column for mappings
**Implementation:** speckit.spex.brainstorm.md:522-531
**Status:** Compliant

#### FR-005: Infer spec-created status
**Implementation:** speckit.spex.brainstorm.md:539-545
**Status:** Compliant
**Notes:** Infers for active/draft/idea (not parked), annotated with "(inferred)"

#### FR-006: Terminal states proposed for attic
**Implementation:** speckit.spex.brainstorm.md:536-537
**Status:** Compliant
**Notes:** All five terminal states listed: spec-created, abandoned, completed, resolved, decided

#### FR-007: Keep states remain in main directory
**Implementation:** speckit.spex.brainstorm.md:539-546
**Status:** Compliant
**Notes:** active, parked, draft, idea. No-status defaults to active. Unknown-status catch-all added during review.

#### FR-008: Interactive multiSelect confirmation
**Implementation:** speckit.spex.brainstorm.md:550-569
**Status:** Compliant
**Notes:** Uses harness:interactive-choice with multiSelect, pre-selected attic candidates

#### FR-009: User must confirm before moves
**Implementation:** speckit.spex.brainstorm.md:564-568
**Status:** Compliant
**Notes:** Cancel option and deselect-all both exit cleanly

#### FR-010: Update overview after moves
**Implementation:** speckit.spex.brainstorm.md:586-589
**Status:** Compliant
**Notes:** Uses idempotent full rebuild (aligned with existing overview update procedure during review)

#### FR-011: Remove open threads from attic'd brainstorms
**Implementation:** speckit.spex.brainstorm.md:586-589
**Status:** Compliant
**Notes:** Handled by full rebuild which naturally excludes attic'd documents

#### FR-012: Use git mv and commit
**Implementation:** speckit.spex.brainstorm.md:578-580, 596-605
**Status:** Compliant
**Notes:** Quoted filenames. Targeted staging (not broad `git add brainstorm/`). Correct commit message format.

#### FR-013: Create attic directory if needed
**Implementation:** speckit.spex.brainstorm.md:574-576
**Status:** Compliant

#### FR-014: idea-inbox.md not modified
**Implementation:** speckit.spex.brainstorm.md:486
**Status:** Compliant
**Notes:** Explicitly excluded from scan

#### FR-015: Skip on filename conflict, warn user
**Implementation:** speckit.spex.brainstorm.md:578-579
**Status:** Compliant

#### FR-016: Short-circuit normal flow on --sync
**Implementation:** speckit.spex.brainstorm.md:26-28
**Status:** Compliant
**Notes:** Skips steps 2-10, jumps to Sync Process section

### Edge Cases

All 5 edge cases from spec handled: attic conflicts (skip+warn), missing Status (default active), missing specs/ (skip cross-ref), user rejects batch (clean exit), empty brainstorm/ (report+exit).

## Deep Review Report

**Gate: PASS** (after fix round 1)

### Review Agents

| Agent | Found | Fixed | Remaining | Status |
|---|---|---|---|---|
| Correctness | 5 | 3 | 2 | completed |
| Architecture & Idioms | 4 | 2 | 2 | completed |
| Security | 2 | 1 | 1 | completed |
| Production Readiness | 5 | 4 | 1 | completed |
| Test Quality | 6 | 0 | 6 | completed |
| CodeRabbit (external) | 4 | 0 | 0 | completed (3 overlap with internal, 1 spec artifact) |
| Copilot (external) | 0 | 0 | 0 | skipped (CLI not installed) |
| Test Suite (regression) | 0 | 0 | 0 | skipped (no test command) |
|---|---|---|---|---|
| Total (dedup) | 20 | 8 | 12 | |

MVP: Production Readiness (5 findings)

### Key fixes applied

1. **Expanded Status values contract** (architecture-agent): Added 5 missing status values to canonical section, grouped into terminal/non-terminal categories
2. **Unified overview update strategy** (architecture-agent): Replaced selective row removal with full rebuild, eliminating duplicate-number ambiguity and missing-file guard issues
3. **Quoted filenames in git mv** (security-agent): Prevented potential command injection from malicious filenames
4. **Added partial-failure handling** (production-agent): Stop-on-error for git mv, no commit after partial failure
5. **Targeted git staging** (production-agent, correctness-agent, coderabbit): Replaced `git add brainstorm/` with explicit `git add brainstorm/attic/` + `git add brainstorm/00-overview.md`
6. **Added tie-breaking for slug matching** (correctness-agent, coderabbit): Deterministic resolution when multiple specs match

### Remaining findings (12 Minor)

All remaining findings are Minor severity and do not block the gate:
- 2 structural convention nits in the skill file (architecture)
- 1 filename validation defense-in-depth suggestion (security, mitigated by quoting fix)
- 1 spec/impl text mismatch on "skip steps 2-7" vs "2-10" (correctness, behavior is correct)
- 6 spec acceptance scenario coverage gaps (test-quality, worth addressing in future spec evolution)
- 1 unnumbered doc cleanup gap (production, resolved by overview rebuild fix)
- 1 unknown status handling (correctness, fixed as part of architecture fix)

### Post-fix spec coverage

All 16 functional requirements verified after fix loop. No requirements dropped.

### Test Suite Results

No test command detected; post-fix test step was skipped.

**Details:** [review-findings.md](review-findings.md)
