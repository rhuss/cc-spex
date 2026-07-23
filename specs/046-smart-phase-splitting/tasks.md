# Tasks: Smart Phase Splitting

**Input**: Design documents from `specs/046-smart-phase-splitting/`

**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

**Organization**: Tasks grouped by user story for independent implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: Add configuration support for the file threshold

- [X] T001 Add `phases` section with `file_threshold: 20` to `spex/extensions/spex-collab/config-template.yml`

---

## Phase 2: US1 + US4 - Threshold Gate with File Estimation (Priority: P1, P3)

**Goal**: Estimate file count and skip phase splitting for small features. US4 (configurable threshold) is implemented together with US1 since reading the config value is a prerequisite for the threshold comparison.

**Independent Test**: Create a tasks.md with 12 tasks under 3 Phase headings and a plan.md referencing 15 files. Run phase-split hook. Verify no prompt appears and phase plan is set to single phase.

- [X] T002 [US1] Add file estimation logic to phase-split: parse file paths from plan.md using grep, deduplicate, fall back to task-count * 1.5 heuristic when fewer than 5 paths found in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md`
- [X] T003 [US1] Add threshold gate: read `phases.file_threshold` from collab-config.yml (default 20), compare against estimated file count, silently default to single-phase mode when at or below threshold in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md`
- [X] T004 [US1] Update single-phase output instructions: when single-phase is selected or threshold-defaulted, output instructions that call phase-manager only once after all tasks complete (not per-phase) in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md`

**Checkpoint**: Small features (< 20 estimated files) should now silently default to single phase with no prompt.

---

## Phase 3: US2 - Uninterrupted Single-Phase Implementation (Priority: P1)

**Goal**: Ensure phase-manager does not fire during implementation in single-phase mode, and fires exactly once at the end.

**Independent Test**: Set up single-phase mode in `.spex-state`, run implement. Verify phase-manager does not fire during implementation but fires once afterward.

- [X] T005 [US2] Add single-phase detection to phase-manager: when `collab.phase_plan` has exactly one entry, handle as final-only invocation (review gate + PR offer) in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md`

**Checkpoint**: Single-phase implementation should run all tasks without interruption, with phase-manager firing once at the end.

---

## Phase 4: US3 - Phase Merge Logic for Large Features (Priority: P2)

**Goal**: When a large feature exceeds the file threshold, merge adjacent small phases from tasks.md into substantial groupings.

**Independent Test**: Create a tasks.md with 7 phases (2-5 tasks each) and plan.md listing 45 file paths. Verify merge produces fewer phases, each touching 10+ files.

- [X] T006 [US3] Add adjacent phase merge algorithm to phase-split: after detecting phases from tasks.md, distribute estimated files proportionally across phases, then greedily merge adjacent phases that touch fewer than 10 files in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md`
- [X] T007 [US3] Update phase proposal display: show merged phase names (combined from originals), preserve "Confirm as-is", "Adjust groupings", "Single phase (no split)" options in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md`

**Checkpoint**: Large features should see merged phase proposals with each phase touching at least 10 files.

---

## Phase 5: Polish & Documentation

**Purpose**: Update documentation and validate the full change

- [X] T008 [P] Update `README.md` collab extension description to mention smart phase splitting and configurable threshold
- [X] T009 [P] Update `spex/docs/help.md` to document `phases.file_threshold` config option
- [X] T010 Run `make release` to validate schema and integration tests pass

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **US1+US4 (Phase 2)**: Depends on Phase 1 (config template must exist)
- **US2 (Phase 3)**: Depends on Phase 2 (needs single-phase plan structure from phase-split)
- **US3 (Phase 4)**: Depends on Phase 2 (builds on file estimation and threshold logic)
- **Polish (Phase 5)**: Depends on Phases 2-4

### Within Each Phase

- Phase 2: T002 → T003 → T004 (sequential, same file, each builds on previous)
- Phase 3: T005 standalone (different file from Phase 2)
- Phase 4: T006 → T007 (sequential, same file)
- Phase 5: T008 and T009 are parallel [P], T010 runs last

### Parallel Opportunities

- Phase 3 (US2) and Phase 4 (US3) can run in parallel after Phase 2 completes (different concerns, Phase 3 modifies phase-manager while Phase 4 modifies phase-split)
- T008 and T009 (docs) can run in parallel

---

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup (config template)
2. Complete Phase 2: US1 threshold gate + file estimation
3. Complete Phase 3: US2 uninterrupted single-phase
4. **STOP and VALIDATE**: Test that small features skip the phase prompt and run uninterrupted
5. This covers the two P1 user stories and delivers the core value

### Incremental Delivery

1. Setup + US1/US4 → Small features silently skip phase splitting
2. Add US2 → Single-phase runs without interruption
3. Add US3 → Large features get merged phase proposals
4. Polish → Documentation updated, validation passes

---

## Notes

- All changes are to existing markdown command files (no new files needed)
- The phase-split command is the primary file (~80% of changes)
- Phase-manager changes are minimal (single-phase detection guard)
- Config template change is one line addition
- Total estimated files: ~5 (3 commands + 2 docs)
