# Feature Specification: Teams Trait Consolidation

**Feature Branch**: `006-teams-trait-consolidation`
**Created**: 2026-03-09
**Status**: Draft
**Input**: User description: "Consolidate teams-vanilla and teams-spec into a single teams trait with spec guardian as default pattern"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single Teams Trait Activation (Priority: P1)

As a project maintainer, I want to enable a single `teams` trait that provides the full spec guardian workflow (parallel spawning + spec compliance review), so that I don't have to understand or choose between two separate traits.

**Why this priority**: This is the core value proposition. The current dual-trait setup causes confusion and leads to both traits being ignored entirely, resulting in no parallel orchestration at all.

**Independent Test**: Can be fully tested by enabling the `teams` trait on a project with multiple implementation tasks and verifying that teammates are spawned in worktrees with spec compliance review before merge.

**Acceptance Scenarios**:

1. **Given** a project with no teams traits enabled, **When** the user runs `/sdd:traits` and enables `teams`, **Then** the trait is activated and the implement skill includes the consolidated teams orchestration instructions.
2. **Given** a project with the `teams` trait active, **When** the implement skill is invoked with 2+ independent tasks, **Then** the system delegates to the unified orchestration skill that spawns teammates in worktrees and reviews their work against spec.md before merging.
3. **Given** a project with the old `teams-vanilla` trait configured, **When** trait loading occurs, **Then** the system resolves the alias to the new `teams` trait and activates the consolidated behavior.

---

### User Story 2 - Decision Gate Enforcement (Priority: P1)

As a developer using SDD, I want the implement skill to enforce Agent Teams usage when multiple independent tasks exist, so that the model cannot silently fall back to regular background agents.

**Why this priority**: The observed failure mode shows that advisory instructions get ignored under cognitive load. Without enforcement, the consolidation provides no reliability improvement.

**Independent Test**: Can be tested by invoking the implement skill with 3+ tasks and verifying the decision gate fires before any direct implementation begins.

**Acceptance Scenarios**:

1. **Given** the `teams` trait is active and 2+ independent tasks exist, **When** the implement skill is invoked, **Then** the decision gate at the top of the skill checks for Agent Teams availability and delegates to the orchestration skill before any implementation begins.
2. **Given** the `teams` trait is active but the Agent Teams environment variable is not set, **When** the implement skill is invoked with multiple tasks, **Then** the system informs the user that the environment variable must be set and stops execution.
3. **Given** the `teams` trait is active and only 1 task exists, **When** the implement skill is invoked, **Then** the decision gate allows direct implementation without teams orchestration.

---

### User Story 3 - Backward-Compatible Migration (Priority: P2)

As a project maintainer with existing `teams-vanilla` or `teams-spec` trait configurations, I want the system to gracefully migrate to the new `teams` trait, so that my existing projects continue to work without manual reconfiguration.

**Why this priority**: Existing projects should not break when upgrading. However, this is secondary to getting the core consolidation right.

**Independent Test**: Can be tested by configuring a project with `teams-vanilla` and/or `teams-spec` in the trait config and verifying that both resolve to the consolidated `teams` trait behavior.

**Acceptance Scenarios**:

1. **Given** a project with `teams-vanilla` in its trait configuration, **When** traits are loaded, **Then** the system treats it as an alias for `teams` and activates the consolidated behavior.
2. **Given** a project with `teams-spec` in its trait configuration, **When** traits are loaded, **Then** the system treats it as an alias for `teams` and activates the consolidated behavior.
3. **Given** a project with both `teams-vanilla` and `teams-spec` in its trait configuration, **When** traits are loaded, **Then** the system activates only the single `teams` trait without duplication or conflict.

---

### User Story 4 - Anti-Pattern Detection (Priority: P3)

As a developer, I want the system to detect when the model uses regular background agents instead of Agent Teams during multi-task implementation, so that the failure mode observed in practice is surfaced rather than silently degrading quality.

**Why this priority**: This is a safety net for the decision gate. If the model somehow bypasses the gate, detection provides a second chance to correct course.

**Independent Test**: Can be tested by simulating a scenario where the model attempts to use the `Agent` tool with `run_in_background` during an active implement session with the `teams` trait enabled.

**Acceptance Scenarios**:

1. **Given** the `teams` trait is active and multi-task implementation is in progress, **When** the model attempts to use `Agent` with `run_in_background`, **Then** the PreToolUse hook blocks the call and directs the model to use Agent Teams instead.

---

### Edge Cases

