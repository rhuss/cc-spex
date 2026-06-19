# Feature Specification: Before/After Finish Hook Support

**Feature Branch**: `027-before-finish-hooks`
**Created**: 2026-06-19
**Status**: Draft
**Input**: Brainstorm #21 - Smoke test integration via before_finish hook

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Smoke Test Prompt Before Finish (Priority: P1)

A developer completes implementation and runs `/speckit-spex-finish`. Before the verification gate runs, the system checks for registered `before_finish` hooks. It finds the smoke test hook (optional), and prompts the developer: "Run interactive smoke test before finishing?" The developer can accept (runs the smoke test) or decline (skips straight to verification).

**Why this priority**: This is the primary motivation for the feature. Without it, users who go directly to finish miss the smoke test entirely, risking that runtime bugs slip through.

**Independent Test**: Can be tested by adding the hook config to extensions.yml, then running the finish skill and verifying the prompt appears before Phase 1 verification.

**Acceptance Scenarios**:

1. **Given** a `before_finish` hook is registered with `optional: true` in extensions.yml, **When** the user invokes `/speckit-spex-finish`, **Then** the system prompts whether to run the hook command before starting Phase 1 verification.
2. **Given** a `before_finish` hook is registered with `optional: true`, **When** the user declines the prompt, **Then** the system skips the hook and proceeds directly to Phase 1 verification.
3. **Given** a `before_finish` hook is registered with `optional: false`, **When** the user invokes `/speckit-spex-finish`, **Then** the system automatically executes the hook command before Phase 1 verification without prompting.
4. **Given** no `before_finish` hooks are registered in extensions.yml, **When** the user invokes `/speckit-spex-finish`, **Then** the system proceeds directly to Phase 1 verification with no hook-related output.

---

### User Story 2 - After Finish Hooks Execute (Priority: P2)

After the finish command completes its action (merge, PR, or keep), any registered `after_finish` hooks execute. The existing flow-state cleanup hook, which is currently dead config, starts working.

**Why this priority**: Fixes an existing gap where the `after_finish` hook for flow-state cleanup was declared but never fired. This is a secondary benefit of adding hook support to the finish skill.

**Independent Test**: Can be tested by verifying that the existing `after_finish` flow-state hook fires and cleans up the state file after finish completes.

**Acceptance Scenarios**:

1. **Given** an `after_finish` hook is registered with `optional: false`, **When** the finish command completes its action successfully, **Then** the system automatically executes the hook command.
2. **Given** an `after_finish` hook is registered with `optional: true`, **When** the finish command completes, **Then** the system prompts whether to run the hook command.
3. **Given** the finish command is in watch mode and a PR was created, **When** watch mode completes or is interrupted, **Then** `after_finish` hooks still execute during cleanup.

---

### User Story 3 - Next-Steps Text Mentions Smoke Test (Priority: P3)

After a code review or deep review passes, the "next steps" output includes the smoke test as a recommended step before finish. This serves as a belt-and-suspenders reminder alongside the hook.

**Why this priority**: Supplementary discoverability measure. Users who read the review output see the smoke test mentioned even if they don't know about hooks.

**Independent Test**: Can be tested by running review-code or deep-review and verifying the output includes `/speckit-spex-smoke-test` in the next-steps text.

**Acceptance Scenarios**:

1. **Given** a code review passes, **When** the review-code skill outputs next steps, **Then** the output lists `/speckit-spex-smoke-test` as step 1, `/clear` as step 2, and `/speckit-spex-finish` as step 3.
2. **Given** a deep review passes, **When** the deep-review skill outputs next steps, **Then** the output lists the same three steps in the same order.

---

### Edge Cases

- What happens when the finish skill runs in autonomous mode (ship pipeline) with `before_finish` hooks? The hook prompt behavior should respect the `ask` level from the state file.
- What happens when a mandatory `before_finish` hook fails? The finish command should stop and not proceed to verification.
- What happens when `.specify/extensions.yml` does not exist or is malformed? The finish skill should skip hook checking silently and proceed normally.
- What happens when the finish skill runs in a worktree? Hook reading should work identically regardless of CWD.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The finish skill MUST read `.specify/extensions.yml` and check for `hooks.before_finish` entries before Phase 1 verification.
- **FR-002**: The finish skill MUST read `.specify/extensions.yml` and check for `hooks.after_finish` entries after Phase 6 state cleanup.
- **FR-003**: For optional hooks (`optional: true`), the system MUST prompt the user before executing the hook command.
- **FR-004**: For mandatory hooks (`optional: false`), the system MUST execute the hook command automatically without prompting.
- **FR-005**: Hooks with `enabled: false` MUST be skipped entirely.
- **FR-006**: Hooks with a non-empty `condition` field MUST be skipped (condition evaluation is deferred to the HookExecutor).
- **FR-007**: The hook-reading boilerplate MUST match the pattern used by core spec-kit commands (implement.md Pre-Execution Checks section is the reference).
- **FR-008**: The spex extension manifest (`spex/extensions/spex/extension.yml`) MUST register a `before_finish` hook for the smoke test command with `optional: true`.
- **FR-009**: The review-code skill MUST include `/speckit-spex-smoke-test` in its next-steps output text.
- **FR-010**: The deep-review skill MUST include `/speckit-spex-smoke-test` in its next-steps output text.
- **FR-011**: When `.specify/extensions.yml` does not exist or cannot be parsed, hook checking MUST be skipped silently.
- **FR-012**: Hook command names MUST be converted from dot notation to hyphen notation for slash command invocation (e.g., `speckit.spex.smoke-test` becomes `/speckit-spex-smoke-test`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running `/speckit-spex-finish` with the smoke test hook registered produces a prompt before verification starts, 100% of the time.
- **SC-002**: The existing `after_finish` flow-state cleanup hook fires after finish completes, eliminating the current dead-config gap.
- **SC-003**: Review-code and deep-review next-steps output includes the smoke test command in all PASS exits.
- **SC-004**: The hook-reading logic handles missing, empty, or malformed extensions.yml without errors or crashes.

## Assumptions

- The spec-kit hook pattern from `implement.md` is stable and will not change in a way that breaks this implementation.
- The smoke test skill (`speckit.spex.smoke-test`) already exists and handles the "no scenarios found" case gracefully.
- The spex extension manifest (`extension.yml`) supports arbitrary hook event names without validation (confirmed by source code inspection).
- The `after_finish` hook execution point is after Phase 6 (state cleanup) but before Phase 7 (watch mode), matching the logical point where the feature action is complete.
- Hook registration in `extension.yml` is automatically aggregated into `.specify/extensions.yml` when the extension is reinstalled via `specify extension add`.
