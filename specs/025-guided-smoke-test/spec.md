# Feature Specification: Guided Smoke Test and Ship Pipeline Safety

**Feature Branch**: `025-guided-smoke-test`
**Created**: 2026-06-11
**Status**: Draft
**Input**: brainstorm/18-guided-smoke-test.md

## Overview

Adds an interactive smoke test command that walks users through acceptance scenarios from the spec, executing each step and waiting for confirmation. Also changes the ship pipeline to always stop before merge/PR, requiring deliberate human action to complete.

## Out of Scope

- Fully automated (non-interactive) smoke testing in any mode
- Smoke test for projects without acceptance scenarios in the spec
- Custom test definition files separate from spec.md
- Visual regression testing or screenshot comparison
- Performance benchmarking during smoke tests
- Cross-session smoke test persistence (runs within a single session)

## User Scenarios & Testing

### User Story 1 - Interactive Smoke Test Validates Runtime Behavior (Priority: P1)

A developer finishes implementing a feature and runs `/speckit-spex-smoke-test`. The command reads the spec's acceptance scenarios, detects the project type, starts the app, and walks through each scenario step by step. For each step, it explains what it will do, executes the command (e.g., curl, browser action), shows the result, and waits for the user to confirm before proceeding. If a scenario fails, the developer fixes the issue with Claude's help before moving on.

**Why this priority**: This is the core deliverable. Without the interactive smoke test, the other changes (pipeline ordering, stop behavior) have no trigger.

**Independent Test**: Run `/speckit-spex-smoke-test` on a project with a spec containing Given/When/Then scenarios. Verify that each scenario is presented, executed, and confirmed interactively.

**Acceptance Scenarios**:

1. **Given** a spec with 3 acceptance scenarios and a startable app, **When** the user runs `/speckit-spex-smoke-test`, **Then** the command starts the app, presents each scenario one at a time, executes the action step, displays the result, and waits for user confirmation before proceeding to the next.
2. **Given** a scenario step fails (unexpected output), **When** the user reports the failure, **Then** the command helps debug interactively: suggests potential causes, offers to inspect logs or code, and lets the user fix the issue before retrying the step or moving on.
3. **Given** a project that cannot be started locally (no detectable start command, requires cloud infrastructure), **When** the user runs `/speckit-spex-smoke-test`, **Then** the command reports "Cannot auto-detect how to start this project. Please start the app manually and confirm when ready." and proceeds with scenario execution once the user confirms.
4. **Given** a spec with no acceptance scenarios (no Given/When/Then blocks), **When** the user runs `/speckit-spex-smoke-test`, **Then** the command reports "No acceptance scenarios found in spec.md. Add Given/When/Then scenarios to enable smoke testing." and exits.

---

### User Story 2 - Verify/Stamp Reminds About Missing Smoke Test (Priority: P1)

A developer runs `/speckit-spex-gates-verify` after implementation. The spec has acceptance scenarios but no smoke test has been recorded in the current session. Verify displays a reminder suggesting the user run the smoke test first.

**Why this priority**: Equal priority with Story 1 because the reminder is what connects the smoke test to the existing workflow. Without it, users forget to run it.

**Independent Test**: Run `/speckit-spex-gates-verify` on a feature with acceptance scenarios but no smoke test recorded. Verify the reminder appears.

**Acceptance Scenarios**:

1. **Given** a spec with acceptance scenarios and no smoke test recorded in the state file, **When** `/speckit-spex-gates-verify` runs, **Then** it displays: "Acceptance scenarios exist but no smoke test was recorded. Consider running `/speckit-spex-smoke-test` first." The reminder is informational and does not block verification.
2. **Given** a smoke test was recorded (results in state file), **When** `/speckit-spex-gates-verify` runs, **Then** no reminder is shown. Verification proceeds normally.
3. **Given** a spec with no acceptance scenarios, **When** `/speckit-spex-gates-verify` runs, **Then** no reminder is shown (nothing to smoke test).

---

### User Story 3 - Ship Pipeline Stops Before Merge/PR (Priority: P2)

A developer runs `/speckit-spex-ship` to autonomously specify, plan, implement, and review a feature. After the review-code stage completes, the pipeline invokes the smoke test (interactive, always pauses) and then stops. The user manually decides whether to merge or create a PR by running `/speckit-spex-finish`.

