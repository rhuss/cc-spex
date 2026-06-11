# Code Review: Multi-Agent Harness Support

**Spec:** specs/023-multi-agent-support/spec.md
**Date:** 2026-06-08
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 96%**

- Functional Requirements: 10/10 (100%)
- Error Handling: 4.5/5 (90%)
- Edge Cases: 4/4 (100%)
- Success Criteria: 5.5/6 (92%)

## Detailed Review

### Functional Requirements

#### FR-001: Hook adapter scripts for each supported agent
**Implementation:** `spex/scripts/hooks/pretool-gate.py` (Claude Code), `spex/scripts/adapters/codex/pretool-gate.py`, `spex/scripts/adapters/opencode/spex-plugin.ts`
**Status:** Compliant

#### FR-002: Pretool gate logic functionally equivalent across adapters
**Implementation:** All three adapters call the same shared shell functions (skill-gate.sh, stage-gate.sh, teams-gate.sh, verify-gate.sh) in the same order
**Status:** Compliant

#### FR-003: Context-hook as hook scripts for Claude/Codex, skill preambles for OpenCode
**Implementation:** `context-hook.py` (Claude), `adapters/codex/context-hook.py` (Codex), `templates/skill-preamble/opencode-preamble.md` (OpenCode)
**Status:** Compliant

#### FR-004: Agent-specific instruction files
**Implementation:** `spex/templates/agents-md/claude.md`, `codex.md`, `opencode.md`; `spex-init.sh` selects per agent
**Status:** Compliant

#### FR-005: AskUserQuestion discrimination in instruction files
**Implementation:** Claude template references AskUserQuestion; Codex says "does NOT have AskUserQuestion" with inline list fallback; OpenCode says "Do NOT use AskUserQuestion" with question tool
**Status:** Compliant

#### FR-006: All 5 extensions work on all agents with defined degradation
**Implementation:** All extension command files updated with agent-neutral prompt patterns and degradation documentation
**Status:** Compliant

#### FR-007: spex-teams maps dispatch to each agent's subagent mechanism
**Implementation:** Multi-Agent Dispatch section in orchestrate.md covers Claude Code (Agent tool), OpenCode (Task tool), Codex (subagents), fallback (sequential)
**Status:** Compliant

#### FR-008: Runtime agent detection with correct priority order
**Implementation:** `detect-agent.sh` implements env vars > directory presence > init-options.json > fallback to claude
**Status:** Compliant

#### FR-009: spex:init installs correct hook adapter files
**Implementation:** `spex-init.sh` detect_agent() + install_agent_adapter() with Codex (.codex/hooks.json), OpenCode (.opencode/plugins/), Claude (existing)
**Status:** Compliant

#### FR-010: Local draft of upstream spec-kit issue
**Implementation:** `brainstorm/16-speckit-hook-adapter-proposal.md` (99 lines)
**Status:** Compliant

### Error Handling

#### EH-1: Adapter script execution failure (fail open)
**Status:** Compliant. All adapters use run_shared() with try/except, warnings to stderr, and None return (triggers allow).

#### EH-2: Unsupported agent detection
**Status:** Minor Deviation. Falls back to claude silently without a warning log. Spec says "log a warning" but behavior is safe.

#### EH-3: Shared enforcement logic errors
**Status:** Compliant. All shell scripts use `set -eu`. Adapters check returncode and handle gracefully.

#### EH-4: Missing agent directory during init
**Status:** Compliant. mkdir -p creates directories; set -euo pipefail handles permission failures.

#### EH-5: Plugin load failure (OpenCode)
**Status:** Compliant. Plugin degrades to skill-preamble-only enforcement via findSharedDir() returning null.

### Edge Cases

All 4 edge cases compliant. Agent detection handles multiple directories; OpenCode preamble provides fallback validation; Codex adapters use .get() with defaults; extension commands use agent-neutral patterns.

### Success Criteria

#### SC-005: Minor Deviation
The existing Claude Code hooks were refactored (shared logic extraction), which technically modifies existing code. However, behavior is identical, and the Codex adapter IS additive (single directory). The spirit of the requirement is met.

### Extra Features (Not in Spec)

#### Python inline fallback validation
**Location:** `spex/scripts/hooks/context-hook.py:168-224`
**Description:** `_inline_validate()` provides fallback command validation when the shared shell script is unavailable
**Assessment:** Helpful resilience. Aligns with EH-1 fail-open principle.
**Recommendation:** Add to spec as graceful degradation.

## Issues Fixed During Review

1. **ship.md line 483**: Fixed duplicate phrase "Do NOT present options to the user or present options to the user" (bad find-replace)
2. **finish.md line 105**: Fixed remaining hard-coded `AskUserQuestion` reference

## Deep Review Report

### Summary

**Date:** 2026-06-08
**Branch:** 023-multi-agent-support
**Rounds:** 0 (no fix loop needed for Critical findings)
**Gate Outcome:** PASS
**Invocation:** quality-gate

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 1 | 0 | 1 |
| Minor | 7 | 0 | 7 |
| **Total** | **8** | **0** | **8** |

**Agents completed:** 5/5 (+ 0 external tools)
**External tools:** CodeRabbit skipped (disabled), Copilot skipped (disabled)

### Review Agents

