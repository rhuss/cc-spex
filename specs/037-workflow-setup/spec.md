# Feature Specification: Workflow-Based Setup

**Feature Branch**: `037-workflow-setup`
**Created**: 2026-07-07
**Status**: Draft
**Input**: Replace spex-init.sh with a spec-kit setup workflow shipped as a bundle

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install Spex on Any Agent Harness via Setup Workflow (Priority: P1)

A developer using any supported agent harness (Claude Code, Codex, OpenCode, or others) installs spex into their project by running a single command. The setup workflow detects the active harness, installs all core extensions, runs per-agent adaptation, and configures the project. The developer does not need to know which harness they are using; the workflow auto-detects and adapts.

**Why this priority**: This is the core value proposition. Without a harness-agnostic install path, spex only works on Claude Code.

**Independent Test**: Run the setup workflow on a clean project with each supported harness. Verify extensions are installed, commands are available, and the agent can execute spex commands.

**Acceptance Scenarios**:

1. **Given** a clean project with `specify` CLI installed, **When** the user runs `specify workflow run <spex-setup-url>`, **Then** all core spex extensions are installed with scripts, per-agent configuration is applied, and spex commands are available.
2. **Given** a project on Claude Code, **When** the setup workflow runs with integration auto-detected as `claude`, **Then** Claude-specific settings (permissions, statusline, hooks) are configured identically to the current `spex-init.sh` behavior.
3. **Given** a project on Codex, **When** the setup workflow runs with integration auto-detected as `codex`, **Then** Codex-specific hooks (`.codex/hooks.json`) and agent context files (`AGENTS.md`) are configured.
4. **Given** a project on an unknown/unsupported harness, **When** the setup workflow runs, **Then** extensions are installed with default (neutral) configuration and a message indicates which agent-specific features are unavailable.

---

### User Story 2 - Interactive Extension Selection During Setup (Priority: P2)

A developer running the setup workflow is offered a choice of which optional extensions to enable. The selection mechanism works across different agent harnesses, degrading gracefully from structured UI (where available) to text-based selection.

**Why this priority**: Users have different needs. Some want the full suite (gates, deep-review, teams, collab), others want just the core SDD workflow.

**Independent Test**: Run the setup workflow in interactive mode. Verify the user is presented with extension choices and that only selected extensions are enabled after setup completes.

**Acceptance Scenarios**:

1. **Given** the setup workflow running in interactive mode, **When** the extension selection step executes, **Then** the user sees a list of optional extensions with descriptions and can select which ones to enable.
2. **Given** the setup workflow running with `--set extensions=spex-gates,spex-worktrees`, **When** the workflow completes, **Then** only the specified extensions (plus core `spex`) are enabled, and unselected optional extensions are disabled.
3. **Given** the setup workflow running with `--set extensions=all`, **When** the workflow completes, **Then** all extensions are enabled without prompting.
4. **Given** a harness that does not support structured prompts, **When** the extension selection step executes, **Then** the selection degrades to a text-based prompt or defaults to all extensions enabled.

---

### User Story 3 - Per-Agent Permission Configuration (Priority: P2)

The setup workflow configures agent-specific permission allowlists so spex commands can execute without excessive permission prompts. Each harness has its own permission model, and the workflow handles the differences transparently.

**Why this priority**: Without proper permissions, every spex command triggers approval prompts, making the workflow unusable.

**Independent Test**: After running the setup workflow on each supported harness, verify that core spex operations (specify, plan, implement) execute without additional permission prompts.

**Acceptance Scenarios**:

1. **Given** a Claude Code project, **When** the setup workflow configures permissions, **Then** `.claude/settings.json` contains allowlists for `specify` CLI, spex scripts, and skill invocations.
2. **Given** a Codex project, **When** the setup workflow configures permissions, **Then** `.codex/hooks.json` contains the appropriate hook configuration for spex commands.
3. **Given** the user selects "standard" permission level, **When** permissions are configured, **Then** only spex-specific commands are auto-approved.
4. **Given** the user selects "full trust" permission level, **When** permissions are configured, **Then** broad auto-approval is configured for unattended workflows.

