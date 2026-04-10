# Feature Specification: Replace Traits with Spec-Kit Extensions

**Feature Branch**: `016-traits-to-extensions`
**Created**: 2026-04-09
**Status**: Draft
**Input**: User description: "Replace the spex traits system with spec-kit extensions for agent portability, upstream alignment, and architectural simplification"

## User Scenarios & Testing

### User Story 1 - Initialize Project with Extensions (Priority: P1)

A developer runs `/spex:init` on a new or existing project. The init process installs spec-kit, then installs the bundled spex extensions (spex, spex-gates, spex-worktrees, spex-teams, spex-deep-review) from the plugin's local extension directory. After init completes, extension commands are registered with the active AI agent and hooks are wired into the spec-kit lifecycle.

**Why this priority**: Without initialization working, nothing else functions. This is the foundation that replaces `spex-traits.sh apply` and the overlay machinery.

**Independent Test**: Run `/spex:init` on a fresh project. Verify that `.specify/extensions/` contains all five extensions, that `.specify/extensions.yml` has the correct hooks registered, and that agent-specific command files exist (e.g., `.claude/commands/speckit.spex.brainstorm.md`).

**Acceptance Scenarios**:

1. **Given** a project with no `.specify/` directory, **When** the user runs `/spex:init`, **Then** `specify init` runs, all five extensions are installed from the plugin's bundled path, hooks are registered in `.specify/extensions.yml`, and agent commands are created.
2. **Given** a project with an existing `.specify/` from a previous version (with `spex-traits.json`), **When** the user runs `/spex:init`, **Then** the old traits config is ignored, extensions are installed fresh, and the project works with the new system.
3. **Given** a project where init has already run with extensions, **When** the user runs `/spex:init` again, **Then** extensions are updated/reinstalled without duplication or error.

---

### User Story 2 - Quality Gates Fire Automatically via Hooks (Priority: P1)

A developer runs the spec-kit workflow (`/speckit.specify` then `/speckit.plan` then `/speckit.implement`). When the spex-gates extension is enabled, review commands fire automatically at lifecycle boundaries: `review-spec` after specify, `review-plan` after plan, `review-code` and `verify` after implement. The developer does not need to invoke review commands manually.

**Why this priority**: Quality gates are the most-used trait functionality. They must work reliably through the hook system to validate that extensions can replace traits.

**Independent Test**: Enable spex-gates extension. Run `/speckit.specify` with a feature description. Verify that `speckit.spex-gates.review-spec` fires automatically after the spec is written.

**Acceptance Scenarios**:

1. **Given** spex-gates is enabled, **When** `/speckit.specify` completes, **Then** `speckit.spex-gates.review-spec` runs automatically as an `after_specify` hook.
2. **Given** spex-gates is enabled, **When** `/speckit.plan` completes, **Then** `speckit.spex-gates.review-plan` runs automatically as an `after_plan` hook.
3. **Given** spex-gates is enabled, **When** `/speckit.implement` completes, **Then** `speckit.spex-gates.review-code` and `speckit.spex-gates.verify` run automatically as `after_implement` hooks in that order.
4. **Given** spex-gates is disabled, **When** any spec-kit command runs, **Then** no review hooks fire and no review-related commands appear in the agent's skill list.

---

### User Story 3 - Enable and Disable Extensions (Priority: P2)

A developer enables or disables optional extensions (spex-gates, spex-worktrees, spex-teams, spex-deep-review) using `specify extension enable/disable`. Disabling an extension removes its commands from the agent, deactivates its hooks, and removes its generated skills. Enabling reinstates everything.

**Why this priority**: Granular control over which features are active is core to the user experience. This replaces the current `spex-traits.sh enable/disable` workflow.

**Independent Test**: Disable spex-teams extension. Verify that `speckit.spex-teams.orchestrate` no longer appears as an available command. Re-enable and verify it returns.

**Acceptance Scenarios**:

1. **Given** spex-teams is enabled, **When** the user runs `specify extension disable spex-teams`, **Then** teams commands are unregistered from the agent, teams hooks are deactivated, and teams skill files are removed.
2. **Given** spex-teams is disabled, **When** the user runs `specify extension enable spex-teams`, **Then** teams commands are re-registered, hooks are reactivated, and skill files are regenerated.
3. **Given** spex-deep-review is disabled, **When** `/speckit.implement` runs, **Then** only spex-gates hooks fire (if enabled), not deep-review hooks.

