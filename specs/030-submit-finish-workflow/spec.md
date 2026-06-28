# Feature Specification: Post-Implementation Workflow Redesign (Submit + Finish)

**Feature Branch**: `030-submit-finish-workflow`
**Created**: 2026-06-28
**Status**: Draft
**Input**: Brainstorm 25 — streamline post-implementation UX with two distinct commands

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Submit work for PR review (Priority: P1)

After completing implementation and code review stages, the user wants to put their work up for external review via a pull request. They run a single command that verifies the code, commits outstanding changes, and creates the PR automatically.

**Why this priority**: This is the primary path for collaborative development — most features go through PR review before landing.

**Independent Test**: Can be tested by completing any implementation on a feature branch and running the submit command to create a PR.

**Acceptance Scenarios**:

1. **Given** a feature branch with completed implementation and passing tests, **When** the user runs `/speckit-spex-submit`, **Then** automated verification gates run (tests, spec compliance, drift check), outstanding changes are committed, and a PR is created with a spec-linked body referencing REVIEWERS.md.
2. **Given** a feature branch where a PR already exists, **When** the user runs `/speckit-spex-submit`, **Then** the command detects the existing PR, pushes new commits to it, and reports the PR URL.
3. **Given** a fork-based workflow with an `upstream` remote, **When** the user runs `/speckit-spex-submit`, **Then** the PR is created against the upstream repository.
4. **Given** the user passes `--watch`, **When** the PR is created, **Then** the command enters a triage polling loop that monitors CI status and invokes `/speckit-spex-collab-triage` when review comments appear.

---

### User Story 2 - Finish and land code after reviews (Priority: P1)

After PR reviews are resolved (or for direct merge without a PR), the user wants to land their code on main with a clean commit history. They run a single command that handles the smoke test gate, squashes commits, merges, and cleans up the worktree.

**Why this priority**: This is the completion step — every feature must land eventually, whether via PR merge or direct merge.

**Independent Test**: Can be tested by having an approved PR (or a feature branch ready for direct merge) and running the finish command.

**Acceptance Scenarios**:

1. **Given** a feature branch with an approved PR and a previously passed smoke test (no new commits since), **When** the user runs `/speckit-spex-finish`, **Then** the smoke test is skipped, commits are squashed into one with a conventional commit message, the user approves/edits the message, the branch is force-pushed, and the PR is merged.
2. **Given** a feature branch with a passed smoke test but new commits since, **When** the user runs `/speckit-spex-finish`, **Then** the user is warned about staleness ("smoke test passed at commit X but Y commits added since") and can choose to re-run or skip.
3. **Given** a feature branch with no prior smoke test, **When** the user runs `/speckit-spex-finish`, **Then** the interactive smoke test runs before proceeding to squash and merge.
4. **Given** a feature branch with no PR (direct merge path), **When** the user runs `/speckit-spex-finish`, **Then** the smoke test runs, commits are squashed, and the branch is merged directly to main.
5. **Given** a worktree-based development setup after merge completes, **When** the user is prompted for worktree cleanup, **Then** they see what will happen (remove worktree, delete branch, sync main) and must confirm before proceeding.
6. **Given** a PR where the user lacks merge permissions, **When** the user runs `/speckit-spex-finish`, **Then** commits are squashed and force-pushed, and the user is informed the branch is ready for the upstream maintainer to merge.

---

### User Story 3 - Ship pipeline end-of-pipeline handoff (Priority: P2)

After the ship pipeline completes its automated stages (specify through review-code), it presents the user with a choice of how to proceed rather than silently stopping.

**Why this priority**: This bridges the automated pipeline and the manual completion steps, making the transition explicit.

**Independent Test**: Can be tested by running a ship pipeline to completion and observing the end-of-pipeline prompt.

**Acceptance Scenarios**:

1. **Given** the ship pipeline completes Stage 7 (review-code), **When** the pipeline finishes, **Then** the user is presented with three options: "Submit PR", "Merge directly", or "Stop here".
2. **Given** the user selects "Submit PR", **When** the choice is made, **Then** the submit logic runs (verify, create PR) and the pipeline ends.
3. **Given** the user selects "Merge directly", **When** the choice is made, **Then** the finish logic runs (smoke test, squash, merge, cleanup) and the pipeline ends.
4. **Given** the user selects "Stop here", **When** the choice is made, **Then** the pipeline ends and the user is told to run `/speckit-spex-submit` or `/speckit-spex-finish` later.

---

### User Story 4 - Squash with conventional commit message (Priority: P2)

When landing code, the user wants a clean, well-formatted commit message that follows conventional commit conventions, generated from the spec and implementation context.

**Why this priority**: Clean commit history matters for maintainability but is not a blocking workflow concern.

**Independent Test**: Can be tested by running finish on any feature branch and reviewing the generated commit message.

**Acceptance Scenarios**:

1. **Given** a feature branch with multiple commits, **When** finish squashes the commits, **Then** the commit title follows conventional commit format (e.g., `feat(extensions): add hot-reload support`) and the body summarizes the spec and key changes.
2. **Given** a generated commit message, **When** it is presented to the user, **Then** the user can approve it as-is or edit it before the squash happens.
3. **Given** the squash is approved, **When** the branch is force-pushed, **Then** the PR shows a single clean commit ready for merge.

---

### Edge Cases

- What happens when verification gates fail during submit? Submit stops and reports the failures; the PR is not created.
- What happens when the smoke test fails during finish? Finish stops after the smoke test; no squash or merge occurs. The user fixes issues and re-runs finish.
- What happens when force-push after squash fails (e.g., branch protection)? Finish reports the error and suggests the user check branch protection settings.
- What happens when `gh pr merge` fails due to required reviews or CI checks? Finish reports the failure and suggests waiting for required checks or requesting reviews.
- What happens when there are uncommitted changes in the worktree during cleanup? A rescue commit is created before worktree removal, and the user is warned.
- What happens when the user runs submit on main branch? Submit detects this and stops with an error: "Cannot submit from the default branch."
- What happens when the user runs finish with no feature branch? Finish detects this and stops with an error: "No feature branch detected."
- What happens when the `gh` CLI is not installed? Submit detects this and stops with a clear error: "The gh CLI is required for PR operations. Install it from https://cli.github.com/"
- What happens when finish is run while a watch loop from submit is still active? Finish warns the user that a watch loop may still be running, but does not block — the user may have cancelled the watch and is proceeding manually.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a `/speckit-spex-submit` command that verifies code, commits outstanding changes, and creates a PR.
- **FR-002**: The system MUST provide a redesigned `/speckit-spex-finish` command that handles smoke test gating, commit squashing, PR merging, and worktree cleanup.
- **FR-003**: Submit MUST run automated verification gates (tests, spec compliance, drift check) before creating a PR.
- **FR-004**: Submit MUST detect existing PRs for the current branch and push to them instead of creating duplicates.
- **FR-005**: Submit MUST handle fork workflows by detecting `upstream` remote and creating PRs against it.
- **FR-006**: Submit MUST support a `--watch` flag that enters a triage polling loop after PR creation.
- **FR-006a**: Submit MUST execute `before_submit` hooks (from `.specify/extensions.yml`) before verification, following the same hook pattern as other speckit commands.
- **FR-006b**: Finish MUST support a `--no-smoke-test` flag that explicitly skips the smoke test gate.
- **FR-007**: Finish MUST check smoke test state before proceeding: skip if passed with no new commits, warn if stale, run if never executed.
- **FR-008**: Finish MUST record the commit hash when a smoke test passes, enabling staleness detection. The smoke test state is stored via the existing `spex-ship-state.sh smoke-test-record` command in `.specify/.spex-state`.
- **FR-009**: Finish MUST squash all feature branch commits into a single commit with a conventional commit message title.
- **FR-010**: Finish MUST present the generated commit message to the user for approval or editing before squashing.
- **FR-011**: Finish MUST force-push the squashed branch after user approval.
- **FR-012**: Finish MUST offer PR merge via `gh pr merge` when the user has merge permissions.
- **FR-013**: Finish MUST handle the case where the user lacks merge permissions by informing them the branch is ready for upstream merge.
- **FR-014**: Finish MUST handle direct merge (no PR) by merging the feature branch to main locally.
- **FR-015**: Finish MUST prompt for worktree cleanup (never automatic), showing what will happen before proceeding.
- **FR-016**: Finish MUST create a rescue commit if uncommitted changes exist in the worktree during cleanup.
- **FR-017**: Finish MUST remove `.specify/.spex-state` and dismiss the status line after completion.
- **FR-018**: The ship pipeline MUST replace Stage 8 (smoke-test) with an end-of-pipeline choice prompt. The pipeline reduces from 9 stages (0-8) to 8 stages (0-7), and the choice prompt runs after the final stage completes. The three options are: "Submit PR", "Merge directly", "Stop here".
- **FR-019**: The smoke test MUST move from being a ship pipeline stage into finish as a pre-landing gate. The ship pipeline no longer invokes or references the smoke test.
- **FR-019a**: Submit's `--watch` flag is the canonical watch mode. Finish does NOT have a `--watch` flag. Watch mode (triage polling, CI monitoring, auto-fix) lives exclusively in submit.
- **FR-020**: The squash commit message title MUST follow conventional commit format: `<type>(<scope>): <description>`.
- **FR-021**: The squash commit message body MUST summarize the spec and key changes, followed by the `Assisted-By: 🤖 Claude Code` tagline.

