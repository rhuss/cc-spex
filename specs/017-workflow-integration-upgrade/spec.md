# Feature Specification: Leverage Spec-Kit 0.7.x Workflows and Integrations

**Feature Branch**: `016-traits-to-extensions`
**Created**: 2026-04-18
**Status**: Draft
**Input**: User description: "Improve the traits-to-extensions migration by leveraging spec-kit 0.7.x workflow engine, native integration management, and plugin ecosystem detection"

## User Scenarios & Testing

### User Story 1 - Ship Pipeline as Declarative Workflow (Priority: P1)

A developer runs `/spex:ship` (or `specify workflow run spex-ship`) to execute the full SDD cycle autonomously. Instead of a 788-line procedural command, the pipeline is defined as a declarative workflow YAML. The workflow engine handles state tracking, stage sequencing, and resume after interruption. The developer can check pipeline status with `specify workflow status` and resume interrupted runs with `specify workflow resume`.

**Why this priority**: Ship is the highest-value orchestration feature and the largest chunk of custom code being replaced. The workflow engine eliminates custom state management, resume logic, and stage sequencing.

**Independent Test**: Run `specify workflow run spex-ship -i spec="Add user authentication"`. Verify the pipeline creates a spec, runs review-spec gate, plans, runs review-plan gate, generates tasks, implements, runs review-code, and verifies. Interrupt mid-run with Ctrl+C, then run `specify workflow resume` and verify it picks up from the interrupted stage.

**Acceptance Scenarios**:

1. **Given** a brainstorm document and all extensions enabled, **When** the user runs `specify workflow run spex-ship -i spec="brainstorm/08-feature.md" -i ask=smart`, **Then** the workflow executes all stages in order (specify, review-spec, plan, review-plan, tasks, implement, review-code, verify) with oversight gates behaving according to the `ask` level.
2. **Given** a running ship workflow, **When** the user interrupts it (Ctrl+C or session disconnect), **Then** `specify workflow status` shows the current stage and `specify workflow resume` continues from where it stopped.
3. **Given** the `ask` input is `never`, **When** review gate steps are reached, **Then** they auto-approve without pausing (unambiguous and ambiguous findings are auto-fixed, only blockers pause).
4. **Given** the `ask` input is `smart`, **When** a review gate step encounters ambiguous findings, **Then** the gate pauses with approve/reject options and presents findings. Unambiguous findings are auto-fixed.
5. **Given** the `ask` input is `always`, **When** any review gate step is reached, **Then** the gate pauses for user approval regardless of finding severity.
6. **Given** spex-teams is enabled and tasks.md has 2+ independent tasks, **When** the implement step runs, **Then** the workflow routes to `speckit.spex-teams.implement` for parallel orchestration.
7. **Given** the `create_pr` input is `true` and all stages pass, **When** the workflow completes, **Then** a pull request is created with the spec, plan, and review artifacts linked.

---

### User Story 2 - Simplified Init with Native Integration Management (Priority: P1)

A developer runs `/spex:init` on a new or existing project. The init process uses `specify integration install` for agent-specific setup (skill files, directory mapping) and `specify extension add` for bundled spex extensions. The init script is a thin wrapper (~100 lines) with no legacy migration code.

**Why this priority**: Init is the entry point for every project. Simplifying it reduces maintenance burden and aligns with upstream spec-kit's native capabilities.

**Independent Test**: Run `/spex:init` on a fresh project with no `.specify/` directory. Verify that `specify integration install claude` sets up agent-specific files, all five extensions are installed, and the project is ready for `/speckit.specify`.

**Acceptance Scenarios**:

1. **Given** a project with no `.specify/` directory, **When** the user runs `/spex:init`, **Then** `specify init` runs, `specify integration install` sets up agent files, all five extensions are installed from the plugin's bundled path, and the project is ready.
2. **Given** a project with spec-kit already initialized but extensions outdated, **When** the user runs `/spex:init --refresh`, **Then** extensions are reinstalled and agent integration is upgraded via `specify integration upgrade`.
3. **Given** a project with old traits config (`.specify/spex-traits.json`), **When** the user runs `/spex:init`, **Then** the old config is ignored silently (no migration, no warning since we're past the transition period).
4. **Given** the `specify` CLI is not installed, **When** the user runs `/spex:init`, **Then** a clear installation command is shown and the process exits.
5. **Given** the `specify` CLI version is below 0.7.4, **When** the user runs `/spex:init`, **Then** an upgrade command is shown and the process exits.

---

### User Story 3 - Plugin Ecosystem Detection (Priority: P2)

A developer has companion plugins installed (prose, copyedit, etc.). During init, spex detects these plugins and records their availability. Extension commands can then conditionally invoke plugin capabilities, for example running `prose:check` on spec content during review.

**Why this priority**: Plugin detection makes the ecosystem composable. It's not required for core functionality but significantly enhances quality gates when companion plugins are available.

**Independent Test**: Install the prose plugin at `~/.claude/plugins/cc-prose`. Run `/spex:init`. Verify that `.specify/spex-plugins.json` records prose as available. Then run `/speckit.specify` followed by review-spec and verify that prose:check is invoked on the spec content.

**Acceptance Scenarios**:

1. **Given** a plugin mapping file (`spex/plugin-integrations.yml`) defines the prose plugin with detection path `~/.claude/plugins/cc-prose`, **When** `/spex:init` runs and that path exists, **Then** `.specify/spex-plugins.json` records prose as available with its skills and injection targets.
2. **Given** prose is recorded as available, **When** the `review-spec` command runs, **Then** it includes the instruction "Run prose:check on spec content before accepting" as defined in the mapping file.
3. **Given** a plugin path does not exist (e.g., copyedit is not installed), **When** `/spex:init` runs, **Then** that plugin is recorded as unavailable and its injection targets are not applied.
4. **Given** the plugin mapping file defines a new plugin, **When** `/spex:init` runs, **Then** the new plugin is detected without code changes to the init script.
5. **Given** `.specify/spex-plugins.json` exists from a previous init, **When** `/spex:init` runs again, **Then** the plugin state is refreshed (plugins added or removed since last init are reflected).

---

### User Story 4 - Hook and Workflow Gate Coordination (Priority: P2)

A developer runs spec-kit commands both inside and outside the ship workflow. When running ad-hoc commands (e.g., `/speckit.specify` directly), spex-gates hooks fire automatically for quality discipline. When running inside the ship workflow, the workflow's own gate steps handle review checkpoints and hooks suppress to avoid double-reviewing.

**Why this priority**: Without coordination, review steps would fire twice during ship (once from hooks, once from workflow gates). This wastes time and creates confusing output.

**Independent Test**: Run `/speckit.specify` directly (outside workflow) and verify that the `after_specify` hook from spex-gates fires `review-spec`. Then run the ship workflow and verify that during the specify step, the spex-gates hook does not fire (the workflow's own review-spec gate handles it instead).

**Acceptance Scenarios**:

1. **Given** spex-gates is enabled and no workflow is running, **When** `/speckit.specify` completes, **Then** the `after_specify` hook fires `speckit.spex-gates.review-spec`.
2. **Given** spex-gates is enabled and a ship workflow is running, **When** the workflow's specify step completes, **Then** the spex-gates `after_specify` hook is suppressed and the workflow's own `review-spec` gate step handles the review.
3. **Given** a workflow run sets a marker (e.g., `.specify/.spex-workflow-active`) via its `pre_run` hook, **When** a spex-gates review command starts execution, **Then** the command detects the marker and exits early with a "handled by workflow" message.
4. **Given** the workflow completes or is aborted, **When** the marker is removed, **Then** hooks resume normal behavior for subsequent ad-hoc commands.

---

### User Story 5 - Version Bump and Legacy Cleanup (Priority: P1)

All extension manifests are updated to require spec-kit `>=0.7.4`. All legacy migration code is removed from `spex-init.sh` (beads migration, old commands migration, constitution symlink fix, traits config migration, old phase marker migration). The codebase starts clean.

**Why this priority**: Legacy code adds maintenance burden and confusion. Since we're making a breaking change with the workflow engine anyway, cleaning up legacy code now is practically free.

**Independent Test**: Run `rg "migrate_" spex/scripts/spex-init.sh` and verify no migration functions exist. Check all `extension.yml` manifests and verify `speckit_version: ">=0.7.4"`.

**Acceptance Scenarios**:

1. **Given** the updated `spex-init.sh`, **When** inspected, **Then** no migration functions exist (`migrate_traits_config`, `migrate_phase_marker`, `migrate_old_commands`, `migrate_from_beads`, `do_beads_migration`, `fix_constitution`).
2. **Given** all five extension manifests, **When** inspected, **Then** each requires `speckit_version: ">=0.7.4"`.
3. **Given** a project with old traits config (`.specify/spex-traits.json`), **When** `/spex:init` runs, **Then** the old file is ignored (not read, not migrated, not warned about).

---

### Edge Cases

- What happens when `specify workflow run` fails mid-step (e.g., specify step produces invalid output)? The workflow engine should handle failure state, and `specify workflow resume` should allow retry of the failed step.
- What happens when the plugin mapping file references a plugin path that exists but doesn't contain the expected structure? Detection checks for `plugin.json` or `.claude-plugin/plugin.json` as the standard Claude Code plugin marker. Directories without this marker are treated as unavailable.
- What happens when multiple workflows are running simultaneously (e.g., in different terminal tabs)? The workflow engine handles this via its own state management, but spex should warn if `.specify/.spex-workflow-active` already exists when starting a new workflow.
- What happens when the user runs `/spex:ship` and the workflow engine is not available (spec-kit version too old)? The init version gate catches this at project setup time, not at ship invocation time.
- What happens when a hook condition depends on workflow state but the hook fires during a non-workflow context? Hooks with `skip_in_workflow: true` only check the marker file, they behave normally when no marker exists.

## Requirements

### Functional Requirements

- **FR-001**: The ship pipeline MUST be defined as a declarative workflow YAML file installable via `specify workflow add`.
- **FR-002**: The ship workflow MUST support three oversight levels (`always`, `smart`, `never`) as a workflow input that controls gate step behavior.
- **FR-003**: The ship wrapper command MUST support a `--create-pr` flag that creates a pull request after the workflow completes successfully. PR creation is handled by the wrapper, not the workflow YAML.
- **FR-004**: The implement step MUST auto-detect teams routing at runtime by checking if spex-teams is enabled and tasks.md contains 2+ independent tasks. This is not a workflow input but a runtime decision inside the implement command.
- **FR-005**: The `spex-init.sh` script MUST use `specify integration install` (or `upgrade` for existing setups) for agent-specific file management instead of custom agent detection logic.
- **FR-006**: The `spex-init.sh` script MUST install bundled extensions using `specify extension add <path> --dev` for each extension in the plugin's `extensions/` directory.
- **FR-007**: The `spex-init.sh` script MUST require spec-kit version `>=0.7.4` and fail with an upgrade instruction if the installed version is older.
- **FR-008**: All extension manifests MUST declare `speckit_version: ">=0.7.4"` in their `requires` section.
- **FR-009**: A plugin mapping file (`spex/plugin-integrations.yml`) MUST define detection paths, skills, and injection targets for companion plugins.
- **FR-010**: The init script MUST scan for companion plugins according to the mapping file and record results in `.specify/spex-plugins.json`. A directory is considered a valid plugin only if it contains `plugin.json` or `.claude-plugin/plugin.json`.
- **FR-011**: Extension commands that support plugin integration MUST read `.specify/spex-plugins.json` and conditionally include plugin instructions when the plugin is available.
- **FR-012**: Spex-gates review commands (review-spec, review-plan, review-code, verify) MUST check for a `.specify/.spex-workflow-active` marker file at the start of execution. If the marker exists, the command MUST exit early with a message indicating the workflow handles this review. This suppression happens inside the command logic, not at the hook configuration level (extension hook conditions do not support file-based predicates).
- **FR-013**: The ship workflow MUST create `.specify/.spex-workflow-active` before execution (via `pre_run` hook) and remove it on completion or abort (via `post_run` hook). The marker file MUST contain the process PID and a timestamp. Review commands MUST verify the PID is still alive before suppressing; if the PID is dead, the marker is treated as stale and ignored. The init script MUST also clean up stale markers on startup.
- **FR-014**: All legacy migration code MUST be removed from `spex-init.sh` (beads, old commands, constitution symlink, traits config, phase markers).
- **FR-015**: The old ship command (`speckit.spex.ship.md`) MUST be replaced with a thin wrapper that invokes `specify workflow run spex-ship` with mapped arguments.
- **FR-016**: The implement and review-code commands MUST spawn isolated subagents (via the Agent tool) when executing inside a workflow (detected by the `.specify/.spex-workflow-active` marker). The subagent receives only file paths, not conversation history. This prevents context accumulation in the orchestrator.
- **FR-017**: The constitution MUST be amended to add workflow naming conventions (e.g., `spex-ship` workflow ID pattern) to section V (Naming Discipline).

### Key Entities

- **Workflow Definition**: A YAML file defining the ship pipeline's stages, gates, and inputs. Installed in `.specify/workflows/spex-ship/`.
- **Plugin Mapping**: A YAML configuration (`spex/plugin-integrations.yml`) that maps companion plugin names to detection paths, skills, and injection targets.
- **Plugin State**: A JSON file (`.specify/spex-plugins.json`) recording which companion plugins are available in the current environment.
- **Workflow Marker**: A JSON file (`.specify/.spex-workflow-active`) containing `{"pid": <int>, "started_at": "<ISO timestamp>"}` that signals to hooks that a workflow is running. Review commands check PID liveness to detect stale markers from crashed sessions.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The ship workflow YAML plus thin wrapper command together represent at least an 80% reduction from the current 788-line procedural command (under ~160 lines combined).
- **SC-002**: The `spex-init.sh` script is under 120 lines after removing legacy migration code and delegating agent management to spec-kit.
- **SC-003**: `specify workflow run spex-ship` completes autonomously end-to-end with the same quality gate behavior as the current procedural ship command.
- **SC-004**: `specify workflow resume` successfully resumes an interrupted ship run from the exact stage where it stopped.
- **SC-005**: Plugin detection correctly identifies installed companion plugins and conditionally enriches review commands without any code changes to the init script (only mapping file changes needed for new plugins).
- **SC-006**: Ad-hoc `/speckit.specify` fires the spex-gates review-spec hook, while the same command inside a workflow run does not fire the hook (coordination works).

## Clarifications

### Session 2026-04-18

- Q: Should ship be a custom workflow or extend the built-in `speckit` workflow? -> A: Custom workflow (`spex-ship`). The built-in workflow has different gate semantics (interactive approve/reject) and doesn't include our oversight levels, subagent forking, or teams routing.
- Q: How do hooks know they're inside a workflow? -> A: Marker file (`.specify/.spex-workflow-active`). The workflow creates it on start, removes on completion/abort. Hooks check for it.
- Q: Should plugin detection be hardcoded or configurable? -> A: Configurable via `spex/plugin-integrations.yml`. New plugins can be added by editing the mapping file without code changes.
- Q: What about backwards compatibility with spec-kit < 0.7.x? -> A: Clean break. Version gate at init, require `>=0.7.4`, remove all legacy code.
- Q: Should the ship command be removed entirely? -> A: Keep it as a thin wrapper that invokes `specify workflow run spex-ship`. Users can use either `/spex:ship` or `specify workflow run spex-ship`.
- Q: Does the workflow engine support conditional steps, extension commands as steps, and pre/post hooks? -> A: Yes, all three verified with test workflows on spec-kit 0.7.4. Conditional steps use `condition` field with template expressions, extension commands work as `command` values, and `pre_run`/`post_run` hooks accept shell commands.
- Q: Can extension hook conditions check for file existence? -> A: No, current `extensions.yml` hook conditions are all `null` and there's no evidence of file-based predicate support. Hook suppression must happen inside the command logic instead.
- Q: How should stale workflow markers be handled after crashes? -> A: Marker contains PID and timestamp. Review commands check PID liveness before suppressing. Init also cleans up stale markers on startup.
- Q: What validates a directory as a real companion plugin? -> A: Check for `plugin.json` or `.claude-plugin/plugin.json` (the standard Claude Code plugin marker). Directories without this marker are treated as unavailable.

## Assumptions

- Spec-kit 0.7.4's workflow engine supports custom workflow definitions with typed inputs, gate steps, conditional steps, workflow-level pre/post hooks, and resume functionality. **Verified**: test workflow with `condition`, `pre_run`/`post_run`, and extension commands installed successfully.
- The `specify workflow run` command can invoke extension commands (e.g., `speckit.spex-gates.review-spec`) as workflow steps. **Verified**: test workflow with `speckit.git.validate` as a step installed and was accepted.
- The workflow engine creates its own state management that is independent of the old `.spex-state` file approach.
- Companion plugins are installed as directories under `~/.claude/plugins/` with a predictable structure.
- The `specify integration install/upgrade` command handles all agent-specific directory mapping (`.claude/skills/`, `.claude/commands/`, etc.) without requiring custom logic in spex.
- The constitution (v2.0.0) will need a minor amendment to add workflow naming conventions to section V (Naming Discipline). This amendment is part of this feature's implementation scope.