---

### User Story 4 - Ship Pipeline with Extensions (Priority: P2)

A developer runs `speckit.spex.ship` for autonomous end-to-end workflow. Ship sequences the core spec-kit commands (specify, plan, tasks, implement) and lets hooks handle quality gates. Ship skips clarify (autonomous mode assumes the spec is ready). Ship sets `.spex-state` for autonomous context and creates a PR at the end.

**Why this priority**: The ship pipeline is the highest-value orchestration feature. It must work cleanly with hook-driven quality gates instead of overlay-injected instructions.

**Independent Test**: Run `/speckit.spex.ship` with a brainstorm document. Verify the full pipeline executes: specify (with review-spec hook), plan (with review-plan hook), tasks, implement (with review-code and verify hooks), and PR creation.

**Acceptance Scenarios**:

1. **Given** a brainstorm document and all extensions enabled, **When** the user runs `/speckit.spex.ship`, **Then** the pipeline runs specify, plan, tasks, implement in sequence, quality gate hooks fire at each boundary, clarify is skipped, and a PR is created.
2. **Given** ship is running, **When** spex-gates hooks fire, **Then** they detect autonomous mode (via `.spex-state`) and run without prompting for user input.
3. **Given** ship is running with spex-teams enabled, **When** implement begins, **Then** the `before_implement` hook analyzes tasks and pre-empts with parallel team orchestration if 2+ independent tasks exist.

---

### User Story 5 - Teams Pre-emption via Hook (Priority: P3)

A developer has spex-teams enabled. When `/speckit.implement` starts, the `before_implement` hook from spex-teams reads `tasks.md`, determines if 2+ independent tasks exist, and if so, pre-empts the standard implement flow with parallel team orchestration. If tasks are sequential or only one exists, implement proceeds normally.

**Why this priority**: This is the most complex behavioral pattern to migrate from overlays to hooks. It validates that the "pre-emption" pattern works as a replacement for in-context behavioral injection.

**Independent Test**: Create a tasks.md with 3 independent tasks. Enable spex-teams. Run `/speckit.implement`. Verify that the teams hook intercepts and spawns parallel agents instead of sequential implementation.

**Acceptance Scenarios**:

1. **Given** spex-teams is enabled and tasks.md has 3 independent tasks, **When** `/speckit.implement` starts, **Then** the `before_implement` hook pre-empts with `speckit.spex-teams.orchestrate`, which spawns parallel agents.
2. **Given** spex-teams is enabled and tasks.md has 1 task, **When** `/speckit.implement` starts, **Then** the `before_implement` hook passes through and implement runs normally.
3. **Given** spex-teams is disabled, **When** `/speckit.implement` starts, **Then** no teams hook fires and implement runs normally.

---

### User Story 6 - Worktree Creation via Hook (Priority: P3)

A developer has spex-worktrees enabled. After `/speckit.specify` completes (and review-spec fires if spex-gates is enabled), the `after_specify` hook from spex-worktrees optionally creates a git worktree for the feature branch, restores main in the original repo, and prints instructions for switching.

**Why this priority**: Worktree creation is a straightforward after-hook pattern. Lower priority because it's a convenience feature, not a quality gate.

**Independent Test**: Enable spex-worktrees. Run `/speckit.specify`. Verify the worktree creation prompt appears after specify and review-spec complete.

**Acceptance Scenarios**:

1. **Given** spex-worktrees is enabled, **When** `/speckit.specify` completes, **Then** the user is prompted to create a worktree (optional hook).
2. **Given** the user accepts the worktree prompt, **Then** a git worktree is created in a sibling directory, main is restored in the original repo, and instructions are displayed.
3. **Given** spex-worktrees is disabled, **When** `/speckit.specify` completes, **Then** no worktree prompt appears.

---

### Edge Cases

