# Feature Specification: Collab Triage Lifecycle

**Feature Branch**: `022-collab-triage-lifecycle`
**Created**: 2026-06-02
**Status**: Draft
**Input**: brainstorm/14-collab-triage-lifecycle.md

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Triage Spec PR Review Comments (Priority: P1)

A developer has created a spec PR via the collab workflow. After the PR is created, CodeRabbit and Copilot post review comments. The developer needs a structured way to triage these comments before deciding whether to continue on the same PR or split into separate spec and implementation PRs.

**Why this priority**: This is the core value proposition. Without the triage-spec phase, developers either ignore bot comments or manually process them without workflow guidance. The gate check after triage is the key decision point that prevents PRs from growing too large.

**Independent Test**: Can be tested by creating a spec PR on a repo with CodeRabbit/Copilot enabled, observing the triage suggestion message, running the triage loop, and verifying the gate check recommends same-PR or split based on comment count.

**Acceptance Scenarios**:

1. **Given** a spec PR was just created via the collab workflow (spex-collab enabled), **When** the PR creation completes, **Then** the flow state transitions to `triage-spec` and a suggestion message is displayed with a ready-to-paste `/loop` command using the configured interval.
2. **Given** the flow state is `triage-spec` and triage has completed, **When** the total review comment count is below the configured threshold (default 100), **Then** the gate check recommends continuing on the same PR and offers to update the title to "[Spec + Impl]" and update labels.
3. **Given** the flow state is `triage-spec` and triage has completed, **When** the total review comment count exceeds the configured threshold, **Then** the gate check recommends merging the spec PR as-is and creating separate implementation PR(s).

---

### User Story 2 - Triage Implementation PR Review Comments (Priority: P1)

A developer has pushed implementation code to a PR (same PR or new, depending on the gate check outcome). Bot reviewers post comments on the implementation. The developer needs the same structured triage flow for implementation reviews.

**Why this priority**: Equal to US1 because both triage phases use the same pattern. Without triage-impl, the implementation review comments get the same unstructured treatment that motivated this feature.

**Independent Test**: Can be tested by pushing implementation commits to a PR, observing the triage-impl suggestion message, running the triage loop, and verifying the status line reflects triage progress.

**Acceptance Scenarios**:

1. **Given** implementation has been pushed to a PR (collab enabled), **When** the push completes, **Then** the flow state transitions to `triage-impl` and a suggestion message is displayed with the `/loop` command.
2. **Given** the deep-review extension is enabled, **When** implementation is complete but not yet pushed, **Then** a deep review suggestion with delay is shown before the triage-impl suggestion.

---

### User Story 3 - Status Line Badge for Triage (Priority: P2)

A developer running the triage workflow needs visual feedback in the Claude Code status line showing whether triage is active, complete, or pending.

**Why this priority**: The status line provides at-a-glance workflow state. Without a triage badge, the developer has no visual indicator of triage progress, which is confusing when triage is a recognized workflow phase.

**Independent Test**: Can be tested by entering the triage-spec or triage-impl flow state and observing the status line output for the `T` badge with appropriate indicators (spinner/checkmark).

**Acceptance Scenarios**:

1. **Given** the flow state has `triage_spec_passed: false` and `running: "triage-spec"`, **When** the status line renders, **Then** a `T` badge with an active indicator (`▶`) is shown.
2. **Given** the flow state has `triage_spec_passed: true`, **When** the status line renders, **Then** a `T` badge with a checkmark (`✓`) is shown.
3. **Given** spex-collab is not enabled, **When** the status line renders, **Then** no `T` badge appears.

---

### User Story 4 - Configurable Triage Thresholds and Intervals (Priority: P3)

A project maintainer wants to customize the review comment threshold for the split recommendation and the default loop interval for triage suggestions, matching their team's review workflow.

**Why this priority**: Defaults work for most cases, but teams with different review cultures need tunability. Lower priority because the feature works without configuration.

**Independent Test**: Can be tested by setting custom values in `collab-config.yml` and verifying the gate check uses the custom threshold and the suggestion message shows the custom interval.

**Acceptance Scenarios**:

1. **Given** `collab-config.yml` has `triage.split_threshold: 50`, **When** the gate check runs after triage-spec with 60 review comments, **Then** the split recommendation is triggered (not the default 100).
2. **Given** `collab-config.yml` has `triage.loop_interval: "3m"`, **When** the triage suggestion message is displayed, **Then** it shows `/loop 3m /speckit-spex-collab-triage`.
3. **Given** `collab-config.yml` has no `triage` section, **When** the gate check and suggestion run, **Then** defaults of 100 and "5m" are used.

---

### Edge Cases

