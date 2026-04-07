# Feature Specification: Flow Status Line

**Feature Branch**: `015-flow-status-line`
**Created**: 2026-04-07
**Status**: Draft
**Input**: User description: "Build on the status line used in spex:ship to show flow steps, current state, and next proposed step. Clear after final spex:stamp."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Manual Flow Progress Visibility (Priority: P1)

A developer runs speckit commands manually (specify, plan, tasks, implement) across multiple sessions. At any point, the status line shows which milestones have been completed and what the next logical step is, so they never lose track of progress.

**Why this priority**: This is the core value proposition. Without flow visibility, developers working outside of ship have no persistent indicator of where they are in the workflow.

**Independent Test**: Run `/speckit-specify` on a brainstorm file. Verify the status line appears showing spec as complete with plan as next step. Run `/speckit-plan`. Verify the status line updates to show both spec and plan complete with tasks as next step.

**Acceptance Scenarios**:

1. **Given** a project with spex initialized and no active pipeline, **When** the user runs `/speckit-specify`, **Then** the status line shows flow mode with spec marked as complete and plan as the next step.
2. **Given** a flow with spec.md and plan.md present, **When** the user starts a new Claude Code session on the same branch, **Then** the status line correctly reflects both milestones as complete (artifact-based detection, not session-dependent).
3. **Given** a flow with all milestones complete, **When** the user views the status line, **Then** it shows a "next: stamp" hint.

---

### User Story 2 - Review Checklist Tracking (Priority: P1)

A developer runs review skills in any order during their workflow. The status line shows which reviews have been completed as a checklist, independent of the linear milestone progression.

**Why this priority**: Reviews are quality gates that can be run in any order. Tracking them separately from milestones gives developers flexibility while ensuring visibility into what has been validated.

**Independent Test**: Run `/spex:review-spec` after creating a spec. Verify the status line shows the spec review as checked. Then run `/spex:review-code` (skipping review-plan). Verify the checklist shows spec and code reviews checked, plan review unchecked.

**Acceptance Scenarios**:

1. **Given** a flow with spec.md present, **When** the user runs `/spex:review-spec`, **Then** the status line review checklist shows the spec review as completed.
2. **Given** reviews can be run in any order, **When** the user runs `/spex:review-code` before `/spex:review-plan`, **Then** the checklist correctly shows code review checked and plan review unchecked.
3. **Given** all three reviews are completed, **When** the user views the status line, **Then** all three review checkboxes are marked.

---

### User Story 3 - REVIEWERS.md Split into Per-Review Artifacts (Priority: P1)

The current monolithic REVIEWERS.md is split into three separate files (REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md), each produced by its corresponding review skill. This enables clean binary artifact detection for the status line.

**Why this priority**: The status line depends on artifact-based detection. Without separate review files, there is no clean way to determine which reviews have been completed. This is a prerequisite for User Story 2.

**Independent Test**: Run `/spex:review-spec`. Verify it produces `REVIEW-SPEC.md` (not REVIEWERS.md). Verify old references to REVIEWERS.md in ship pipeline and state advancement scripts are updated.

**Acceptance Scenarios**:

1. **Given** a spec exists, **When** `/spex:review-spec` runs, **Then** it creates `REVIEW-SPEC.md` in the spec directory.
2. **Given** a plan and tasks exist, **When** `/spex:review-plan` runs, **Then** it creates `REVIEW-PLAN.md` in the spec directory.
3. **Given** implementation exists, **When** `/spex:review-code` runs, **Then** it creates `REVIEW-CODE.md` in the spec directory.
4. **Given** the ship pipeline is active, **When** review stages run, **Then** they produce the same split files (not a monolithic REVIEWERS.md).

---

### User Story 4 - Active Traits Display (Priority: P2)

A developer glances at the status line and immediately sees which spex traits are enabled (e.g., superpowers, worktrees, deep-review). This removes the need to check `spex-traits.json` or remember what was configured during init.

**Why this priority**: Trait configuration affects available quality gates and workflows. Making it visible prevents confusion when, for example, a developer wonders why review-plan was skipped (teams trait disabled) or why worktree isolation kicked in.

**Independent Test**: Enable superpowers and worktrees traits via `/spex:init`. Start a flow. Verify the status line shows both trait names. Disable worktrees. Verify the status line updates to show only superpowers.

**Acceptance Scenarios**:

1. **Given** a flow is active and traits are configured, **When** the status line renders, **Then** it shows the names of all enabled traits in a compact format.
2. **Given** no traits are enabled, **When** the status line renders, **Then** the traits section is omitted (no empty placeholder).
3. **Given** traits change between sessions (user runs `/spex:init` again), **When** the status line renders in the next session, **Then** it reflects the current trait configuration (reads fresh from config).
4. **Given** a ship pipeline is active and traits are configured, **When** the status line renders, **Then** it appends trait names after the ship progress display.

---

### User Story 5 - Ship Mode vs Flow Mode Distinction (Priority: P2)

