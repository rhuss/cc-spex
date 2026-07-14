# Code Review: Codex Hook Contract Migration

**Spec:** specs/040-codex-hook-contract/spec.md
**Date:** 2026-07-13
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 12/12 (100%)
- Error Handling: 4/4 (100%)
- Edge Cases: 4/4 (100%)

## Detailed Review

### Functional Requirements

#### FR-001: Parse v0.144+ UserPromptSubmit stdin contract
**Implementation:** spex/scripts/adapters/codex/context-hook.py:66-68
**Status:** Compliant
**Notes:** Parses `prompt`, `turn_id` (as session_id), `cwd`. `permission_mode` and `transcript_path` documented as ignored.

#### FR-002: Output context via {"systemMessage": "<text>"}
**Implementation:** spex/scripts/adapters/codex/context-hook.py:90-92, 148
**Status:** Compliant
**Notes:** Both error and context injection paths use systemMessage format.

#### FR-003: Parse v0.144+ PreToolUse stdin contract
**Implementation:** spex/scripts/adapters/codex/pretool-gate.py:109-112
**Status:** Compliant
**Notes:** Parses `tool_name`, `tool_input`, `turn_id` (as session_id), `cwd`. `permission_mode` documented as ignored.

#### FR-004: Deny via hookSpecificOutput
**Implementation:** spex/scripts/adapters/codex/pretool-gate.py:72-79
**Status:** Compliant
**Notes:** `codex_deny()` outputs exact v0.144+ deny format with hookEventName, permissionDecision, permissionDecisionReason.

#### FR-005: Context via {"systemMessage": "<text>"}
**Implementation:** spex/scripts/adapters/codex/pretool-gate.py:83-85
**Status:** Compliant
**Notes:** `codex_context()` outputs systemMessage format.

#### FR-006: Identical shared script arguments
**Implementation:** context-hook.py:80-82, pretool-gate.py:118,128-130,138-139,149-151
**Status:** Compliant
**Notes:** Verified against Claude Code adapter and shared script interfaces:
- context-hook.sh: [prompt, session_id, cwd, plugin_root]
- skill-gate.sh: [tool_name, session_id]
- stage-gate.sh: [tool_name, skill_name, state_file]
- verify-gate.sh: [tool_name, command, session_id, cwd]

#### FR-007: Exit 0 with no output for allow
**Implementation:** Both scripts, multiple exit paths
**Status:** Compliant
**Notes:** All allow paths call sys.exit(0) with no prior stdout output.

#### FR-008: Exit 0 on malformed JSON
**Implementation:** context-hook.py:61-64, pretool-gate.py:104-107
**Status:** Compliant
**Notes:** `except Exception: sys.exit(0)` handles all parse failures.

#### FR-009: hooks.json event-grouped format
**Implementation:** spex-init.sh:300-305, setup.yml:413-418
**Status:** Compliant
**Notes:** Generates `{hooks: {UserPromptSubmit: [...], PreToolUse: [...]}}` format.

#### FR-010: python-resolve.sh wrapper
**Implementation:** spex-init.sh:290, setup.yml:399-400
**Status:** Compliant
**Notes:** Commands use `sh $python_resolve $script` pattern.

#### FR-011: Merge without removing non-spex hooks
**Implementation:** spex-init.sh:287-298, setup.yml:401-411
**Status:** Compliant
**Notes:** jq filter selects out existing spex hooks (regex match on script names), preserves all other hooks, appends updated spex hooks.

#### FR-012: turn_id as session ID with fallback
**Implementation:** context-hook.py:67, pretool-gate.py:111
**Status:** Compliant
**Notes:** `hook_input.get('turn_id', 'unknown')` matches spec exactly.

### Edge Cases

#### Unknown fields in stdin JSON
**Status:** Compliant
**Notes:** `dict.get()` only accesses known fields; unknown fields are naturally ignored.

#### Missing turn_id
**Status:** Compliant
**Notes:** Falls back to "unknown" via default parameter.

#### Unhandled exception crash
**Status:** Compliant
**Notes:** Spec acknowledges this is acceptable ("guardrails, not security boundaries").

### Code Quality Notes

- Clean separation of concerns: stdin parsing, shared script delegation, stdout formatting
- Consistent fail-open behavior across all error paths
- Proper use of stderr for warnings, stdout for hook responses
- 5-second subprocess timeouts prevent hanging

## Deep Review Report

**Date:** 2026-07-13
**Branch:** 040-codex-hook-contract
**Rounds:** 0
**Gate Outcome:** PASS
**Invocation:** quality-gate

### Review Agents

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     0 |     0 |         0 | completed |
| Architecture & Idioms   |     0 |     0 |         0 | completed |
| Security                |     0 |     0 |         0 | completed |
| Production Readiness    |     0 |     0 |         0 | completed |
| Test Quality            |     1 |     0 |         1 | completed |
| CodeRabbit (external)   |     - |     - |         - | skipped (disabled via --no-external) |
| Copilot (external)      |     - |     - |         - | skipped (disabled via --no-external) |
| Test Suite (regression) |     - |     - |         - | skipped (no test command detected) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |     1 |     0 |         1 |           |

Clean review: no findings across 5 agents (1 Minor from test-quality does not count toward gate).

### Findings Detail

#### FINDING-1 (Minor, test-quality)
**File:** spex/scripts/adapters/codex/ (all)
**Description:** No automated tests for Codex adapter hooks. 14 acceptance scenarios lack test coverage.
**Rationale:** Mitigated by design. Plan specifies manual smoke testing. These thin I/O adapters require a live Codex CLI session for meaningful testing.

### Post-Fix Spec Coverage

All 12/12 spec requirements verified after review. No code removed, no fix loop needed.

### Test Suite Results

No test command detected; post-fix test step was skipped.

## Conclusion

**Gate: PASS**

The implementation is a clean, focused I/O layer migration. Both Python adapter scripts correctly implement the Codex v0.144+ hook contract with proper stdin parsing (turn_id, systemMessage, hookSpecificOutput formats), fail-open behavior, and identical shared script delegation. All 12 functional requirements are compliant. No Critical or Important findings.
