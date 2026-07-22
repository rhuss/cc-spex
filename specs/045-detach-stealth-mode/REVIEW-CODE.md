# Code Review: Detach Stealth Mode

**Spec:** specs/045-detach-stealth-mode/spec.md
**Date:** 2026-07-21
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 16/16 (100%)
- Error Handling: 5/5 (100%)
- Edge Cases: 5/5 (100%)

## Detailed Review

### Functional Requirements

#### FR-001: Write exclude entries
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:cmd_enable()
**Status:** Compliant
**Notes:** Writes .specify/, specs/, brainstorm/ to .git/info/exclude via append mode

#### FR-002: Idempotent enable
**Implementation:** spex-detach.py:101-105 (set-based dedup)
**Status:** Compliant
**Notes:** Uses set of existing lines to avoid duplicates. Test verified (33 pass).

#### FR-003: Create .git/info/ if missing
**Implementation:** spex-detach.py:92 (os.makedirs with exist_ok=True)
**Status:** Compliant

#### FR-004: Preserve existing entries
**Implementation:** spex-detach.py:97-99,108 (read existing, append new)
**Status:** Compliant

#### FR-005: Warn if tracked
**Implementation:** spex-detach.py:116-133 (git ls-files check, stderr warning)
**Status:** Compliant

#### FR-006: after_init hook
**Implementation:** extension.yml:34-39
**Status:** Compliant

#### FR-007: Archive copies artifacts
**Implementation:** spex-detach.py:184-198 (shutil.copytree for .specify/, specs/<feature>/, brainstorm/)
**Status:** Compliant

#### FR-008: project/feature structure
**Implementation:** spex-detach.py:179 (os.path.join(target, project, feature))
**Status:** Compliant

#### FR-009: Auto-commit
**Implementation:** spex-detach.py:201-209
**Status:** Compliant

#### FR-010: before_finish hook
**Implementation:** extension.yml:41-46
**Status:** Compliant

#### FR-011: Skip gracefully
**Implementation:** spex-detach.py:163-165 (exit 0 with {"skipped": true})
**Status:** Compliant

#### FR-012: Remove old detach subcommand
**Implementation:** Removed from COMMANDS dict, old cmd_detach function deleted
**Status:** Compliant

#### FR-013: Remove old verify subcommand
**Implementation:** Removed from COMMANDS dict, old cmd_verify function deleted
**Status:** Compliant

#### FR-014: Remove old clean-branch-name subcommand
**Implementation:** Removed from COMMANDS dict, old cmd_clean_branch_name deleted
**Status:** Compliant

#### FR-015: is-enabled preserved
**Implementation:** spex-detach.py:81-82
**Status:** Compliant

#### FR-016: Default mode unchanged
**Implementation:** Extension is opt-in (disabled by default)
**Status:** Compliant

### Error Handling

| Error Case | Implemented | Location | Status |
|------------|------------|----------|--------|
| Not a git repository | Yes | spex-detach.py:87-89 | Compliant |
| Archive target not reachable | Yes | spex-detach.py:166-169 | Compliant |
| No archive path configured | Yes | spex-detach.py:163-165 | Compliant |
| Path traversal attempt | Yes | spex-detach.py:66-72 | Compliant |
| Missing CLI argument value | Yes | spex-detach.py:75-78 | Compliant |

### Edge Cases

| Edge Case | Handled | Location | Status |
|-----------|---------|----------|--------|
| .git/info/ missing | Yes | spex-detach.py:92 | Compliant |
| Files already tracked | Yes | spex-detach.py:116-133 | Compliant |
| Sibling repo doesn't exist | Yes | spex-detach.py:166-169 | Compliant |
| Concurrent archives | Yes | spex-detach.py:179 (separate dirs) | Compliant |
| Not in git repo | Yes | spex-detach.py:87-89 | Compliant |

### Documentation Updates

| File | Updated | Status |
|------|---------|--------|
| README.md | Yes (line 242) | Compliant |
| spex/docs/help.md | Yes (lines 134-145) | Compliant |
| command doc | Yes (rewritten) | Compliant |
| extension.yml | Yes (v2.0.0) | Compliant |
| config-template.yml | Yes (new schema) | Compliant |

## Deep Review Report

### Stage 1: Spec Compliance
Score: 100% (16/16 functional requirements compliant). All acceptance scenarios verified against code.

### Stage 2: Multi-Perspective Review (5 agents)

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

### Findings Detail

**FINDING-1 (Minor, Architecture):** Dead `check` parameter in `git()` helper (line 12-14), never used with `check=True`. Carried over from old version. No functional impact.

**FINDING-2 (Minor, Architecture):** Inconsistent error output pattern at line 167 (`json.dump` to stderr) vs rest of file (`print("ERROR: ...")` to stderr). No functional impact.

### Test Suite Results

33 assertions passed, 0 failed. Coverage includes:
- Enable: writes entries, idempotent, preserves existing, warns on tracked, creates .git/info/, hides from git status, allows git add -f
- Is-enabled: returns 0/1 based on extension directory
- Archive: skips without path, copies to sibling repo, includes brainstorm, fails on bad target, preserves existing archives
- Edge cases: fails outside git repo

### Gate Outcome

**PASS** - 0 Critical, 0 Important, 2 Minor findings. No fix loop needed.
Spec compliance: 100% (16/16). Test suite: 33/33 pass.
