# Tasks: Guided Smoke Test and Ship Pipeline Safety

**Input**: Design documents from `specs/025-guided-smoke-test/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: Read existing files and understand the structures to modify.

- [ ] T001 Read existing files to understand current structure: `spex/extensions/spex/commands/speckit.spex.ship.md` (Stage 8 finish subagent), `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md` (verify command), `spex/scripts/spex-ship-state.sh` (state management), `spex/scripts/spex-ship-statusline.sh` (statusline rendering), `spex/extensions/spex/extension.yml` (command registration)

---

## Phase 2: Smoke Test Command (US1, US4)

**Goal**: Create the interactive smoke test command that parses acceptance scenarios from spec.md, starts the app, walks through each scenario step by step, and records results.
**Independent Test**: Run `/speckit-spex-smoke-test` on a project with a spec containing Given/When/Then scenarios and verify interactive walkthrough.

- [ ] T002 [US1] Create `spex/extensions/spex/commands/speckit.spex.smoke-test.md` with the command skeleton: description frontmatter, spec resolution via `check-prerequisites.sh`, and argument parsing
- [ ] T003 [US1] Add scenario parsing logic to the smoke test command: scan the "User Scenarios & Testing" section of spec.md for numbered items with bold **Given**, **When**, **Then** keywords. Exclude the Edge Cases section. Parse each into a structured triple (given, when, then) with the parent user story title
- [ ] T004 [US1] Add project type detection and app startup logic: auto-detect start command (Makefile run/serve target, package.json start, go run, python app.py, cargo run). Check for `/run` skill availability at runtime and delegate if present. Start app as background process, wait for ready signal (port open or stdout marker), handle "cannot detect" case by asking user to start manually
- [ ] T005 [US1] Add the interactive scenario walkthrough loop: for each parsed scenario, (a) display the scenario (Given/When/Then) with context, (b) explain what command will be executed, (c) execute the action step (curl, CLI command, etc.), (d) display the result, (e) ask user to confirm (pass/fail/skip) via AskUserQuestion, (f) on failure offer interactive debugging (inspect logs, examine code, suggest fixes, retry)
- [ ] T006 [US1] Add app cleanup logic: when all scenarios are complete or user exits early, attempt SIGTERM on the background app process. If still running after 5 seconds, SIGKILL. Report cleanup status
- [ ] T007 [US4] Add state recording to `spex/scripts/spex-ship-state.sh`: new `smoke-test-record` command that accepts `completed` (boolean), `scenarios` (count), `total` (count), `skipped` (count) and writes `smoke_test_completed`, `smoke_test_at`, `smoke_test_scenarios`, `smoke_test_total`, `smoke_test_skipped` to the state file
- [ ] T008 [US4] Integrate state recording into the smoke test command: after all scenarios are processed (or user exits early), invoke `spex-ship-state.sh smoke-test-record` with the results
- [ ] T009 [US1] Handle edge cases in the smoke test command: (a) spec with no acceptance scenarios: report and exit, (b) library projects (no runnable app): suggest function-call or test-based verification, ask user how to exercise, (c) app crash during scenario: detect, report, offer restart

---

## Phase 3: Ship Pipeline Changes (US3)

**Goal**: Replace finish (stage 8) with smoke-test in the ship pipeline. Pipeline always stops, user runs finish manually.
**Independent Test**: Run `/speckit-spex-ship` and verify it stops after smoke-test without auto-merging.

- [ ] T010 [US3] Modify Stage 8 in `spex/extensions/spex/commands/speckit.spex.ship.md`: replace the finish subagent spawn with a smoke-test invocation. The smoke test always runs interactively (ignores `ask` level). After smoke-test completes, output: "Pipeline complete through review and smoke test. Run `/speckit-spex-finish` to merge or create a PR."
- [ ] T011 [US3] Handle the no-scenarios case in ship pipeline: when the spec has no acceptance scenarios, skip the smoke test but still stop the pipeline with: "Pipeline complete through review. No acceptance scenarios for smoke test. Run `/speckit-spex-finish` to merge or create a PR."
- [ ] T012 [US3] Update the `--start-from` valid stage names in the ship command: replace `finish` with `smoke-test` in the validation list and error message
- [ ] T013 [US3] Update `spex/scripts/spex-ship-state.sh`: ensure the stage list uses `smoke-test` at index 8 instead of `finish`. The `advance` command at index 8 should output `PIPELINE_COMPLETE` with instructions to run finish manually

---

## Phase 4: Verify Reminder and Statusline (US2)

**Goal**: Verify/stamp shows a reminder when acceptance scenarios exist but no smoke test was recorded. Statusline shows smoke test indicator.
**Independent Test**: Run verify on a feature with acceptance scenarios but no smoke test and verify the reminder appears.

- [ ] T014 [P] [US2] Add smoke test reminder to `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: before the "Run Tests" step, check if the spec has acceptance scenarios (grep for bold Given/When/Then in the User Scenarios section) and if the state file lacks `smoke_test_completed: true`. If both conditions are true, display: "Acceptance scenarios exist but no smoke test was recorded. Consider running `/speckit-spex-smoke-test` first." The reminder is informational and does not block verification
- [ ] T015 [P] [US2] Add smoke test indicator to `spex/scripts/spex-ship-statusline.sh`: when the state file contains `smoke_test_completed`, show "ST ✓" (if true) or "ST N/M" (if false, showing completed vs total). Add this to both flow and ship mode rendering

---

## Phase 5: Registration and Documentation

**Purpose**: Register the command and update all documentation.

- [ ] T016 [P] Register the smoke-test command in `spex/extensions/spex/extension.yml`: add entry for `speckit.spex.smoke-test` with description "Interactive spec-driven acceptance scenario walkthrough"
- [ ] T017 [P] Update `README.md`: add `/speckit-spex-smoke-test` to the Commands Reference table, update the ship pipeline stages table to show smoke-test at stage 8 replacing finish, add note about ship pipeline always stopping before merge
- [ ] T018 [P] Update `spex/docs/help.md`: add smoke-test to the quick reference commands section

---

## Dependencies

```
T001 → T002 (read existing files first)
T002 → T003 → T004 → T005 → T006 (smoke test command built sequentially)
T005 → T007 → T008 (state recording after walkthrough loop)
T005 → T009 (edge cases after main loop)
T008, T009 → T010 (command complete before ship pipeline integration)
T010 → T011, T012, T013 (ship pipeline changes)
T008 → T014 (state recording before verify reminder)
T008 → T015 (state recording before statusline)
T013 → T016, T017, T018 (all features before docs)
```

## Parallel Opportunities

- **T014, T015**: Verify reminder and statusline modify different files, can be parallel
- **T016, T017, T018**: Registration and docs are all independent files

## Implementation Strategy

**MVP**: Phase 2 (smoke test command with state recording) delivers the core interactive experience.

**Incremental delivery**:
1. Phase 2 (US1, US4): Smoke test command with state recording
2. Phase 3 (US3): Ship pipeline restructuring
3. Phase 4 (US2): Verify reminder and statusline
4. Phase 5: Documentation and registration
