# Feature Specification: Backpressure Loops for Implementation and Post-PR

**Feature Branch**: `024-backpressure-loops`
**Created**: 2026-06-11
**Status**: Draft
**Input**: brainstorm/17-backpressure-loops.md

## Overview

Adds two backpressure mechanisms to the spex workflow: (1) inter-task test checkpoints during `/speckit-implement` that catch regressions before they compound across tasks, and (2) a post-PR watch mode for `/speckit-spex-finish` that monitors CI, auto-fixes failures, and optionally triages review comments.

## Out of Scope

- Test checkpoints during brainstorm, planning, or spec phases (only implementation)
- Cross-session watch persistence via external schedulers (watch runs within a single Claude Code session)
- Parallel test execution or test suite optimization
- Custom CI provider integrations beyond what `gh` CLI supports
- Watch mode for non-PR finishes (direct merges to default branch)

## User Scenarios & Testing

### User Story 1 - Per-Task Test Checkpoints Catch Compounding Failures (Priority: P1)

A developer runs `/speckit-implement` on a feature with 5 tasks. After task 2 completes, the test suite runs automatically and catches a regression. The agent fixes the failing test before proceeding to task 3. Without this checkpoint, tasks 3-5 would have built on a broken foundation, and the failure would only surface at verify/stamp.

**Why this priority**: This is the highest-value change because it prevents the most common failure mode: compounding breakage during implementation that only surfaces at the end.

**Independent Test**: Can be tested by running `/speckit-implement` on any project with a test suite and multiple tasks. Verify that tests run between tasks and that a failing test blocks progression.

**Acceptance Scenarios**:

1. **Given** a project with a test suite and a `tasks.md` with 3+ tasks, **When** `/speckit-implement` completes task N and the test suite passes, **Then** the agent proceeds to task N+1 without user intervention.
2. **Given** a project with a test suite and task N introduces a test failure, **When** the inter-task test checkpoint runs, **Then** the agent attempts to fix the failure before proceeding. If the fix succeeds within 2 attempts, the agent continues. If not, implementation pauses with a report of the failing tests.
3. **Given** a project where `implement.test_between_tasks` is set to `false` in `.specify/extensions/spex/spex-config.yml`, **When** `/speckit-implement` runs, **Then** no inter-task test checkpoints execute (existing behavior preserved).

---

### User Story 2 - Post-PR CI Monitoring Fixes Failures Autonomously (Priority: P1)

A developer runs `/speckit-spex-finish --watch` which creates a PR and then monitors CI. A CI check fails due to a linting error introduced by the implementation. The watch mode reads the CI failure log, applies the fix, pushes the commit, and continues monitoring until CI passes.

**Why this priority**: Equal priority with Story 1 because unattended PRs with failing CI are a real gap. CI monitoring is mechanical and high-value.

**Independent Test**: Can be tested by creating a PR on a project with CI configured, introducing a fixable CI failure, and verifying that watch mode detects and fixes it.

**Acceptance Scenarios**:

1. **Given** a PR was just created/pushed via `/speckit-spex-finish --watch`, **When** the watch loop polls `gh pr checks` and all checks pass, **Then** the watch loop reports success and cleans up state.
2. **Given** a PR with a failing CI check, **When** the watch loop detects the failure, **Then** it reads the failure log via `gh pr checks` and `gh run view`, attempts a fix, commits, and pushes. If the fix resolves the failure, monitoring continues. If not after 2 attempts, the watch loop pauses and reports the unresolvable failure.
3. **Given** a PR where CI checks are still pending, **When** the watch loop polls, **Then** it waits and polls again at the configured interval without taking action.
4. **Given** the watch timeout (default 30 minutes) has expired, **When** the watch loop checks, **Then** it exits cleanly, reports final CI status, and cleans up state regardless of CI outcome.

---

### User Story 3 - Watch Mode Integrates with Collab Triage (Priority: P2)

A developer has the `spex-collab` extension enabled and runs `/speckit-spex-finish --watch`. After CI passes, a CodeRabbit bot posts review comments. The watch loop detects the new comments and invokes the collab triage command to assess, apply valid fixes, reject invalid suggestions, and push the results.

**Why this priority**: This builds on Story 2 and requires the collab extension. It's high value for teams using bot reviewers but is an enhancement to the core CI monitoring.

**Independent Test**: Can be tested by enabling spex-collab, creating a PR, and verifying that watch mode invokes triage when new review comments appear.

