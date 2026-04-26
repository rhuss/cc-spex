# Feature Specification: spex-collab Extension

**Feature Branch**: `018-collab-extension`
**Created**: 2026-04-26
**Status**: Draft

## User Scenarios & Testing

### User Story 1 - Spec PR with REVIEWERS.md (Priority: P1)

A developer finishes the specification phase (specify, plan, tasks) and wants to open a PR for team review. The extension generates a `REVIEWERS.md` that helps reviewers complete their review within 30 minutes, even for large specs.

**Why this priority**: This is the core value proposition. Without a reviewer guide, spec PRs get rubber-stamped or take hours.

**Independent Test**: After running `/speckit-tasks` with spex-collab enabled, `REVIEWERS.md` exists in the spec directory and contains sections for controversial points, key decisions, and scope boundaries.

**Acceptance Scenarios**:

1. **Given** spex-collab is enabled and spec phase completes, **When** review-plan hook fires, **Then** `REVIEWERS.md` is generated in the spec directory with a human-readable review guide.
2. **Given** the spec contains trade-off decisions from brainstorming, **When** REVIEWERS.md is generated, **Then** those trade-offs appear in the "Areas Needing Attention" section with context on why they might be controversial.
3. **Given** spex-collab is disabled, **When** review-plan hook fires, **Then** no `REVIEWERS.md` is generated (vanilla spec-kit behavior).

---

### User Story 2 - Phase-Based Implementation PRs (Priority: P1)

A developer starts implementation and the extension asks how to split the work into PRs based on task phases. Implementation pauses after each phase for PR creation before continuing.

**Why this priority**: Equally important as REVIEWERS.md. Large implementations become reviewable by splitting into focused PRs.

**Independent Test**: When `/speckit-implement` runs with spex-collab enabled (not in ship mode), the user is prompted to confirm or adjust the PR split before implementation begins, and implementation pauses after each phase.

**Acceptance Scenarios**:

1. **Given** spex-collab is enabled and tasks.md has phase markers, **When** `/speckit-implement` starts, **Then** the extension presents the proposed PR split based on task phases and asks the user to confirm or adjust.
2. **Given** the user confirms a 3-phase split, **When** phase 1 completes, **Then** code review gates run, REVIEWERS.md is updated with code-specific guidance, and the extension offers to create a PR.
3. **Given** the user confirms PR creation, **When** PR is created via `gh pr create`, **Then** the extension pauses and waits for the user to indicate the PR is merged before starting phase 2.
4. **Given** the ship pipeline is running (`.specify/.spex-state` with mode "ship"), **When** `/speckit-implement` runs, **Then** the extension is skipped entirely and implementation runs straight through.

---

### User Story 3 - Code PR with Updated REVIEWERS.md (Priority: P2)

After each implementation phase, the extension updates `REVIEWERS.md` with code-specific review guidance before offering PR creation.

**Why this priority**: Builds on Story 2. Code PRs need different review guidance than spec PRs.

**Independent Test**: After an implementation phase completes and review gates pass, `REVIEWERS.md` is updated with code-focused sections (compliance notes, areas of concern, what changed).

**Acceptance Scenarios**:

1. **Given** an implementation phase completes, **When** code review gate runs, **Then** `REVIEWERS.md` is updated with a section specific to this phase's changes.
2. **Given** a multi-phase implementation, **When** phase 2 completes, **Then** `REVIEWERS.md` reflects phase 2's changes without overwriting phase 1's content.

---

### Edge Cases

- What happens when tasks.md has no phase markers? Fall back to treating all tasks as a single phase (one PR for all implementation).
- What happens when the user wants to change the PR split mid-implementation? Allow re-grouping of remaining phases but not already-completed ones.
- What happens when a phase's code review finds critical issues? The fix loop runs within the phase before offering PR creation, same as current review-code behavior.
- What happens when the user declines PR creation after a phase? Continue to the next phase without creating a PR. The work accumulates for a later PR.

## Requirements

### Functional Requirements

