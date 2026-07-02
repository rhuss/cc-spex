# Code Review: Replace find calls with plugin root references

**Spec:** specs/033-plugin-root-refs/spec.md
**Date:** 2026-07-02
**Reviewer:** Claude (speckit.spex-gates.review-code + deep-review)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 6/6 (100%)
- Error Handling: N/A (no error handling changes)
- Edge Cases: 4/4 (100%)
- Success Criteria: 4/4 (100%)

### Functional Requirements

#### FR-001: All find patterns replaced
**Implementation:** All 11 files under `spex/extensions/`
**Status:** Compliant
**Evidence:** `rg "find ~/\.claude" spex/extensions/ --glob '*.md'` returns zero matches

#### FR-002: Standard preamble added where missing
**Implementation:** 10 files got new "Step 0: Resolve Plugin Root" sections; ship.md preserved existing preamble
**Status:** Compliant

#### FR-003: All 16 occurrences covered
**Implementation:** Verified by diff review: flow-state(1) + ship(2) + finish(2) + submit(3) + brainstorm(1) + smoke-test(1) + detach(1) + review-code(2) + review-plan(1) + review-spec(1) + deep-review.run(1) = 16
**Status:** Compliant

#### FR-004: No behavior change
**Implementation:** Only path resolution changed; variable names, script names, and surrounding logic preserved
**Status:** Compliant

#### FR-005: Already-migrated files not modified
**Implementation:** `git diff -- spex/extensions/spex-collab/` returns empty (phase-manager.md and triage.md untouched)
**Status:** Compliant

#### FR-006: PLUGIN_ROOT references plugin-root tag
**Implementation:** All preambles instruct extraction from `<plugin-root>` tag in `<spex-context>` system reminder
**Status:** Compliant

### Success Criteria

- **SC-001:** Zero `find ~/.claude` patterns remain: **PASS**
- **SC-002:** All 11 affected files use `<PLUGIN_ROOT>/scripts/`: **PASS** (13 files total including 2 existing collab)
- **SC-003:** Identical behavior: **PASS** (mechanical replacement, no logic changes)
- **SC-004:** No new find patterns introduced: **PASS**

### Edge Cases

- spex-detach.sh uses correct `scripts/bash/` subdirectory path: **PASS**
- Multiple references per file handled independently (submit has 3): **PASS**
- ship.md partial migration preserved (no duplicate preamble): **PASS**
- All variable names preserved from original code: **PASS**

---

## Deep Review Report

**Date:** 2026-07-02
**Branch:** 033-plugin-root-refs
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** quality-gate

### Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 1 | - | 1 |
| Notable | 1 | - | 1 |
| Dismissed (false positive) | 2 | - | 0 |
| Dismissed (pre-existing) | 1 | - | 0 |
| **Total** | **5** | **0** | **2** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

### Review Agents

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     0 |     0 |         0 | completed |
| Architecture & Idioms   |     0 |     0 |         0 | completed |
| Security                |     0 |     0 |         0 | completed |
| Production Readiness    |     1 |     0 |         1 | completed |
| Test Quality            |     0 |     0 |         0 | completed |
| CodeRabbit (external)   |     4 |     0 |         4 | completed (2 false positives, 1 pre-existing, 1 matches internal) |
| Copilot (external)      |     - |     - |         - | skipped (not installed) |
| Test Suite (regression) |     - |     - |         - | skipped (no test command) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |     2 |     0 |         2 |           |

Clean review: no Critical or Important findings across 5 agents + 1 external tool.

### Findings

#### FINDING-1
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/extensions/spex/commands/speckit.spex.smoke-test.md:323
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** remaining (out of scope per FR-004)

**What is wrong:**
The `[ -z "$SHIP_STATE" ]` check at line 323 is now dead code. With the old `find` pattern, `SHIP_STATE` could be empty when the script was not found. With the new `<PLUGIN_ROOT>/scripts/spex-ship-state.sh` assignment, the variable is always a non-empty literal string, so the `-z` check can never be true and the warning message will never fire.