**Acceptance Scenarios**:

1. **Given** spex-collab is enabled and a PR has new unresolved review comments, **When** the watch loop detects them, **Then** it invokes `/speckit-spex-collab-triage --pr <number>` and reports the triage summary.
2. **Given** spex-collab is NOT enabled and a PR has review comments, **When** the watch loop runs, **Then** it reports the comment count but does NOT attempt to triage them. It suggests enabling spex-collab for automated comment handling.
3. **Given** the watch loop has already triaged comments in a previous iteration, **When** no new comments have appeared since the last triage, **Then** it skips triage and only checks CI status.

---

### User Story 4 - State File Survives PR Creation in Watch Mode (Priority: P2)

A developer uses watch mode. The `.specify/.spex-state` file persists after PR creation with `mode: "watch"` instead of being cleaned up immediately. The state tracks the PR number, watch start time, and timeout. When the watch completes (success or timeout), the state file is cleaned up.

**Why this priority**: This is infrastructure that Stories 2 and 3 depend on, but it's not user-facing on its own.

**Independent Test**: Can be tested by running `/speckit-spex-finish --watch`, verifying the state file exists with `mode: "watch"` after PR creation, and verifying cleanup after watch completion.

**Acceptance Scenarios**:

1. **Given** `/speckit-spex-finish --watch` creates a PR, **When** the PR is successfully pushed, **Then** `.specify/.spex-state` is updated with `mode: "watch"`, `pr_number`, `watch_started_at`, and `watch_timeout_minutes`.
2. **Given** a state file with `mode: "watch"`, **When** the watch loop completes (CI passes, no pending comments, or timeout), **Then** the state file is removed and the status line disappears.
3. **Given** a state file with `mode: "watch"` and the user starts a new session, **When** they run `/speckit-spex-finish --watch --resume`, **Then** the watch loop resumes from the existing state (re-reads PR number, recalculates remaining timeout).

---

### Edge Cases

- What happens when the project has no test suite? The inter-task checkpoint is skipped with a warning ("No test command detected, skipping inter-task checks").
- What happens when `gh` CLI is not available during watch mode? Watch mode requires `gh`. If not available, report the error and fall back to non-watch finish behavior.
- What happens when the PR is closed or merged externally during watch? The watch loop detects this via `gh pr view --json state` and exits cleanly.
- What happens when CI checks are configured but none have started yet? The watch loop waits up to 5 minutes for checks to appear before reporting "No CI checks detected" and exiting.
- What happens when watch mode is used without `--create-pr`? Watch mode requires a PR. If finish merged directly to the default branch (no PR), `--watch` is ignored with a warning.
- What happens when a test checkpoint fix introduces new failures? The agent gets 2 fix attempts per checkpoint. After 2 failed attempts, implementation pauses with the test failure report.

## Requirements

### Functional Requirements

- **FR-001**: `/speckit-implement` MUST run the project's test suite after completing each task in `tasks.md`, before starting the next task.
- **FR-002**: The test command MUST be auto-detected from project structure (Makefile targets, package.json scripts, go.mod presence, pytest/cargo presence) using the same detection logic as the verify command.
- **FR-003**: If the inter-task test run fails, the agent MUST attempt to fix the failure (max 2 attempts) before either continuing (on success) or pausing implementation (on failure).
- **FR-004**: Inter-task test checkpoints MUST be disableable via `implement.test_between_tasks: false` in `.specify/extensions/spex/spex-config.yml`. The default MUST be `true`.
- **FR-005**: `/speckit-spex-finish` MUST accept a `--watch` flag that enters a post-PR monitoring loop instead of cleaning up state after PR creation.
- **FR-006**: The watch loop MUST poll CI status via `gh pr checks <PR_NUMBER>` at a configurable interval (default: 60 seconds).
- **FR-007**: On CI failure, the watch loop MUST read the failure details via `gh run view <RUN_ID> --log-failed`, attempt a fix, commit, and push.
- **FR-008**: The watch loop MUST respect a configurable timeout (default: 30 minutes) after which it exits regardless of CI state.
- **FR-009**: When spex-collab is enabled, the watch loop MUST invoke `/speckit-spex-collab-triage --pr <number>` when new unresolved review comments are detected.
- **FR-010**: When spex-collab is NOT enabled, the watch loop MUST NOT attempt review comment triage. It MUST only monitor CI status.
- **FR-011**: The `.specify/.spex-state` file MUST NOT be removed after PR creation when `--watch` is active. It MUST be updated with `mode: "watch"` and watch-specific metadata (PR number, start time, timeout).
- **FR-012**: The state file MUST be cleaned up when the watch loop exits (success, timeout, or error).
- **FR-013**: The watch loop MUST detect externally closed/merged PRs and exit cleanly.
- **FR-014**: The status line script (`spex-ship-statusline.sh`) MUST render watch mode state, showing PR number, elapsed time, and last CI status.
- **FR-015**: The ship pipeline (`/speckit-spex-ship`) MUST pass `--watch` through to the finish stage when `--create-pr` is also set.
- **FR-016**: `--watch` MUST work when pushing to an existing PR (Option B1 in finish), not only when creating a new PR. The watch loop reads the PR number from the push target.
- **FR-017**: Fix attempts during watch mode MUST be scoped to files included in the PR diff. The watch loop MUST NOT make changes outside the PR's changed file set.
- **FR-018**: When watch mode invokes collab triage, it MUST pass the current `ask` level from the ship pipeline state to control triage autonomy (autonomous in `smart`/`never`, interactive in `always`).