- **FR-001**: Extension MUST generate `REVIEWERS.md` in the spec directory after the review-plan gate completes (spec phase).
- **FR-002**: Extension MUST update `REVIEWERS.md` in the spec directory after each implementation phase's review-code gate completes.
- **FR-003**: `REVIEWERS.md` MUST be a human-readable document aimed at PR reviewers, NOT a dump of automated review findings.
- **FR-004**: `REVIEWERS.md` for spec PRs MUST include: feature overview, scope boundaries, key decisions with trade-offs, areas needing attention (controversial points), and open questions.
- **FR-005**: `REVIEWERS.md` for code PRs MUST include: what changed in this phase, spec compliance notes, areas where the reviewer should focus, and any assumptions the AI made during implementation.
- **FR-006**: When the ship pipeline is running, the extension MUST be completely skipped (no REVIEWERS.md generation, no phase pausing, no PR assistance).
- **FR-007**: When spex-collab is disabled, it has no effect. No REVIEWERS.md is generated, no phase pausing occurs. Vanilla spec-kit behavior is preserved.
- **FR-008**: At the start of implementation (not in ship mode), the extension MUST present a PR split proposal based on task phases from tasks.md and allow the user to adjust groupings before proceeding.
- **FR-009**: The extension MUST hook into spec-kit's phase system transparently, so that `/speckit-implement` pauses between phases without requiring a separate wrapper command. The user calls `/speckit-implement` as normal; spex-collab intercepts at phase boundaries.
- **FR-010**: After each implementation phase completes and review gates pass, the extension MUST offer to create a PR via `gh pr create`, letting the user confirm or adjust before creating.
- **FR-011**: After PR creation, the extension MUST pause and wait for the user to indicate readiness (e.g., PR merged) before starting the next phase. The user resumes by responding in the conversation.
- **FR-012**: If tasks.md has no phase markers, the extension MUST treat all tasks as a single phase.

### Key Entities

- **REVIEWERS.md**: A human-readable review guide generated in the spec directory. Contains different content depending on whether it accompanies a spec PR or a code PR.
- **Phase Split Plan**: A grouping of tasks into PR-sized phases, derived from tasks.md phase markers and optionally adjusted by the user.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A reviewer unfamiliar with the feature can complete a spec PR review within 30 minutes using REVIEWERS.md as their primary guide.
- **SC-002**: Implementation PRs from phase splits contain focused, coherent changes that a reviewer can understand without reading the entire spec from scratch.
- **SC-003**: The extension adds no overhead to the ship pipeline (zero additional latency or artifacts when ship mode is active).
- **SC-004**: When the extension is disabled, vanilla spec-kit behavior is preserved with no additional artifacts.

## Extension Integration

### Lifecycle Hooks

The extension registers these hooks in its `extension.yml`:

- `after_tasks`: generates REVIEWERS.md for the spec PR (feature overview, scope, key decisions, controversial points)
- `before_implement`: presents the phase split proposal, asks user to confirm or adjust
- `after_implement_phase` (or equivalent spec-kit phase boundary hook): runs review gates, updates REVIEWERS.md with code guidance, offers PR creation, pauses for user

The exact hook names depend on what spec-kit's phase system exposes. If spec-kit does not provide a phase boundary hook, the extension command that wraps implementation will need to manage phase transitions internally while still being invoked transparently via `/speckit-implement`.

### Ship Mode Guard

All hooks check for `.specify/.spex-state` with `mode: "ship"`. If detected, the hook returns immediately without action.

## Assumptions

- Task phases in tasks.md are indicated by `[P]` markers or sequential grouping. The extension reads whatever phase structure spec-kit produces.
- `gh` CLI is available for PR creation. If not installed, the extension warns and skips PR creation (user creates manually).
- The spec directory path is resolvable from the current git branch name, consistent with existing spex conventions.
- The brainstorm command's `review_brief.md` concept is superseded by this extension's `REVIEWERS.md`. The brainstorm skill should be updated to remove review_brief generation.