**Why this priority**: This is a safety improvement that changes existing behavior. It's important but depends on Story 1 for the smoke test pause point.

**Independent Test**: Run `/speckit-spex-ship` with `--ask never` and verify the pipeline stops after the smoke test stage without auto-merging.

**Acceptance Scenarios**:

1. **Given** a ship pipeline running with any `ask` level, **When** all stages through review-code complete, **Then** the pipeline invokes `/speckit-spex-smoke-test` interactively (always pauses regardless of `ask` level) and stops after the smoke test. It does NOT invoke `/speckit-spex-finish` automatically.
2. **Given** a ship pipeline that has stopped after the smoke test, **When** the user runs `/speckit-spex-finish` manually, **Then** finish runs verification and presents merge/PR options as usual.
3. **Given** a ship pipeline where the smoke test is skipped (no acceptance scenarios), **When** review-code completes, **Then** the pipeline still stops and reports: "Pipeline complete through review. Run `/speckit-spex-finish` to merge or create a PR."

---

### User Story 4 - Smoke Test Records Results for Downstream Gates (Priority: P2)

The smoke test records its results (scenarios tested, pass/fail per scenario, timestamp) in the `.specify/.spex-state` file so that verify/stamp and the ship pipeline can check whether a smoke test was performed.

**Why this priority**: Infrastructure that Stories 2 and 3 depend on, but not user-facing on its own.

**Independent Test**: Run the smoke test, then inspect `.specify/.spex-state` for smoke test results.

**Acceptance Scenarios**:

1. **Given** a completed smoke test (all scenarios confirmed), **When** the results are recorded, **Then** `.specify/.spex-state` contains `smoke_test_completed: true`, `smoke_test_at: <timestamp>`, and `smoke_test_scenarios: <count>`.
2. **Given** a partially completed smoke test (user stopped early), **When** the results are recorded, **Then** the state reflects partial completion: `smoke_test_completed: false` with the count of scenarios completed vs total.
3. **Given** no smoke test has been run, **When** verify/stamp checks the state file, **Then** `smoke_test_completed` is absent or null.

---

### Edge Cases

- What happens when the app crashes during a smoke test scenario? The command detects the crash (process exit), reports it to the user, and offers to restart the app before retrying the scenario.
- What happens when multiple acceptance scenarios require different app states (e.g., clean database)? Each scenario is independent. The command does not manage state between scenarios. If a scenario needs a clean state, it should be described in the Given clause, and the user confirms readiness.
- What happens when the user wants to skip a scenario? The command accepts "skip" as a valid response during confirmation, marks the scenario as skipped, and moves to the next one.
- What happens when the spec has acceptance scenarios but the project is a library (no runnable app)? The command detects library projects (no server, no CLI entry point) and adapts: instead of starting an app, it suggests running the scenarios as function calls or test invocations, or asks the user how to exercise the behavior.
- What happens when the ship pipeline is interrupted during the smoke test? The state file retains the pipeline state. Resuming with `--resume` returns to the smoke test stage.

## Requirements

### Functional Requirements

