# Deep Review Findings

**Date:** 2026-07-13
**Branch:** 040-codex-hook-contract
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 1 | - | 1 |
| Notable | 0 | - | 0 |
| **Total** | **1** | **0** | **1** |

**Agents completed:** 5/5 (+ 0 external tools)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 80
- **File:** spex/scripts/adapters/codex/context-hook.py (all)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (by design)

**What is wrong:**
No automated tests exist for the Codex adapter hook scripts (`context-hook.py`, `pretool-gate.py`). All 14 acceptance scenarios from the spec (US1-1 through US4-4) lack corresponding test coverage.

**Why this matters:**
Without automated tests, regressions in the I/O contract (stdin parsing, stdout formatting) would only be caught during manual smoke testing with a live Codex CLI session. However, this is mitigated by: (1) the scripts are thin I/O adapters with no business logic (delegation goes to shared shell scripts), (2) the plan explicitly specifies "Manual smoke test" as the testing strategy, (3) meaningful testing requires a running Codex CLI session that cannot be easily mocked.

**How it was resolved:**
Not fixed. Accepted as a deliberate design choice per the implementation plan. Manual smoke testing is the appropriate strategy for these hook adapter scripts.

## Post-Fix Spec Coverage

No fix loop was needed (0 Critical + 0 Important findings).

All spec requirements verified:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001: parse v0.144+ UserPromptSubmit stdin | context-hook.py:66-68 | ok |
| FR-002: output {"systemMessage": ...} | context-hook.py:90-92, 148 | ok |
| FR-003: parse v0.144+ PreToolUse stdin | pretool-gate.py:109-112 | ok |
| FR-004: deny via hookSpecificOutput | pretool-gate.py:72-79 | ok |
| FR-005: context via systemMessage | pretool-gate.py:83-85 | ok |
| FR-006: identical shared script args | context-hook.py:80-82, pretool-gate.py:118,128-130,138-139,149-151 | ok |
| FR-007: exit 0 + no output for allow | Both scripts, multiple paths | ok |
| FR-008: exit 0 + no output on malformed JSON | context-hook.py:61-64, pretool-gate.py:104-107 | ok |
| FR-009: hooks.json event-grouped format | spex-init.sh:300-305, setup.yml:413-418 | ok |
| FR-010: python-resolve.sh wrapper | spex-init.sh:290, setup.yml:399-400 | ok |
| FR-011: merge without removing non-spex hooks | spex-init.sh:287-298, setup.yml:401-411 | ok |
| FR-012: turn_id as session ID, fallback "unknown" | context-hook.py:67, pretool-gate.py:111 | ok |

## Test Suite Results

No test command detected; post-fix test step was skipped.
