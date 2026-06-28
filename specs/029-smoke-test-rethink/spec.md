# Feature Specification: Focused Interactive Smoke Test

**Feature Branch**: `029-smoke-test-rethink`  
**Created**: 2026-06-28  
**Status**: Draft  
**Input**: Brainstorm #24 — Smoke Test Rethink (supersedes #18, #22)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Curated Smoke Test for Runnable Features (Priority: P1)

A developer has shipped a feature that produces a runnable artifact (CLI tool, server, UI component). The spec includes a `## Smoke Test` section with 3-5 hand-picked scenarios that require human judgment. The developer invokes `/speckit-spex-smoke-test`, and Claude handles all setup (starting the app, seeding data, navigating browsers) while the developer only provides pass/fail judgment on each scenario.

**Why this priority**: This is the core value proposition — eliminating busywork while preserving genuine human validation for scenarios that need eyes.

**Independent Test**: Can be tested by creating a spec with a `## Smoke Test` section, invoking the command, and verifying that Claude automates setup/execution and only asks the human for judgment calls.

**Acceptance Scenarios**:

1. **Given** a spec with a `## Smoke Test` section containing 3 scenarios, **When** the developer invokes `/speckit-spex-smoke-test`, **Then** Claude parses the scenarios from the `## Smoke Test` section, sets up the environment, executes each scenario, and presents evidence for human judgment one at a time.
2. **Given** a scenario that requires a running server, **When** Claude executes that scenario, **Then** Claude starts the server automatically (using `/run` or auto-detection), exercises the scenario against the live server, and presents the result for human judgment.
3. **Given** a scenario that requires browser interaction, **When** Claude executes that scenario and Playwright MCP is available, **Then** Claude navigates to the correct URL, performs the required interactions (clicks, form fills), takes a screenshot, and presents the screenshot as evidence for human judgment.
4. **Given** a scenario that requires browser interaction but Playwright MCP is unavailable, **When** Claude reaches that scenario, **Then** Claude degrades gracefully by providing step-by-step manual instructions (URL to open, actions to perform, what to look for) and asks the human to perform and judge it.

---

### User Story 2 - Auto-Skip for Non-Runnable Features (Priority: P1)

A developer has shipped a library or skill feature with no runnable artifact. The spec has no `## Smoke Test` section. When the smoke test stage runs (either directly or via the ship pipeline), it detects the absence and skips cleanly without wasting the developer's time.

**Why this priority**: Equally critical to the core — the old smoke test forced library features through a meaningless walkthrough. Auto-skip eliminates that friction entirely.

**Independent Test**: Can be tested by invoking the smoke test against a spec that has no `## Smoke Test` section and verifying it skips without error.

**Acceptance Scenarios**:

1. **Given** a spec with no `## Smoke Test` section, **When** the developer invokes `/speckit-spex-smoke-test`, **Then** the command reports "No smoke test scenarios defined — skipping" and exits without error.
2. **Given** the ship pipeline reaches the smoke test stage and the spec has no `## Smoke Test` section, **When** the pipeline evaluates the stage, **Then** it skips the smoke test, reports the skip, and proceeds to pipeline completion.

---

### User Story 3 - Spec Template Integration (Priority: P2)

A developer is writing a spec for a new feature using `/speckit-specify`. The spec template includes an optional `## Smoke Test` section with guidance on when to include it and how to write effective scenarios. The developer can include or omit the section based on whether the feature has a runnable artifact.

**Why this priority**: The template change enables the whole workflow but is a smaller piece of implementation compared to the runtime behavior.

**Independent Test**: Can be tested by running `/speckit-specify` for a feature with a runnable artifact and verifying the generated spec includes a `## Smoke Test` section with appropriate guidance.

**Acceptance Scenarios**:

1. **Given** a feature description that implies a runnable artifact (CLI, server, UI), **When** `/speckit-specify` generates the spec, **Then** the spec includes a `## Smoke Test` section with 3-5 scenario placeholders and guidance comments explaining what makes a good smoke test scenario.
2. **Given** a feature description for a library or internal module with no runnable artifact, **When** `/speckit-specify` generates the spec, **Then** the spec omits the `## Smoke Test` section entirely (no empty placeholder).

---

### User Story 4 - Ship Pipeline Integration (Priority: P2)

A developer runs `/speckit-spex-ship` to ship a feature end-to-end. At Stage 8 (smoke test), the pipeline checks for a `## Smoke Test` section. If present, it pauses for interactive walkthrough. If absent, it skips and completes.

**Why this priority**: Pipeline integration is how most developers encounter the smoke test. The behavior must be correct, but it builds on the core smoke test implementation.

**Independent Test**: Can be tested by running the ship pipeline on a spec with and without a `## Smoke Test` section and verifying correct Stage 8 behavior.

**Acceptance Scenarios**:

1. **Given** the ship pipeline reaches Stage 8 and the spec has a `## Smoke Test` section with scenarios, **When** the pipeline evaluates the stage, **Then** it pauses and runs the interactive smoke test (always interactive, regardless of `--ask` level).
2. **Given** the ship pipeline reaches Stage 8 and the spec has no `## Smoke Test` section, **When** the pipeline evaluates the stage, **Then** it reports "No smoke test scenarios — skipping" and completes the pipeline.