- **FR-001**: The `/speckit-spex-smoke-test` command MUST parse all Given/When/Then acceptance scenarios from the feature spec. Parsing rules: scan only the "User Scenarios & Testing" section (and its subsections) for numbered list items containing bold `**Given**`/`**When**`/`**Then**` keywords. Each numbered item is one scenario. The "Edge Cases" section MUST NOT be scanned for scenarios. Each parsed scenario consists of the full text of the numbered list item.
- **FR-002**: For each scenario, the command MUST explain the step it will execute, execute it, display the result, and wait for user confirmation before proceeding.
- **FR-003**: The command MUST auto-detect the project type and start command using the same detection logic as the verify command (Makefile, package.json, go.mod, etc.).
- **FR-004**: When the project cannot be started automatically, the command MUST ask the user to start it manually and confirm when ready.
- **FR-005**: When a scenario step produces unexpected results, the command MUST offer interactive debugging assistance (inspect logs, examine code, suggest fixes).
- **FR-006**: The command MUST accept "skip" as a valid response to skip the current scenario.
- **FR-007**: The command MUST record smoke test results in `.specify/.spex-state` with fields: `smoke_test_completed` (boolean), `smoke_test_at` (timestamp), `smoke_test_scenarios` (count completed), `smoke_test_total` (total count).
- **FR-008**: `/speckit-spex-gates-verify` MUST display a reminder when acceptance scenarios exist in the spec but no smoke test is recorded in the state file.
- **FR-009**: The verify reminder MUST be informational only and MUST NOT block verification.
- **FR-010**: The ship pipeline MUST invoke `/speckit-spex-smoke-test` as the final stage (replacing the current finish stage). The pipeline stage sequence becomes: specify(0), clarify(1), review-spec(2), plan(3), tasks(4), review-plan(5), implement(6), review-code(7), smoke-test(8). Finish is no longer a pipeline stage; the user invokes it manually after the pipeline stops. The `--start-from` flag MUST accept `smoke-test` instead of `finish`, and the valid stage names list and error message template in the ship command MUST be updated accordingly.
- **FR-011**: The smoke test stage in the ship pipeline MUST always be interactive, regardless of the `ask` level.
- **FR-012**: The ship pipeline MUST NOT invoke `/speckit-spex-finish` automatically. After the smoke test (or after review-code if no scenarios exist), the pipeline MUST stop and instruct the user to run finish manually.
- **FR-013**: When a spec has no acceptance scenarios, the smoke test command MUST report this and exit without error.
- **FR-014**: The command MUST delegate app startup to the `/run` skill when available (detected at runtime via the active skill list, not a hard installation dependency), falling back to its own auto-detection logic (Makefile, package.json, go.mod, etc.) when `/run` is not available.
- **FR-015**: For library projects (no runnable app), the command MUST adapt by suggesting function-call or test-based verification and asking the user how to exercise the behavior.

### Non-Functional Requirements

- **NFR-001**: The smoke test MUST NOT add more than 5 seconds of overhead per scenario beyond the actual execution time (parsing, formatting, state recording).
- **NFR-002**: The smoke test state data MUST add less than 500 bytes to the state file.

### Key Entities

- **Smoke Test Session**: A walkthrough of all acceptance scenarios. Has a start time, completion status, scenario results list, and associated spec path.
- **Scenario Result**: An individual acceptance scenario outcome. Has a scenario description (from spec), status (passed/failed/skipped), user confirmation timestamp, and optional failure notes.
- **Smoke Test State**: Extension of `.specify/.spex-state` with smoke test fields: `smoke_test_completed`, `smoke_test_at`, `smoke_test_scenarios`, `smoke_test_total`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Runtime bugs that manifest only when the app is actually running are caught before code review or merge, not after deployment.
- **SC-002**: 100% of acceptance scenarios from the spec are presented during a smoke test session (none silently skipped).
- **SC-003**: The ship pipeline never auto-merges or auto-creates PRs, requiring explicit human action for every merge.
- **SC-004**: Developers who run the smoke test confirm that the interactive step-by-step format catches issues they would have missed with a simple "run the tests" approach.

## Assumptions

- The spec's acceptance scenarios (Given/When/Then) provide enough detail for Claude to determine what command to run and what output to check. Vague scenarios may require the user to guide the execution.
- Projects have a way to start locally (server, CLI, REPL) or the user can start the app manually and confirm readiness.
- The `/run` skill exists and can launch common project types. When it's not available, the smoke test falls back to its own auto-detection.
- The smoke test runs within a single Claude Code session. It does not persist across sessions or use cron/loop for continuity.
- The ship pipeline stop behavior is a deliberate design choice that trades full autonomy for safety. Users who want fully unattended pipelines must accept the pause point.

## Clarifications

### Session 2026-06-11

- Q: How does the smoke test fit into the ship pipeline's fixed 0-8 stage indexing? → A: Smoke test replaces the finish stage (index 8). The pipeline becomes: specify(0), clarify(1), review-spec(2), plan(3), tasks(4), review-plan(5), implement(6), review-code(7), smoke-test(8). Finish is no longer a pipeline stage; the user runs it manually.
- Q: In the regular (non-ship) flow, what ordering is recommended? → A: Smoke test before deep review. The user runs `/speckit-spex-smoke-test` after implementation, then `/speckit-spex-gates-review-code`, then `/speckit-spex-finish`. Verify/stamp reminds about the smoke test if it wasn't run.
- Q: Should the smoke test clean up the app process it started when the session ends? → A: Yes. If the smoke test started the app, it must attempt to stop it (kill the background process) when all scenarios are complete or the user exits early.
