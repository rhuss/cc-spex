# Code Review: Modernize Generated Permission Rules

**Spec:** specs/061-permission-rule-modernize/spec.md
**Date:** 2026-11-03
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 19/19 (100%)
- Acceptance Scenarios: 13/13 (100%)
- Edge Cases: 7/7 (100%)
- Success Criteria: 5/5 automated parts covered (the Claude Code 2.1.317 warning checks in SC-001/SC-002 are manual)
- Spec-declared constants: none (the spec has no `## Constants` section)

## Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 interactive YOLO writes bare Bash, Read, Edit, Write | spex/skills/init/SKILL.md Step 2 YOLO block (`spex-permissions.sh apply`) | Compliant |
| FR-002 workflow `security: yolo` writes bare names | spex/setup.yml `claude-permissions` | Compliant |
| FR-003 merge rewrites legacy forms, each bare form once | spex/scripts/spex-permissions.sh `JQ_APPLY` + `mig` | Compliant |
| FR-004 every entry point migrates both files, all levels | setup.yml `migrate-permissions` (top level), spex-init.sh `migrate_permissions` in `do_refresh`/`do_update`, SKILL.md Standard/YOLO/None blocks | Compliant |
| FR-005 exact strings only, in `permissions.allow` only | `legacy_map` / `is_legacy` | Compliant |
| FR-006 dedup of bare names only after a rewrite, first occurrence kept | `mig` reduce with `seen` | Compliant |
| FR-007 other keys unchanged | `.permissions.allow = $m.list` only | Compliant |
| FR-008 no write without change | `status: unchanged` path | Compliant |
| FR-009 `Migrated:` line format, list order, relative path | `migrate_file`, `do_apply` | Compliant |
| FR-009a 2-space layout on change, exact bytes otherwise | `jq '.doc'` output, no write when unchanged | Compliant |
| FR-010 messages visible on every entry point | spex-setup-report.sh step list, SKILL.md Step 1 and Step 4 relay | Compliant |
| FR-011 missing/invalid/odd shapes untouched, warning for invalid JSON | `is_json_document`, `JQ_MIGRATE` shape guard, non-strings kept | Compliant |
| FR-011a write failure keeps original, warns, run continues | `safe_write` temp file + `mv` | Compliant |
| FR-012 never user-level settings | `project_target`, `is_user_settings`, `same_file`, `canon` (hardened in the fix loop) | Compliant |
| FR-013 skill no longer says refresh leaves permissions unchanged | SKILL.md Step 1 refresh bullet | Compliant |
| FR-014 YOLO text explains bare names | SKILL.md YOLO note | Compliant |
| FR-015 help.md and README describe the rewrite | spex/docs/help.md, spex/extensions/spex/docs/help.md, README.md | Compliant |
| FR-016 one script, no prose rewrite | spex/scripts/spex-permissions.sh | Compliant |
| FR-017 append only, no re-sorting | `JQ_APPLY` reduce over `$orig` | Compliant |

## Edge Cases

All seven spec edge cases are implemented and tested in tests/test_permissions.sh, plus the non-Claude harness case in tests/test_workflow_setup.sh (added during review). The symlink edge case (update the target, keep the link) still holds for links to ordinary files; links that resolve to user-level settings are now refused, as FR-012 requires.

## Extra Features (Not in Spec)

- `spex-permissions.sh apply` (the order-preserving merge) and its `Permissions configured in ...` and `Default mode set to ...` lines. Helpful: they are the FR-017 mechanism and the restart signal for the init skill. Documented in contracts/spex-permissions-cli.md.
- `--root DIR` for both subcommands. Helpful for tests.

## Spec Evolution Candidates

- FR-012 could name the hardening explicitly (symlinks, hard links, `$CLAUDE_CONFIG_DIR`, case-insensitive file systems), since the review showed that "never touch `~/.claude/settings.json`" needs path identity, not a path string.

## Deep Review Report

**Gate:** PASS (after fix round 3)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 9 | 9 | 0 |
| Minor | 15 | 12 | 3 |
| Notable | 3 | - | 3 |

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 3 | 3 | 0 | completed |
| Architecture & Idioms | 4 | 2 | 1 Minor, 1 Notable | completed |
| Security | 1 | 1 | 0 | completed |
| Production Readiness | 5 | 4 | 1 Notable | completed |
| Test Quality | 5 | 4 | 1 Minor | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review (fix rounds 1 and 2) | 9 | 8 | 1 Notable | completed |
| CodeRabbit (external) | 6 | 6 | 0 | completed (4 initial, 2 round 1, 0 rounds 2 and 3) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 4 | 3 | 1 Minor | completed (1 initial, 1 round 1, 2 round 2, 0 round 3) |
| Test Suite (regression) | 0 | 0 | 0 | passed in all rounds |

These are raw counts per source before deduplication. After deduplication: 1 Critical and 9 Important (all fixed), 15 Minor (12 fixed, 3 remaining), 3 Notable. Details are in review-findings.md.

**MVP:** Test Quality (5 findings; ties broken alphabetically with Production Readiness). The re-review passes found the most severe issues.

**Key fixes:** the FR-012 boundary (symlinked settings file, symlinked `.claude`, project root equal to `$HOME`, symlinked dotfile user settings, `$CLAUDE_CONFIG_DIR`, hard links, case-insensitive APFS, newline-named links, `CDPATH`) is enforced by canonical path identity, with every read and write on the checked path; rules containing newlines stay single rules; refresh/update and the real skill and setup.yml rule lists are now tested; setup.yml no longer claims success after a warning; temp files are trap-cleaned and raw shell errors are suppressed; jq 1.5 works; missing jq no longer turns a refresh into an `ERROR`; a defaultMode-only change now triggers the restart advice.

**Remaining (Minor):**
- `apply` + `migrate` print two warnings for the same invalid `settings.json` (judgment call: changing the apply contract).
- No workflow-level test that the setup report relays `WARNING:` lines (clear-cut, covered at script and refresh level).
- A dangling settings symlink is skipped silently by migrate (judgment call: matches FR-011's missing-file rule; the contract was clarified).

**Notable:** rule lists duplicated between the init skill and setup.yml (pre-existing), no lock against concurrent writes to `settings.local.json`, check-then-act window (mitigated by the re-check in `safe_write`).

**Post-fix spec coverage:** 19/19 requirements verified.

**Tests after fixes:** tests/test_permissions.sh 300/300 (sh and dash), tests/test_init_worktrees_git.sh 70/70, tests/test_workflow_setup.sh 16/16 cases, tests/test_cc_spex_codex_plugin.sh 94/94, tests/test_apply_extensions.sh 83/83, `make sync-scripts-check` in sync.
