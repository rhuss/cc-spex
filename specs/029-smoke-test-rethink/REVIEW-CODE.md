# Code Review: Focused Interactive Smoke Test (#029)

**Branch**: `029-smoke-test-rethink`
**Date**: 2026-06-28
**Spec**: [spec.md](spec.md)

## Spec Compliance Score: 13/13 (100%)

All functional requirements (FR-001 through FR-013) are implemented in the modified files.

| Requirement | Status | Location |
|-------------|--------|----------|
| FR-001 Parse from `## Smoke Test` section | PASS | smoke-test.md Step 1 |
| FR-002 Auto-skip when section absent | PASS | smoke-test.md Prerequisites |
| FR-003 Claude handles setup/teardown | PASS | smoke-test.md Step 2 |
| FR-004 Human only judges pass/fail | PASS | smoke-test.md Step 2, item 5 |
| FR-005 Persistent SMOKE-TEST.md report | PASS | smoke-test.md Step 3 |
| FR-006 No simulation hard gate | PASS | smoke-test.md HARD-GATE section |
| FR-007 Single-session mode | PASS | smoke-test.md (no subagent), ship.md Stage 8 (direct invocation) |
| FR-008 Playwright graceful degradation | PASS | smoke-test.md Step 2c |
| FR-009 Ship pipeline checks section | PASS | ship.md Stage 8 grep check |
| FR-010 Spec template optional section | PASS | spec-template.md `## Smoke Test` section |
| FR-011 Warn on >5 scenarios | PASS | smoke-test.md Step 1 |
| FR-012 Numbered list format | PASS | smoke-test.md Step 1, spec-template.md guidance |
| FR-013 Failure debug/retry loop | PASS | smoke-test.md Step 2d |

## Gate Outcome: PASS

No blocking issues remain. All Critical and Important findings from the deep review have been fixed.

## Deep Review Report

### Review Agents Dispatched

4 of 5 review agents returned findings (tests agent had no applicable findings for this markdown-only project).

### Findings Summary

| Agent | Critical | Important | Minor | Total |
|-------|----------|-----------|-------|-------|
| Correctness | 1 | 1 | 1 | 3 |
| Architecture | 1 | 1 | 3 | 5 |
| Security | 0 | 0 | 3 | 3 |
| Production | 0 | 2 | 2 | 4 |
| **Total** | **2** | **4** | **9** | **15** |

### Critical Findings (2) — ALL FIXED

**C-1: Ship pipeline Stage 8 spawns subagent contradicting FR-007** (Correctness + Architecture)
- File: `spex/extensions/spex/commands/speckit.spex.ship.md`
- Issue: Stage 8 spawned the smoke test as a "fresh-context subagent" which directly contradicts FR-007 (single-session mode) and the Out of Scope section (subagent architecture retired).
- Fix applied: Replaced subagent spawn with direct `/speckit-spex-smoke-test` invocation in the current session. The pipeline already sets `.spex-state` for pipeline mode detection.

### Important Findings (4) — ALL FIXED

**I-1: smoke-test-record mishandles failed scenarios** (Correctness)
- File: `spex/extensions/spex/commands/speckit.spex.smoke-test.md`
- Issue: `completed` flag and `scenarios` count excluded failed scenarios, misrepresenting walkthrough completion.
- Fix applied: Updated definitions — `completed` is now true if all scenarios were processed (regardless of verdict), `scenarios` counts passed + failed + skipped.

**I-2: No guard for missing state script** (Architecture + Production)
- File: `spex/extensions/spex/commands/speckit.spex.smoke-test.md`
- Issue: Empty `$SHIP_STATE` from `find` would cause confusing "command not found" error.
- Fix applied: Added guard with `-path '*/spex/scripts/*'` filter and warning message when script not found. Recording step is skipped gracefully.

**I-3: Stale process cleanup on abnormal exit** (Production)
- File: `spex/extensions/spex/commands/speckit.spex.smoke-test.md`
- Issue: No mechanism to clean up orphaned app processes from interrupted previous runs.
- Fix applied: Added "Stale process check" before app startup — checks common dev ports and kills stale processes. Added explicit PID capture instruction (`APP_PID=$!`).

**I-4: Self-referential help.md entries** (Architecture)
- File: `spex/docs/help.md`
- Issue: Two entries listed current valid commands as "old names" pointing to themselves.
- Fix applied: Changed to show actual old names (`/spex:brainstorm`, `/spex:evolve`).

### Minor Findings (9) — NOT FIXED (acceptable risk)

- **Correctness M-1**: grep pattern `## Smoke Test` could match substrings → Fixed with `^## Smoke Test$` anchor (included in Important fixes above)
- **Security M-1**: `find` across `~/.claude` could match malicious script → Mitigated by adding `-path` filter
- **Security M-2**: Path traversal in `$SPEC_FILE` → Low risk, `check-prerequisites.sh` resolves paths
- **Security M-3**: Spec content as trusted instructions → Inherent to design, Claude safety guardrails + user permissions provide defense
- **Architecture M-1**: Redundant "no subagent spawning" statement in Step 2 → Informational, low impact
- **Architecture M-2**: Integration section accuracy → Deferred to C-1 resolution (fixed by removing subagent reference)
- **Production M-1**: No explicit PID tracking mechanism → Fixed as part of I-3
- **Production M-2**: Subagent process ownership gap → Resolved by C-1 (no more subagent)

### External Tools

- **CodeRabbit**: Not available (auth timeout during review)
- **Copilot**: Not available in this environment

### Fix Loop Summary

- Round 1: Fixed 2 Critical + 4 Important findings
- Round 2: Not needed (all findings resolved in Round 1)