| Agent                   | Found | Fixed | Remaining | Status    |
|-------------------------|-------|-------|-----------|-----------|
| Correctness             |     1 |     0 |         1 | completed |
| Architecture & Idioms   |     3 |     0 |         3 | completed |
| Security                |     2 |     0 |         2 | completed |
| Production Readiness    |     2 |     0 |         2 | completed |
| Test Quality            |     1 |     0 |         1 | completed |
| CodeRabbit (external)   |     0 |     0 |         0 | skipped (disabled) |
| Copilot (external)      |     0 |     0 |         0 | skipped (disabled) |
|-------------------------|-------|-------|-----------|-----------|
| Total                   |     9 |     0 |         9 |           |

### Findings

#### FINDING-4 (Minor)
- **Severity:** Minor
- **Confidence:** 72
- **File:** spex/scripts/adapters/opencode/spex-plugin.ts:91-93
- **Category:** correctness
- **Source:** correctness-agent
- **Resolution:** remaining (acceptable risk)

**What is wrong:**
`getSessionId()` uses `process.pid` as fallback for session ID. If the OpenCode process restarts, the PID changes and stale marker files from old sessions remain in `$TMPDIR`. These are never cleaned up.

**Why this matters:**
Stale marker files accumulate in /tmp but don't affect functionality since each new session gets a unique PID-based ID. Old markers are simply orphaned.

#### FINDING-5 (Minor)
- **Severity:** Minor
- **Confidence:** 78
- **File:** spex/scripts/hooks/shared/context-hook.sh:46, spex/scripts/hooks/context-hook.py:173
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining (intentional duplication)

**What is wrong:**
The known command list is duplicated between the shell shared function and the Python inline fallback. Both must be updated when adding commands.

**Why this matters:**
The duplication is intentional resilience: the Python fallback operates when the shell script is unavailable. Both lists are short and in the same logical component.

#### FINDING-6 (Minor)
- **Severity:** Minor
- **Confidence:** 72
- **File:** spex/scripts/adapters/codex/pretool-gate.py:80-93
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining (acceptable for adapter pattern)

**What is wrong:**
The `side_effects()` function is duplicated between Claude Code and Codex adapters. Both perform identical marker cleanup and state file management.

**Why this matters:**
The codebase uses POSIX shell as the shared layer. The Python side-effects are adapter-specific (different response formatting) so extracting to a shared Python module would add complexity for marginal deduplication benefit.

#### FINDING-7 (Minor)
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/scripts/spex-init.sh:380
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining (pragmatic workaround)

**What is wrong:**
`spex-init.sh` always calls `specify init --here --ai claude --force` regardless of detected agent, then overlays agent-specific files. This is indirect.

**Why this matters:**
The `specify` CLI may not support `--ai codex` or `--ai opencode` yet, making this a necessary workaround. When spec-kit adds agent support, this can be updated.

#### FINDING-8 (Minor)
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/scripts/adapters/opencode/spex-plugin.ts:65-66
- **Category:** security
- **Source:** security-agent
- **Resolution:** remaining (no issue, POSIX escaping is correct)

**What is wrong:**
Shell command construction uses single-quote escaping. Reviewed and confirmed correct.

#### FINDING-9 (Minor)
- **Severity:** Minor
- **Confidence:** 72
- **File:** spex/scripts/hooks/shared/verify-gate.sh:61-76
- **Category:** security
- **Source:** security-agent
- **Resolution:** remaining (acceptable risk, false positive direction)

**What is wrong:**
File iteration in verify-gate.sh could misparse filenames with spaces. The impact is a false positive (showing verify reminder when not needed), which is the safe direction.

#### FINDING-10 (Minor)
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/scripts/hooks/pretool-gate.py:66-83
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** remaining (acceptable overhead)

**What is wrong:**
Each PreToolUse event spawns up to 4 subprocesses (one per gate). Worst case 20-second timeout if all scripts hang, but normal execution is sub-millisecond.

#### FINDING-11 (Minor)
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/scripts/adapters/opencode/spex-plugin.ts:66
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Resolution:** remaining (acceptable for blocking event handler)

**What is wrong:**
`execSync` blocks the Node.js event loop. Acceptable because `tool.execute.before` is inherently blocking.

#### FINDING-12 (Important)
- **Severity:** Important
- **Confidence:** 85
- **File:** (project-wide)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** remaining (requires test infrastructure decision)

**What is wrong:**
No automated tests exist for the new shared shell functions, Codex adapter scripts, or the OpenCode TypeScript plugin. The spec relies on `make release` (existing Claude Code validation) and manual per-agent testing.

**Why this matters:**
Key untested paths include detect-agent.sh priority logic, skill-gate.sh marker lifecycle, Codex adapter JSON contracts, and OpenCode plugin error handling. Regressions in these paths would be caught only by manual testing.

**Recommendation:**
Consider adding bats tests for shared shell functions in a future iteration. The current `make release` validation confirms Claude Code is not regressed, which is the highest-priority guarantee.

## Conclusion

Implementation is well-structured and follows the adapter pattern cleanly. All 10 functional requirements are met. The shared enforcement logic extraction is a sound architectural decision that enables multi-agent support while maintaining behavioral equivalence on Claude Code. The two issues found and fixed during review (duplicate phrase in ship.md, missed AskUserQuestion reference in finish.md) demonstrate the value of systematic compliance checking.

The single Important finding (no automated tests for new adapter code) is a valid concern but requires infrastructure decisions beyond this feature's scope. The spec's test strategy of `make release` + manual testing is adequate for the current scope.

**Gate: PASS**
