# Tasks: Autonomous Full-Cycle Workflow (spex:yolo)

**Input**: Design documents from `/specs/010-yolo-autonomous-workflow/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No automated tests. Verification is done via `make reinstall` + manual Claude Code session testing.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Plugin root**: `spex/` at repository root
- **Skills**: `spex/skills/<name>/SKILL.md`
- **Scripts**: `spex/scripts/`

---

## Phase 1: Setup

**Purpose**: Create skill file structure and frontmatter

- [x] T001 Create skill directory and SKILL.md with frontmatter (name, description, argument-hint) at `spex/skills/yolo/SKILL.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core sections of the SKILL.md that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Write Prerequisites section in `spex/skills/yolo/SKILL.md`: validate superpowers and deep-review traits are enabled by reading `.specify/spex-traits.json` with `jq`; fail with clear enable instructions if missing
- [x] T003 Write Argument Parsing section in `spex/skills/yolo/SKILL.md`: parse brainstorm file path (positional), `--autonomy` flag with validation (cautious/balanced/autopilot, default balanced), `--create-pr` flag, `--resume` flag, `--start-from <stage>` flag with stage name validation, and external tool flags (`--no-external`, `--[no-]coderabbit`, `--[no-]copilot`) following the review-code skill's flag resolution pattern with config defaults from `.specify/spex-traits.json`
- [x] T004 Write Brainstorm File Resolution section in `spex/skills/yolo/SKILL.md`: if path provided, validate it exists; if omitted, auto-detect highest-numbered file in `brainstorm/` directory; fail with error listing available brainstorm files if none found
- [x] T005 Write State File Management section in `spex/skills/yolo/SKILL.md`: define helper instructions for writing `.specify/.spex-yolo-phase` JSON (stage, stage_index, total_stages, autonomy, started_at, retries, status, brainstorm_file, feature_branch) at each stage transition; include cleanup on completion
- [x] T006 Write Dirty Worktree Check section in `spex/skills/yolo/SKILL.md`: check `git status --porcelain` before starting; if dirty, fail with message to commit or stash changes
- [x] T007 Write External Tool Auth Validation section in `spex/skills/yolo/SKILL.md`: if `--coderabbit` is explicitly set, validate CodeRabbit authentication at startup before any pipeline work; fail with clear error if auth check fails

**Checkpoint**: Foundation ready - skill has all validation, parsing, and state management infrastructure

---

## Phase 3: User Story 1 - Run Full Pipeline After Brainstorm (Priority: P1) MVP

**Goal**: Execute the full 9-stage pipeline autonomously from a brainstorm document

**Independent Test**: Create a brainstorm document, run `/spex:yolo brainstorm/05-test-feature.md`, verify all 9 stages execute in sequence producing spec, plan, tasks, implementation, review, and verification

### Implementation for User Story 1

- [x] T008 [US1] Write Pipeline Stages section in `spex/skills/yolo/SKILL.md`: define the ordered stage list (specify, clarify, review-spec, plan, review-plan, tasks, implement, deep-review, verify) with stage indices 0-8 and the invocation method for each (slash commands for speckit stages, `{Skill:}` references for spex skills)
- [x] T009 [US1] Write Stage 0 (specify) orchestration in `spex/skills/yolo/SKILL.md`: read brainstorm document content, invoke `/speckit.specify` passing brainstorm content as feature description, update state file after completion
- [x] T010 [US1] Write Stage 1 (clarify) orchestration in `spex/skills/yolo/SKILL.md`: invoke `/speckit.clarify` on the generated spec, update state file
- [x] T011 [US1] Write Stage 2 (review-spec) orchestration in `spex/skills/yolo/SKILL.md`: invoke `{Skill: spex:review-spec}`, capture review findings, update state file
- [x] T012 [US1] Write Stage 3 (plan) orchestration in `spex/skills/yolo/SKILL.md`: invoke `/speckit.plan`, update state file after plan artifacts generated
- [x] T013 [US1] Write Stage 4 (review-plan) orchestration in `spex/skills/yolo/SKILL.md`: invoke `{Skill: spex:review-plan}`, capture findings, update state file
- [x] T014 [US1] Write Stage 5 (tasks) orchestration in `spex/skills/yolo/SKILL.md`: invoke `/speckit.tasks`, update state file
- [x] T015 [US1] Write Stage 6 (implement) orchestration in `spex/skills/yolo/SKILL.md`: invoke `/speckit.implement`, update state file after implementation completes
- [x] T016 [US1] Write Stage 7 (deep-review) orchestration in `spex/skills/yolo/SKILL.md`: invoke `{Skill: spex:deep-review}` with resolved external tool flags passed through, update state file
- [x] T017 [US1] Write Stage 8 (verify) orchestration in `spex/skills/yolo/SKILL.md`: invoke `{Skill: spex:verification-before-completion}`, update state file, mark pipeline as completed
- [x] T018 [US1] Write Pipeline Completion section in `spex/skills/yolo/SKILL.md`: report completion summary (stages completed, time elapsed, branch name), clean up state file, inform user of next steps

