# Deep Review Findings

**Date:** 2026-07-06
**Branch:** 036-extension-local-scripts
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** quality-gate

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 2 | 2 | 0 |
| Minor | 6 | 0 | 6 |
| Notable | 0 | 0 | 0 |
| **Total** | **8** | **2** | **6** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** Makefile:108-120
- **Category:** correctness
- **Source:** coderabbit (also reported by: correctness-agent, production-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `sync-scripts` target called `$(MAKE) -s _print-scripts-$$ext 2>/dev/null`, suppressing stderr. If a helper target was missing (e.g., new extension added to EXTENSIONS without its `_print-scripts-*` target), the scripts variable would silently become empty and no scripts would be synced for that extension. The `cp` command also lacked error checking, so a missing canonical script would not halt the sync.

**Why this matters:**
A configuration error (missing helper target or missing canonical script) would cause `sync-scripts` to succeed with incomplete results, and `sync-scripts-check` would also pass since it uses the same mechanism. This creates a blind spot in the sync pipeline.

**How it was resolved:**
Removed `2>/dev/null` from the `$(MAKE)` call and added explicit error checks: the script list helper must succeed (`|| exit 1`) and must return a non-empty list. The `cp` command now also checks its exit code. The fix was verified by testing with a bogus extension name, confirming it fails loudly.

**External tool analysis (CodeRabbit):**
> The sync-scripts recipe is masking failures by swallowing stderr from the recursive $(MAKE) call and by not checking copy errors, so make it fail loudly instead of silently skipping work. Update sync-scripts to validate the result of _print-scripts-$$ext for each entry in EXTENSIONS, and ensure any missing _print-scripts-* target or empty script list stops the recipe.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** Makefile:134-158
- **Category:** correctness
- **Source:** coderabbit (also reported by: correctness-agent, production-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `sync-scripts-check` target had the same silent-failure risk: it called `$(MAKE) -s _print-scripts-$$ext 2>/dev/null` without verifying success, so a failed lookup would produce an empty scripts list and a false "all in sync" result.

**Why this matters:**
The sync-scripts-check is a CI gate and a release prerequisite. Silent failure means stale extension scripts could ship without detection.

**How it was resolved:**
Applied the same error handling pattern as FINDING-1: removed `2>/dev/null`, added exit-on-failure for the helper target call, and added an empty-list guard.

### FINDING-3
- **Severity:** Minor
- **Confidence:** 65
- **File:** spex/extensions/spex-gates/scripts/spex-closeout-gate.sh:57-67
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** not applicable (pre-existing in canonical script)

**What is wrong:**
The `parse_remaining` function defaults to returning 0 for malformed REVIEW_FILE rows, which could let CLOSEOUT_PASS succeed when findings still exist.

**Why this matters:**
This is a pre-existing issue in the canonical `spex/scripts/spex-closeout-gate.sh`. The extension copy is an exact sync of the canonical source. Fixing the copy would create a sync mismatch. This should be addressed in the canonical script as a separate issue.

### FINDING-4
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/extensions/spex/scripts/spex-flow-state.sh:101-108
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** not applicable (pre-existing in canonical script)

**What is wrong:**
The `do_running` function interpolates `$phase` directly into jq syntax, which could break state updates if phase contains special characters.

**Why this matters:**
Pre-existing in canonical `spex/scripts/spex-flow-state.sh`. Phase values are controlled internally and currently contain only alphanumeric/hyphen characters, but the pattern is fragile.

### FINDING-5
- **Severity:** Minor
- **Confidence:** 70
- **File:** spex/extensions/spex/scripts/spex-ship-state.sh:38-54
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** not applicable (pre-existing in canonical script)

**What is wrong:**
The `write_state` function interpolates raw shell values into JSON without using a JSON encoder, risking invalid JSON if values contain quotes or backslashes.

**Why this matters:**
Pre-existing in canonical `spex/scripts/spex-ship-state.sh`. Values are typically controlled strings, but the pattern is fragile.

### FINDING-6
- **Severity:** Minor
- **Confidence:** 65
- **File:** spex/extensions/spex/scripts/spex-ship-state.sh:261-285
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** not applicable (pre-existing in canonical script)

**What is wrong:**
Numeric validation uses `[0-9]*` pattern which matches strings like "123abc". Should use strict integer validation.

### FINDING-7
- **Severity:** Minor
- **Confidence:** 60
- **File:** spex/extensions/spex-detach/scripts/bash/spex-detach.sh:1-16
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** not applicable (pre-existing in canonical script)

**What is wrong:**
No upfront `jq` availability check despite the script relying on jq throughout.

### FINDING-8
- **Severity:** Minor
- **Confidence:** 60
- **File:** spex/extensions/spex/scripts/spex-ship-statusline.sh:179-234
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** not applicable (pre-existing in canonical script)

**What is wrong:**
Triage gate display logic (`gate_t`) turns green when either `tri_spec` or `tri_impl` is true, but `all_done` requires both. Inconsistent completion semantics.

## Post-Fix Spec Coverage

All spec requirements verified after fix loop.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001: Extension scripts/ dirs | spex/extensions/*/scripts/ | PASS |
| FR-002: make sync-scripts | Makefile:108-120 | PASS |
| FR-003: release depends on sync-scripts-check | Makefile:59 | PASS |
| FR-004: CI sync check | Makefile:134-162 | PASS |
| FR-005: Extension-local paths in commands/skills | 14 commands, 13 skills | PASS |
| FR-006: No plugin-root tag in context hook | context-hook.py | PASS |
| FR-007: No Step 0 preambles | Zero matches in rg | PASS |
| FR-008: spex-init.sh uses extension add | spex-init.sh | PASS |
| FR-009: Single inventory location | Makefile variables | PASS |
| FR-010: Constitution updated | constitution.md | PASS |

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1     | make test-install | 0 | 0 | passed |

## Remaining Findings

No Critical or Important findings remain. 6 Minor findings relate to pre-existing issues in canonical scripts that were copied to extension directories as part of the sync mechanism. These should be addressed in the canonical scripts (`spex/scripts/`) as separate maintenance items, not in the extension copies.
