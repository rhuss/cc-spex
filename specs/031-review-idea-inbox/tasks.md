# Tasks: Review Idea Inbox

**Input**: Design documents from `specs/031-review-idea-inbox/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: User Story 1 — Triage Captures Out-of-Scope Ideas to Inbox (Priority: P1) MVP

**Goal**: Replace triage Step 15's broken threshold with thematic clustering and write selected themes to `brainstorm/idea-inbox.md` instead of invoking brainstorm directly.

**Independent Test**: Run `/speckit-spex-collab-triage` on a PR with 2+ deferred findings on the same theme. Verify the inbox prompt appears and entries are written.

### Implementation

- [x] T001 [US1] Modify Step 15 skip condition in `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md` — change from "no deferred AND fewer than 3 rejected" to "no deferred AND no rejected" (line ~480)
- [x] T002 [US1] Replace Step 15 thematic clustering trigger in `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md` — trigger when any theme cluster has 2+ findings regardless of verdict mix (deferred + rejected combined), not 3+ rejected only
- [x] T003 [US1] Replace Step 15 brainstorm invocation with inbox write in `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md` — for each selected theme, append an entry to `brainstorm/idea-inbox.md` using the inbox entry format (theme slug heading, source=triage, date, PR reference, summary, context). Create the file with the `# Idea Inbox` header if it doesn't exist.
- [x] T004 [US1] Remove GitHub issue creation from Step 15 in `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md` — the "Link back to PR" substep (lines ~516-525) is no longer needed since brainstorm handles issue creation when consuming inbox items later

**Checkpoint**: Triage Step 15 now writes to idea-inbox.md instead of invoking brainstorm directly, with a lower thematic threshold.

---

## Phase 2: User Story 2 — Brainstorm Skill Consumes Inbox Items (Priority: P1)

**Goal**: The brainstorm skill checks the idea inbox at startup and offers accumulated items as brainstorm seeds. Consumed items are removed from the inbox.

**Independent Test**: Manually populate `brainstorm/idea-inbox.md` with 2-3 entries, invoke `/speckit-spex-brainstorm`, verify inbox items are presented as seeds.

### Implementation

