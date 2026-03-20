# Tasks: Worktrees Trait

**Input**: Design documents from `/specs/007-worktrees-trait/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: No automated tests (manual verification via `make reinstall` + Claude Code session testing per constitution).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Register the worktrees trait in the SDD plugin infrastructure

- [x] T001 Add `worktrees` to valid traits list and config handling in `sdd/scripts/sdd-traits.sh`
- [x] T002 [P] Create overlay directory structure at `sdd/overlays/worktrees/commands/`

**Checkpoint**: `sdd:traits` can enable/disable the worktrees trait, config includes `worktrees_config.base_path`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the command and skill skeleton that all user stories build upon

- [x] T003 Create command wrapper at `sdd/commands/worktree.md` with frontmatter (name, description, argument-hint) delegating to `{Skill: sdd:worktree}`
- [x] T004 Create skill skeleton at `sdd/skills/worktree/SKILL.md` with frontmatter, overview, and action routing (create/list/cleanup) but no implementation yet

**Checkpoint**: Command and skill exist, `sdd:worktree` is invocable (routes to correct action but no-ops)

---

## Phase 3: User Story 1 - Isolated Feature Development After Specify (Priority: P1) MVP

**Goal**: After `speckit.specify`, automatically create a worktree, restore main, write handoff file, and print switch instructions.

**Independent Test**: Enable worktrees trait, run `speckit.specify` for a test feature, verify: (1) worktree exists at `../<branch-name>`, (2) original repo is on `main`, (3) `<worktree>/.claude/handoff.md` exists with summary + pointers, (4) instructions printed.

### Implementation for User Story 1

- [x] T005 [US1] Create overlay at `sdd/overlays/worktrees/commands/speckit.specify.append.md` that adds a post-specify section delegating to `{Skill: sdd:worktree}` with action "create"
- [x] T006 [US1] Implement the "create" action in `sdd/skills/worktree/SKILL.md`: read `base_path` from `.specify/sdd-traits.json` (key `worktrees_config.base_path`, default `..`), get current branch name, compute worktree target path
- [x] T007 [US1] Add worktree detection logic in `sdd/skills/worktree/SKILL.md`: detect if already inside a worktree (`.git` is a file not a directory), warn and skip if so (FR-009)
- [x] T008 [US1] Add pre-creation validation in `sdd/skills/worktree/SKILL.md`: check target path does not already exist (FR-008), report error if it does
- [x] T009 [US1] Implement worktree creation in `sdd/skills/worktree/SKILL.md`: run `git worktree add <path> <branch>`, handle failure with clear error message (edge case 3)
- [x] T010 [US1] Implement branch restore in `sdd/skills/worktree/SKILL.md`: run `git checkout main`, handle uncommitted changes failure by warning user instead of aborting (FR-002 clarification)
- [x] T011 [US1] Implement handoff file generation in `sdd/skills/worktree/SKILL.md`: create `<worktree>/.claude/` directory, write `handoff.md` with brainstorm summary (5-10 lines), spec pointer, and suggested next step (FR-003)
- [x] T012 [US1] Implement switch instructions in `sdd/skills/worktree/SKILL.md`: print formatted instruction box with exact `cd <path> && claude` command (FR-004)
- [x] T013 [US1] Run `sdd-traits.sh apply` to apply the new overlay onto `speckit.specify.md` and verify the overlay appears with correct sentinel marker

**Checkpoint**: User Story 1 fully functional. `speckit.specify` with worktrees trait creates worktree, restores main, writes handoff, prints instructions.

---

## Phase 4: User Story 2 - Worktree Listing (Priority: P2)

**Goal**: Show all active feature worktrees with path, branch, and feature name.

**Independent Test**: Create two worktrees manually, run `sdd:worktree list`, verify both appear with correct metadata. Run with no worktrees, verify "no worktrees active" message.

### Implementation for User Story 2

- [x] T014 [US2] Implement the "list" action in `sdd/skills/worktree/SKILL.md`: run `git worktree list --porcelain`, parse output for worktree paths and branch names
- [x] T015 [US2] Add feature branch filtering in `sdd/skills/worktree/SKILL.md`: filter worktree list to only show branches matching `NNN-*` pattern, extract feature name from branch
- [x] T016 [US2] Format listing output in `sdd/skills/worktree/SKILL.md`: display table with path, branch, and feature columns; handle empty case with "no worktrees active" message (FR-005)

**Checkpoint**: `sdd:worktree list` shows all feature worktrees with correct metadata.

---

## Phase 5: User Story 3 - Worktree Cleanup After Merge (Priority: P3)

**Goal**: Detect merged worktrees and offer removal with safety checks.

**Independent Test**: Merge a feature branch into main, run `sdd:worktree cleanup`, verify merged worktree is identified and removal offered. Test with unmerged branch, verify warning shown.

### Implementation for User Story 3

- [x] T017 [US3] Implement the "cleanup" action in `sdd/skills/worktree/SKILL.md`: get worktree list, check each feature branch against `git branch --merged main` to identify merged branches (FR-006)
- [x] T018 [US3] Add merged worktree removal in `sdd/skills/worktree/SKILL.md`: for merged branches, offer removal via `git worktree remove <path>` and `git branch -d <branch>` (acceptance scenario 3)
- [x] T019 [US3] Add unmerged branch safety in `sdd/skills/worktree/SKILL.md`: warn when branch is unmerged, require explicit confirmation before removal (FR-007)

**Checkpoint**: `sdd:worktree cleanup` correctly identifies merged branches and safely handles removal.

---

## Phase 6: Polish and Cross-Cutting Concerns

**Purpose**: Documentation and integration updates

- [x] T020 [P] Update `sdd/skills/help/SKILL.md` to include `sdd:worktree` command with list/cleanup subcommands
- [x] T021 [P] Update `CLAUDE.md` active technologies and traits list to include `worktrees`

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion, this is the MVP
- **User Story 2 (Phase 4)**: Depends on Phase 2 completion (independent of US1)
- **User Story 3 (Phase 5)**: Depends on Phase 2 completion (independent of US1, US2)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent, can start after Phase 2
- **User Story 2 (P2)**: Independent, can start after Phase 2 (shares skill file with US1)
- **User Story 3 (P3)**: Independent, can start after Phase 2 (shares skill file with US1, US2)

### Within User Story 1

- T005 (overlay) and T006-T08 (skill setup) can start in parallel
- T009 (creation) depends on T006-T08
- T010 (restore) depends on T009
- T011 (handoff) depends on T009
- T012 (instructions) depends on T009
- T013 (apply) depends on T005

### Parallel Opportunities

- T001 and T002 in Phase 1 (T002 marked [P])
- T003 and T004 in Phase 2 (different files)
- T020 and T021 in Phase 6 (different files)
- US2 and US3 phases can run in parallel after Phase 2 (both add to the same skill file, so sequential is safer)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T004)
3. Complete Phase 3: User Story 1 (T005-T013)
4. **STOP and VALIDATE**: Enable trait, run `speckit.specify`, verify full flow
5. This delivers the core value: worktree isolation after specify

### Incremental Delivery

1. Setup + Foundational -> Trait registered and skeleton ready
2. User Story 1 -> Test independently -> Core feature works (MVP)
3. User Story 2 -> Test independently -> Listing works
4. User Story 3 -> Test independently -> Cleanup works
5. Polish -> Documentation updated

---

## Notes

- All implementation is Markdown + Bash (no compiled artifacts per constitution)
- Overlays must be < 30 lines per constitution Principle II
- Manual verification via `make reinstall` + Claude Code session testing
- The skill file (`sdd/skills/worktree/SKILL.md`) is the main implementation artifact; it grows across US1, US2, US3
