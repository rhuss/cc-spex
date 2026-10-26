# Code Review: Ship Progress in Codex

**Spec:** specs/058-codex-ship-progress/spec.md
**Date:** 2026-10-26
**Reviewer:** Claude (speckit-spex-gates-review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 29/29 (100%)
- Edge Cases: 11/11 (100%)
- Success Criteria: 5/5 (100%)
- Spec-declared constants: none (the spec has no `## Constants` section)

## Functional Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| FR-001 to FR-005 plan at start, advance, start-from, done, pause/fail/resume | spex/scripts/spex-ship-state.py `build_plan`, `do_progress`; Codex token in spex/scripts/adapters/codex/command-map.json | Compliant |
| FR-006, FR-006a step labels start with the stage name, produced by the script | `build_plan` (STAGES plus a ` (paused)`/` (failed)` suffix), PLAN line | Compliant |
| FR-007 no other plan until completion | Codex token, last bullet | Compliant |
| FR-008, FR-009 banner at each point, deterministic, shown verbatim | `progress` prints BANNER from `spex-ship-statusline.sh --banner`; token says verbatim | Compliant |
| FR-010, FR-011 banner content, done line, no color codes | banner mode blanks the color variables; done line `🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8` | Compliant |
| FR-012 single source, Claude line byte-identical | banner reuses `render_ship`; golden tests; manual byte comparison with main for 6 states | Compliant |
| FR-013 no output for missing, unreadable, flow or watch states | `do_progress` and banner dispatch | Compliant |
| FR-014 to FR-017a harness markers, empty Claude expansion | `{harness:ship-progress}` in ship.md; `jq -j` plus the empty-file branch in spex-adapt-commands.sh; Claude adapted tree identical to main | Compliant |
| FR-018, FR-019 ask once, Codex only, after bootstrap | spex/codex/skills/cc-spex-init/SKILL.md "Codex progress display"; Claude init untouched | Compliant |
| FR-020 to FR-022 append/defaults, preserve content, atomic, supported forms only | spex/scripts/spex-codex-progress.py `plan_edit`, `write_atomic`, verify by re-parse | Compliant |
| FR-023 approval, snippet and hint on failure | SKILL.md step 5; `apply` exit 3/4 with snippet | Compliant |
| FR-024 decline recorded and kept across refresh | spex-setup-profile.py `OPTIONAL`, `decline-codex-progress`, resolve keeps the field | Compliant |
| FR-025 standalone script with a check mode | `spex-codex-progress.py check` | Compliant |
| FR-026 docs | README "Ship progress in Codex", spex/docs/help.md | Compliant |
| FR-027 tests | tests/test_adapt_ship_progress.sh, test_ship_state.sh, test_ship_statusline.sh, test_codex_progress.py, test_setup_profile.py, test_cc_spex_codex_plugin.sh | Compliant |

## Extra Features (Not in Spec)

- `UNSUPPORTED` result from `check` when no TOML parser is available (added in the fix loop). This is a helpful addition and keeps FR-018 correct on Python 3.9 and 3.10. Spec evolution candidate.
- Symlinked `config.toml` is edited through the link. Helpful; it supports FR-021's content preservation.

## Spec Evolution Candidates

- The neutral ship command (line 254) says `advance` removes the state file, which is wrong (it writes stage `done`). FR-016 blocks fixing the neutral text, so the Codex and OpenCode tokens override it explicitly. A spec or command cleanup could fix the sentence in all harnesses together.

## Deep Review Report

**Gate:** PASS (after fix round 3)

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 4 | 4 | 0 | completed |
| Architecture & Idioms | 8 | 4 | 2 Minor, 2 Notable | completed |
| Security | 4 | 3 | 1 Minor | completed |
| Production Readiness | 4 | 4 | 0 | completed |
| Test Quality | 5 | 4 | 1 Notable | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review (fix rounds) | 4 | 3 | 1 Notable | completed |
| CodeRabbit (external) | 1 | 1 | 0 | completed (duplicate of the symlink finding) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 3 | 3 | 0 | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed in all rounds |

These are raw counts per source before deduplication. After deduplication: 10 Important (all fixed), 14 Minor (10 fixed, 4 remaining), 4 Notable. Details are in review-findings.md.

**Key fixes:** a symlinked Codex config is edited through the link; the Python < 3.11 TOML gap is handled; the snippet is safe to paste; the TypeError on malformed profile values is gone; banner mode is protected against arithmetic command injection, control codes, octal and unbounded values (Claude output unchanged); the Codex/OpenCode instructions override the outdated advance sentence; regression tests compare against real pre-feature output and are proven to fail on the old code.

**Remaining (Minor, design decisions):** escalated `apply` still resolves `./spex` or `SPEX_SOURCE` first (codex-progress.sh:13-16); ship-ness is decided in both Python and bash (spex-ship-state.py:354-370); source resolution is copied from bootstrap.sh (codex-progress.sh:13-28); SKILL.md derives the config path itself (SKILL.md:93-94).

**Post-fix spec coverage:** 29/29 requirements verified.
