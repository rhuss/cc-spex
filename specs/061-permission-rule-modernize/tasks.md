# Tasks: Modernize Generated Permission Rules

**Input**: Design documents from `specs/061-permission-rule-modernize/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/spex-permissions-cli.md, quickstart.md

**Tests**: Included. SC-001 to SC-005 require automated checks (`make test-permissions`).

## Phase 1: Setup

- [X] T001 Create `tests/test_permissions.sh` skeleton (bash, `set -euo pipefail`, temp project per case, `assert_eq`/`assert_contains`, PASS/FAIL summary, exit 1 on failures) following `tests/test_apply_extensions.sh`, pointing at `spex/scripts/spex-permissions.sh`
- [X] T002 Add `test-permissions` target (`@tests/test_permissions.sh`), its `.PHONY` entry and a `help` line in `Makefile`

## Phase 2: Foundational

- [X] T003 Create `spex/scripts/spex-permissions.sh` (POSIX sh, executable) with argument parsing for `migrate [--root DIR]` and `apply [--root DIR] [--default-mode MODE] RULE...`, usage on stderr, exit 2 for usage errors, exit 1 when `jq` is missing, per `contracts/spex-permissions-cli.md`
- [X] T004 Implement the shared safe-write helper `safe_write <target> <content_file>` (returns non-zero on failure) in `spex/scripts/spex-permissions.sh`: resolve symlinks with a `readlink` loop (relative targets resolved against the link directory), write to a temp file in the resolved target's directory, copy the target's file mode, `mv` onto the resolved target, clean up and return non-zero on any failure (FR-011a, symlink edge case)

## Phase 3: User Story 2 - Refresh repairs existing projects (P1)

**Goal**: `migrate` rewrites the four legacy rules in both project settings files and reports it.
**Independent Test**: legacy settings + user rule → bare rules, user rule and other keys unchanged, `Migrated:` line; second run no output, same bytes.

- [X] T005 [US2] Add migrate tests to `tests/test_permissions.sh`: four-rule rewrite with exact `Migrated:` line (US2-1); `settings.local.json` migrated with its own line (US2-2); `Read` + `Read(*)` → one `Read` at first position (US2-3); user rules `Bash(npm test)`, `Read(~/notes/**)`, `Agent(*)` kept in order (US2-4); second run byte-identical with no output (US2-5, SC-003); `defaultMode`, `hooks`, `statusLine`, `deny`, `ask` unchanged (US2-6); duplicate non-legacy rules without legacy rules left byte-identical; repeated `Read(*)` collapses; look-alikes (`Read(./*)`, `Bash(* )`, `bash(*)`, `Read(**)`) untouched; user-level settings untouched (`HOME` set to a temp dir holding `.claude/settings.json` with `Read(*)`, byte-identical after migrate, FR-012); symlinked settings file stays a symlink with migrated target content
- [X] T006 [US2] Implement `migrate_file <root> <relpath>` (used by both `migrate` and `apply`) and the `migrate` subcommand in `spex/scripts/spex-permissions.sh` per `data-model.md`: iterate `.claude/settings.json` and `.claude/settings.local.json` under root; one jq program computing rewritten list, `old -> new` pairs (first-occurrence order) and bare-name dedup only when pairs is non-empty; write via the safe-write helper only when pairs is non-empty; print `Migrated: <relpath> permissions: ...` on stderr; always exit 0 (FR-004 to FR-009a, FR-012)
- [X] T007 [US2] Call `sh "$(dirname "$0")/spex-permissions.sh" migrate` in `do_refresh` and `do_update` after `install_agent_adapter` in `spex/scripts/spex-init.sh` (FR-004)
- [X] T008 [US2] Add a top-level `migrate-permissions` shell step after `configure-permissions` in `spex/setup.yml` running `sh "$SOURCE/scripts/spex-permissions.sh" migrate` (with the same `SOURCE="${SPEX_SOURCE:-$SPECKIT_WORKFLOW_DIR}"` pattern), outside the security `if` and the harness switch (FR-004)
- [X] T009 [US2] Add `claude-permissions` and `migrate-permissions` to the relayed step ids in `spex/scripts/spex-setup-report.sh`, and update its header comment (FR-010)

## Phase 4: User Story 3 - Never damage unhandled settings (P2)

**Goal**: missing, partial and broken settings stay untouched.
**Independent Test**: invalid JSON and no-`allow` files are byte-identical after migrate; only invalid JSON warns.

- [X] T010 [US3] Add tests to `tests/test_permissions.sh`: no `.claude/` → nothing created, no output (US3-1); no `permissions` / no `allow` → unchanged (US3-2); invalid JSON → unchanged, `WARNING:` naming the file, exit 0 (US3-3); non-list `allow`, top-level array/`null`, non-object `permissions` → unchanged, exit 0 (US3-4, FR-011); non-string entries in `allow` kept as-is when migrating; unwritable directory → original intact, `WARNING: could not write`, exit 0 (FR-011a; print SKIP when `id -u` is 0)
- [X] T011 [US3] Implement the shape guard and invalid-JSON warning in `migrate` in `spex/scripts/spex-permissions.sh` (FR-011), and the write-failure warning path (FR-011a)

## Phase 5: User Story 1 - Fresh YOLO init writes bare rules (P1)

**Goal**: both init paths write bare `Bash`, `Read`, `Edit`, `Write`, merging without reordering.
**Independent Test**: YOLO apply on empty project and on legacy settings yields bare rules exactly once; existing order kept.

- [X] T012 [US1] Add apply tests to `tests/test_permissions.sh`: missing file → created with given rules and `defaultMode` (US1-1/US1-2); existing legacy file + YOLO apply → bare rules once each, legacy gone, `Migrated:` line (US1-3, FR-003); existing user rules keep order, new rules appended, no sorting (FR-017); already-present rule not duplicated; existing file with `hooks`/`statusLine` but no `permissions` (and with `permissions` but no `allow`) → rules added, other keys unchanged; re-applying the same level is byte-identical with `(0 rules added)`; legacy rules in `settings.local.json` are migrated by the Step 2 sequence (`apply` then `migrate`); invalid JSON / wrong shape → unchanged with `WARNING: ... permissions not applied`, exit 0; usage errors exit 2
- [X] T013 [US1] Implement `apply` in `spex/scripts/spex-permissions.sh`: create `.claude/` and `{}` when missing, create missing `permissions`/`allow`, treat only a non-object top level/`permissions` or non-array `allow` as wrong shape, append missing rules in argument order, set `defaultMode` when given, safe write, then run `migrate_file` on the same file; skip the write when no rule was added, `defaultMode` is unchanged and no migration happened; compute n after migration; print `Permissions configured in <file> (<n> rules added)` (FR-001 to FR-003, FR-017)
- [X] T014 [US1] Replace the inline jq merge in the `claude-permissions` step of `spex/setup.yml` with `sh "$SOURCE/scripts/spex-permissions.sh" apply ...`, keeping the Standard list and switching the YOLO list to `Bash Read Edit Write Skill 'Agent(*)' WebFetch WebSearch EnterPlanMode ExitPlanMode EnterWorktree ExitWorktree` with `--default-mode bypassPermissions` (FR-002, FR-016)
- [X] T015 [US1] Rewrite the Permissions part of Step 2 in `spex/skills/init/SKILL.md`: one `sh "<scripts>/spex-permissions.sh" apply ...` call per level with the exact argument lists (YOLO with bare `Bash Read Edit Write`), every level (Standard, YOLO, None) then runs `sh "<scripts>/spex-permissions.sh" migrate` so both settings files are migrated (FR-004), a note that bare tool names allow every path and `(*)` forms must not be reintroduced, and remove the prose merge instruction (FR-001, FR-014, FR-016)
- [X] T016 [US1] Update Step 1 refresh text in `spex/skills/init/SKILL.md` (replace "Permissions are unchanged" with the rule migration description) and Step 4 to relay `Migrated:` and `WARNING:` lines from Step 1 and Step 2 output for full init, refresh and update; replace the "Step 2 permissions said CHANGED" restart trigger with: a `Permissions configured` line with n > 0 or any `Migrated:` line (FR-010, FR-013)

## Phase 6: Polish

- [X] T017 [P] Update the `/spex:init` `--refresh` entry in `spex/docs/help.md` to say refresh rewrites legacy `Bash(*)`, `Read(*)`, `Edit(*)`, `Write(*)` rules to bare names (FR-015)
- [X] T018 [P] Add a short paragraph after the "next refresh ... resets manually toggled spex extensions" paragraph in `README.md` (around line 396), and update the Commands Reference row for `/spex:init` if it describes refresh, stating the permission rule migration on refresh/update and that YOLO now writes bare tool names (FR-015)
- [X] T018a Extend `tests/test_workflow_setup.sh`: `security=yolo` yields bare `Bash`/`Read`/`Edit`/`Write` with no `(*)` forms; `security=safe` with a pre-seeded legacy `.claude/settings.json` migrates it; `spex-setup-report.sh` output contains the `Migrated:` line (FR-002, FR-004, FR-010)
- [X] T019 Run `make test-permissions`, `make test-workflow-setup` and `sh -n spex/scripts/spex-permissions.sh`; fix failures
- [X] T020 Run the `quickstart.md` scenarios 2-4 and confirm expected output; check no `Read(*)`/`Edit(*)`/`Write(*)`/`Bash(*)` remains in `spex/setup.yml` or `spex/skills/init/SKILL.md` (SC-001)

## Dependencies

- T001 → T005, T010, T012 (test file exists)
- T003 → T004 → T006 → T011, T013
- T006 → T007, T008 (callers need migrate)
- T013 → T014, T015
- T008, T009, T014 → T018a
- US2 (Phase 3) and US3 (Phase 4) before US1 (Phase 5): `apply` reuses migrate
- T019, T020 last

## Parallel Opportunities

- T005, T010, T012 share `tests/test_permissions.sh` and run sequentially
- T007, T008, T009 after T006 (different files)
- T017, T018 any time after the behavior is settled

## Implementation Strategy

MVP: Phases 1-3 (migrate + refresh wiring) fix existing projects. Phase 4 hardens it; Phase 5 fixes new inits; Phase 6 documents and validates.