### Non-Functional Requirements

- **NFR-001**: The watch mode polling loop MUST NOT consume significant CPU while waiting. It MUST sleep between polls rather than busy-waiting.
- **NFR-002**: Inter-task test checkpoints MUST NOT add more than 10 seconds of overhead beyond the test suite's own execution time.
- **NFR-003**: The `.spex-state` file MUST remain under 1 KB during watch mode operations.

### Dependencies

- `gh` CLI (authenticated): Required for watch mode (PR checks, run logs, PR state). Already a dependency for finish PR creation.
- `spex-collab` extension (optional): Required only for Story 3 (review comment triage). Watch mode functions without it.
- Test detection logic from verify/stamp: Reused for inter-task checkpoints (FR-002).
- `.specify/.spex-state`: Extended with watch-mode fields; existing state management scripts handle read/write.

### Key Entities

- **Test Checkpoint**: A test suite execution between tasks during implementation. Has a result (pass/fail), fix attempts count, and associated task ID.
- **Watch Session**: A post-PR monitoring loop. Has a PR number, start time, timeout, poll interval, last CI status, and triage history.
- **Watch State**: Extension of `.specify/.spex-state` with `mode: "watch"` and watch-specific fields (`pr_number`, `watch_started_at`, `watch_timeout_minutes`, `last_ci_status`, `last_triage_at`).

## Success Criteria

### Measurable Outcomes

- **SC-001**: Implementation failures caused by compounding task breakage are detected before the next task begins, not at verify/stamp.
- **SC-002**: PRs created via `/speckit-spex-finish --watch` have CI failures detected and fix attempts made within 2 minutes of the failure appearing.
- **SC-003**: Watch mode reduces the manual intervention needed for CI fixes to zero for fixable failures. A failure is "fixable" when the fix requires only changes to files already in the PR diff and falls into one of these categories: linting violations, formatting issues, import ordering, minor test assertion updates, or missing type annotations.
- **SC-004**: The watch loop exits cleanly (no orphaned state, no zombie processes) in all termination scenarios: success, timeout, external PR close, and user interrupt.

## Assumptions

- Projects using inter-task checkpoints have a test suite that completes in a reasonable time (under 5 minutes). Projects with slower suites should opt out.
- The `gh` CLI is available and authenticated for watch mode. This is already a requirement for other spex features (finish PR creation, collab triage).
- CI checks appear on the PR within 5 minutes of pushing. If no checks appear, watch mode assumes no CI is configured.
- The watch loop runs within a single Claude Code session. Cross-session persistence (via `/loop` or cron) is used to keep the session alive but the watch logic itself is stateless between polls (reads state file each iteration).
- Fix attempts during watch mode are limited to files in the PR diff. The watch loop does not make architectural changes or touch files outside the changeset.

## Clarifications

### Session 2026-06-11

- Q: Should `--watch` work only when creating a new PR, or also when pushing to an existing PR? → A: Both. The watch loop reads the PR number from whichever path is taken (B1 existing or B2 new).
- Q: What is the scope of fix attempts during watch mode? → A: Limited to files in the PR diff. No changes outside the PR's changed file set.
- Q: When watch mode invokes collab triage, should triage run autonomously or interactively? → A: It inherits the current `ask` level from the ship pipeline state.
