# Feature Specification: Mid-Implementation Review Checkpoints with Deep Review Statistics

**Feature Branch**: `026-mid-impl-review`
**Created**: 2026-06-11
**Status**: Draft
**Input**: brainstorm/20-mid-impl-review.md

## Overview

Adds two correctness-focused review checkpoints during ship pipeline implementation (at 1/3 and 2/3 of task completion) and per-agent statistics tracking for all deep review runs. The checkpoints catch logic errors and spec drift before they compound. The statistics reveal which review agents deliver the most value and whether mid-implementation checkpoints are worth their cost.

## Out of Scope

- Per-task review (too expensive, rejected in brainstorm #20)
- Non-correctness review perspectives at checkpoints (architecture, security, production readiness, test quality wait for the full deep review)
- Checkpoints in regular (non-ship) flow (no automated implement pipeline to hook into)
- Cross-session statistics aggregation or persistent trend tracking
- New extensions or standalone commands

## User Scenarios & Testing

### User Story 1 - Mid-Implementation Checkpoints Catch Drift Early (Priority: P1)

A developer runs `/speckit-spex-ship` on a feature with 15 tasks. After task 5 completes (~33%), a fresh-context subagent reviews the implementation so far against the spec. It finds that a function returns the wrong data shape for FR-003. The implementing agent fixes it before tasks 6-15 build on the incorrect foundation. Without the checkpoint, this would only surface at the final deep review, requiring more complex fixes across 10 additional tasks.

**Why this priority**: This is the core value proposition. Catching correctness issues at 1/3 prevents compounding across the remaining 2/3 of implementation.

**Independent Test**: Run `/speckit-spex-ship` on a project with 9+ tasks and `spex-deep-review` enabled. Verify that review checkpoints run after tasks 3 and 6, and that findings are reported and fixed before continuing.

**Acceptance Scenarios**:

1. **Given** a ship pipeline with 15 tasks and `spex-deep-review` enabled, **When** task 5 completes (~33%), **Then** a fresh-context correctness review subagent is spawned, reviews code against spec requirements for completed tasks, and reports findings. If findings exist, the implementing agent fixes them before proceeding to task 6.
2. **Given** a ship pipeline with 15 tasks, **When** task 10 completes (~66%), **Then** a second correctness review checkpoint runs with the same behavior as the first.
3. **Given** `spex-deep-review` is NOT enabled, **When** the ship pipeline runs implementation, **Then** no mid-implementation checkpoints run (existing behavior preserved).
4. **Given** `implement.review_checkpoints` is set to `false` in `.specify/extensions/spex/spex-config.yml`, **When** the ship pipeline runs with `spex-deep-review` enabled, **Then** no mid-implementation checkpoints run.
5. **Given** a feature with only 2 tasks, **When** the ship pipeline runs, **Then** no checkpoints run (too few tasks to justify the overhead; minimum threshold is 3 tasks).

---

### User Story 2 - Deep Review Agent Leaderboard (Priority: P1)

A developer runs a deep review (via ship pipeline or manually via `/speckit-spex-deep-review-run`). After the review completes, a statistics summary is displayed showing per-agent breakdown: how many findings each agent found, how many were fixed, and how many remain. The agent with the most findings is highlighted as the "MVP."

**Why this priority**: Equal priority because the statistics apply to every deep review run (not just ship mode) and provide the data needed to evaluate whether checkpoints are worth their cost.

**Independent Test**: Run `/speckit-spex-deep-review-run` on any project and verify the agent leaderboard is displayed after the review completes.

**Acceptance Scenarios**:

1. **Given** a deep review run with 5 agents, **When** the review completes, **Then** a statistics table is displayed showing: agent name, findings found, findings fixed, findings remaining, for each of the 5 agents plus a total row.
2. **Given** a deep review where the correctness agent found 5 issues and the security agent found 0, **When** the statistics are displayed, **Then** the correctness agent is highlighted as "MVP: Correctness agent (5 findings)."
3. **Given** a deep review where all agents found 0 issues, **When** the statistics are displayed, **Then** the summary shows "Clean review: no findings across 5 agents" without an MVP designation.

---

### User Story 3 - Layer Comparison in Ship Mode (Priority: P2)

A developer runs `/speckit-spex-ship` with checkpoints enabled. After the final deep review completes, the statistics report includes a layer comparison showing what each layer caught: checkpoint 1 findings, checkpoint 2 findings, and final deep review findings, with a "Unique" column showing findings that only that layer caught.

**Why this priority**: This is the data that answers "are checkpoints worth it?" It depends on both Stories 1 and 2 being implemented first.

**Independent Test**: Run a ship pipeline with checkpoints, then verify the layer comparison appears in the final statistics alongside the agent leaderboard.

**Acceptance Scenarios**:

1. **Given** a ship pipeline where checkpoint 1 found 2 issues and checkpoint 2 found 3 issues, **When** the final deep review completes with 11 findings, **Then** the layer comparison shows each layer's findings count, fixed count, and unique count (findings not caught by any other layer).
2. **Given** a ship pipeline where checkpoints found 0 unique findings (all were also caught by the final deep review), **When** the layer comparison is displayed, **Then** the Unique column shows 0 for both checkpoints, signaling they added no value this run.
3. **Given** a regular flow deep review (no ship pipeline, no checkpoints), **When** the statistics are displayed, **Then** no layer comparison is shown (only the agent leaderboard).

---

### Edge Cases

- What happens when a checkpoint finds issues but the implementing agent can't fix them in 2 attempts? Implementation pauses with a report of the unfixed findings, same behavior as test checkpoint failures.
- What happens when the task count changes during implementation (e.g., agent discovers a task needs splitting)? Checkpoint positions are calculated from the original task count in tasks.md at implementation start, not recalculated mid-run.
- What happens when all tasks are marked `[P]` (parallel)? Checkpoints still run at the 1/3 and 2/3 task count boundaries regardless of parallelism markers.
- What happens when a checkpoint review subagent times out or fails? The checkpoint is skipped with a warning, implementation continues. The failure is noted in the statistics.

## Requirements

### Functional Requirements

- **FR-001**: The ship pipeline's implement stage MUST spawn a fresh-context correctness review subagent after approximately 1/3 of tasks are completed.
- **FR-002**: The ship pipeline's implement stage MUST spawn a second fresh-context correctness review subagent after approximately 2/3 of tasks are completed.
- **FR-003**: Checkpoint positions MUST be calculated from the total task count in tasks.md: checkpoint 1 at `round(total * 0.33)`, checkpoint 2 at `round(total * 0.67)`.
- **FR-004**: Checkpoints MUST only run when the `spex-deep-review` extension is enabled.
- **FR-005**: Checkpoints MUST be disableable via `implement.review_checkpoints: false` in `.specify/extensions/spex/spex-config.yml`. The default MUST be `true`.
- **FR-006**: Checkpoints MUST NOT run when the total task count is less than 3.
- **FR-007**: Each checkpoint subagent MUST review only correctness: does the code match the spec requirements for the tasks completed so far? It MUST NOT review architecture, security, production readiness, or test quality.
- **FR-008**: Each checkpoint subagent MUST run in a fresh context (spawned via Agent tool, not inline in the implementing agent's session).
- **FR-009**: If a checkpoint finds issues, the implementing agent MUST attempt to fix them (max 2 attempts) before continuing to the next task.
- **FR-010**: Every deep review run MUST output a per-agent statistics summary after completion, regardless of invocation mode (ship pipeline or manual).
- **FR-011**: The statistics summary MUST include: agent name, findings found, findings fixed, findings remaining, for each review agent, plus a total row.
- **FR-012**: The statistics summary MUST highlight the agent with the most findings as "MVP: {agent name} ({count} findings)."
- **FR-013**: When no agent found any findings, the statistics MUST display "Clean review: no findings across {N} agents."
- **FR-014**: In ship mode with checkpoints enabled, the deep review statistics MUST include a layer comparison table showing: layer name (checkpoint 1/3, checkpoint 2/3, final review), findings count, fixed count, and unique findings count per layer.
- **FR-015**: The "unique findings" count MUST represent findings that were only caught by that specific layer and not by any other layer in the same pipeline run.
- **FR-016**: Checkpoint findings MUST be recorded in the state file so the layer comparison can be computed after the final deep review.
- **FR-017**: When running in regular flow (no ship pipeline, no checkpoints), the statistics MUST show only the agent leaderboard without a layer comparison.

### Non-Functional Requirements

- **NFR-001**: Each checkpoint review MUST complete in under 2 minutes for projects with up to 50 changed files.
- **NFR-002**: The statistics summary MUST add less than 1KB to console output.

### Key Entities

- **Review Checkpoint**: A correctness-focused review at a task boundary. Has a position (1/3 or 2/3), findings list, fix attempts count, and completion status.
- **Agent Statistics**: Per-agent metrics from a deep review run. Has agent name, findings found, findings fixed, findings remaining.
- **Layer Comparison**: Cross-layer metrics from a ship pipeline run with checkpoints. Has layer name, findings count, fixed count, unique count.
- **Checkpoint State**: Extension of `.specify/.spex-state` with checkpoint fields: `checkpoint_1_findings` (count), `checkpoint_2_findings` (count), `checkpoint_1_fixed` (count), `checkpoint_2_fixed` (count).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Correctness issues introduced in the first third of tasks are caught before the remaining two-thirds build on them.
- **SC-002**: The agent leaderboard is displayed after every deep review run, providing visibility into which agents deliver the most value.
- **SC-003**: After 5+ ship pipeline runs with checkpoints enabled, the layer comparison data answers whether checkpoints are catching unique findings or duplicating the final deep review's work.
- **SC-004**: Users can make a data-driven decision to disable checkpoints (via config) if the statistics show they add no unique value for their project.

## Assumptions

- The deep review already tracks per-agent findings internally during its run. The statistics feature surfaces this data in a structured format rather than collecting it from scratch.
- Checkpoint review subagents have access to the spec and the current code via the file system (same as the implementing subagent).
- The "unique findings" calculation is approximate: it compares finding descriptions/locations across layers. Exact deduplication is not required; reasonable text matching is sufficient.
- Projects using checkpoints have enough tasks (3+) to make the 1/3 and 2/3 split meaningful. Features with 1-2 tasks skip checkpoints automatically.

## Clarifications

### Session 2026-06-11

- Q: How does the implementing subagent know when to trigger checkpoints? → A: The ship pipeline calculates checkpoint positions (task numbers) before spawning the implement subagent and passes them in the subagent prompt as explicit instructions: "After completing task N, pause and spawn a correctness review subagent before continuing."
- Q: What format should checkpoint findings use in the state file? → A: Simple counts per checkpoint: `checkpoint_1_findings`, `checkpoint_1_fixed`, `checkpoint_2_findings`, `checkpoint_2_fixed`. Finding descriptions are not stored in the state file; they're only in the console output. The layer comparison uses counts, not individual finding details.
- Q: Should the checkpoint review scope include all code so far or just the diff since the last checkpoint? → A: All code so far (cumulative). The first checkpoint reviews tasks 1-N, the second reviews tasks 1-M. This catches issues in earlier code that become apparent only with later context.
