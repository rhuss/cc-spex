# Deep Review Findings

**Date:** 2026-07-21
**Branch:** 045-detach-stealth-mode
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 2 | - | 2 |
| Notable | 0 | - | 0 |
| **Total** | **2** | **0** | **2** |

**Agents completed:** 5/5 (+ 0 external tools)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py:12-16
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, no fix required)

**What is wrong:**
The `git()` helper function has a `check` parameter (line 13-14) that is never used with `check=True` anywhere in the codebase. When `check=True` and the command fails, it returns `None` instead of empty string. No caller passes `check=True`, making this dead code carried over from the previous version.

**Why this matters:**
Dead code increases cognitive load for future maintainers who may wonder about the unused code path. The `check` parameter also has confusing semantics (returning `None` vs `""` for failures depending on a flag).

**How to resolve:**
Remove the `check` parameter and the conditional branch. All callers use the default behavior (return empty string on failure). This is a Minor cleanup and does not affect functionality.

### FINDING-2
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py:167-168
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (Minor, no fix required)

**What is wrong:**
The error output pattern for "archive target not reachable" uses `json.dump({"error": ...}, sys.stderr)` followed by `print(file=sys.stderr)` (for the trailing newline). All other error messages in the script use `print("ERROR: ...", file=sys.stderr)`.

**Why this matters:**
Inconsistent error output patterns make it harder to reason about what the caller should expect on stderr. The `json.dump` to stderr is functional but diverges from the established convention in the same file.

**How to resolve:**
Change to `print("ERROR: Archive target not reachable: {}".format(target), file=sys.stderr)` for consistency, or change to `print(json.dumps({"error": ...}), file=sys.stderr)` to at least use the same output mechanism. This is a Minor style inconsistency.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| - | bash tests/test_spex_detach.sh | 0 | 0 | passed |

Test suite: 33 assertions passed, 0 failed. Covers all major acceptance scenarios from the spec.

## Spec Compliance

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001: Write exclude entries | spex-detach.py:cmd_enable() | Compliant |
| FR-002: Idempotent enable | spex-detach.py:101-105 (set-based dedup) | Compliant |
| FR-003: Create .git/info/ | spex-detach.py:92 (makedirs) | Compliant |
| FR-004: Preserve existing entries | spex-detach.py:97-99,108 (read then append) | Compliant |
| FR-005: Warn if tracked | spex-detach.py:116-133 (git ls-files check) | Compliant |
| FR-006: after_init hook | extension.yml:34-39 | Compliant |
| FR-007: Archive copies artifacts | spex-detach.py:184-198 (copytree) | Compliant |
| FR-008: project/feature structure | spex-detach.py:179 (os.path.join) | Compliant |
| FR-009: Auto-commit | spex-detach.py:201-209 | Compliant |
| FR-010: before_finish hook | extension.yml:41-46 | Compliant |
| FR-011: Skip gracefully | spex-detach.py:163-165 (exit 0 with JSON) | Compliant |
| FR-012: Remove old detach | Removed from COMMANDS dict | Compliant |
| FR-013: Remove old verify | Removed from COMMANDS dict | Compliant |
| FR-014: Remove old clean-branch-name | Removed from COMMANDS dict | Compliant |
| FR-015: is-enabled preserved | spex-detach.py:81-82 | Compliant |
| FR-016: Default mode unchanged | Extension is opt-in | Compliant |

**Compliance Score: 100% (16/16)**

## Deep Review Report

### Stage 1: Spec Compliance
Score: 100% (16/16 functional requirements compliant). All acceptance scenarios verified.

### Stage 2: Multi-Perspective Review
5 internal review agents completed sequentially (teams dispatch unavailable in teammate context).

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     0 |     0 |         0 | completed |
| Architecture & Idioms   |     2 |     0 |         2 | completed |
| Security                |     0 |     0 |         0 | completed |
| Production Readiness    |     0 |     0 |         0 | completed |
| Test Quality            |     0 |     0 |         0 | completed |
| CodeRabbit (external)   |     - |     - |         - | skipped (disabled) |
| Copilot (external)      |     - |     - |         - | skipped (disabled) |
| Test Suite              |    33 |     - |         0 | passed (33/33) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |     2 |     0 |         2 |           |

Clean review: no Critical or Important findings across 5 agents.

### Gate Outcome: PASS

0 Critical + 0 Important findings. 2 Minor findings (architecture style, no action required).
All 33 test assertions pass. Spec compliance 100%.