**Checkpoint**: Full pipeline executes end-to-end in default balanced mode with no review findings

---

## Phase 4: User Story 2 - Control Autonomy Level (Priority: P2)

**Goal**: Implement three autonomy levels that control when the pipeline pauses vs auto-fixes

**Independent Test**: Run `/spex:yolo --autonomy cautious` and verify it stops at each review finding. Run `/spex:yolo --autonomy autopilot` and verify it only stops on blockers.

### Implementation for User Story 2

- [x] T019 [US2] Write Autonomy Decision Logic section in `spex/skills/yolo/SKILL.md`: after each review stage (review-spec, review-plan, deep-review), classify findings as unambiguous (formatting, style, minor), ambiguous (architecture, design, requirements), or blocker (compilation, missing deps, test failures); apply autonomy rules: cautious pauses on all, balanced auto-fixes unambiguous and pauses on ambiguous, autopilot fixes all and pauses only on blockers
- [x] T020 [US2] Write Auto-Fix and Re-run section in `spex/skills/yolo/SKILL.md`: when auto-fixing, apply fixes then re-run the same review stage; track retry count in state file; max 2 retry cycles per stage; after 2 retries with remaining findings, pause regardless of autonomy level
- [x] T021 [US2] Write Pause and Resume section in `spex/skills/yolo/SKILL.md`: when pausing, present all findings to user with context; update state file status to "paused"; after user responds with guidance, update state to "running" and resume from current stage

**Checkpoint**: All three autonomy modes work correctly with appropriate pause/continue behavior

---

## Phase 5: User Story 3 - Control External Review Tools (Priority: P2)

**Goal**: Pass review tool flags through to the deep-review stage

**Independent Test**: Run `/spex:yolo --no-coderabbit` and verify CodeRabbit is skipped during deep-review. Run `/spex:yolo --coderabbit` with invalid auth and verify startup failure.

### Implementation for User Story 3

- [x] T022 [US3] Write External Tool Flag Pass-through in `spex/skills/yolo/SKILL.md`: in Stage 7 (deep-review), pass resolved external tool settings (coderabbit: true/false, copilot: true/false) to the deep-review skill invocation; ensure flags from CLI override config defaults following the same resolution order as review-code

**Checkpoint**: External tool flags correctly control deep-review behavior

---

## Phase 6: User Story 4 - Worktree Isolation (Priority: P3)

**Goal**: Integrate with the worktrees trait so specify creates the worktree and subsequent stages run inside it

**Independent Test**: Enable worktrees trait, run `/spex:yolo`. Verify specify creates the worktree and subsequent stages run inside it.

### Implementation for User Story 4

- [x] T023 [US4] Write Worktree Integration note in `spex/skills/yolo/SKILL.md`: document that worktree creation is handled by the worktrees trait's overlay on `/speckit.specify`; yolo does not need to manage worktrees directly; after specify completes, the session is already in the worktree context and subsequent stages inherit it automatically

**Checkpoint**: Pipeline runs correctly with worktrees trait enabled, all stages execute in the worktree

---

## Phase 7: User Story 5 - Optional PR Creation (Priority: P3)

**Goal**: Create a pull request after successful pipeline completion when `--create-pr` is specified

**Independent Test**: Run `/spex:yolo --create-pr` and verify a PR is created after verify succeeds.

### Implementation for User Story 5

- [x] T024 [US5] Write PR Creation section in `spex/skills/yolo/SKILL.md`: after verify succeeds and `--create-pr` is set, push feature branch to remote (upstream if configured, otherwise origin) and create PR using `gh pr create` with title from feature name and body summarizing the feature with link to spec; if `--create-pr` is not set, inform user of successful completion without creating PR

**Checkpoint**: PR creation works when flag is set; no PR created when flag is omitted

---

## Phase 8: User Story 6 - Resume and Start-From (Priority: P2)

**Goal**: Resume interrupted pipelines and start from a specific stage

**Independent Test**: Interrupt a pipeline with Ctrl+C, then run `/spex:yolo --resume` and verify it picks up from the next stage. Run `/spex:yolo --start-from plan` and verify it skips specify/clarify/review-spec.

### Implementation for User Story 6

