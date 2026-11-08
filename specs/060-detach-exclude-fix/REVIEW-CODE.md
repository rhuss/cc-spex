# Code Review: Detach Stealth-Mode Exclude Gap and Config Loss on Refresh

**Spec:** specs/060-detach-exclude-fix/spec.md
**Date:** 2026-11-03
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 15/15 (FR-001 to FR-014, FR-009a)
- User story acceptance scenarios: 16/16
- Edge cases: 8/8
- Success criteria: 5/5
- Spec-declared constants: none (the spec has no `## Constants` section)

## Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 write entries when spex-detach ends enabled, both flows, first run, re-run, refresh | spex/scripts/spex-apply-extensions.sh (`ensure` after the selection loop); spex-init.sh `run_detach_enable` for refresh/update/fast path without declaration; setup.yml apply-extensions step (Codex and /spex:init) | Compliant |
| FR-002 probes per entry form, re-include files, tracked check | spex-detach.py `probe_for`, `synthesize`, `covers`, `is_tracked`, `run_verify` | Compliant (see remaining FINDING-4 for unanchored depth) |
| FR-003 active line with verified paths | `print_verify_lines` (`Stealth mode: active (verified: ...)`) | Compliant |
| FR-004 warning names each path, says tracked, never fails setup | `print_verify_lines`; callers use `|| true` | Compliant |
| FR-005 idempotent | `run_enable` dedups against existing lines and within the list | Compliant |
| FR-006 standalone verify | `spex-detach.py verify`, documented in the detach command | Compliant |
| FR-007 config identical after reinstall, enabled or disabled | spex-detach-config.sh save/restore; setup.yml save-detach-config + install-ext-spex-detach; spex-init.sh save_detach_config + restore in install_extensions | Compliant |
| FR-008 no config installs template | restore no-op without saved copy | Compliant |
| FR-009 save before uninstall, stop with error naming file | save-detach-config step is before any changing step; `save_detach_config` before `specify init` / install | Compliant |
| FR-009a no merge | byte copy via `cp -p` / `mv` | Compliant |
| FR-010 repair reported only when enabled before | `--was-enabled` from `--before` snapshot, registry state, or the init marker | Compliant |
| FR-011 no repair when all present | `ensure` prints a repair only for added paths | Compliant |
| FR-012 nothing when not enabled | ensure only runs for an enabled spex-detach; fast-path awk filter prints nothing else | Compliant |
| FR-013 tests | tests/test_spex_detach.sh, test_detach_config_preserve.sh, test_init_detach.sh, test_apply_extensions.sh, test_workflow_setup.sh | Compliant |
| FR-014 docs | README.md spex-detach paragraph, spex/docs/help.md | Compliant |

## Extra Features (Not in Spec)

- `Stealth mode: cannot read <config> ...` line when the configuration exists but cannot be read (added in the fix loop). It makes the spec's fallback visible without changing it. Spec evolution candidate.
- `save` keeps an earlier saved copy when the live config equals the template (added in the fix loop). It protects FR-007 across an interrupted run. Spec evolution candidate.
- Codex init skill relay paragraph (added in the fix loop), mirrors the Claude init skill.

## Spec Evolution Candidates

- FR-002 "tracked files under each path": decide whether unanchored entries (`specs/`) must count tracked files at any depth (FINDING-4).
- Edge case "Configuration unreadable": record the new visible warning.

## Deep Review Report

