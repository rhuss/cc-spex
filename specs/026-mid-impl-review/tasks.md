# Tasks: Mid-Implementation Review Checkpoints with Deep Review Statistics

**Input**: Design documents from `specs/026-mid-impl-review/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: Read existing files to understand current structure.

- [ ] T001 Read existing files: `spex/extensions/spex/commands/speckit.spex.ship.md` (Stage 6 implement subagent prompt), `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` (deep review command), `spex/scripts/spex-ship-state.sh` (state management)

---

## Phase 2: Checkpoint State Management (US1 infrastructure)

**Goal**: Add checkpoint result recording to the state script.
**Independent Test**: Run `spex-ship-state.sh checkpoint-record --checkpoint 1 --findings 3 --fixed 2` and verify state file contains the correct fields.

- [ ] T002 [US1] Add `checkpoint-record` command to `spex/scripts/spex-ship-state.sh`: accepts `--checkpoint <1|2> --findings <N> --fixed <N>`, writes `checkpoint_N_findings` and `checkpoint_N_fixed` to the state file. If the state file doesn't exist, create a minimal one. Update the script's usage comment to include the new command

---

## Phase 3: Mid-Implementation Checkpoints (US1)

**Goal**: Add checkpoint instructions to the ship pipeline's implement subagent prompt so correctness reviews run at 1/3 and 2/3 of task completion.
**Independent Test**: Run `/speckit-spex-ship` on a project with 9+ tasks and `spex-deep-review` enabled. Verify checkpoints run after tasks 3 and 6.

- [ ] T003 [US1] In `spex/extensions/spex/commands/speckit.spex.ship.md` Stage 6, before spawning the implement subagent, add logic to: (a) count total tasks from tasks.md (`grep -c '^\- \[ \]' tasks.md`), (b) check if `spex-deep-review` extension is enabled via `.specify/extensions/.registry`, (c) read `implement.review_checkpoints` from `.specify/extensions/spex/spex-config.yml` via `yq` (default true), (d) if all conditions met and total_tasks >= 3, calculate `cp1 = round(total * 0.33)` and `cp2 = round(total * 0.67)`
- [ ] T004 [US1] Add checkpoint instruction block to the implement subagent prompt (both standard and teams variants) in `speckit.spex.ship.md`. The block tells the implementing agent: "After completing task N (checkpoint 1/3), pause implementation. Spawn a fresh-context Agent with this prompt: 'Review the implementation so far against the spec at <SPEC_PATH>. Focus only on correctness: does the code match the spec requirements for the completed tasks? Report findings with file paths and line numbers. Do not review architecture, security, or test quality.' After the review agent returns, fix any findings (max 2 attempts per finding). Record results via `spex-ship-state.sh checkpoint-record --checkpoint 1 --findings <N> --fixed <N>`. Then continue to the next task. Repeat at task M (checkpoint 2/3)."
- [ ] T005 [US1] Add the minimum task threshold guard: when total_tasks < 3, skip checkpoint instructions entirely. Add a comment in the prompt noting "Checkpoints skipped: fewer than 3 tasks"

---

## Phase 4: Deep Review Statistics (US2)

**Goal**: Add per-agent statistics reporting to the deep review command, displayed after every run.
**Independent Test**: Run `/speckit-spex-deep-review-run` and verify the agent leaderboard table appears after the review.

- [ ] T006 [US2] In `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`, after the fix loop completes and the Deep Review Report is output, add a statistics section. The deep review already collects per-agent findings during its dispatch-and-merge process. Add instructions to format these as a markdown table with columns: Agent, Found, Fixed, Remaining
- [ ] T007 [US2] Add MVP designation logic: after the statistics table, identify the agent with the highest "Found" count and output "MVP: {agent name} ({count} findings)". If all agents found 0, output "Clean review: no findings across {N} agents"
- [ ] T008 [US2] Add a total row to the statistics table summing Found, Fixed, and Remaining across all agents

---

## Phase 5: Layer Comparison (US3)

**Goal**: When checkpoint data exists in the state file, add a layer comparison to the deep review statistics.
**Independent Test**: Run a ship pipeline with checkpoints, then verify the layer comparison table appears alongside the agent leaderboard.

- [ ] T009 [US3] In `speckit.spex-deep-review.run.md`, after the agent leaderboard, check the state file for `checkpoint_1_findings` and `checkpoint_2_findings`. If present, output a layer comparison table with columns: Layer, Findings, Fixed, Unique
- [ ] T010 [US3] Implement the "unique" calculation: for each layer, compare its finding locations (file path + line range) against all other layers' findings. A finding is "unique" if no other layer reported a finding at the same file path with overlapping lines. If line numbers are unavailable, fall back to finding description substring match
- [ ] T011 [US3] When no checkpoint data exists in the state file (regular flow or checkpoints disabled), skip the layer comparison entirely. Only show the agent leaderboard

---

## Phase 6: Documentation

**Purpose**: Update docs to cover checkpoints and statistics.

- [ ] T012 [P] Update `README.md`: add mid-implementation review checkpoints description to the ship pipeline section, mention agent leaderboard in the deep review extension description
- [ ] T013 [P] Update `spex/docs/help.md`: add `implement.review_checkpoints` config key alongside existing `implement.test_between_tasks`

---

## Dependencies

```
T001 → T002 (read files first)
T002 → T003 (state recording before checkpoint instructions)
T003 → T004 → T005 (checkpoint logic built sequentially)
T001 → T006 (read files first)
T006 → T007 → T008 (statistics built sequentially)
T005, T008 → T009 (checkpoints + statistics before layer comparison)
T009 → T010 → T011 (layer comparison built sequentially)
T011 → T012, T013 (all features before docs)
```

## Parallel Opportunities

- **T002 and T006**: Checkpoint state management and deep review statistics modify different files, can be parallel
- **T012, T013**: Documentation tasks are independent

## Implementation Strategy

**MVP**: Phase 4 (deep review statistics with agent leaderboard) delivers immediate value for every deep review run, not just ship mode.

**Incremental delivery**:
1. Phase 2 (US1 infra): Checkpoint state recording (1 task, foundation)
2. Phase 4 (US2): Deep review statistics (3 tasks, immediate value for all modes)
3. Phase 3 (US1): Mid-implementation checkpoints (3 tasks, ship mode only)
4. Phase 5 (US3): Layer comparison (3 tasks, depends on both checkpoints and statistics)
5. Phase 6: Documentation (2 tasks, after all features)
