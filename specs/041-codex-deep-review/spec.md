# Feature Specification: Codex Integration for Deep Review

**Feature Branch**: `041-codex-deep-review`  
**Created**: 2026-07-14  
**Status**: Draft  
**Input**: Integrate Codex as an external review tool in the deep-review extension

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Codex review runs automatically during deep review (Priority: P1)

A developer runs the deep-review pipeline on their feature branch. When Codex CLI is installed and enabled in config, the deep review automatically invokes `codex review` alongside CodeRabbit and Copilot. Codex findings appear in the merged results and enter the fix loop if they are Critical or Important.

**Why this priority**: This is the core value proposition. Without this, there is no Codex integration.

**Independent Test**: Can be tested by running `/speckit-spex-deep-review-run` on a branch with `codex` CLI installed and `codex: true` in the deep-review config. Verify that a "Codex (external)" row appears in the agent summary table with finding counts.

**Acceptance Scenarios**:

1. **Given** Codex CLI is installed and `external_tools.codex` is `true` in config, **When** deep review runs, **Then** `codex review --base $MAIN_BRANCH` is invoked and its output is parsed into the common finding schema.
2. **Given** Codex CLI is installed and enabled, **When** Codex returns findings with Critical or Important severity, **Then** those findings enter the fix loop and are treated identically to CodeRabbit findings.
3. **Given** Codex CLI is installed and enabled, **When** deep review completes, **Then** the agent summary table includes a "Codex (external)" row showing found/fixed/remaining counts and status.

---

### User Story 2 - Codex review is skipped when not available (Priority: P1)

A developer runs deep review on a machine where Codex CLI is not installed, or where Codex is disabled in config. The deep review proceeds normally without Codex, just as it does when CodeRabbit is not installed.

**Why this priority**: Codex is optional. The deep review must never fail because Codex is missing.

**Independent Test**: Run deep review without `codex` CLI installed. Verify the review completes normally and the agent summary table shows "Codex (external) - skipped (CLI not installed)".

**Acceptance Scenarios**:

1. **Given** Codex CLI is NOT installed, **When** deep review runs, **Then** the review completes normally without error and the Codex row shows "skipped (CLI not installed)".
2. **Given** Codex CLI is installed but `external_tools.codex` is `false` in config, **When** deep review runs, **Then** the Codex detection is skipped entirely and the Codex row shows "skipped (disabled in config)".
3. **Given** Codex CLI is installed but authentication fails, **When** deep review runs, **Then** the failure is logged, the review continues without Codex, and the Codex row shows "failed" with the error reason.

---

### User Story 3 - Codex review is skipped when running inside Codex (Priority: P1)

A developer uses spex inside the Codex harness (running on Codex instead of Claude Code). The deep review detects that it is running inside Codex and skips the Codex external tool to avoid recursive invocation.

**Why this priority**: Without this guard, Codex would call itself, wasting resources and potentially creating infinite loops.

**Independent Test**: Run deep review via the Codex harness adapter. Verify that the Codex external tool block is absent from the adapted command (harness marker omission) and no Codex CLI invocation occurs.

**Acceptance Scenarios**:

1. **Given** spex is running inside the Codex harness, **When** the deep-review command is adapted for Codex, **Then** the Codex detection and dispatch block is omitted from the command.
2. **Given** spex is running inside the Claude Code harness, **When** the deep-review command is adapted for Claude Code, **Then** the Codex detection and dispatch block is present in the command.
3. **Given** spex is running inside the OpenCode harness, **When** the deep-review command is adapted for OpenCode, **Then** the Codex detection and dispatch block is present in the command.

---

### User Story 4 - Codex re-review during fix loop (Priority: P2)

During the fix loop, after fixes are applied, Codex is re-invoked to review only the uncommitted changes (narrowed scope), following the same pattern as CodeRabbit re-review.

**Why this priority**: Re-review ensures fixes don't introduce new issues, but the initial review (P1) is more critical.

**Independent Test**: Trigger a fix loop with a Codex finding. After the fix is applied, verify that `codex review --uncommitted` is invoked and its output is merged into the re-review findings.

**Acceptance Scenarios**:

1. **Given** the fix loop has applied fixes, **When** re-review runs, **Then** Codex is invoked with `codex review --uncommitted` instead of `--base`.
2. **Given** the fix loop re-review finds new Codex findings, **When** findings are merged, **Then** new Codex findings are deduplicated against existing findings using the standard merge logic.