---

### User Story 5 - Persistent Report with Evidence (Priority: P3)

After the smoke test completes, a SMOKE-TEST.md report is written to the spec directory. The report captures each scenario's evidence and verdict, serving as a persistent record of what was validated and how.

**Why this priority**: The report is valuable for audit trails and review, but the core interactive workflow comes first.

**Independent Test**: Can be tested by running a smoke test to completion and verifying SMOKE-TEST.md is created with correct structure and content.

**Acceptance Scenarios**:

1. **Given** a completed smoke test with 3 scenarios (2 passed, 1 skipped), **When** the report is generated, **Then** SMOKE-TEST.md is written to the spec directory with each scenario's evidence, verdict, and any notes from the reviewer.
2. **Given** a scenario that failed and was retried after a fix, **When** the report is generated, **Then** the report documents both the initial failure and the retry result.

---

### Edge Cases

- What happens when the `## Smoke Test` section exists but contains no parseable scenarios (empty or malformed)? The command treats it as "no scenarios" and skips with a warning.
- What happens when the app crashes mid-scenario? Claude detects the crash, reports it, offers to restart, and the scenario can be retried.
- What happens when a scenario requires external infrastructure the developer does not have? Claude marks it as "skip" with manual instructions for later.
- What happens when the `## Smoke Test` section has more than 5 scenarios? A warning is shown recommending the developer trim to 5 or fewer, but execution proceeds.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The smoke test command MUST parse scenarios exclusively from the `## Smoke Test` section of the spec (not from acceptance scenarios in user stories).
- **FR-002**: The command MUST skip automatically when no `## Smoke Test` section exists in the spec, reporting the skip cleanly.
- **FR-003**: Claude MUST handle all setup and teardown for scenarios: starting/stopping servers, preparing test data, navigating browsers, running commands.
- **FR-004**: The human MUST only be asked for pass/fail judgment — never for setup, execution, or evidence collection.
- **FR-005**: The command MUST produce a persistent SMOKE-TEST.md report in the spec directory after every run.
- **FR-006**: The command MUST NOT simulate, fake, or manually reproduce expected output. Every scenario must exercise the real system. If a scenario cannot be tested, it must be skipped honestly with manual instructions.
- **FR-007**: The command MUST run in single-session mode (no subagent architecture). The current session executes scenarios directly.
- **FR-008**: The command MUST degrade gracefully when Playwright MCP is unavailable — browser scenarios fall back to step-by-step manual instructions.
- **FR-009**: The ship pipeline MUST check for the `## Smoke Test` section to decide whether to run or skip the smoke test stage.
- **FR-010**: The spec template MUST include an optional `## Smoke Test` section with guidance on when to include it and how to write scenarios.
- **FR-011**: The command MUST warn (but not block) when more than 5 scenarios are defined in the `## Smoke Test` section.

### Key Entities

- **Smoke Test Scenario**: A human-readable instruction in the `## Smoke Test` section describing what to validate. Contains a description, setup steps (implicit or explicit), and what the human should judge.
- **SMOKE-TEST.md Report**: Persistent record of smoke test results, including evidence collected and human verdicts for each scenario.
- **Spec `## Smoke Test` Section**: Optional section in the feature spec containing curated scenarios. Its presence or absence controls whether the smoke test runs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Smoke test walkthrough completes in under 5 minutes for a 3-scenario spec (excluding fix/retry time), compared to 15+ minutes for the v2 17-scenario approach.
- **SC-002**: The human provides judgment on every scenario presented — no scenarios are auto-verified without human awareness.
- **SC-003**: Features without runnable artifacts (libraries, skills) skip the smoke test in under 2 seconds with zero human interaction.
- **SC-004**: Every smoke test run produces a SMOKE-TEST.md report regardless of outcome (all pass, some fail, some skip).
- **SC-005**: The spec template change enables spec authors to add smoke test scenarios without reading separate documentation.

## Smoke Test

1. Run `/speckit-spex-smoke-test` against a spec with a `## Smoke Test` section containing 3 scenarios — verify Claude parses the section, automates setup, and presents each scenario for human judgment without auto-verifying any.
2. Run `/speckit-spex-smoke-test` against a spec with no `## Smoke Test` section — verify it skips cleanly with a message and exits without error.
3. Run the ship pipeline on a feature with a `## Smoke Test` section — verify Stage 8 pauses for interactive walkthrough and produces SMOKE-TEST.md.

## Assumptions

- Playwright MCP is available in most developer environments but is not guaranteed — graceful degradation to manual instructions is acceptable.
- Spec authors will curate 3-5 scenarios for the `## Smoke Test` section. The system warns but does not enforce a hard limit.
- The `/run` skill may or may not be available. Auto-detection of project type serves as the fallback for starting apps.
- The `## Smoke Test` section uses a simple format (numbered list of human-readable instructions), not Given/When/Then triples. Scenarios are prose descriptions of what to validate, not structured test definitions.
- The existing no-simulation hard gate from v2 carries forward unchanged as a core principle.
