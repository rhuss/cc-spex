# Tasks: Smoke Test V2 - Two-Phase Fresh Context

**Input**: Design documents from `specs/028-smoke-test-v2/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: No project initialization needed. The smoke test skill already exists. This is a rewrite of existing file.

(No setup tasks.)

## Phase 2: User Story 1 - Fresh Context Execution via Subagent (P1)

**Story Goal**: The smoke test spawns a subagent with no implementation memory to execute scenarios and collect evidence. The subagent returns structured text with evidence per scenario.

**Independent Test**: Invoke `/speckit-spex-smoke-test` on a project with acceptance scenarios and verify the Agent tool is called for execution.

- [X] T001 [US1] Read the current smoke test skill at `spex/extensions/spex/commands/speckit.spex.smoke-test.md`. Identify all sections to preserve (frontmatter, hard gates, ship pipeline guard, no-simulated-tests gate) and sections to rewrite (Steps 2-5).
- [X] T002 [US1] Rewrite Step 2 in `spex/extensions/spex/commands/speckit.spex.smoke-test.md`: rename to "Step 2: App Lifecycle (Main Session)". The main session detects project type and starts the app BEFORE spawning the subagent. Reuse existing project type detection logic (Go, Node, Python, Cargo, library detection). Track the process ID for cleanup. If startup fails, ask the user to start manually and confirm.
- [X] T003 [US1] Rewrite Step 3 in `spex/extensions/spex/commands/speckit.spex.smoke-test.md`: rename to "Step 3: Execute via Subagent (Phase 1)". Spawn a subagent via the Agent tool with a prompt that includes: (a) the spec file path to read scenarios from, (b) the project root path, (c) whether the app is running, (d) instructions to categorize each scenario as automated/manual/skip, (e) for automated: run the command and capture output, (f) for manual: prepare step-by-step instructions, (g) for skip: explain why and give manual instructions, (h) the no-simulated-tests rule, (i) instruction to return structured text evidence per scenario using the format from plan.md (Scenario N of TOTAL, Type, Given/When/Then, Why it matters, Evidence section). The subagent MUST NOT read plan.md or tasks.md.

## Phase 3: User Story 2 - Interactive Human Review Phase (P2)

**Story Goal**: The main session presents each scenario with full context and waits for human judgement. On fail, interactive debugging helps resolve issues.

**Independent Test**: After Phase 1 subagent returns, verify each scenario is presented with Given/When/Then, why it matters, evidence, and verdict prompt.

- [X] T004 [US2] Rewrite Step 4 in `spex/extensions/spex/commands/speckit.spex.smoke-test.md`: rename to "Step 4: Interactive Review (Phase 2)". Parse the subagent's return text. For each scenario: present scenario number, user story title, Given/When/Then, "Why it matters" explanation, and evidence. For automated scenarios: show command + output, ask human for pass/fail/skip. For manual scenarios: show step-by-step instructions, wait for human to perform and report. For skip scenarios: show skip reason + manual instructions, let human confirm skip or attempt manual verification.
- [X] T005 [US2] Add Step 4f (debugging loop) to `spex/extensions/spex/commands/speckit.spex.smoke-test.md`: When a scenario is marked "fail", ask "What went wrong?", analyze the evidence to suggest possible causes, offer to inspect logs/code/config, offer to fix the issue, and offer to retry the scenario after the fix. Track both initial failure and retry result.

## Phase 4: User Story 3 - Persistent SMOKE-TEST.md Report (P3)

**Story Goal**: At the end of the review, write SMOKE-TEST.md with full context per scenario.

**Independent Test**: Run a complete smoke test and verify SMOKE-TEST.md is created with the expected structure.

- [X] T006 [US3] Rewrite Step 5 in `spex/extensions/spex/commands/speckit.spex.smoke-test.md`: rename to "Step 5: Write SMOKE-TEST.md". After all scenarios are reviewed, generate `SMOKE-TEST.md` in the spec directory using the report format from plan.md. Each scenario entry includes: Given/When/Then, "Why it matters", Evidence section (command + output for automated, instructions for manual, reason for skip), Verdict (pass/fail/skip with notes). Include header with feature name, date, spec path, and summary line (N passed, M skipped, K failed). If a scenario was retried after a fix, show both initial failure and retry result.

## Phase 5: User Story 4 - Ship Pipeline Integration (P4)

**Story Goal**: Ship pipeline Stage 8 announces readiness and asks user to opt in before running the smoke test.

**Independent Test**: Run `/speckit-spex-ship` and verify Stage 8 presents scenario counts and waits for opt-in.

- [X] T007 [US4] Update Stage 8 in `spex/extensions/spex/commands/speckit.spex.ship.md`. After review-code (Stage 7) completes and advances, Stage 8 should: (a) read the spec and count scenarios (grep for Given), (b) announce "Pipeline is technically done. N scenarios found.", (c) ask "Ready to walk through the verification?", (d) on opt-in: invoke `/speckit-spex-smoke-test`, (e) on decline: record smoke test skipped via state script, announce completion, tell user to run `/speckit-spex-finish` manually.

## Phase 6: Polish & Documentation

**Purpose**: Documentation updates per constitution requirement.

- [X] T008 [P] Update `README.md` to describe the two-phase smoke test architecture (subagent execution + human review) and mention SMOKE-TEST.md report.
- [X] T009 [P] Update `spex/docs/help.md` to describe the two-phase smoke test flow and SMOKE-TEST.md output.

## Dependencies

```text
T001 → T002, T003 (need to understand current skill before rewriting)
T003 → T004, T005 (review phase parses subagent output)
T004, T005 → T006 (report writes from collected verdicts)
T007 is independent of T001-T006 (different file)
T008, T009 are independent of all other tasks (different files)
```

## Parallel Execution

```text
Group 1: T001 (sequential, read current skill)
Group 2: T002 + T003 (parallel, different sections of same file but independent content)
Group 3: T004 + T005 (sequential within same section)
Group 4: T006 (sequential, depends on T004/T005)
Group 5: T007 + T008 + T009 (all parallel, different files)
```

## Implementation Strategy

**MVP**: T001 + T002 + T003 + T004 (User Stories 1 & 2 core). This delivers the two-phase architecture with human review. No report file yet, no ship integration.

**Full delivery**: All 9 tasks. Moderate feature, can be completed in a single pass.

## Summary

- **Total tasks**: 9
- **US1 (subagent execution)**: 3 tasks
- **US2 (human review)**: 2 tasks
- **US3 (SMOKE-TEST.md report)**: 1 task
- **US4 (ship pipeline)**: 1 task
- **Polish/docs**: 2 tasks
- **Parallel opportunities**: T007, T008, T009 can all run in parallel after T006