---

### User Story 4 - Bundle Distribution from GitHub (Priority: P1)

The spex setup workflow and extensions are packaged as a spec-kit bundle, installable directly from a GitHub release URL. Users do not need to clone the repository or manage local paths.

**Why this priority**: A single-URL install is the target UX. Without bundle distribution, setup requires cloning the repo first.

**Independent Test**: Run `specify workflow run <github-release-url>` on a clean project. Verify the bundle installs correctly and all extensions are available.

**Acceptance Scenarios**:

1. **Given** a published setup workflow at a GitHub release URL, **When** a user runs `specify workflow run <url>`, **Then** the workflow clones the spex repository to a temporary location, installs extensions from the clone via `specify extension add`, configures the project, and cleans up the temporary clone.
2. **Given** a user with a local clone of the spex repository, **When** they run `specify workflow run setup.yml`, **Then** extensions are installed from the local clone without network access.
3. **Given** the bundle declares extensions in `provides.extensions`, **When** `specify bundle install` runs as an alternative install path, **Then** each extension is installed with its commands and scripts in the correct order (dependencies first).

---

### User Story 5 - Claude Code Plugin Compatibility Shim (Priority: P3)

Existing Claude Code users who installed spex via `claude plugin install` continue to work during the transition. The plugin's init script delegates to the setup workflow.

**Why this priority**: 100 existing users should not be broken by the migration. This is a compatibility bridge, not a permanent feature.

**Independent Test**: Run `claude plugin install spex@...` and verify the plugin's init delegates to the setup workflow, producing the same result as running the workflow directly.

**Acceptance Scenarios**:

1. **Given** a Claude Code user with the existing spex plugin installed, **When** they run `/spex:init`, **Then** the init delegates to the setup workflow and produces equivalent results.
2. **Given** a new Claude Code user, **When** they install the plugin from the marketplace and run `/spex:init`, **Then** the init script checks if `specify` CLI is installed. If present, it delegates to `specify workflow run setup.yml` (using the local plugin copy). If absent, it falls back to the legacy direct init path.

---

### Edge Cases