- What happens when the Agent Teams environment variable becomes unset mid-session (e.g., user restarts without it)?
- How does the system behave when only 1 of 3 tasks is independent and the other 2 are sequential?
- What happens when a teammate's worktree has merge conflicts with another teammate's changes?
- Vanilla-only orchestration (without spec review) is explicitly not supported. The spec guardian pattern is always-on by design, as it is strictly better than unreviewed parallel implementation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a single `teams` trait that combines the parallel task spawning capability (from teams-vanilla) with the spec guardian review pattern (from teams-spec).
- **FR-002**: System MUST recognize `teams-vanilla` and `teams-spec` as aliases that resolve to the consolidated `teams` trait.
- **FR-003**: When both old trait names are configured, the system MUST activate only one instance of the consolidated trait without duplicating instructions.
- **FR-004**: The implement skill MUST include a decision gate at the top (not buried in trait blocks) that enforces Agent Teams usage when 2+ independent tasks are present.
- **FR-005**: The decision gate MUST check for the Agent Teams environment variable and halt execution with a clear message if it is not set.
- **FR-006**: The consolidated orchestration skill MUST perform task graph analysis, spawn teammates in git worktrees, review each teammate's work against spec.md, and only merge compliant changes.
- **FR-007**: The `sdd:teams-research` skill MUST remain separate and unaffected by the consolidation, as it serves a different use case (parallel codebase research during planning).
- **FR-008**: When only a single task exists (no parallelism opportunity), the system MUST allow direct implementation without requiring Agent Teams.
- **FR-009**: The system MUST enforce Agent Teams usage via a PreToolUse hook that blocks `Agent` tool calls with `run_in_background` when the `teams` trait is active during multi-task implementation, combined with prompt-level guidance text in the implement skill overlay.
- **FR-010**: The system MUST display a deprecation notice when old trait names (`teams-vanilla`, `teams-spec`) are used, directing the user to use `teams` instead.

### Key Entities

- **Teams Trait**: The consolidated trait configuration that activates the spec guardian orchestration pattern for parallel task implementation.
- **Decision Gate**: A mandatory checkpoint at the top of the implement skill that determines whether Agent Teams should be used based on task count and independence.
- **Orchestration Skill**: The unified `sdd:teams-orchestrate` skill that handles task graph analysis, teammate spawning, spec compliance review, and merge coordination.
- **Trait Alias**: A mapping from old trait names to the consolidated trait, ensuring backward compatibility during migration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Projects with the `teams` trait active correctly use Agent Teams for multi-task implementation in 100% of cases where 2+ independent tasks exist (eliminating the observed fallback to regular background agents).
- **SC-002**: Users can activate the teams capability by enabling a single trait, reducing configuration complexity from 2 traits to 1.
- **SC-003**: Existing projects with `teams-vanilla` or `teams-spec` configurations continue to function correctly after the consolidation, with zero manual reconfiguration required.
- **SC-004**: The decision gate prevents implementation from proceeding without Agent Teams when multiple independent tasks exist, catching the failure mode within the first 30 seconds of the implement skill invocation.
- **SC-005**: All teammates' work is reviewed against spec.md before merge, with non-compliant changes rejected and flagged for revision.

## Clarifications

### Session 2026-03-09

- Q: Should the decision gate be a hook (hard enforcement) or prompt injection (soft guidance)? → A: Hook + prompt: PreToolUse hook blocks `Agent` with `run_in_background` when teams trait is active, plus prompt text for guidance.
- Q: Should users be able to opt out of spec review (vanilla-only mode)? → A: No. Spec guardian review is always-on with no opt-out. Vanilla-only orchestration is not supported.

## Assumptions

- The Agent Teams experimental feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) will remain available and stable.
- The `sdd-traits.sh` script and trait infrastructure (from spec 002) supports trait aliasing or can be extended to support it.
- Worktree-based isolation (from teams-spec) is the correct approach for all parallel implementation scenarios.
- The minimum threshold for mandatory teams usage is 2+ independent tasks (tasks with no dependencies between them).
- Hook-based enforcement via PreToolUse is the chosen mechanism for the decision gate, combined with prompt-level guidance in the implement skill overlay.

## Scope

### In Scope

- Consolidating `teams-vanilla` and `teams-spec` into a single `teams` trait
- Merging `sdd:teams-spec-guardian` into `sdd:teams-orchestrate`
- Adding a decision gate to the implement skill
- Backward-compatible alias support for old trait names
- Anti-pattern detection for regular background agent usage

### Out of Scope

- Changes to `sdd:teams-research` (stays separate)
- Changes to the beads bridge mechanism (used as-is)
- Agent Teams runtime behavior or the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` feature itself
- Removal of old trait name aliases (planned for a future release cycle)