- [x] T005 [US2] Add inbox check to step 2 (explore context) in `spex/extensions/spex/commands/speckit.spex.brainstorm.md` — after the "Scan `brainstorm/` directory" bullet in the "Check context first" section, add: check if `brainstorm/idea-inbox.md` exists and has entries. Parse entries by `### ` headings with their metadata fields.
- [x] T006 [US2] Add inbox presentation logic before step 3 in `spex/extensions/spex/commands/speckit.spex.brainstorm.md` — if inbox entries exist, present them grouped by theme as a multi-select question with options for each theme plus a "Start fresh" option. If the user selects themes, use them as brainstorm seeds (pre-fill the problem framing with the inbox entry's summary and context). If "Start fresh" or inbox is empty, proceed with normal flow.
- [x] T007 [US2] Add inbox consumption to step 7 (write brainstorm document) in `spex/extensions/spex/commands/speckit.spex.brainstorm.md` — after writing the brainstorm document, if the session was seeded from inbox items, remove the consumed entries from `brainstorm/idea-inbox.md` using the Edit tool (match the `### <theme-slug>` heading and its content block through the next heading or end of file). If all entries are consumed, leave the file with just the `# Idea Inbox` header line.
- [x] T008 [US2] Update the brainstorm skill checklist in `spex/extensions/spex/commands/speckit.spex.brainstorm.md` — add "Check idea inbox" as step 2.5 between "Explore project context" and "Check for related brainstorms" in the checklist at the top of the file

**Checkpoint**: Brainstorm skill presents inbox items as seeds and removes consumed entries.

---

## Phase 3: User Story 3 — Deep Review Captures Notable Observations (Priority: P2)

**Goal**: Add a "Notable" verdict to the deep review agent classification. Notable findings appear in review-findings.md and are appended to the idea inbox.

**Independent Test**: Run `/speckit-spex-deep-review-run` on code with a design-level concern. Verify Notable findings appear in review-findings.md and idea-inbox.md.

### Implementation

- [x] T009 [US3] Add Notable to finding severity enum in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` — extend the severity field in the finding schema (line ~259) from `Critical|Important|Minor` to `Critical|Important|Minor|Notable`
- [x] T010 [US3] Add Notable guidance to review agent prompt instructions in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` — in the agent prompt section, add guidance explaining Notable: "For design-level observations that are not bugs but are worth revisiting (e.g., an interface that will need to evolve, a pattern that works now but won't scale under future requirements), classify as Notable. Notable findings are informational and do not trigger fixes."
- [x] T011 [US3] Exclude Notable from gate check and fix loop in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` — in Step 6 (gate check, line ~291), ensure the gate logic remains `Critical + Important = 0` (Notable is excluded). In Step 7 (fix loop, line ~300), ensure only Critical and Important findings are collected for fixing.
- [x] T012 [US3] Add Notable row to summary table in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` — in Step 8 (write review-findings.md, line ~413), add a Notable row to the summary table between Minor and Total
- [x] T013 [US3] Add "Notable Observations" section to review-findings.md output in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` — after the Findings section in Step 8, add a `## Notable Observations` section that lists Notable findings with a simplified format (no resolution tracking since they aren't fixed)
- [x] T014 [US3] Add inbox write for Notable findings in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` — after writing review-findings.md in Step 8, append each Notable finding to `brainstorm/idea-inbox.md` with source=deep-review, using the finding's description as summary and rationale as context. Create the inbox file if it doesn't exist.

**Checkpoint**: Deep review agents can classify Notable findings; these appear in review-findings.md and idea-inbox.md.

---

## Phase 4: User Story 4 — Conversational Nudge (Priority: P3)

**Goal**: Add a gentle suggestion about the idea inbox when review discussions contain deferred-idea signals.

**Independent Test**: Process a review discussion with "out of scope" phrases. Verify a suggestion mentioning the inbox appears.

### Implementation

- [x] T015 [US4] Add conversational nudge guidance to `spex/extensions/spex/commands/speckit.spex.brainstorm.md` — in the skill description frontmatter or an early section, add a note that when the brainstorm skill is invoked after a review discussion containing deferred-idea signals ("out of scope", "worth considering later", "design tension", "follow-up", "for a future PR"), the skill should mention that ideas can be added to the inbox. This is documentation-level guidance, not code behavior.

**Checkpoint**: The brainstorm skill documentation mentions the inbox in review-adjacent contexts.

---

## Phase 5: User Story 5 — README Documents Idea Capture Workflow (Priority: P2)

**Goal**: Add an "Idea Capture During Reviews" section to the README explaining the complete workflow.

**Independent Test**: Read the README section and verify it explains the problem, inbox mechanism, all sources, and consumption.

### Implementation

- [x] T016 [P] [US5] Add "Idea Capture During Reviews" section to `README.md` — insert after the "Deep Review" section (line ~362). Cover: the problem (review ideas getting lost), the inbox mechanism (`brainstorm/idea-inbox.md`), three sources (triage thematic clustering, deep review Notable verdict, manual addition), consumption via `/speckit-spex-brainstorm`, and a brief example of an inbox entry format.
- [x] T017 [P] [US5] Add inbox reference to `spex/docs/help.md` — add a brief mention of the idea inbox under the brainstorm and triage command descriptions

**Checkpoint**: New users can discover and understand the idea capture workflow from the README.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T018 Verify cross-references between modified files are consistent — ensure triage Step 15 references the inbox format from data-model.md, deep review references the same format, and brainstorm skill's parsing matches what the writers produce
- [x] T019 Commit all changes with descriptive messages per user story

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (US1 — Triage)**: No dependencies — can start immediately
- **Phase 2 (US2 — Brainstorm)**: No dependency on Phase 1 (reads inbox format, doesn't depend on triage writing it)
- **Phase 3 (US3 — Deep Review)**: No dependency on Phase 1 or 2 (writes same inbox format independently)
- **Phase 4 (US4 — Nudge)**: Depends on Phase 2 (references brainstorm skill)
- **Phase 5 (US5 — README)**: Depends on Phases 1-3 (documents the complete workflow)
- **Phase 6 (Polish)**: Depends on all prior phases

### Parallel Opportunities

- **Phases 1, 2, 3 can run in parallel** — they modify different files and share only the inbox file format
- **Phase 5 tasks T016 and T017 can run in parallel** — different files
- Within Phase 3, tasks T009-T014 are sequential (same file)

---

## Implementation Strategy

### MVP First (User Stories 1 + 2)

1. Complete Phase 1 (triage writes to inbox)
2. Complete Phase 2 (brainstorm reads from inbox)
3. **STOP and VALIDATE**: Manually test the write-read cycle
4. Proceed to Phase 3 (deep review Notable)

### Incremental Delivery

1. Triage → inbox write works → Phase 1 done
2. Brainstorm → inbox read + consume works → Phase 2 done
3. Deep review → Notable verdict + inbox write → Phase 3 done
4. Documentation → README + help → Phase 5 done
5. Each phase adds a new source or consumer without breaking previous ones

---

## Notes

- All changes are to markdown skill/command files (no compiled code)
- The inbox format is the shared contract — all writers and readers must agree on the `### <theme-slug>` heading structure
- No setup or foundational phase needed — all infrastructure (brainstorm directory, extensions) already exists
- Tests are manual (skill files are AI instructions, not executable code)