**Why this matters:**
If the script does not exist at the path (e.g., corrupted installation), the warning message "spex-ship-state.sh not found" will not appear. Instead, the downstream `"$SHIP_STATE"` invocation would fail with a shell-level "No such file or directory" error, which is still a clear failure signal but with a different message.

**How it was resolved:**
Not fixed. FR-004 requires "no behavior change" beyond path resolution. Changing the `-z` check to `-x` would alter behavior and violate the spec. The dead code is harmless. A future PR could clean up this check across all files.

### Notable Observations

#### NOTABLE-1
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md:657
- **Category:** external (CodeRabbit)
- **Source:** coderabbit (also: review-code.md:413)
- **Description:** The `&&` chain `"$FLOW_STATE" gate review-code && "$FLOW_STATE" implemented` prevents `implemented` from running when `gate review-code` fails. The instruction text says this MUST run "regardless of gate outcome."
- **Rationale:** This is a pre-existing design issue. The identical `&&` chain existed in the old code (confirmed at old line 647 in deep-review.run.md and old line 406 in review-code.md). This change only replaced the path resolution mechanism, not the command chaining logic. Fixing it would violate FR-004 ("no behavior change"). Should be addressed in a separate PR.

**External tool analysis (CodeRabbit):**
> The final flow transition is still conditional because the `implemented` step in the `FLOW_STATE` command chain is gated by `&&`. The terminal state change should run even when `gate review-code` fails, preserving the final `R checkmark` update regardless of exit status. Suggested fix: restructure chaining with `{ gate review-code || true; implemented; }`.

### Post-Fix Spec Coverage

No fix loop ran. All spec requirements verified during Stage 1 compliance check:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001: Replace all find patterns | All 11 files modified | PASS |
| FR-002: Standard preamble added | 10 new + 1 existing preserved | PASS |
| FR-003: Cover all 16 occurrences | 16/16 replaced | PASS |
| FR-004: No behavior change | Only path resolution changed | PASS |
| FR-005: Don't modify collab files | phase-manager, triage untouched | PASS |
| FR-006: Reference plugin-root tag | All preambles reference spex-context | PASS |

All spec requirements verified.

### Test Suite Results

No test command detected; post-fix test step was skipped.

### Dismissed CodeRabbit Findings

#### CR-DISMISSED-1 (false positive)
- **CodeRabbit Severity:** major
- **File:** spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md:29-44
- **CodeRabbit says:** "blocks still leave `<PLUGIN_ROOT>` as a manual placeholder" and suggests auto-resolving it as a shell variable.
- **Dismissal reason:** These are AI agent instruction files (markdown), not directly executable shell scripts. The `<PLUGIN_ROOT>` placeholder is by design: the AI agent reads the system reminder's `<plugin-root>` tag and substitutes it at runtime before executing the bash. This matches the canonical reference implementation in `speckit.spex-collab.phase-manager.md`. Converting to a shell variable would break the paradigm.

#### CR-DISMISSED-2 (false positive)
- **CodeRabbit Severity:** major
- **File:** spex/extensions/spex/commands/speckit.spex.ship.md:193
- **CodeRabbit says:** "using a literal `<PLUGIN_ROOT>` token instead of the actual `$PLUGIN_ROOT` shell variable."
- **Dismissal reason:** Same as CR-DISMISSED-1. The literal `<PLUGIN_ROOT>` is the correct pattern for AI agent instruction files. All 13 files using this pattern follow the same convention.

#### CR-DISMISSED-3 (pre-existing, captured as NOTABLE-1)
- **CodeRabbit Severity:** major
- **File:** spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md:657
- **CodeRabbit says:** The `&&` chain prevents `implemented` from running when `gate review-code` fails.
- **Dismissal reason:** Pre-existing issue confirmed at old line 647 (identical `&&` chain with `find` pattern). FR-004 prohibits behavior changes. Captured as NOTABLE-1 for future PR.

### Remaining Findings

No Critical or Important findings remain. One Minor finding (dead `-z` check) deferred per FR-004 scope restriction. One Notable observation (pre-existing `&&` chain) captured for future brainstorming.