### Key Entities

- **Submit Command**: New command (`/speckit-spex-submit`) that handles PR creation workflow.
- **Finish Command**: Redesigned command (`/speckit-spex-finish`) that handles code landing workflow.
- **Smoke Test State**: Record of smoke test result including commit hash, pass/fail status, and scenario counts.
- **Ship Pipeline End-Stage**: The choice prompt that replaces the current Stage 8 smoke test in the ship pipeline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users complete the post-implementation workflow using at most two commands (submit + finish) instead of running the same command multiple times with unpredictable behavior.
- **SC-002**: Every feature branch lands on main as a single squashed commit with a conventional commit message.
- **SC-003**: The smoke test gates code landing (finish) rather than PR creation (submit), ensuring quality checks happen before code reaches main.
- **SC-004**: Worktree cleanup never happens without explicit user confirmation.
- **SC-005**: The ship pipeline transitions to user-controlled completion without requiring the user to remember which command to run — it tells them.
- **SC-006**: Users who lack merge permissions can still squash their branch and have it ready for upstream merge in a single finish invocation.

## Smoke Test

1. Run `/speckit-spex-submit` on a feature branch and verify the PR is created with correct title, body, and labels
2. Run `/speckit-spex-finish` with no prior smoke test and verify it triggers the interactive smoke test before proceeding to squash
3. Run `/speckit-spex-finish` after the smoke test passed, verify the squash commit message is generated in conventional commit format, approve it, and confirm the branch is force-pushed with a single clean commit

## Assumptions

- The `gh` CLI is installed and authenticated for PR operations.
- Git is configured with push access to the remote repository (or fork).
- The existing verification gate infrastructure (`/speckit-spex-gates-verify`) remains unchanged — submit reuses it.
- The existing smoke test infrastructure (`/speckit-spex-smoke-test`) remains unchanged — finish invokes it.
- The existing triage infrastructure (`/speckit-spex-collab-triage`) remains unchanged — submit's watch mode invokes it.
- Conventional commit types (feat, fix, refactor, docs, chore, etc.) are well-understood by users.
- The `spex-ship-state.sh` script already supports smoke test state recording via `smoke-test-record` command.