- [x] T025 [US6] Write Resume Logic section in `spex/skills/yolo/SKILL.md`: when `--resume` is set, read `.specify/.spex-yolo-phase` JSON, validate state file exists and contains a valid pipeline state (status: paused or running), extract the last completed stage, and begin execution from the next stage in the pipeline sequence; fail with clear error if no state file exists
- [x] T026 [US6] Write Start-From Logic section in `spex/skills/yolo/SKILL.md`: when `--start-from <stage>` is set, validate stage name against the 9 defined stages, skip all prior stages (assuming their artifacts already exist), and begin pipeline execution from the named stage; warn if expected artifacts (spec.md, plan.md, tasks.md) are missing for stages that depend on them

**Checkpoint**: `--resume` correctly picks up interrupted pipelines; `--start-from` skips stages as expected

---

## Phase 9: Polish and Cross-Cutting Concerns

**Purpose**: Status line integration, documentation, and validation

- [x] T027 [P] Create status line script at `spex/scripts/spex-yolo-statusline.sh` that reads `.specify/.spex-yolo-phase` JSON and outputs a compact status string (e.g., "yolo: implement [6/9] balanced") for Claude Code status line integration
- [x] T028 Run `make reinstall` and validate the skill appears in Claude Code's skill list; test with a sample brainstorm document in balanced mode
- [x] T029 Verify all edge cases from spec: missing brainstorm file error, missing traits error, dirty worktree error, max retry behavior, Ctrl+C state file persistence, `--resume` with no state file, `--start-from` with invalid stage name

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001)
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion (T002-T007)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (US1 provides the pipeline to add autonomy to)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (US1 provides Stage 7 to pass flags to)
- **User Story 4 (Phase 6)**: Depends on Phase 3 (US1 provides the pipeline)
- **User Story 5 (Phase 7)**: Depends on Phase 3 (US1 provides pipeline completion flow)
- **User Story 6 (Phase 8)**: Depends on Phase 2 (T005 state file management) and Phase 3 (US1 pipeline)
- **Polish (Phase 9)**: Depends on all user stories

### User Story Dependencies

- **US1 (P1)**: Foundation only. MVP.
- **US2 (P2)**: Depends on US1 (adds autonomy logic to existing pipeline stages)
- **US3 (P2)**: Can start after US1 (modifies Stage 7 only). Can run parallel with US2.
- **US4 (P3)**: Can start after US1 (documentation task, minimal code). Can run parallel with US2/US3.
- **US5 (P3)**: Can start after US1 (adds post-completion step). Can run parallel with US2/US3/US4.
- **US6 (P2)**: Depends on US1 (needs pipeline and state file). Can run parallel with US2/US3.

### Within Each User Story

- Tasks within US1 are sequential (each stage depends on previous stage definition)
- US2 tasks are sequential (decision logic, then auto-fix, then pause/resume)
- US3, US4, US5 are single-task stories

### Parallel Opportunities

- T002-T007 (foundational) can be written in parallel since they are independent sections of the same file
- US3, US4, US5 can be implemented in parallel after US1 is complete
- T027 (status line script) can run in parallel with any user story work

---

## Parallel Example: Foundational Phase

```bash
# Launch all foundational tasks together (different sections of SKILL.md):
Task: "Write Prerequisites section" (T002)
Task: "Write Argument Parsing section" (T003)
Task: "Write Brainstorm File Resolution section" (T004)
Task: "Write State File Management section" (T005)
Task: "Write Dirty Worktree Check section" (T006)
Task: "Write External Tool Auth section" (T007)
```

## Parallel Example: After US1 Complete

```bash
# Launch independent user stories together:
Task: "Write External Tool Flag Pass-through" (T022, US3)
Task: "Write Worktree Integration note" (T023, US4)
Task: "Write PR Creation section" (T024, US5)
Task: "Write Resume Logic section" (T025, US6)
Task: "Write Start-From Logic section" (T026, US6)
Task: "Create status line script" (T027, polish)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002-T007)
3. Complete Phase 3: User Story 1 (T008-T018)
4. **STOP and VALIDATE**: Run `/spex:yolo brainstorm/05-test.md` end-to-end
5. The pipeline works in balanced mode with full stage execution

### Incremental Delivery

1. Setup + Foundational -> Skill file with validation and parsing ready
2. Add US1 -> Full pipeline works (MVP!)
3. Add US2 -> Autonomy levels control pause/fix behavior
4. Add US3 -> External tool flags pass through to deep-review
5. Add US4 -> Worktree integration documented
6. Add US5 -> PR creation optional
7. Polish -> Status line script, validation

---

## Notes

- Total: 29 tasks across 9 phases
- All tasks write to a single file: `spex/skills/yolo/SKILL.md`
- The skill is pure Markdown (instructions for Claude), not executable code
- State file management is via `jq` commands embedded in the skill instructions
- No new hooks, commands, or overlays needed for this feature
- Commit after each phase or logical group of tasks