- What happens when `specify` CLI is not installed? The workflow requires it. The error message should direct the user to install spec-kit first.
- What happens when the workflow is run on an already-initialized project? It should be idempotent, updating configuration without duplicating extensions.
- What happens when the user runs the workflow offline (no internet)? The workflow should work from a locally cloned bundle. The HTTPS URL path requires connectivity.
- What happens when a newer version of the bundle is released? The user re-runs the workflow URL. The bundle system handles version tracking.
- What happens when an extension has dependencies (spex-teams requires spex-gates)? The workflow enforces installation order. If a user disables a dependency, the dependent extension is also disabled with a warning.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A setup workflow (`setup.yml`) MUST install all spex extensions in dependency order and configure the project for the detected agent harness.
- **FR-002**: The workflow MUST auto-detect the active agent harness via `inputs.integration` with `default: "auto"` and the spec-kit expression engine's auto-resolution.
- **FR-003**: The workflow MUST configure agent-specific settings (permissions, hooks, context files) via `switch` steps on the detected integration.
- **FR-004**: The workflow MUST support interactive extension selection via `prompt` or `gate` steps. If the harness does not support structured prompts or the `prompt` step cannot drive selection, the workflow MUST fall back to installing all extensions (the `all` default) and log a message that extensions can be disabled individually via `specify extension disable <name>`.
- **FR-005**: The workflow MUST accept a `--set extensions=<list>` input for non-interactive extension selection (CI, scripted setups, re-initialization).
- **FR-006**: The workflow MUST be idempotent using a check-and-skip strategy: skip already-installed extensions (relying on `specify extension add`'s existing-check behavior), and merge permission entries into existing config files rather than overwriting them. User-modified settings in permission files and extension configs MUST be preserved on re-run.
- **FR-007**: A bundle manifest (`bundle.yml`) MUST declare all spex extensions and the setup workflow in `provides.extensions` and `provides.workflows`. The bundle is a provenance/metadata artifact, not the primary install mechanism.
- **FR-008**: The setup workflow MUST be the single-command install entry point, executable directly from a GitHub release URL via `specify workflow run <url>`. The workflow handles extension installation (via `specify extension add`), harness detection, and configuration. No prior `specify bundle install` is required.
- **FR-009**: The Claude Code plugin MUST continue to function during the transition period, delegating init to the setup workflow.
- **FR-010**: Extension dependency ordering (spex-gates before spex-teams) MUST be enforced during installation, whether the user installs all or a subset.

### Key Entities

- **Setup Workflow**: A spec-kit workflow YAML file that orchestrates the full spex installation and configuration for any supported harness.
- **Bundle Manifest**: A `bundle.yml` declaring the spex distribution: extensions, presets, and workflows.
- **Integration Switch**: A workflow `switch` step that branches on the detected agent harness to apply harness-specific configuration.
- **Permission Profile**: A per-harness configuration block that sets up auto-approval rules so spex commands execute without excessive prompts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can install spex on any spec-kit-supported harness with a single command (`specify workflow run <url>`) in under 60 seconds.
- **SC-002**: The setup workflow produces identical functional results to the current `spex-init.sh` on Claude Code (all extensions installed, permissions configured, statusline active).
- **SC-003**: The setup workflow successfully configures at least 3 different agent harnesses (Claude Code, Codex, and OpenCode) without harness-specific manual steps.
- **SC-004**: Re-running the setup workflow on an already-initialized project completes without errors and does not duplicate extensions or overwrite user settings.
- **SC-005**: Interactive extension selection works on at least 2 different harnesses, with graceful degradation on harnesses that lack structured prompts.

## Out of Scope

- **Command content neutralization**: Rewriting command markdown to remove agent-specific tool references (Agent, AskUserQuestion, EnterWorktree). This is a separate feature (brainstorm #28, Phase 2-3) that requires presets and the `post_process_command_content()` upstream hook.
- **Repository rename**: Renaming `cc-spex` to `spex` on GitHub. Deferred until the workflow-based setup is proven.
- **Deprecating the Claude Code plugin**: The plugin stays as a compatibility shim. Full deprecation is a future decision based on adoption.

## Clarifications

### Session 2026-07-07

- Q: What idempotency strategy should re-runs use? → A: Check-and-skip. Skip already-installed extensions, merge permissions into existing config files. Preserve user-modified settings.
- Q: Which is the third harness for SC-003 (beyond Claude Code and Codex)? → A: OpenCode. It already has adapter scripts and brainstorm #15 explored its adaptation.
- Q: What is the relationship between bundle and workflow distribution? → A: Workflow-first, per spec-kit's canonical pattern. `specify workflow run <url>` is the single-command entry point. The workflow calls `specify extension add` itself. The bundle manifest exists for provenance but is not required for installation.

## Assumptions

- The spec-kit workflow engine supports all required step types (`shell`, `switch`, `if`, `prompt`, `gate`, `init`) in the current release.
- `specify workflow run <https-url>` works for downloading and executing workflows from GitHub release assets.
- The setup workflow enforces extension dependency ordering via sequential `shell` steps (installing extensions one at a time in the correct order). This does not depend on `specify bundle install` handling ordering.
- The `prompt` workflow step sends text to the AI agent, which can then use its native mechanism to present choices to the user. The quality of the UX depends on the agent but the workflow completes regardless.
- The Claude Code plugin marketplace will continue to function during the transition period.
- The `inputs.integration` auto-detection in the expression engine correctly identifies Claude Code, Codex, and OpenCode from the project's `.specify/init-options.json`.
