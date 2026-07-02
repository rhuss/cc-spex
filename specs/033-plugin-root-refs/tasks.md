# Tasks: Replace find calls with plugin root references

**Input**: Design documents from `specs/033-plugin-root-refs/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Identify the reference preamble pattern and validate all script paths

- [X] T001 Read reference implementation in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md` to capture the exact "Step 0: Resolve Plugin Root" preamble text and formatting

---

## Phase 2: User Story 1+2 - Replace find patterns and add preambles (Priority: P1) MVP

**Goal**: Replace all 16 find patterns across 11 files with `<PLUGIN_ROOT>/scripts/...` references and add preambles where missing

**Independent Test**: Run `rg "find ~/\.claude" spex/extensions/ --glob '*.md'` and confirm zero matches

### spex core extension (6 files, 10 occurrences)

- [X] T002 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-flow-state.sh` in `spex/extensions/spex/commands/speckit.spex.flow-state.md`
- [X] T003 [P] [US1] Add plugin root preamble and replace 2 `find` patterns for `spex-ship-state.sh` in `spex/extensions/spex/commands/speckit.spex.ship.md` (preserve existing `<PLUGIN_ROOT>` reference for `spex-worktree-cwd.sh`)
- [X] T004 [P] [US1] Add plugin root preamble and replace 2 `find` patterns for `spex-ship-state.sh` and `spex-finish-context.sh` in `spex/extensions/spex/commands/speckit.spex.finish.md`
- [X] T005 [P] [US1] Add plugin root preamble and replace 3 `find` patterns for `spex-detach.sh`, `spex-finish-context.sh`, and `spex-ship-state.sh` in `spex/extensions/spex/commands/speckit.spex.submit.md`
- [X] T006 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-detach.sh` in `spex/extensions/spex/commands/speckit.spex.brainstorm.md`
- [X] T007 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-ship-state.sh` in `spex/extensions/spex/commands/speckit.spex.smoke-test.md`

### spex-detach extension (1 file, 1 occurrence)

- [X] T008 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-detach.sh` in `spex/extensions/spex-detach/commands/speckit.spex-detach.detach.md`

### spex-gates extension (3 files, 4 occurrences)

- [X] T009 [P] [US1] Add plugin root preamble and replace 2 `find` patterns for `spex-flow-state.sh` in `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`
- [X] T010 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-flow-state.sh` in `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md`
- [X] T011 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-flow-state.sh` in `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md`

### spex-deep-review extension (1 file, 1 occurrence)

- [X] T012 [P] [US1] Add plugin root preamble and replace 1 `find` pattern for `spex-flow-state.sh` in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`

**Checkpoint**: All 16 find patterns replaced, all 11 files have preambles. `rg "find ~/\.claude" spex/extensions/ --glob '*.md'` returns zero matches.

---

## Phase 3: User Story 3 - Preamble consistency (Priority: P2)

**Goal**: Ensure all preambles follow the same format and list only the scripts referenced in that file

- [X] T013 [US3] Verify each of the 11 modified files has a consistent preamble format matching the reference implementation in phase-manager, and that no duplicate preambles exist in files that already had one (ship.md)

**Checkpoint**: All preambles follow the canonical format from phase-manager.

---

## Phase 4: Polish & Verification

**Purpose**: Final validation across all affected files

- [X] T014 Run `rg "find ~/\.claude" spex/extensions/ --glob '*.md'` to verify zero remaining find patterns
- [X] T015 Run `rg "PLUGIN_ROOT" spex/extensions/ --glob '*.md' -l` to verify all 11 affected files plus existing collab files appear
- [X] T016 Verify that collab extension commands (`speckit.spex-collab.phase-manager.md`, `speckit.spex-collab.triage.md`) were NOT modified by any prior task (FR-005: already-migrated files must be preserved)
- [X] T017 Run `make release` to validate full integration test passes

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, captures reference pattern
- **Phase 2 (US1+US2)**: Depends on Phase 1. All tasks marked [P] can run in parallel since each modifies a different file
- **Phase 3 (US3)**: Depends on Phase 2 completion
- **Phase 4 (Polish)**: Depends on all prior phases

### Parallel Opportunities

All 11 file modification tasks (T002-T012) are marked [P] because each modifies a different file with no cross-file dependencies. These can all be executed concurrently.

---

## Implementation Strategy

### MVP First

1. Complete Phase 1: Read reference implementation
2. Complete Phase 2: Replace all 16 find patterns (all parallelizable)
3. **STOP and VALIDATE**: Verify zero find patterns remain
4. Complete Phase 3: Preamble consistency check
5. Complete Phase 4: Full verification with `make release`

---

## Notes

- All tasks modify markdown files only, no shell scripts or Python
- `spex-detach.sh` path is `scripts/bash/spex-detach.sh` (not `scripts/spex-detach.sh`)
- `ship.md` already has a partial `<PLUGIN_ROOT>` preamble; do not duplicate it
- Commit after each logical group of file changes