---

### Edge Cases

- What happens when `codex review` times out? The error is logged, the review continues without Codex findings, and the status shows "failed (timeout)".
- What happens when `codex review` returns no output? Treated as zero findings. The Codex row shows "completed" with 0 found.
- What happens when `codex review` output cannot be parsed? The raw output is logged as a warning, zero findings are recorded, and the status shows "completed (parse error)".
- What happens when Codex is the only external tool and it fails? The review continues with only the 5 internal agent findings. External tool failures never block the review.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The deep-review config template MUST include a `codex` key under `external_tools` with a default value of `true`.
- **FR-002**: The deep-review command MUST detect Codex CLI availability using `which codex >/dev/null 2>&1` at runtime, respecting the config toggle.
- **FR-003**: The deep-review command MUST wrap Codex detection and dispatch in a harness marker block that is present for Claude and OpenCode adapters but absent for the Codex adapter.
- **FR-004**: The deep-review command MUST invoke `codex review --base $MAIN_BRANCH` for the initial review pass in Step 4.
- **FR-005**: The deep-review command MUST invoke `codex review --uncommitted` for fix-loop re-review rounds.
- **FR-006**: The deep-review command MUST parse Codex review output and normalize findings to the common schema with `source_agent = "codex"` and `confidence = 75`.
- **FR-007**: Codex findings with Critical or Important severity MUST enter the fix loop identically to CodeRabbit findings.
- **FR-008**: The agent summary table in Step 9 MUST include a "Codex (external)" row with found/fixed/remaining counts and status.
- **FR-009**: The Claude adapter command-map MUST include a token for the Codex review harness marker block.
- **FR-010**: The OpenCode adapter command-map MUST include a token for the Codex review harness marker block.
- **FR-011**: The Codex adapter command-map MUST NOT include a token for the Codex review harness marker block (omission prevents recursion).
- **FR-012**: External tool error handling for Codex MUST follow the same pattern as CodeRabbit: log the failure, continue the review, do NOT block the pipeline.
- **FR-013**: The ship pipeline's external tool flag resolution MUST support `--codex` and `--no-codex` flags alongside existing `--coderabbit` and `--copilot` flags.

### Key Entities

- **External Tool Config**: The `external_tools` section in `deep-review-config.yml`, extended with a `codex` boolean key.
- **Harness Marker Block**: A `{harness:codex-review-tool}...{/harness:codex-review-tool}` block in the deep-review command that is conditionally included or excluded by the adapter system.
- **Finding Schema**: The common finding schema used by all review agents and external tools, with `source_agent = "codex"` for Codex-originated findings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Deep review on a branch with Codex CLI installed produces a "Codex (external)" row in the agent summary table with accurate finding counts.
- **SC-002**: Deep review on a machine without Codex CLI completes without error and reports Codex as "skipped".
- **SC-003**: Deep review running inside the Codex harness does not invoke `codex review` (no recursive call).
- **SC-004**: Codex Critical/Important findings trigger the fix loop and are resolved or reported as remaining, same as CodeRabbit findings.
- **SC-005**: The `--codex` and `--no-codex` flags in the ship pipeline correctly override the config default.

## Out of Scope

- Codex CLI installation or setup instructions (users are expected to install Codex independently)
- Codex authentication configuration (assumed pre-configured via `codex login`)
- Changes to existing CodeRabbit or Copilot external tool patterns (this feature adds Codex alongside them)
- Generic "add any external tool" plugin architecture (Codex is added as a specific integration, not a generic framework)
- Timeout configuration per external tool (uses the existing implicit timeout behavior)

## Assumptions

- Codex CLI (`codex`) is a standalone binary that can be invoked without additional runtime dependencies beyond authentication.
- The `codex review` subcommand accepts `--base <branch>` and `--uncommitted` flags for scoping the review target.
- Codex review output is free-text that can be parsed for file paths, line numbers, severity indicators, and descriptions using pattern matching.
- The harness adapter system's marker block mechanism (include/exclude blocks per adapter) is sufficient to prevent recursive invocation without runtime checks. If the adapter system fails to strip the marker block, Codex would invoke itself; implementation should verify adapter stripping works correctly during testing.
- Users who have Codex installed have already authenticated via `codex login`.
