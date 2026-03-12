# Feature Specification: SDD Command Consolidation

**Feature Branch**: `003-command-consolidation`
**Created**: 2026-02-13
**Status**: Draft
**Input**: User description: "Command Consolidation: remove sdd wrapper commands, redistribute discipline into trait overlays"
**Depends On**: `002-traits-infrastructure` (traits infrastructure must be implemented first)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Specify with SDD Trait Active (Priority: P1)

A user runs `/speckit.specify` in a project with the `sdd` trait enabled. The spec-kit command executes normally, and at the end the SDD quality gate fires automatically: it checks constitution alignment and invokes `sdd:review-spec` to validate completeness. The user never needs to know about `/sdd:spec` because the discipline is embedded in the command they already use.

**Why this priority**: This is the primary use case that replaces `/sdd:spec`. If `/speckit.specify` with the sdd trait does not deliver the same quality gates, users lose discipline when the wrapper commands are removed.

**Independent Test**: Enable the sdd trait, run `/speckit.specify` with a feature description. Verify the spec is created and that a spec review gate runs automatically after spec creation.

**Acceptance Scenarios**:

1. **Given** a project with the `sdd` trait enabled (overlay applied to `speckit.specify.md`), **When** the user runs `/speckit.specify "Add user authentication"`, **Then** spec-kit creates the spec normally, and after completion the SDD overlay invokes `{Skill: sdd:review-spec}` to validate the spec, and checks `.specify/memory/constitution.md` for alignment if it exists.

2. **Given** a project with no traits enabled, **When** the user runs `/speckit.specify`, **Then** spec-kit creates the spec normally with no additional quality gates (baseline spec-kit behavior).

---

### User Story 2 - Implement with Beads Trait Active (Priority: P1)

A user runs `/speckit.implement` in a project with both `sdd` and `beads` traits enabled. The SDD overlay adds pre-implementation verification (spec package exists) and post-implementation review. The beads overlay routes execution through beads-driven task management: bootstrapping beads issues from tasks.md, using `bd ready` to get unblocked tasks, and syncing state back.

**Why this priority**: This replaces the most complex wrapper, `/sdd:implement`, which currently handles both SDD discipline and beads integration. Both overlays must work together on the same target command.

**Independent Test**: Enable both traits, create a complete spec package (spec.md, plan.md, tasks.md), then run `/speckit.implement`. Verify that beads issues are created from tasks, the `bd ready` loop drives execution, and post-implementation review fires.

**Acceptance Scenarios**:

1. **Given** a project with `sdd` and `beads` traits enabled and a complete spec package, **When** the user runs `/speckit.implement`, **Then** the SDD overlay verifies the spec package exists before implementation starts, and after implementation completes, invokes `{Skill: sdd:review-code}` and `{Skill: sdd:verification-before-completion}`.

2. **Given** a project with the `beads` trait enabled and a complete spec package, **When** the user runs `/speckit.implement`, **Then** the beads overlay delegates execution to `{Skill: sdd:beads-execute}` which bootstraps beads issues from tasks.md, uses `bd ready --json` for task scheduling, and runs `bd sync` for state persistence.

3. **Given** a project with only the `sdd` trait enabled (beads disabled), **When** the user runs `/speckit.implement`, **Then** only SDD quality gates (pre/post verification) are applied, with no beads integration.

---

### User Story 3 - Plan with SDD Trait Active (Priority: P1)

A user runs `/speckit.plan` in a project with the `sdd` trait enabled. The SDD overlay validates the spec before planning, then after plan and task generation, invokes `sdd:review-plan` to check coverage matrix, red flags, and task quality. The user gets the same discipline that `/sdd:plan` previously provided, without needing a separate command.

**Why this priority**: This replaces `/sdd:plan`. The plan validation logic (coverage matrix, red flag scanning, task quality enforcement) is substantial and must not be lost when the wrapper is removed.

**Independent Test**: Enable the sdd trait, create a spec, run `/speckit.plan`. Verify that spec review runs before planning and that `sdd:review-plan` runs after task generation.

**Acceptance Scenarios**:

1. **Given** a project with the `sdd` trait enabled, **When** the user runs `/speckit.plan`, **Then** the SDD overlay first invokes `{Skill: sdd:review-spec}` to validate the spec, then the base plan is generated, then `/speckit.tasks` runs to generate the task breakdown, and finally `{Skill: sdd:review-plan}` validates coverage matrix, red flags, task quality, and generates `review-summary.md`.

