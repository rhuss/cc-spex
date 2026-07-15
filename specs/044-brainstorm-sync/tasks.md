# Tasks: Brainstorm Directory Sync

**Input**: Design documents from `/specs/044-brainstorm-sync/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Add `--sync` argument detection and short-circuit logic to the brainstorm skill

- [x] T001 Add `--sync` argument detection at the top of the brainstorm skill in `spex/extensions/spex/commands/speckit.spex.brainstorm.md` that short-circuits the normal brainstorm flow (skips checklist steps 2-7) and routes to the sync-specific section

---

## Phase 2: User Story 1 - Sync and Archive Completed Brainstorms (Priority: P1)

**Goal**: Scan all brainstorm documents, classify by status, present interactive confirmation, move terminal-state docs to attic

**Independent Test**: Invoke `--sync` on the real brainstorm directory and verify the summary table shows correct classifications and moves are executed after confirmation

- [x] T002 [US1] Add the document scanning logic section to the sync flow in `spex/extensions/spex/commands/speckit.spex.brainstorm.md`: first check that `brainstorm/` exists and contains `.md` files (if not, report "No brainstorm documents found" and exit cleanly). List all `.md` files in `brainstorm/` excluding `00-overview.md` and `idea-inbox.md`, parse the `**Status:**` field from each document header, extract the first word as canonical status, default to `active` if no Status field found
- [x] T003 [US1] Add the classification logic section: categorize each document as `attic` (terminal states: spec-created, abandoned, completed, resolved, decided) or `keep` (active, parked, draft, idea), build a structured list of documents with their filename, number, slug, status, and proposed action
- [x] T004 [US1] Add the interactive confirmation section using `AskUserQuestion` with `multiSelect: true`: each attic candidate is a pre-selected option (label = document name, description = current status + " -> attic"), include a summary of keep items in the question text, handle user deselection to override individual items
- [x] T005 [US1] Add the file move execution section: create `brainstorm/attic/` if it doesn't exist, run `git mv brainstorm/<file> brainstorm/attic/<file>` for each confirmed item, skip and warn on filename conflicts (file already exists in attic), handle empty confirmation (user deselected all items) by exiting cleanly

---

## Phase 3: User Story 2 - Auto-detect Spec Matches by Filename (Priority: P1)

**Goal**: Cross-reference brainstorm documents against specs/ to detect implemented brainstorms even when status wasn't updated

**Independent Test**: Verify that brainstorms like `09-traits-to-extensions.md` are correctly matched to `specs/016-traits-to-extensions/` and proposed for attic with inferred status

- [x] T006 [US2] Add the spec slug index builder section to the sync flow in `spex/extensions/spex/commands/speckit.spex.brainstorm.md`: check if `specs/` directory exists (if not, skip spec cross-referencing entirely and rely only on document status fields). List all directories in `specs/`, extract number and slug from each directory name, build a lookup structure for slug matching
- [x] T007 [US2] Add the slug token matching algorithm section: for each brainstorm document, split its slug and each spec slug on hyphens, count shared tokens, match if >= 2 shared tokens or one slug is a complete substring of the other
- [x] T008 [US2] Add the overview table Spec column parser section: read `brainstorm/00-overview.md`, parse the Sessions table rows, extract brainstorm number and Spec column value, use these mappings to supplement slug-based matching
- [x] T009 [US2] Integrate spec matching into the classification logic (T003): when a spec match is found but the document's status is a keep-state (active, draft, idea), set inferred_status to `spec-created`, mark action as `attic`, and annotate with "(inferred)" in the confirmation table

---

## Phase 4: User Story 3 - Overview Update After Sync (Priority: P2)

**Goal**: Selectively remove attic'd documents from the overview so it only references remaining documents

**Independent Test**: After sync moves documents to attic, verify the overview's Sessions table, Open Threads, and Parked Ideas no longer reference archived brainstorms

- [x] T010 [US3] Add the overview update section to the sync flow in `spex/extensions/spex/commands/speckit.spex.brainstorm.md`: after file moves complete, read `brainstorm/00-overview.md`, identify rows in the Sessions table whose document number matches an attic'd file, remove those rows
- [x] T011 [US3] Add open thread cleanup: scan the Open Threads section for entries tagged with `(from #NN)` where NN matches an attic'd document's number, remove those entries
- [x] T012 [US3] Add the git commit section: stage all changes (`git add brainstorm/`), commit with message `chore(brainstorm): sync - archive N documents to attic` where N is the count of moved files

---

## Phase 5: User Story 4 - Handle Unnumbered Files (Priority: P3)

**Goal**: Include unnumbered brainstorm files in the scan and classification

**Independent Test**: Verify that unnumbered files like `sdd-showcase-projects.md` appear in the summary table and are handled correctly

- [x] T013 [US4] Update the document scanning logic (T002) to handle unnumbered files: for files without a `NN-` prefix, set number to null and use the full filename (minus `.md`) as the slug, ensure they appear in the confirmation table alongside numbered files

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates and sync of canonical source to installed copy

- [x] T014 [P] Sync the modified canonical command file to the installed location by running `make sync-scripts` or manually copying `spex/extensions/spex/commands/speckit.spex.brainstorm.md` to `.specify/extensions/spex/commands/speckit.spex.brainstorm.md` and `.claude/skills/speckit-spex-brainstorm/SKILL.md`
- [x] T015 [P] Update `spex/docs/help.md` to document the `--sync` option under the brainstorm command entry
- [x] T016 [P] Update `README.md` to mention the `--sync` option in the Commands Reference table for the brainstorm command

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies, start immediately
- **Phase 2 (US1 - Core sync)**: Depends on Phase 1
- **Phase 3 (US2 - Spec matching)**: Depends on Phase 2 (integrates into classification logic)
- **Phase 4 (US3 - Overview update)**: Depends on Phase 2 (runs after file moves)
- **Phase 5 (US4 - Unnumbered files)**: Depends on Phase 2 (extends scanning logic)
- **Phase 6 (Polish)**: Depends on all previous phases

### User Story Dependencies

- **US1 (Core sync)**: Foundation, must complete first
- **US2 (Spec matching)**: Enhances US1's classification, integrates into T003
- **US3 (Overview update)**: Runs after US1's file moves, can be built independently
- **US4 (Unnumbered files)**: Extends US1's scanning, minor addition to T002

### Within Each User Story

- Scanning before classification
- Classification before confirmation
- Confirmation before file moves
- File moves before overview update
- Overview update before commit

### Parallel Opportunities

- T006, T007, T008 (US2 spec matching components) can be written in parallel
- T010, T011 (US3 overview update components) can be written in parallel
- T014, T015, T016 (Polish tasks) can all run in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: US1 Core Sync (T002-T005)
3. **STOP and VALIDATE**: Test `--sync` with manual status checking only
4. This delivers the core value: terminal-state documents get archived

### Incremental Delivery

1. Add US1 (Core sync) -> Test with explicit statuses -> Working sync
2. Add US2 (Spec matching) -> Test with spec cross-reference -> Smarter sync
3. Add US3 (Overview update) -> Test overview cleanup -> Clean overview
4. Add US4 (Unnumbered files) -> Test with edge cases -> Complete coverage
5. Polish: docs and file sync

---

## Notes

- All implementation happens in a single file: `spex/extensions/spex/commands/speckit.spex.brainstorm.md`
- The file is a skill markdown document, not executable code. Instructions are written as prose that an AI agent interprets
- No test tasks included since there is no automated test framework for skill files; validation is via smoke test
- Total tasks: 16
- Tasks per story: US1=4, US2=4, US3=3, US4=1, Setup=1, Polish=3
