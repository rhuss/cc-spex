# Tasks: Flow Status Line

**Input**: Design documents from `specs/015-flow-status-line/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (State File Rename)

**Purpose**: Rename `.spex-ship-phase` to `.spex-state` across the entire codebase. Foundation for all subsequent work.

- [X] T001 [P] Rename state file path in `spex/scripts/spex-ship-statusline.sh` (replace `.spex-ship-phase` with `.spex-state`)
- [X] T002 [P] Rename state file path in `spex/scripts/spex-ship-state.sh` (replace `.spex-ship-phase` with `.spex-state`)
- [X] T003 [P] Rename state file path in `spex/scripts/hooks/pretool-gate.py` (3 occurrences of `.spex-ship-phase`)
- [X] T004 [P] Rename state file path in `spex/skills/ship/SKILL.md` (all occurrences of `.spex-ship-phase`)
- [X] T005 [P] Rename state file path in all `.claude/skills/speckit-*/SKILL.md` guard sections (specify, clarify, plan, tasks, implement)
- [X] T006 [P] Rename state file path in all overlay files under `spex/overlays/` that reference `.spex-ship-phase`
- [X] T007 Validate rename complete: `rg '\.spex-ship-phase' spex/ .claude/` returns zero matches

**Checkpoint**: All references updated. No `.spex-ship-phase` strings remain in codebase.

---

## Phase 2: Foundational (State File Schema Extension)

**Purpose**: Add `mode` field to state file and update state management script

- [X] T008 Update `spex/scripts/spex-ship-state.sh` `do_create()` function to add `"mode": "ship"` field to state JSON
- [X] T009 Update `spex/scripts/spex-ship-state.sh` `do_status()` to include mode in status output

**Checkpoint**: Ship mode continues to work with new `mode` field. No regressions.

---

## Phase 3: User Story 3 - Review Artifact Split (Priority: P1)

**Goal**: Split monolithic REVIEWERS.md into per-review files (REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md).

**Independent Test**: Run `/spex:review-spec` and verify it produces `REVIEW-SPEC.md` in the spec directory.

- [X] T010 [US3] Update `spex/skills/review-spec/SKILL.md` to write output to `REVIEW-SPEC.md` in spec directory instead of inline review output
- [X] T011 [US3] Update `spex/skills/review-plan/SKILL.md` to write output to `REVIEW-PLAN.md` instead of `REVIEWERS.md`
- [X] T012 [US3] Update `spex/skills/review-code/SKILL.md` to write output to `REVIEW-CODE.md` instead of appending to `REVIEWERS.md`
- [X] T013 [US3] Update `spex/scripts/spex-ship-state.sh` `verify_stage_artifacts()` to check for split review files (REVIEW-PLAN.md at stage 5, REVIEW-CODE.md at stage 7) with REVIEWERS.md fallback (FR-015a)
- [X] T014 [US3] Update `spex/skills/ship/SKILL.md` stage references to use split review file names

**Checkpoint**: Review skills produce individual files. Ship pipeline validates both old and new formats.

---

## Phase 4: User Story 1 - Flow Mode Status Line (Priority: P1) :dart: MVP

**Goal**: Status line shows milestone completion and next step in flow mode via artifact detection.

**Independent Test**: Run `/speckit-specify`, verify status line shows spec complete with plan as next step.

- [X] T015 [US1] Add flow mode branch to `spex/scripts/spex-ship-statusline.sh`: read `mode` field from state file, branch to flow rendering when `mode=flow`
- [X] T016 [US1] Implement milestone detection in `spex/scripts/spex-ship-statusline.sh`: check existence of `spec.md`, `plan.md`, `tasks.md` in spec_dir from state file, read `implemented` field
- [X] T017 [US1] Implement next-step computation in `spex/scripts/spex-ship-statusline.sh` per FR-004 priority: first incomplete milestone, then first incomplete review, then stamp
- [X] T018 [US1] Implement flow mode checkmark line rendering in `spex/scripts/spex-ship-statusline.sh` with ANSI colors matching ship scheme (green ✓ for complete, dim ○ for pending, highlighted next step) per FR-006a

**Checkpoint**: Flow mode status line renders correctly for various artifact combinations.

---

## Phase 5: User Story 2 - Review Checklist Tracking (Priority: P1)

**Goal**: Status line shows which reviews have been completed as a checklist, independent of milestone order.

**Independent Test**: Run `/spex:review-spec` then `/spex:review-code` (skipping plan review). Verify checklist shows spec and code checked, plan unchecked.

- [X] T019 [US2] Add review artifact detection to `spex/scripts/spex-ship-statusline.sh`: check existence of `REVIEW-SPEC.md`, `REVIEW-PLAN.md`, `REVIEW-CODE.md` in spec_dir
- [X] T020 [US2] Add review checklist rendering to flow mode display: abbreviated format `✓S ○P ○C` with same color scheme

**Checkpoint**: Review checklist displays correctly. Reviews can be completed in any order.

---

## Phase 6: User Story 4 - Active Traits Display (Priority: P2)

**Goal**: Status line shows enabled traits from `spex-traits.json` in both ship and flow modes.

**Independent Test**: Enable superpowers and worktrees traits, start a flow, verify both trait names appear in status line.

- [X] T021 [US4] Add trait reading to `spex/scripts/spex-ship-statusline.sh`: read `.specify/spex-traits.json` with `jq`, extract trait names where value is `true`
- [X] T022 [US4] Append trait display to both ship and flow mode output in `spex/scripts/spex-ship-statusline.sh`: format as `[trait1, trait2]` in muted color, omit if no traits or file missing

**Checkpoint**: Traits display in both modes. Omitted when none enabled. Updates when config changes.

---

## Phase 7: User Stories 5 & 6 - Flow Lifecycle Integration (Priority: P2)

**Goal**: Wire flow state creation into specify, ship mode distinction, and implementation tracking.

**Independent Test**: Run `/speckit-specify`, verify `.spex-state` created with `mode=flow`. Run `/spex:ship`, verify mode switches to `ship`.

- [X] T023 [US5] Update `speckit-specify` skill overlay or guard section to create `.specify/.spex-state` with `"mode": "flow"`, `started_at`, `feature_branch`, `spec_dir` fields when no state file exists (FR-010, FR-016)
- [X] T024 [US6] Update `spex/skills/ship/SKILL.md` state creation to include `"mode": "ship"` field (FR-011)
- [X] T025 [US6] Update `speckit-implement` skill overlay or guard section to set `"implemented": true` in state file on successful completion (FR-018)

**Checkpoint**: Flow state lifecycle works end-to-end. Ship mode overwrites flow state.

---

## Phase 8: User Story 7 - Completion Celebration (Priority: P3)

**Goal**: Display ASCII art celebration with stats on successful stamp, then remove state file.

**Independent Test**: Complete full flow (specify through stamp), verify celebration banner appears with correct stats.

- [X] T026 [US7] Add celebration display to `spex/skills/verification-before-completion/SKILL.md`: after all checks pass and state file exists, show ASCII art banner
- [X] T027 [US7] Add stats computation to celebration in `spex/skills/verification-before-completion/SKILL.md`: feature name from `feature_branch`, duration from `started_at`, review count from REVIEW-*.md files, commit count from `git rev-list --count main..HEAD`
- [X] T028 [US7] Add randomized sign-off message pool (5+ messages) and state file removal after celebration display in `spex/skills/verification-before-completion/SKILL.md`

**Checkpoint**: Celebration displays once on successful stamp. State file removed. No celebration if no state file.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Validation and cleanup across all changes

- [X] T029 [P] Run `make release` to validate plugin integrity (all commands, skills, hooks, overlays present)
- [X] T030 Verify backward compatibility: existing ship pipelines on other branches continue to work with renamed state file

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Rename)**: No dependencies, start immediately
- **Phase 2 (Schema)**: Depends on Phase 1
- **Phase 3 (Review Split)**: Depends on Phase 1 (renamed paths)
- **Phase 4 (Flow Status Line)**: Depends on Phase 2 (mode field) and Phase 3 (review artifacts)
- **Phase 5 (Review Checklist)**: Depends on Phase 3 (split review files) and Phase 4 (flow rendering)
- **Phase 6 (Traits)**: Depends on Phase 4 (status line flow mode exists)
- **Phase 7 (Lifecycle)**: Depends on Phase 2 (state schema)
- **Phase 8 (Celebration)**: Depends on Phase 7 (state file lifecycle)
- **Phase 9 (Polish)**: Depends on all previous phases

### Parallel Opportunities

- Phase 1: All T001-T006 can run in parallel (different files)
- Phase 3 and Phase 7 can start concurrently after Phase 2
- Phase 5 and Phase 6 can start concurrently after Phase 4
- T029 and T030 can run in parallel

---

## Implementation Strategy

### MVP First (User Stories 1 + 3)

1. Complete Phase 1: State file rename
2. Complete Phase 2: Schema extension
3. Complete Phase 3: Review artifact split (prerequisite for flow mode)
4. Complete Phase 4: Flow mode status line
5. **STOP and VALIDATE**: Test flow mode independently

### Incremental Delivery

1. Phases 1-4 -> MVP: Flow status line with milestone tracking
2. Phase 5 -> Add review checklist to status line
3. Phase 6 -> Add trait display
4. Phase 7 -> Wire lifecycle (specify creates state, implement sets flag)
5. Phase 8 -> Add celebration
6. Phase 9 -> Validate everything

---

## Notes

- Total tasks: 30
- Per user story: US1=4, US2=2, US3=5, US4=2, US5=1, US6=2, US7=3
- Parallel opportunities: Phases 1, 3+7, 5+6
- MVP scope: Phases 1-4 (US1 + US3)
- All tasks modify existing files, no new files created (except review artifacts per feature)