The status line clearly distinguishes between ship mode (autonomous pipeline) and flow mode (manual workflow). Only one mode is active at a time. Ship mode retains its existing display; flow mode uses the new artifact-driven display.

**Why this priority**: Users need to immediately see which mode they are operating in. Ship has different guarantees (linear pipeline discipline, stage gates) than flow (flexible, user-driven).

**Independent Test**: Start a ship pipeline with `/spex:ship`. Verify the status line shows `spex:ship` with the progress bar. Then, in a separate project, run `/speckit-specify` manually. Verify the status line shows `spex` with milestone checkmarks.

**Acceptance Scenarios**:

1. **Given** no active pipeline or flow, **When** the user runs `/speckit-specify`, **Then** flow mode activates and the status line shows `spex` (without `:ship` suffix).
2. **Given** an active flow, **When** the user runs `/spex:ship`, **Then** the mode switches to ship and the status line changes to `spex:ship` with the progress bar.
3. **Given** a ship pipeline is active, **When** the user views the status line, **Then** it shows the ship-specific display (unchanged from current behavior).

---

### User Story 6 - Generalized State File (Priority: P2)

The `.spex-state` state file is generalized to support both ship and flow modes. In flow mode, the state file tracks mode and metadata while artifact detection drives progress display. In ship mode, it continues to drive stage progression.

**Why this priority**: A unified state file avoids maintaining two separate state mechanisms. The `mode` field enables the status line script to branch between display modes.

**Independent Test**: Run `/speckit-specify`. Verify `.spex-state` is created with `"mode": "flow"`. Run `/spex:ship`. Verify the state file has `"mode": "ship"` with all ship-specific fields.

**Acceptance Scenarios**:

1. **Given** no state file exists, **When** `/speckit-specify` runs, **Then** a state file is created with `"mode": "flow"`, `started_at`, and `feature_branch`.
2. **Given** a flow state file exists, **When** the user starts `/spex:ship`, **Then** the state file is replaced with ship mode fields.
3. **Given** a ship pipeline completes, **When** the state file is cleaned up, **Then** no state file remains (same as current behavior).

---

### User Story 7 - Completion Celebration (Priority: P3)

When stamp passes successfully, the system displays a celebration with an ASCII art banner, a stats summary (duration, reviews passed, commits), and a randomized sign-off message before clearing the state.

**Why this priority**: Adds a rewarding moment of closure after completing the full workflow. Lower priority because it is a polish feature that does not affect core functionality.

**Independent Test**: Complete a full flow (specify through stamp). Verify the celebration banner appears with correct stats. Run stamp again on the same branch. Verify no celebration (state already cleared).

**Acceptance Scenarios**:

1. **Given** all milestones and reviews are complete, **When** stamp passes, **Then** a celebration banner is displayed with an ASCII art header.
2. **Given** the celebration displays, **When** the stats summary renders, **Then** it shows feature name, duration (from state file `started_at` to now), reviews passed count, and commit count on the branch.
3. **Given** the celebration displays, **When** the sign-off renders, **Then** it shows one randomly selected message from a pool of at least 5 options.
4. **Given** the celebration has displayed, **When** the state file is checked, **Then** it has been removed.

---

### Edge Cases

- What happens when the user is on `main` branch with no feature branch? Status line does not appear.
- What happens when artifacts are deleted mid-flow (e.g., user deletes plan.md)? Status line reflects current artifact state, showing plan as incomplete.
- What happens when `/spex:evolve` modifies the spec after review-spec? The review artifact remains (stale review detection is out of scope for v1).
- What happens when the user switches branches? Status line updates based on the new branch's spec directory and artifacts.
- What happens when the spec directory cannot be determined? Status line does not display (silent degradation).
- What happens when a state file exists but its `spec_dir` points to a missing directory? Status line does not display.

## Requirements *(mandatory)*

### Functional Requirements

**Status Line Core**:

- **FR-001**: Status line script MUST detect the operating mode (ship vs flow) from the state file's `mode` field.
- **FR-002**: In flow mode, the status line MUST detect milestone completion from artifact file existence in the spec directory (spec.md, plan.md, tasks.md).
- **FR-003**: In flow mode, the status line MUST detect review completion from review artifact file existence (REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md).
- **FR-004**: In flow mode, the status line MUST display the next recommended step using this priority: (1) first incomplete milestone in order: specify, plan, tasks, implement; (2) if all milestones complete, first incomplete review in order: spec, plan, code; (3) if all milestones and reviews complete, "stamp".
- **FR-005**: In ship mode, the status line MUST retain its current behavior (stage name, progress bar, ask level).
- **FR-006**: The status line MUST produce no output when no state file exists.
- **FR-006a**: In flow mode, the status line MUST use a checkmark line format: completed milestones shown with ✓ (green), pending milestones with ○ (dim/gray), review status with abbreviated checkmarks (✓S/○P/○C), and the next recommended step highlighted. ANSI colors MUST match the spex:ship color scheme.
- **FR-007**: The status line script MUST complete within 500ms to avoid visible lag.

**State File**:

- **FR-008**: The state file (`.specify/.spex-state`) MUST include a `mode` field with value `"ship"` or `"flow"`.
- **FR-009**: In flow mode, the state file MUST include `started_at`, `feature_branch`, `spec_dir`, and optionally `brainstorm_file` fields.
- **FR-010**: `/speckit-specify` MUST create the state file with `"mode": "flow"` when no state file exists, or overwrite an existing flow state file (handles abandoned flows from previous sessions).
- **FR-011**: `/spex:ship` MUST create the state file with `"mode": "ship"` (overwriting any existing flow state).

**Review Artifact Split**:

- **FR-012**: `/spex:review-spec` MUST produce `REVIEW-SPEC.md` in the spec directory.
- **FR-013**: `/spex:review-plan` MUST produce `REVIEW-PLAN.md` in the spec directory.
- **FR-014**: `/spex:review-code` MUST produce `REVIEW-CODE.md` in the spec directory.
- **FR-015**: The ship pipeline's artifact validation (in `spex-ship-state.sh`) MUST check for the split review files instead of monolithic REVIEWERS.md.
- **FR-015a**: During transition, the artifact validation MUST accept both old format (REVIEWERS.md) and new format (REVIEW-*.md) to avoid breaking in-progress pipelines on existing branches.

**Trait Display**:

- **FR-023**: The status line MUST read enabled traits from `.specify/spex-traits.json` and display their names when a flow or ship state is active.
- **FR-024**: The trait display MUST only show traits whose value is `true` in the config file.
- **FR-025**: If no traits are enabled or the traits config file is missing, the traits section MUST be omitted from the status line.
- **FR-026**: The traits MUST be read fresh on each status line render (no caching across sessions) so that changes via `/spex:init` are reflected immediately.

**Flow Lifecycle**:

- **FR-016**: Flow mode MUST activate automatically when `/speckit-specify` creates the first spec artifact.
- **FR-017**: Flow mode MUST clear (state file removed) when `/spex:stamp` passes successfully.
- **FR-018**: Implementation completion MUST be tracked via an `"implemented": true` field in the state file, set by `/speckit-implement` on successful completion. If implementation is interrupted, the field remains absent or false.

**Celebration**:

- **FR-019**: When stamp passes, the system MUST display an ASCII art celebration banner.
- **FR-020**: The celebration MUST include a stats summary with feature name, duration, reviews passed, and commit count.
- **FR-021**: The celebration MUST include a randomly selected sign-off message from a pool of at least 5 messages.
- **FR-022**: After the celebration displays, the state file MUST be removed.

### Key Entities

- **State File** (`.specify/.spex-state`, renamed from `.spex-ship-phase`): JSON file tracking active mode, timestamps, and metadata. Source of truth for mode; supplements artifact detection in flow mode.
- **Milestone Artifacts**: spec.md, plan.md, tasks.md. Their existence signals completion of the corresponding workflow step.
- **Review Artifacts**: REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md. Their existence signals completion of the corresponding review.
- **Spec Directory**: Feature-specific directory under `specs/` containing all artifacts for a feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The status line displays current milestone completion, review checklist state, and next recommended step whenever a flow or ship state file exists.
- **SC-002**: The status line correctly reflects artifact state across session restarts (no session-dependent state lost).
- **SC-003**: Review skills can be run in any order and the status line accurately tracks which have been completed.
- **SC-004**: The status line script executes in under 500ms to avoid visible lag in the terminal.
- **SC-005**: The celebration display appears exactly once per successful stamp completion.
- **SC-006**: The status line displays currently enabled traits and updates when trait configuration changes between sessions.

## Clarifications

### Session 2026-04-07

- Q: What visual format should the flow mode status line use? → A: Checkmark line with ANSI colors (matching spex:ship color scheme). Format: `spex ✓spec ✓plan ✓tasks ○impl | reviews: ✓S ○P ○C | next: implement`. Completed items in green, pending in dim/gray, next step highlighted.
- Q: Should implementation completion use artifact-based detection like other milestones? → A: No. Keep state file field (`"implemented": true`). Implementation produces code changes across the repo with no single natural artifact to check.
- Q: Should traits be displayed in ship mode as well as flow mode? → A: Yes, both modes. Append traits after the existing ship/flow display.
- Q: Should the state file be renamed to reflect its generalized role? → A: Yes, rename from `.spex-state` to `.spex-state`.

## Assumptions

- The spec directory path can be reliably determined from the feature branch name or state file.
- The `jq` command-line tool is available for JSON parsing in the status line script.
- The status line rendering environment supports ANSI color codes and Unicode characters (emoji).
- Review skills will be updated to produce the split review files as part of this feature (not deferred).
- The ship pipeline's REVIEWERS.md references can be updated without breaking backward compatibility (no external tooling depends on REVIEWERS.md by name).
- The `.specify/spex-traits.json` file follows the existing schema with a `traits` object mapping trait names to boolean values.
- All existing references to `.spex-ship-phase` in ship scripts and overlays will be updated to `.spex-state` as part of this feature.