2. **Given** a project with no traits enabled, **When** the user runs `/speckit.plan`, **Then** spec-kit generates the plan normally with no additional quality gates.

---

### User Story 4 - Updated Help Shows Unified Workflow (Priority: P2)

A user runs `/sdd:help` and sees a workflow diagram that shows `/speckit.*` as the core workflow with SDD helpers alongside (review-spec, review-plan, review-code, brainstorm, evolve). The old wrapper commands (`/sdd:spec`, `/sdd:plan`, `/sdd:implement`) no longer appear. The `/sdd:traits` command is listed for discipline configuration.

**Why this priority**: Help documentation must reflect the new architecture. Without updated help, users will try to use removed commands and get confused.

**Independent Test**: Run `/sdd:help` and verify the output shows `/speckit.*` as primary workflow commands, lists `/sdd:traits` and `/sdd:review-plan`, and does not list `/sdd:spec`, `/sdd:plan`, or `/sdd:implement`.

**Acceptance Scenarios**:

1. **Given** the command consolidation is complete, **When** the user runs `/sdd:help`, **Then** the workflow diagram shows `/speckit.specify`, `/speckit.plan`, `/speckit.implement` as the main workflow steps, with `/sdd:brainstorm`, `/sdd:review-spec`, `/sdd:review-plan`, `/sdd:review-code`, `/sdd:evolve`, `/sdd:traits` as helper commands alongside.

2. **Given** the command consolidation is complete, **When** the user runs `/sdd:help`, **Then** the commands `/sdd:spec`, `/sdd:plan`, `/sdd:implement` do not appear anywhere in the output.

---

### User Story 5 - Existing User Upgrades (Priority: P2)

An existing user who previously used `/sdd:spec`, `/sdd:plan`, and `/sdd:implement` upgrades to the new version. The old commands are gone. When they run `/sdd:help`, they see clear guidance pointing to `/speckit.*` commands with `/sdd:traits` for discipline configuration. The `using-superpowers-sdd` routing skill no longer routes to removed commands.

**Why this priority**: Smooth upgrade path prevents user frustration. Without clear migration guidance, existing users will be lost.

**Independent Test**: Verify that the command files for `sdd:spec`, `sdd:plan`, `sdd:implement` no longer exist in the plugin. Verify `using-superpowers-sdd` SKILL.md no longer references them.

**Acceptance Scenarios**:

1. **Given** a user who previously used `/sdd:spec`, **When** they upgrade to the consolidated version, **Then** the command file `sdd/commands/spec.md` no longer exists, and `/sdd:help` points them to `/speckit.specify` with the sdd trait enabled.

2. **Given** a user who previously used `/sdd:implement`, **When** they upgrade and run `/sdd:help`, **Then** they see guidance to use `/speckit.implement` with traits enabled for quality gates, and `/sdd:traits` to configure which discipline overlays are active.

3. **Given** the `using-superpowers-sdd` SKILL.md, **When** the upgrade is complete, **Then** the workflow decision tree routes to `/speckit.*` commands instead of removed `/sdd:*` wrappers, and references `/sdd:traits` for trait management.

---

### Edge Cases

- What happens if a user tries to run a removed command (e.g., `/sdd:spec`)? Claude Code will report that the command does not exist. The `/sdd:help` output provides migration guidance.
- What happens when both sdd and beads overlays target the same file (e.g., `speckit.implement.md`)? Both overlays are appended sequentially, each with its own sentinel marker. They coexist without conflict because each overlay block is self-contained.
- What happens if a user has beads trait enabled but the beads plugin is not installed? The beads overlay references `{Skill: sdd:beads-execute}` which will report that beads CLI (`bd`) is not available and suggest installation steps.
- What happens to existing spec packages created with old commands? They remain valid. The spec format is unchanged; only the command entry points change.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST remove the following command files from the SDD plugin: `sdd/commands/spec.md`, `sdd/commands/plan.md`, `sdd/commands/implement.md`.
- **FR-002**: System MUST remove the following skill files from the SDD plugin: `sdd/skills/spec/SKILL.md`, `sdd/skills/plan/SKILL.md`, `sdd/skills/implement/SKILL.md`.
- **FR-003**: System MUST retain the following commands and skills:
  - **Commands**: `sdd:brainstorm`, `sdd:review-spec`, `sdd:review-code`, `sdd:evolve`, `sdd:constitution`, `sdd:help`, `sdd:init`, `sdd:traits`.
  - **Retained skills (unchanged purpose)**: `sdd:review-spec`, `sdd:review-code`, `sdd:brainstorm`, `sdd:evolve`, `sdd:constitution`, `sdd:verification-before-completion`, `sdd:spec-kit` (infrastructure), `sdd:spec-refactoring`.
  - **New**: `sdd:review-plan` (command + skill), `sdd:beads-execute` (skill only).
