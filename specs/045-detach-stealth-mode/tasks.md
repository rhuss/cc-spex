# Tasks: Detach Stealth Mode

**Input**: Design documents from `specs/045-detach-stealth-mode/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Update config template and extension manifest for the new approach

- [x] T001 Update config template to new schema (remove upstream/detach sections, add exclude section) in spex/extensions/spex-detach/config-template.yml
- [x] T002 Update extension manifest in spex/extensions/spex-detach/extension.yml: rename command to reflect enable/archive, add `after_init` lifecycle hook that invokes `enable` subcommand (FR-006), update `before_finish` hook to invoke `archive`

---

## Phase 2: Core Script Rewrite

**Purpose**: Replace the Python script's detach/verify/clean-branch-name subcommands with enable, simplify archive

- [x] T003 Add `enable` subcommand to spex/extensions/spex-detach/scripts/spex-detach.py: write configured exclude paths to .git/info/exclude (idempotent, create .git/info/ if missing, preserve existing entries, warn if spec files are tracked)
- [x] T004 Simplify `archive` subcommand in spex/extensions/spex-detach/scripts/spex-detach.py: remove --move flag and branch context logic, keep copy-and-commit to sibling repo with project/feature directory structure
- [x] T005 Remove `detach`, `verify`, and `clean-branch-name` subcommands from spex/extensions/spex-detach/scripts/spex-detach.py
- [x] T006 Update COMMANDS dispatch table and usage string in spex/extensions/spex-detach/scripts/spex-detach.py: final table must include `enable`, `archive`, and `is-enabled` only (FR-015: is-enabled MUST be preserved)

**Checkpoint**: Core script has enable + archive + is-enabled subcommands only

---

## Phase 3: User Story 1 - Enable Stealth Mode (Priority: P1)

**Goal**: Spec artifacts are invisible to git after enabling detach extension

**Independent Test**: Run `enable`, then verify `git add .` and `git status` do not include spec files

- [x] T007 [US1] Rewrite command documentation to describe enable and archive subcommands in spex/extensions/spex-detach/commands/speckit.spex-detach.detach.md
- [x] T008 [US1] Update the detach skill file to match new command documentation in .claude/skills/speckit-spex-detach-detach/SKILL.md
- [x] T009 [US1] Add integration test for enable subcommand in tests/test_spex_detach.sh: verify .git/info/exclude entries are written, idempotency, preserves existing entries, warns on tracked files, and verify `is-enabled` returns exit 0 when extension dir exists and exit 1 otherwise (FR-015)

**Checkpoint**: Enable subcommand works end-to-end, tested

---

## Phase 4: User Story 2 - Archive at Finish Time (Priority: P2)

**Goal**: Spec artifacts are archived to sibling repo during spex-finish

**Independent Test**: Configure archive path, run archive subcommand, verify files copied and committed

- [x] T010 [US2] Verify before_finish hook in spex/extensions/spex-detach/extension.yml invokes `archive` subcommand with correct arguments; update hook entry to pass the project root and feature branch name to the archive command
- [x] T011 [US2] Add integration test for archive subcommand in tests/test_spex_detach.sh: verify copy to sibling repo, auto-commit, project/feature directory structure, graceful skip when no path configured

**Checkpoint**: Archive works via finish hook, tested

---

## Phase 5: User Story 3 - Enable/Verify Exclude Entries (Priority: P3)

**Goal**: Manual enable command for existing clones and troubleshooting

**Independent Test**: Run enable on repo without entries, verify added; run again, verify idempotent

- [x] T012 [US3] Add integration test for edge cases in tests/test_spex_detach.sh: missing .git/info/ directory, already-tracked files warning, non-git directory error

**Checkpoint**: All edge cases covered by tests

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Update documentation, clean up references to old approach

- [x] T013 [P] Remove detach detection logic (Phase 2b) from submit skill in .claude/skills/speckit-spex-submit/SKILL.md
- [x] T014 [P] Update detach extension description in README.md (change "Strip spec artifacts at PR time" to stealth mode description)
- [x] T015 [P] Update detach extension description in spex/docs/help.md
- [x] T016 Run `make release` to validate extension installation and integration tests in Makefile

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies, start immediately
- **Phase 2 (Core Script)**: Depends on Phase 1 (config and manifest define what the script reads)
- **Phase 3 (US1)**: Depends on Phase 2 (enable subcommand must exist)
- **Phase 4 (US2)**: Depends on Phase 2 (archive subcommand must exist); can run in parallel with Phase 3
- **Phase 5 (US3)**: Depends on Phase 3 (tests exercise enable edge cases)
- **Phase 6 (Polish)**: Depends on Phases 3-5

### Parallel Opportunities

- T013, T014, T015 can all run in parallel (different files, no dependencies)
- Phase 3 and Phase 4 can run in parallel after Phase 2 completes

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Config + manifest updates
2. Complete Phase 2: Rewrite Python script
3. Complete Phase 3: Enable subcommand + test
4. **STOP and VALIDATE**: Run enable, verify `git status` hides spec files

### Incremental Delivery

1. Setup + Core Script rewrite -> new subcommands available
2. Add US1 (enable + docs) -> stealth mode works
3. Add US2 (archive at finish) -> version control for specs
4. Add US3 (edge case tests) -> robustness
5. Polish (docs, cleanup) -> ready for release

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- The Python script rewrite (Phase 2) is the critical path
- Commit after each task or logical group
- Run `make release` at the end to verify integration