- What happens when `specify extension add` fails during init (e.g., extension manifest validation error)? Init should report the failure but continue installing remaining extensions.
- What happens when multiple `after_implement` hooks exist from different extensions (spex-deep-review and spex-gates)? They must execute sequentially in manifest registration order.
- What happens when a user has the old traits system (`.specify/spex-traits.json`) and runs the new init? The old config is ignored; extensions are installed fresh.
- What happens when the `before_implement` hook from spex-teams pre-empts but teams orchestration fails? The failure should be reported and the user can retry or run implement without teams.

## Requirements

### Functional Requirements

- **FR-001**: System MUST create five spec-kit extensions (spex, spex-gates, spex-worktrees, spex-teams, spex-deep-review) with valid `extension.yml` manifests.
- **FR-002**: Each extension MUST provide commands following the `speckit.{ext-id}.{command}` naming pattern.
- **FR-003**: Extensions with lifecycle hooks MUST register them in `.specify/extensions.yml` with correct event names, optional/mandatory flags, and descriptions.
- **FR-004**: The `spex-init.sh` script MUST install all bundled extensions from the plugin's local extension directory using `specify extension add <path> --dev`.
- **FR-005**: The spex core extension MUST always be installed during init. Optional extensions (spex-gates, spex-worktrees, spex-teams, spex-deep-review) MUST be installed by default but can be disabled after init.
- **FR-006**: Disabling an extension via `specify extension disable` MUST remove its commands from the agent, deactivate its hooks, and remove its generated skill files.
- **FR-007**: The ship command (`speckit.spex.ship`) MUST sequence core spec-kit commands (specify, plan, tasks, implement), skip clarify, set `.spex-state` for autonomous mode, and create a PR on completion.
- **FR-008**: The spex-teams `before_implement` hook MUST analyze `tasks.md` for independent tasks and pre-empt the implement step with parallel orchestration when 2+ independent tasks exist.
- **FR-009**: The old overlay system (overlays directory, `spex-traits.sh`, sentinel markers) MUST be removed entirely.
- **FR-010**: The old skills directory and commands directory in the plugin MUST be removed, with all functionality migrated to extension commands.
- **FR-011**: Multiple hooks on the same lifecycle event MUST execute sequentially in the order they appear in `.specify/extensions.yml`.
- **FR-012**: The constitution MUST be updated to remove references to overlay delegation (section II), trait composability (section III), and overlay application constraints, replacing them with extension-based architecture descriptions.

### Key Entities

- **Extension**: A spec-kit extension with manifest, commands, and optional hooks. Installed in `.specify/extensions/{ext-id}/`.
- **Extension Command**: A markdown file defining an AI agent command. Registered in agent-specific directories (e.g., `.claude/commands/`).
- **Lifecycle Hook**: A before/after trigger on a spec-kit command that invokes an extension command. Configured in `.specify/extensions.yml`.
- **Extension Config**: Per-extension YAML configuration in `.specify/extensions/{ext-id}/{ext-id}-config.yml` with layered overrides.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All four current trait capabilities (quality gates, worktrees, teams, deep-review) function identically through the extension system as they did through overlays.
- **SC-002**: The cc-spex plugin codebase is reduced by removing all overlay files, `spex-traits.sh`, plugin skills directory, and plugin commands directory.
- **SC-003**: Extension commands work with at least two AI agents (Claude Code and one other, e.g., Codex) without agent-specific code in the extensions.
- **SC-004**: Enabling and disabling extensions produces zero context pollution (disabled extension commands do not appear in the agent's available commands).
- **SC-005**: The ship pipeline completes autonomously end-to-end with hook-driven quality gates, no manual intervention required.
- **SC-006**: Integration tests (`make release`) pass with the new extension-based architecture, validating that all commands, hooks, and skills are correctly installed.

## Assumptions

- Spec-kit's `specify extension add <local-path> --dev` command works reliably for installing from bundled paths within a plugin directory.
- Spec-kit guarantees sequential execution of multiple hooks on the same lifecycle event in manifest order.
- The `before_implement` hook mechanism allows a hook command to effectively pre-empt (replace) the standard implement behavior when teams orchestration is triggered.
- Users accept the namespace change from `/spex:*` to `/speckit.spex*.*` commands.
- The current spec-kit version (0.5.2+) supports all required extension features (hooks with conditions, multiple hooks per event, skill auto-generation).
- The constitution update (removing overlay/trait sections, adding extension architecture) is within scope of this feature.
