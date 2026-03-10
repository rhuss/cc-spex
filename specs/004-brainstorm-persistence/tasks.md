# Tasks: Brainstorm Persistence

**Input**: Design documents from `specs/004-brainstorm-persistence/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: Not requested. No test tasks included.

**Organization**: Tasks are grouped by user story. All tasks modify a single file (`sdd/skills/brainstorm/SKILL.md`) unless noted otherwise.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- All paths are relative to repository root

---

## Phase 1: Setup

**Purpose**: Understand the existing skill structure before modifying it

- [x] T001 Read and analyze current brainstorm skill structure in sdd/skills/brainstorm/SKILL.md, identify insertion points for each new section per plan.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add structural definitions and update the workflow checklist. These provide the shared foundations that all user story tasks reference.

- [x] T002 Update the Checklist section in sdd/skills/brainstorm/SKILL.md to add new steps: insert revisit detection after step 2, add "Write brainstorm document" and "Update overview" after step 8 (Transition)
- [x] T003 Add "Brainstorm Document Structure" section to sdd/skills/brainstorm/SKILL.md defining the inline document template with fields: date, status (active/parked/abandoned/spec-created), spec reference, problem framing, approaches considered, decision, and open threads
- [x] T004 Add "Overview Document Structure" section to sdd/skills/brainstorm/SKILL.md defining the overview template with: sessions index table (number, date, topic, status, spec), open threads section, and parked ideas section

**Checkpoint**: Structural definitions in place. User story implementation can begin.

---

## Phase 3: User Story 1 - Complete brainstorm session produces a document (Priority: P1)

**Goal**: At session end, the skill writes a structured summary document to `brainstorm/NN-topic-slug.md`. Directory is auto-created.

**Independent Test**: Run `/sdd:brainstorm`, complete a full session. Confirm a numbered markdown file appears in `brainstorm/` with all required sections.

- [x] T005 [US1] Add "Writing the Brainstorm Document" section to sdd/skills/brainstorm/SKILL.md covering: directory creation (mkdir -p brainstorm/), sequential number detection (scan existing NN-*.md, use max+1), topic slug generation, file writing with the document template, and status assignment logic
- [x] T006 [US1] Modify the "After spec creation" section in sdd/skills/brainstorm/SKILL.md to capture the spec path (specs/NNNN-feature-name/) for the brainstorm document's Spec field when status is spec-created
- [x] T007 [US1] Add the brainstorm document writing step to the main workflow in sdd/skills/brainstorm/SKILL.md: insert it after the "Offer next steps" block, before the terminal state, so it executes at session end for completed sessions

**Checkpoint**: A completed brainstorm session produces a numbered document in `brainstorm/`.

---

## Phase 4: User Story 2 - Overview index tracks all sessions (Priority: P1)

**Goal**: After any brainstorm document is written or updated, `brainstorm/00-overview.md` is created or refreshed with an index of all sessions, aggregated open threads, and parked ideas.

**Independent Test**: After two brainstorm sessions, open `00-overview.md` and verify both sessions appear with correct status and open threads are aggregated.

- [x] T008 [US2] Add "Updating the Overview" section to sdd/skills/brainstorm/SKILL.md covering: create 00-overview.md if missing, always regenerate by scanning all NN-*.md files, extract frontmatter (date, status, spec), extract open threads, build sessions table, aggregate open threads, collect parked ideas, write updated 00-overview.md
- [x] T009 [US2] Add the overview update step to the main workflow in sdd/skills/brainstorm/SKILL.md immediately after the brainstorm document writing step (T007), ensuring it runs after every document write or update
- [x] T010 [US2] Add edge case handling for missing overview: if brainstorm/ directory exists but 00-overview.md is missing, regenerate it from existing documents in sdd/skills/brainstorm/SKILL.md

**Checkpoint**: Every brainstorm document write triggers an overview update. Overview accurately reflects all documents.

---

## Phase 5: User Story 3 - Incomplete sessions offer save choice (Priority: P2)

**Goal**: When a user stops a brainstorm before creating a spec, the skill asks whether to save the session as a document.

**Independent Test**: Start a brainstorm, answer two questions, say "let's stop". Verify the skill asks to save and respects the answer.

- [x] T011 [US3] Add incomplete session handling to sdd/skills/brainstorm/SKILL.md: when the user stops before spec creation, use AskUserQuestion to ask "Save this brainstorm session?" with options to save (parked/abandoned) or discard
- [x] T012 [US3] Add zero-interaction guard to sdd/skills/brainstorm/SKILL.md: if the session had no meaningful interaction (no approaches explored, no clarifying questions answered), skip the save prompt entirely and do not create a document

**Checkpoint**: Incomplete sessions prompt the user. Zero-interaction sessions produce no artifacts.

---

## Phase 6: User Story 4 - Revisiting an existing topic (Priority: P2)

**Goal**: When starting a brainstorm on a topic with existing brainstorm documents, the skill detects the overlap and offers to create new or update existing.

**Independent Test**: Create a brainstorm about "auth system", then start another about "auth". Verify the skill detects the existing doc and offers the choice.

- [x] T013 [US4] Add "Revisit Detection" section to sdd/skills/brainstorm/SKILL.md: after exploring project context (step 2), scan brainstorm/ for existing documents, extract topic slugs from filenames, compare against current topic using keyword overlap
- [x] T014 [US4] Add revisit choice handling to sdd/skills/brainstorm/SKILL.md: when a match is found, use AskUserQuestion with options "Create new document" or "Update existing". If updating, append a new dated section to the existing document rather than overwriting.
- [x] T015 [US4] Modify the context exploration step in sdd/skills/brainstorm/SKILL.md ("Check context first" under "Understanding the idea") to include scanning brainstorm/ directory alongside existing specs, constitution, and recent commits

**Checkpoint**: Revisit detection works. User can choose new doc or update existing. Updated docs get a new dated section appended.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final integration and verification across all user stories

- [x] T016 Update the process flow diagram (dot graph) in sdd/skills/brainstorm/SKILL.md to include: revisit detection diamond after "Explore project context", document writing node after transition, overview update node after document writing
- [x] T017 Review all edge cases from spec.md against the final sdd/skills/brainstorm/SKILL.md: first brainstorm ever, missing overview, manually deleted docs (max+1 not gap-filling), multiple brainstorms on same topic, zero-interaction bail
- [x] T018 Manual verification: run /sdd:brainstorm in a Claude Code session, complete a full brainstorm, verify document and overview are created correctly

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001)
- **US1 (Phase 3)**: Depends on Foundational (T002-T004)
- **US2 (Phase 4)**: Depends on US1 (T007, needs document writing in place first)
- **US3 (Phase 5)**: Depends on Foundational (T002-T004), independent of US1/US2
- **US4 (Phase 6)**: Depends on Foundational (T002-T004), independent of US1/US2
- **Polish (Phase 7)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational
- **US2 (P1)**: Depends on US1 (overview references documents that US1 creates)
- **US3 (P2)**: Can start after Foundational, independent of US1/US2
- **US4 (P2)**: Can start after Foundational, independent of US1/US2

### Within Each User Story

All tasks within a story are sequential (same file, each builds on previous additions).

### Parallel Opportunities

- US3 and US4 can proceed in parallel after Foundational (they modify different sections of the skill file)
- T003 and T004 can be written in parallel (independent structure definition sections)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002-T004)
3. Complete Phase 3: User Story 1 (T005-T007)
4. **STOP and VALIDATE**: Run a brainstorm session, verify document is created
5. Functional MVP: brainstorm sessions produce persistent documents

### Incremental Delivery

1. Setup + Foundational (T001-T004)
2. US1: Document writing (T005-T007) -> Validate -> MVP
3. US2: Overview management (T008-T010) -> Validate -> Documents are navigable
4. US3: Incomplete session handling (T011-T012) -> Validate -> Clutter prevention
5. US4: Revisit detection (T013-T015) -> Validate -> Topic evolution tracking
6. Polish (T016-T018) -> Final verification

---

## Summary

- **Total tasks**: 18
- **US1 tasks**: 3 (document writing)
- **US2 tasks**: 3 (overview management)
- **US3 tasks**: 2 (incomplete session handling)
- **US4 tasks**: 3 (revisit detection)
- **Setup/Foundational**: 4
- **Polish**: 3
- **Parallel opportunities**: T003/T004, US3/US4
- **MVP scope**: T001-T007 (7 tasks, Setup + Foundational + US1)


<!-- SDD-TRAIT:beads -->
## Beads Task Management

This project uses beads (`bd`) for persistent task tracking across sessions:
- Run `/sdd:beads-task-sync` to create bd issues from this file
- `bd ready --json` returns unblocked tasks (dependencies resolved)
- `bd close <id>` marks a task complete (use `-r "reason"` for close reason, NOT `--comment`)
- `bd comments add <id> "text"` adds a detailed comment to an issue
- `bd backup` persists state to git
- `bd create "DISCOVERED: [short title]" --labels discovered` tracks new work
  - Keep titles crisp (under 80 chars); add details via `bd comments add <id> "details"`
- Run `/sdd:beads-task-sync --reverse` to update checkboxes from bd state
- **Always use `jq` to parse bd JSON output, NEVER inline Python one-liners**