- **FR-004**: System MUST provide an sdd trait overlay for `speckit.specify` that invokes `{Skill: sdd:review-spec}` and checks constitution alignment after spec creation.
- **FR-005**: System MUST provide an sdd trait overlay for `speckit.plan`. The overlay text is appended to the command file, so the agent reads base instructions plus overlay before executing. The overlay uses instruction ordering to specify timing:
  - "Before generating the plan": invoke `{Skill: sdd:review-spec}` to validate the spec is sound.
  - "After the plan is generated": instruct the agent to also run `/speckit.tasks`, then invoke `{Skill: sdd:review-plan}` for post-planning validation.
  - This ensures a single `/speckit.plan` invocation produces the full pipeline: spec review, plan generation, task generation, and plan quality validation.
- **FR-006**: System MUST provide an sdd trait overlay for `speckit.implement` that verifies spec package completeness before implementation and invokes `{Skill: sdd:review-code}` and `{Skill: sdd:verification-before-completion}` after implementation.
- **FR-007**: System MUST provide a beads trait overlay for `speckit.implement` that delegates execution to a new `{Skill: sdd:beads-execute}` skill for beads-driven task management.
- **FR-008**: System MUST provide a beads trait overlay for the tasks template. The overlay target filename should be discovered by matching against available templates in `.specify/templates/` (the current template is `tasks-template.md`). The overlay adds beads usage instructions (how to use `bd` commands, the memory model, discovered work tracking).
- **FR-009**: System MUST create a new `sdd:beads-execute` skill containing the beads execution logic (previously in `sdd:implement` SKILL.md): beads bootstrapping, `bd ready` loop, `bd sync`, discovered work tracking.
- **FR-010**: System MUST update `sdd/commands/help.md` and `sdd/skills/help/SKILL.md` to reflect the consolidated architecture:
  - Show `/speckit.specify`, `/speckit.plan`, `/speckit.implement` as the primary workflow.
  - List SDD helpers alongside: `/sdd:brainstorm` (ideation), `/sdd:review-spec` (spec validation), `/sdd:review-plan` (plan validation), `/sdd:review-code` (code compliance), `/sdd:evolve` (drift reconciliation).
  - List configuration commands: `/sdd:traits`, `/sdd:init`, `/sdd:constitution`.
  - Remove all references to `/sdd:spec`, `/sdd:plan`, `/sdd:implement`.
  - The "SDD vs spec-kit" comparison table is replaced by a single workflow description since SDD traits now augment spec-kit directly.
  - Include a brief migration note for users upgrading from the old command structure.
- **FR-011**: System MUST update `sdd/skills/using-superpowers-sdd/SKILL.md` to route to `/speckit.*` commands instead of removed wrappers, and reference `/sdd:traits` for trait configuration.
- **FR-012**: Each overlay file MUST be under 20 lines and delegate to existing skills rather than inlining discipline logic.
- **FR-013**: System MUST create a new `sdd:review-plan` command and skill that provides post-planning quality validation:
  - Coverage matrix (requirement to task to test mapping)
  - Red flag scanning (vague language, TBD items, missing file paths)
  - Task quality enforcement (Actionable, Testable, Atomic, Ordered)
  - NFR validation (concrete measurement methods, acceptance thresholds)
  - Error/edge case coverage check (every spec error/edge case addressed in plan)
  - Generate `review-summary.md` in the spec directory: distilled decision points, scope boundaries, critical decisions, areas of potential disagreement, naming decisions, schema definitions, open questions, and risk areas for stakeholder review.
  - This skill extracts the post-planning validation logic and review summary generation from the current `sdd:plan` SKILL.md (sections 5-8). It MUST only run after both plan.md and tasks.md exist.
