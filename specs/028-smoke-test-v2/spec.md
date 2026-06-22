# Feature Specification: Smoke Test V2 - Two-Phase Fresh Context

**Feature Branch**: `028-smoke-test-v2`
**Created**: 2026-06-22
**Status**: Draft
**Input**: Brainstorm #22 - Smoke test v2 with fresh context and human judgement

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fresh Context Execution via Subagent (Priority: P1)

A developer has just completed implementation and wants to smoke test the feature. The smoke test spawns a subagent that has no memory of the implementation session. The subagent reads the spec's acceptance scenarios, executes every automatable step (runs commands, captures output), and for scenarios requiring human action, prepares precise step-by-step instructions. The subagent returns a structured evidence payload to the main session. The developer never interacts with the subagent directly.

**Why this priority**: This is the core architectural change. Without fresh context, the smoke test has self-testing bias, which is the primary problem motivating this feature.

**Independent Test**: Invoke `/speckit-spex-smoke-test` on a project with acceptance scenarios. Verify the execution phase runs in a subagent (check that the Agent tool is called) and the subagent's output contains evidence for each scenario without referencing implementation details.

**Acceptance Scenarios**:

1. **Given** a spec with 5 acceptance scenarios, **When** the smoke test is invoked, **Then** a subagent is spawned that reads only the spec (not the implementation conversation) and executes each automatable scenario.
2. **Given** a scenario that requires running a command (e.g., `curl`, `make test`), **When** the subagent processes it, **Then** the full command and its output are captured in the evidence payload.
3. **Given** a scenario that cannot be automated (e.g., "open browser and check layout"), **When** the subagent processes it, **Then** it is marked as "manual" with step-by-step instructions including exact commands, URLs, and what to look for.
4. **Given** a scenario that cannot be exercised at all in this session (e.g., requires a prior separate run), **When** the subagent processes it, **Then** it is marked as "skip" with a clear reason and manual test instructions for later. The subagent MUST NOT simulate the expected output.

---

### User Story 2 - Interactive Human Review Phase (Priority: P2)

After the subagent returns its evidence, the main session presents each scenario one at a time to the developer. For each scenario, the developer sees the full context (Given/When/Then, why it matters, the evidence collected) and makes a pass/fail/skip judgement. On failure, the system helps debug interactively.

**Why this priority**: The human review is what gives the smoke test its value. Without it, the smoke test is just another automated check that can't catch nuanced issues.

**Independent Test**: Manually trigger the review phase with a mock evidence payload. Verify each scenario is presented with full context and the system waits for human input before advancing.

**Acceptance Scenarios**:

1. **Given** the subagent has returned evidence for 5 scenarios, **When** the review phase begins, **Then** the first scenario is presented with: the Given/When/Then text, a one-sentence explanation of why this scenario matters (what risk it catches), the command that was run, and the full output.
2. **Given** an automated scenario is presented, **When** the developer says "pass", **Then** the verdict is recorded and the next scenario is presented.
3. **Given** a manual scenario is presented, **When** the review phase reaches it, **Then** the step-by-step instructions are shown and the system waits for the developer to perform the steps and report the result.
4. **Given** a scenario the developer marks as "fail", **When** the failure is recorded, **Then** the system asks what went wrong, analyzes the evidence to suggest possible causes, offers to fix the issue, and offers to retry the scenario after the fix.
5. **Given** a scenario marked as "skip" by the subagent, **When** the review phase reaches it, **Then** the skip reason and manual test instructions are shown, and the developer can confirm skip or attempt manual verification.

---

### User Story 3 - Persistent SMOKE-TEST.md Report (Priority: P3)

At the end of the review phase, a SMOKE-TEST.md report is written to the spec directory. The report includes full context for each scenario: the Given/When/Then, why it matters, the evidence, and the human verdict. This provides a persistent record of what was tested and how.

**Why this priority**: The report is the artifact that persists after the session ends. It allows others (or future self) to understand what was validated and how thoroughly.

**Independent Test**: Run a complete smoke test and verify SMOKE-TEST.md is created in the spec directory with the expected structure and content for each scenario.

**Acceptance Scenarios**:

1. **Given** all scenarios have been reviewed, **When** the review phase completes, **Then** a file `SMOKE-TEST.md` is written to the spec directory (e.g., `specs/NNN-feature/SMOKE-TEST.md`).
2. **Given** SMOKE-TEST.md is written, **When** a reader opens it, **Then** each scenario entry contains: Given/When/Then text, a "Why it matters" explanation, the evidence (command + output or manual instructions), and the verdict (pass/fail/skip with reason).
3. **Given** some scenarios were skipped, **When** SMOKE-TEST.md is written, **Then** the skipped scenarios include the skip reason and manual test instructions so a reader knows how to verify them later.
4. **Given** a scenario failed and was debugged/retried, **When** SMOKE-TEST.md is written, **Then** the report shows both the initial failure and the retry result.

