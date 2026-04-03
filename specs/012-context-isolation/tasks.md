# Tasks: Context Isolation for Workflow Transitions

**Input**: Design documents from `/specs/012-context-isolation/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: User Story 1 - Context Clear Warnings (Priority: P1) + User Story 2 - Branch Resolution (Priority: P1) 

**Goal**: Add context clear warnings at two transition points AND enable branch-based spec resolution so review skills work seamlessly after `/clear`. These two P1 stories are tightly coupled (warnings recommend `/clear`, branch resolution makes `/clear` seamless) and should ship together.

**Independent Test**: Run `/spex:review-plan` on a feature branch, verify the clear warning appears. Run `/clear`, then `/spex:review-code`, verify spec resolves automatically from branch.

### Implementation

- [ ] T001 [P] [US1] Add context clear recommendation after plan review in spex/overlays/superpowers/commands/speckit.plan.append.md
- [ ] T002 [P] [US1] Add context clear recommendation after implementation in spex/overlays/superpowers/commands/speckit.implement.append.md
- [ ] T003 [P] [US2] Update spec selection to use branch-based resolution in spex/skills/review-code/SKILL.md
- [ ] T004 [P] [US2] Update spec selection to use branch-based resolution in spex/skills/review-spec/SKILL.md
- [ ] T005 [P] [US2] Update spec selection to use branch-based resolution in spex/skills/deep-review/SKILL.md
- [ ] T006 [P] [US2] Update spec selection to use branch-based resolution in spex/skills/verification-before-completion/SKILL.md
- [ ] T007 [US1] [US2] Manual validation: run review-plan on feature branch, verify warning, run /clear, run review-code, verify auto-resolution

**Checkpoint**: Context warnings display at both transition points. Review skills resolve specs from branch after `/clear`.

---

## Phase 2: User Story 3 - Forked Subagent Stages in Ship (Priority: P2)

**Goal**: Run implementation and review-code stages as forked subagents in the ship pipeline for context isolation.

**Independent Test**: Run `/spex:ship` with a brainstorm file. Verify implementation and review stages execute in isolated contexts. Verify the orchestrator does not trigger auto-compaction.

### Implementation

- [ ] T008 [US3] Restructure ship skill stage 6 (implement) to use Agent tool with isolation in spex/skills/ship/SKILL.md
- [ ] T009 [US3] Restructure ship skill stage 7 (review-code) to use Agent tool with isolation in spex/skills/ship/SKILL.md
- [ ] T010 [US3] Update ship skill handoff mechanism: pass spec/plan/tasks file paths as Agent prompt context in spex/skills/ship/SKILL.md
- [ ] T011 [US3] Manual validation: run /spex:ship end-to-end, verify isolated execution and summarized results

**Checkpoint**: Ship pipeline runs stages 6-7 in isolated contexts. Orchestrator stays lightweight.

---

## Phase 3: Polish & Cross-Cutting

- [ ] T012 [P] Update integration test to verify no regressions in tests/test_marketplace_install.sh
- [ ] T013 [P] Update README.md with context isolation documentation
- [ ] T014 [P] Update help text in spex/docs/help.md (if needed)
- [ ] T015 Run `make release` to validate plugin

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (US1+US2)**: No dependencies, can start immediately. All tasks T001-T006 are parallelizable (different files).
- **Phase 2 (US3)**: Independent of Phase 1. Can run in parallel if desired, but recommended after Phase 1 since it's lower priority.
- **Phase 3 (Polish)**: After Phase 1 and Phase 2 complete.

### User Story Dependencies

- **US1 (Warnings)** + **US2 (Branch Resolution)**: Co-dependent. Ship together.
- **US3 (Ship Forking)**: Fully independent. Can ship separately.

### Parallel Opportunities

```
# Phase 1: All 6 implementation tasks run in parallel (different files):
T001: speckit.plan.append.md
T002: speckit.implement.append.md  
T003: review-code/SKILL.md
T004: review-spec/SKILL.md
T005: deep-review/SKILL.md
T006: verification-before-completion/SKILL.md

# Phase 3: All polish tasks run in parallel:
T012: test_marketplace_install.sh
T013: README.md
T014: help.md
```

---

## Implementation Strategy

### MVP (Phase 1 only)

1. Implement T001-T006 in parallel (6 files, no conflicts)
2. Manual validation (T007)
3. Ship as a patch release

### Full Feature

1. Complete Phase 1 (US1+US2)
2. Complete Phase 2 (US3)
3. Polish (Phase 3)
4. Release

---

## Notes

- All Phase 1 tasks modify different files and can run in parallel
- The branch resolution pattern (T003-T006) is identical across all 4 skills: replace the "Spec Selection" section with the same check-prerequisites.sh logic
- Phase 2 (ship forking) is more experimental and should be prototyped before committing to the approach
- No test code needed (Markdown/Bash plugin, validated by manual testing + `make test-install`)