- What happens when the triage state file (`.specify/.pr-triage-state.json`) doesn't exist at gate check time? The gate check should treat this as 0 comments and recommend continuing on the same PR.
- What happens when spex-collab is disabled mid-workflow? The triage states should be skipped, and the flow should proceed directly to the next non-collab phase.
- What happens when the user runs triage manually without the flow state being in a triage phase? Triage should work normally (it's already a standalone command), but no flow state transition occurs.
- What happens when the PR has no review comments at all? The gate check should recommend continuing on the same PR (0 is below any threshold).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST add `triage-spec` and `triage-impl` as recognized phases in the flow state, tracked via `triage_spec_passed` and `triage_impl_passed` boolean fields in `.specify/.spex-state`.
- **FR-002**: System MUST only activate triage phases when the `spex-collab` extension is enabled in `.specify/extensions/.registry`. When spex-collab is not enabled, triage phases MUST be skipped entirely.
- **FR-003**: After a spec PR is created via the collab workflow, the system MUST transition the flow state to `triage-spec` and display a suggestion message with a delay notice and ready-to-paste `/loop` command.
- **FR-004**: After implementation is pushed to a PR via the collab workflow, the system MUST transition the flow state to `triage-impl` and display a suggestion message with a delay notice and ready-to-paste `/loop` command.
- **FR-005**: The suggestion message MUST include a notice that bot reviewers need 1-2 minutes to post comments and the `/loop` command with the configured interval.
- **FR-006**: The `/loop` interval in the suggestion MUST be read from `collab-config.yml` at `triage.loop_interval`, defaulting to `"5m"` if the key is missing or the config file doesn't exist.
- **FR-007**: Triage completion MUST be signaled by marking `triage_spec_passed: true` (or `triage_impl_passed: true`) in the flow state via `spex-flow-state.sh gate triage-spec` (or `gate triage-impl`). The user invokes the phase-manager manually after triage completes.
- **FR-008**: After triage-spec is marked complete, the phase-manager MUST read the triage state file (`.specify/.pr-triage-state.json`) and count total review comments handled.
- **FR-009**: The phase-manager MUST compare the comment count against `triage.split_threshold` from `collab-config.yml` (default 100).
- **FR-010**: When the comment count is below the threshold, the phase-manager MUST recommend continuing on the same PR, offering to update the PR title to include "[Spec + Impl]" and update labels.
- **FR-011**: When the comment count exceeds the threshold, the phase-manager MUST recommend merging the spec PR as-is and creating separate implementation PR(s). This MUST be a recommendation with user choice, not forced.
- **FR-012**: The status line script (`spex-ship-statusline.sh`) MUST display a `T` badge for triage state in `render_flow()`, using the same visual pattern as existing gates (`▶` when active, `✓` when complete, `○` when pending). This requires reading `triage_spec_passed` and `triage_impl_passed` from the state JSON and rendering them alongside the existing `C S P R` gate badges.
- **FR-013**: The `T` badge MUST only appear when the `spex-collab` extension is enabled (check `.specify/extensions/.registry` for `spex-collab` with `enabled: true`).
- **FR-014**: The flow state script (`spex-flow-state.sh`) MUST support new `gate triage-spec` and `gate triage-impl` actions in its `do_gate()` case statement to mark triage gates as passed, mapping to `triage_spec_passed` and `triage_impl_passed` fields respectively.
- **FR-015**: When the deep-review extension is enabled, the system MUST show a deep review suggestion with delay before the triage-impl suggestion, after implementation is complete but before pushing to the PR.
- **FR-016**: The `collab-config.yml` template MUST include `triage.split_threshold` (default 100) and `triage.loop_interval` (default "5m") entries.
- **FR-017**: The existing triage command (`/speckit-spex-collab-triage`) MUST NOT be modified. The new work is about when and how it's invoked in the workflow.
- **FR-018**: The existing implementation phase-split (`before_implement` hook) MUST NOT be modified.

### Key Entities

- **Flow State** (`.specify/.spex-state`): Extended with `triage_spec_passed` and `triage_impl_passed` boolean fields, and `triage-spec`/`triage-impl` as valid `running` phase values.
- **Triage State** (`.specify/.pr-triage-state.json`): Existing file, read by the gate check to count handled comments. Not modified by this feature.
- **Collab Config** (`.specify/extensions/spex-collab/collab-config.yml`): Extended with `triage.split_threshold` and `triage.loop_interval` entries.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a spec PR is created with collab enabled, the developer sees a triage suggestion within the PR creation output, without having to remember or look up the triage command.
- **SC-002**: The gate check after triage-spec correctly distinguishes between PRs that should continue (< threshold comments) and PRs that should split (>= threshold comments) based on the configured threshold.
- **SC-003**: The status line accurately reflects triage state (pending, active, complete) using the `T` badge whenever collab is enabled.
- **SC-004**: A developer using the collab workflow can complete the full lifecycle (specify → triage-spec → gate check → plan → implement → triage-impl) without leaving the spex workflow or manually tracking triage state.
- **SC-005**: Projects without spex-collab enabled experience no workflow changes; triage phases are entirely invisible.

## Clarifications

### Session 2026-06-02

- Q: How does the phase-manager know triage-spec is complete? → A: The triage command (or user) marks `triage_spec_passed: true` in the flow state via `spex-flow-state.sh gate triage-spec`. Phase-manager checks this field before running the gate check. Consistent with existing gate pattern.
- Q: Who triggers the gate check after triage-spec? → A: The user invokes phase-manager manually after triage completes. Consistent with the suggest-with-delay pattern (user-driven transitions, not automatic).

## Assumptions

- The triage command (`/speckit-spex-collab-triage`) already works correctly for both bot and human comment handling. This feature only adds lifecycle integration, not triage functionality.
- The `.specify/.pr-triage-state.json` file contains enough information (handled comment entries) to derive a total comment count for the gate check.
- The phase-manager already has the infrastructure to read collab state and create/manage PRs. The gate check extends this existing capability.
- The suggest-with-delay pattern is sufficient; auto-starting triage is not needed because bots need time to post reviews.
- The `T` badge uses the same rendering pattern as existing gates (`C`, `S`, `P`, `R`) in the statusline script, requiring only additive changes.