**Gate:** PASS (after fix round 2, plus a follow-up round 3 on the user's decisions for the remaining findings; final re-reviews clean)

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 5 | 5 | 0 (2 merged into Codex findings) | completed |
| Architecture & Idioms | 8 | 2 | 5 Minor (1 merged) | completed |
| Security | 5 | 4 | 1 Minor | completed |
| Production Readiness | 5 | 2 | 2 Minor (1 merged) | completed |
| Test Quality | 6 | 1 | 4 Minor, 1 Notable | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review agent (round 1) | 3 | 3 | 0 | completed |
| Re-review agent (round 3) | 3 | 3 | 0 | completed |
| Workflow test (round 3) | 1 | 1 | 0 | new restore-failure test exposed an FR-023 interaction |
| CodeRabbit (external) | 0 | 0 | 0 | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 6 | 5 | 1 Minor (reclassified, won't fix) | completed (round 2 and 3 re-reviews: 0) |
| Test Suite (regression) | 0 | 0 | 0 | passed |

### Severity Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 11 | 10 | 0 |
| Minor | 24 | 20 | 5 |
| Notable | 1 | - | 1 |

One Important finding (unanchored tracked check, Codex) was reclassified to Minor as an ambiguous requirement interpretation and is counted under Minor remaining (R1, won't fix by user decision). The other Minor remaining are R2 and R8 (accepted) and R3 and R4 (deferred).

MVP: Architecture & Idioms (8 findings)

### Key fixes applied

1. Stealth-mode verification now runs after spex's own exclude rules are written (setup.yml step order, spex-init.sh call order). (codex, architecture, correctness)
2. The directory probe is no longer a dotfile, so a `.*` rule cannot fake an active report. (security)
3. A retry after an interrupted reinstall no longer overwrites the user's saved config with the template; the save is staged and never writes through a symlink. (production, codex)
4. Glob probes satisfy ranges, negations, POSIX classes and literal `.`/`]` classes; no more StopIteration. (codex, correctness, re-review)
5. Unreadable detach config is reported instead of silently replaced by defaults. (security)
6. Codex init skill relays stealth-mode lines verbatim. (production)
7. A failed config restore leaves spex-detach disabled; a failed `extension add` stops the workflow step; the fast path no longer prints READY after a failed restore. (correctness, re-review)
8. Workflow test isolated from the global git excludes file, plus new regression tests for each fix. (test quality)
9. Round 3: one entry normalizer for enable, verify and disable (git-style trailing-whitespace handling); a failing `ensure` prints a WARNING with its last error line in both callers; `pending` helper instead of a hard-coded saved-copy path; `run_detach_ensure` rename; a failed restore leaves spex-detach in its pre-run state so the next refresh does not drop it from the declaration (FR-023); tests for the before-snapshot decision, `--update`, marker creation, the legacy fast path, a linked worktree, and workflow save, add and restore failures.

### Remaining Findings (status after round 3)

| # | Severity | File:line | Description | Status |
|---|----------|-----------|-------------|--------|
| R1 | Minor | spex/extensions/spex-detach/scripts/spex-detach.py:is_tracked | Unanchored entries (`specs/`) only count tracked files at the root | won't fix (user decision): forked upstreams track nested `specs/` dirs of their own and spex only writes root paths; documented in a code comment at `is_tracked` |
| R2 | Minor | spex/scripts/spex-init.sh, spex-apply-extensions.sh | A stale `.specify/.spex-detach-was-enabled` marker can mislabel a later Codex setup run as "Repaired" | accepted (user decision): needs an interrupted run plus an unusual follow-up; worst case is a wrong label |
| R3 | Minor | spex/scripts/spex-init.sh SPEX_DETACH_ENSURED / `_declared` | "ensure already ran" is derived twice | deferred: the cleanup moves the ensure call into install_extensions on every path, not cheap or low-risk in this PR |
| R4 | Minor | spex/scripts/spex-init.sh fast-path awk filter | Output rescue keyed on literal message text | deferred: needs a message-format change across spex-detach.py, both skills and docs; the failure warning now carries its error in a filtered line |
| R5 | Minor | spex-detach.py run_enable / verify_entries / cmd_disable | Different entry normalization | fixed (round 3): `configured_entries()` shared; exclude lines compared like git (trailing whitespace only) |
| R6 | Minor | spex/scripts/spex-init.sh fast path | Hard-coded saved-copy path | fixed (round 3): `detach_config pending` |
| R7 | Minor | spex/scripts/spex-apply-extensions.sh, spex-init.sh | A failing `ensure` printed no stealth-mode line | fixed (round 3): WARNING block with exit code and last error line; exit code unchanged |
| R8 | Minor | spex/scripts/spex-detach-config.sh save | A stale saved copy can return after the user deletes the config | accepted (user decision): needs an interrupted run plus an unusual follow-up; worst case is an earlier saved config returning |
| R9 | Minor | tests/test_apply_extensions.sh | Before-snapshot decision not exercised | fixed (round 3) |
| R10 | Minor | tests/test_init_detach.sh | `--update`, marker creation, legacy fast path untested | fixed (round 3) |
| R11 | Minor | tests/test_workflow_setup.sh | Workflow save failure untested | fixed (round 3): injected through an unreadable config, because a read-only `.specify/` would also break the engine's run state |
| R12 | Minor | tests/test_spex_detach.sh | No linked-worktree test | fixed (round 3) |
| R13 | Minor | spex/setup.yml install-ext-spex-detach | Disable-before-restore and `add || exit 1` untested | fixed (round 3): specify wrapper fails the add or makes the restore fail |
| R14 | Minor | spex/scripts/spex-init.sh | `run_detach_enable` name | fixed (round 3): renamed `run_detach_ensure` |
| N1 | Notable | Makefile release, CI | Detach suites not run by release or CI | informational |

Post-fix spec coverage: 15/15 requirements verified, all covered.

Details: specs/060-detach-exclude-fix/review-findings.md