---

### User Story 4 - Ship Pipeline Integration (Priority: P4)

When the smoke test runs as part of the ship pipeline (Stage 8), the pipeline announces that it is "technically done" after the review-code stage, presents what it has prepared for the smoke test, and asks the user whether they want to proceed with the interactive verification.

**Why this priority**: Ship pipeline integration ensures the smoke test is surfaced at the right moment without disrupting the autonomous flow.

**Independent Test**: Run `/speckit-spex-ship` and verify that after Stage 7 (review-code), the pipeline presents the smoke test preparation summary and waits for user opt-in before spawning the subagent.

**Acceptance Scenarios**:

1. **Given** the ship pipeline has completed Stage 7 (review-code), **When** Stage 8 (smoke-test) begins, **Then** the pipeline announces what scenarios were found (count of automated vs. manual) and asks: "Ready to walk through the verification?"
2. **Given** the user opts in to the smoke test, **When** the smoke test runs, **Then** Phase 1 (subagent execution) and Phase 2 (interactive review) proceed as described in User Stories 1 and 2.
3. **Given** the user declines the smoke test, **When** they respond "no" or "skip", **Then** the pipeline records that the smoke test was skipped and proceeds to the completion announcement (user runs `/speckit-spex-finish` manually).
4. **Given** the smoke test runs in standalone mode (not ship pipeline), **When** the user invokes `/speckit-spex-smoke-test`, **Then** the same two-phase pattern runs with the same report output.

---

### Edge Cases

- What happens when the subagent fails or times out? The main session should report the failure and offer to retry or skip the entire smoke test.
- What happens when no acceptance scenarios are found in the spec? The smoke test should report "no scenarios found" and exit cleanly (same as current behavior).
- What happens when all scenarios are marked as "manual"? The review phase presents all instructions and the developer performs each one. No subagent execution needed (but the subagent still runs to categorize them).
- What happens when the app requires startup before testing? The subagent should attempt project type detection and app startup (same as current behavior), falling back to asking the main session to instruct the user.
- What happens when a scenario was already tested in a prior smoke test run? SMOKE-TEST.md is overwritten (not appended). Each run is a fresh validation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The smoke test MUST spawn a subagent (via the Agent tool) for the execution phase. The subagent MUST NOT have access to the implementation conversation context.
- **FR-002**: The subagent MUST read acceptance scenarios only from the feature spec (spec.md). It MUST NOT reference implementation artifacts (plan.md, tasks.md) to determine test expectations.
- **FR-003**: For each automatable scenario, the subagent MUST execute the actual command and capture the full output as evidence.
- **FR-004**: For each scenario requiring human action, the subagent MUST prepare step-by-step instructions including exact commands, URLs, expected observations, and what to look for.
- **FR-005**: For scenarios that cannot be exercised, the subagent MUST mark them as "skip" with a reason and manual test instructions. It MUST NOT simulate or fake the expected output.
- **FR-006**: The review phase MUST present each scenario one at a time with: Given/When/Then text, why it matters (what risk it catches), evidence collected, and a verdict prompt.
- **FR-007**: On a "fail" verdict, the review phase MUST ask what went wrong, analyze the evidence, suggest possible causes, offer to fix, and offer to retry the scenario.
- **FR-008**: The review phase MUST write SMOKE-TEST.md to the spec directory after all scenarios are reviewed.
- **FR-009**: Each entry in SMOKE-TEST.md MUST include: Given/When/Then, why it matters, evidence, and verdict with any notes.
- **FR-010**: In ship pipeline mode, the pipeline MUST announce readiness after Stage 7, present scenario counts, and ask for user opt-in before running the smoke test.
- **FR-011**: In standalone mode, the smoke test MUST follow the same two-phase pattern as in ship mode.
- **FR-012**: The existing no-simulated-tests hard gate MUST remain in the smoke test skill.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The smoke test execution phase runs in a subagent with no implementation context, verified by the absence of implementation-specific references in the subagent's evidence payload.
- **SC-002**: Every scenario in SMOKE-TEST.md includes the full context (Given/When/Then, why it matters, evidence, verdict) for every smoke test run.
- **SC-003**: When a scenario cannot be exercised, it is skipped with manual instructions in 100% of cases (never simulated).
- **SC-004**: The human reviewer can make an informed pass/fail judgement for each scenario based solely on the evidence presented, without needing to re-read the spec or implementation.

## Assumptions

- The Agent tool in Claude Code supports spawning subagents that have no access to the parent conversation's context (this is the documented behavior).
- The subagent can execute bash commands, read files, and return text results to the parent session.
- The current smoke test skill (spec 025) is the baseline being enhanced. The existing project type detection, app startup, and scenario parsing logic are reused.
- SMOKE-TEST.md follows the same pattern as REVIEW-CODE.md (review artifact in the spec directory).
- The ship pipeline's Stage 8 is the smoke test stage (established in spec 025 and spec 027).