- **FR-014**: System MUST update cross-references in all retained skills to point to `/speckit.*` commands instead of removed `/sdd:*` wrappers. Specifically:
  - `sdd:brainstorm` SKILL.md: Replace "offer `sdd:plan` or `sdd:implement`" with "offer `/speckit.plan` or `/speckit.implement`"
  - `sdd:evolve` SKILL.md: Replace "Use `sdd:spec`" with "Use `/speckit.specify`"
  - `sdd:review-spec` SKILL.md: Replace "Proceed with `sdd:implement`" with "Proceed with `/speckit.implement`", replace "Use `sdd:spec`" with "Use `/speckit.specify`"
  - `sdd:review-code` SKILL.md: Replace "Use `sdd:spec`" with "Use `/speckit.specify`"
  - `sdd:verification-before-completion` SKILL.md: Replace "As final gate in `sdd:implement`" with "As final gate in `/speckit.implement` (via sdd trait overlay)", replace "Use `sdd:spec`" with "Use `/speckit.specify`"
  - `sdd:spec-kit` SKILL.md: Replace "Use `sdd:spec`" with "Use `/speckit.specify`", update integration points list
  - `sdd:spec-refactoring` SKILL.md: No references to removed commands (no changes needed)
  - `sdd:help` SKILL.md: Replace "Try `/sdd:implement`" with "Try `/speckit.implement`" in tutorial next steps

### Key Entities

- **Overlay** (sdd trait, commands): Small markdown fragments appended to `/speckit.specify`, `/speckit.plan`, and `/speckit.implement` command files. Each contains a sentinel marker and `{Skill:}` delegation references.
- **Overlay** (beads trait, commands): Markdown fragment appended to `/speckit.implement` that delegates to `sdd:beads-execute` for beads-driven task execution.
- **Overlay** (beads trait, templates): Markdown fragment appended to the tasks template explaining beads usage for task management. Target file discovered dynamically from `.specify/templates/`.
- **`sdd:review-plan` Command/Skill**: New command and skill extracted from the current `sdd:plan` SKILL.md. Contains coverage matrix validation, red flag scanning, task quality enforcement, NFR validation, error/edge case coverage checks, and `review-summary.md` generation. Invoked by the sdd trait overlay for `/speckit.plan` after task generation. Requires both plan.md and tasks.md to exist before running.
- **`sdd:beads-execute` Skill**: New skill extracted from the current `sdd:implement` SKILL.md. Contains beads bootstrapping, `bd ready` scheduling loop, `bd sync` state persistence, and discovered work tracking.
- **Removed Commands**: `sdd:spec`, `sdd:plan`, `sdd:implement` command and skill files. Their discipline logic is redistributed into trait overlays that delegate to retained skills (`sdd:review-spec`, `sdd:review-plan`, `sdd:review-code`, `sdd:verification-before-completion`, `sdd:beads-execute`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `/speckit.specify` with the sdd trait enabled produces the same spec quality validation (review gate) that `/sdd:spec` previously provided.
- **SC-002**: Running `/speckit.implement` with both sdd and beads traits enabled provides the same pre/post quality gates and beads execution that `/sdd:implement` previously provided.
- **SC-003**: Running `/speckit.plan` with the sdd trait enabled produces spec validation before planning and coverage/quality validation after, matching what `/sdd:plan` previously provided.
- **SC-004**: The command files `sdd/commands/spec.md`, `sdd/commands/plan.md`, `sdd/commands/implement.md` and corresponding skill files no longer exist in the plugin.
- **SC-005**: The `/sdd:help` output shows `/speckit.*` as primary workflow, lists `/sdd:traits` and `/sdd:review-plan`, and does not reference `/sdd:spec`, `/sdd:plan`, or `/sdd:implement`.
- **SC-006**: The `using-superpowers-sdd` SKILL.md workflow decision tree routes to `/speckit.*` commands and references `/sdd:traits`.
- **SC-007**: All overlay files are under 20 lines each and contain `{Skill:}` delegation references rather than inlined discipline logic.
- **SC-008**: The `sdd:beads-execute` skill exists and contains the beads execution loop logic previously housed in `sdd:implement` SKILL.md.
- **SC-009**: The `sdd:review-plan` command and skill exist and contain the plan quality validation logic (coverage matrix, red flags, task quality, NFR validation) and `review-summary.md` generation previously housed in `sdd:plan` SKILL.md.
- **SC-010**: No retained skill file contains references to `sdd:spec`, `sdd:plan`, or `sdd:implement` as callable commands. All cross-references point to `/speckit.*` equivalents.
