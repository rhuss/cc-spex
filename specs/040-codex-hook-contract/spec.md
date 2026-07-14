# Feature Specification: Codex Hook Contract Migration

**Feature Branch**: `040-codex-hook-contract`  
**Created**: 2026-07-13  
**Status**: Draft  
**Input**: Brainstorm 36: Update Codex CLI hook adapter scripts to match the v0.144+ hook contract.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Context injection on UserPromptSubmit (Priority: P1)

A user types a `/spex:` command in Codex CLI. The `context-hook.py` fires, parses the Codex v0.144+ stdin format, delegates to the shared `context-hook.sh` for command validation, and injects spex context into the Codex session via the `systemMessage` stdout format. Codex renders the context as additional system-level information for the model.

**Why this priority**: Without working context injection, Codex cannot route `/spex:` commands to the correct skills or inject enforcement blocks.

**Independent Test**: Type `/spex:help` in a Codex session with spex installed. Verify the hook fires without errors and Codex receives the spex context.

**Acceptance Scenarios**:

1. **Given** a Codex session with spex installed, **When** the user types `/spex:ship my-feature`, **Then** the hook reads `prompt` from the v0.144+ stdin format, delegates to `context-hook.sh`, and outputs `{"systemMessage": "<spex-context>...</spex-context><skill-enforcement>...</skill-enforcement>"}`.
2. **Given** a Codex session, **When** the user types a non-spex prompt (e.g., "fix the bug"), **Then** the hook clears any stale skill marker and exits with code 0 and no output.
3. **Given** malformed JSON on stdin, **When** the hook runs, **Then** it exits with code 0 and produces no output.
4. **Given** the shared `context-hook.sh` returns an error, **When** the hook processes the result, **Then** it outputs the error via `{"systemMessage": "..."}` format.

---

### User Story 2 - Tool gating on PreToolUse (Priority: P1)

A user is in a Codex session where the skill gate requires invoking a Skill tool first. When any other tool is called, `pretool-gate.py` fires, parses the v0.144+ stdin format, delegates to the shared gate scripts, and blocks the tool call via `hookSpecificOutput` with `permissionDecision: "deny"`.

**Why this priority**: Without working tool gating, workflow enforcement is absent on Codex.

**Independent Test**: In a Codex session with a skill-pending marker set, attempt to call Bash. Verify the hook blocks the call with a deny message.

**Acceptance Scenarios**:

1. **Given** a skill-pending marker exists for the session, **When** a non-Skill tool call is attempted, **Then** the hook outputs `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "<reason>"}}`.
2. **Given** a Skill tool call is attempted, **When** the hook fires, **Then** it clears the skill-pending marker and allows the call (exit 0, no output).
3. **Given** the ship pipeline state file exists with `status: running`, **When** a tool call is made, **Then** the stage-gate context is injected via `{"systemMessage": "<context>"}`.
4. **Given** multiple gates fire and one returns deny while others return context, **Then** the deny takes precedence and the tool call is blocked.

---

### User Story 3 - hooks.json generation during setup (Priority: P1)

A user runs setup with codex integration. The setup generates `.codex/hooks.json` in the v0.144+ event-grouped format, using `python-resolve.sh` for cross-platform Python resolution.

**Why this priority**: If hooks.json is malformed, Codex CLI refuses to load hooks entirely.

**Independent Test**: Run setup with codex integration in a fresh repo. Verify `.codex/hooks.json` parses without errors when Codex starts.

**Acceptance Scenarios**:

1. **Given** a fresh project with no `.codex/` directory, **When** setup runs with `integration=codex`, **Then** `.codex/hooks.json` is created with event-grouped format containing `UserPromptSubmit` and `PreToolUse` entries.
2. **Given** an existing `.codex/hooks.json` with other hooks, **When** setup runs, **Then** spex hooks are merged without removing existing hooks, and existing spex hooks are replaced (not duplicated).
3. **Given** a system where `python3` is not available but `python` or `py` is, **When** hooks fire, **Then** they execute successfully via the `python-resolve.sh` wrapper.
4. **Given** Codex CLI v0.144.1, **When** loading the generated hooks.json, **Then** no parse errors occur.

---

### User Story 4 - Shared shell script compatibility (Priority: P2)

The updated Python adapters call the shared POSIX shell scripts with identical arguments as the Claude Code adapters. The shared scripts are not modified.

**Why this priority**: The shared scripts are the canonical enforcement logic. Argument divergence would cause different behavior between Claude Code and Codex.

**Independent Test**: Compare the `run_shared()` calls in the updated Codex adapters with the Claude Code adapters. Arguments must match.

**Acceptance Scenarios**:

1. **Given** the updated `context-hook.py`, **When** it calls `context-hook.sh`, **Then** the arguments are `[prompt, session_id, cwd, plugin_root]`.
2. **Given** the updated `pretool-gate.py`, **When** it calls `skill-gate.sh`, **Then** the arguments are `[tool_name, session_id]`.
3. **Given** the updated `pretool-gate.py`, **When** it calls `stage-gate.sh`, **Then** the arguments are `[tool_name, skill_name, state_file_path]`.
4. **Given** the updated `pretool-gate.py`, **When** it calls `verify-gate.sh`, **Then** the arguments are `[tool_name, command, session_id, cwd]`.

---

### Edge Cases

- What happens when Codex sends additional/unknown fields in stdin JSON? The hook ignores unknown fields (parses only known fields).
- What happens when `permission_mode` is an unexpected value? Ignored (shared scripts don't use it).
- What happens when `turn_id` is missing from stdin? Fall back to `"unknown"` for marker file naming.
- What happens when the hook script crashes with an unhandled exception? Codex treats non-zero exit as a hook failure and continues. Acceptable since hooks are guardrails, not security boundaries.
- What happens with tools that don't emit PreToolUse events (e.g., WebSearch, some MCP tools)? These tools bypass the hook entirely (Codex architecture limitation). The PreToolUse gate only covers tools that fire the event (primarily Bash and apply_patch). This is acceptable since the gate is a guardrail, not a complete enforcement boundary.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `context-hook.py` MUST parse the Codex v0.144+ `UserPromptSubmit` stdin contract: `prompt`, `turn_id`, `cwd`, `permission_mode`, `transcript_path`.
- **FR-002**: `context-hook.py` MUST output context using `{"systemMessage": "<text>"}` format.
- **FR-003**: `pretool-gate.py` MUST parse the Codex v0.144+ `PreToolUse` stdin contract: `tool_name`, `tool_input`, `turn_id`, `cwd`, `permission_mode`.
- **FR-004**: `pretool-gate.py` MUST output deny decisions using `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "<reason>"}}`.
- **FR-005**: `pretool-gate.py` MUST output context injection using `{"systemMessage": "<text>"}`.
- **FR-006**: Both hooks MUST delegate to the same shared POSIX shell scripts with identical arguments as the Claude Code adapters.
- **FR-007**: Both hooks MUST exit with code 0 and no output for "allow" decisions.
- **FR-008**: Both hooks MUST exit with code 0 and no output when stdin contains malformed JSON.
- **FR-009**: `setup.yml` and `spex-init.sh` MUST generate `.codex/hooks.json` in the v0.144+ event-grouped format.
- **FR-010**: Hook commands in hooks.json MUST use `sh .../python-resolve.sh` wrapper instead of hardcoded `python3`.
- **FR-011**: Setup MUST merge spex hooks into existing `.codex/hooks.json` without removing non-spex hooks.
- **FR-012**: The `turn_id` field from Codex stdin MUST be used as the session identifier for marker file naming, falling back to `"unknown"` if absent.

### Key Entities

- **Hook Script**: A Python script that reads JSON from stdin, delegates to shared shell scripts, and writes JSON to stdout per the Codex CLI hook contract.
- **Shared Shell Script**: A POSIX shell script in `spex/scripts/hooks/shared/` that implements enforcement logic independently of the calling agent.
- **hooks.json**: Per-project Codex CLI configuration at `.codex/hooks.json` defining which hook scripts fire on which events.
- **python-resolve.sh**: Cross-platform Python interpreter resolver that tries `python3`, `py`, then `python`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Codex CLI v0.144+ starts without hooks.json parse errors when spex is installed.
- **SC-002**: Typing `/spex:help` in a Codex session triggers context injection (model receives spex context).
- **SC-003**: The skill-gate blocks non-Skill tool calls when a skill-pending marker is set.
- **SC-004**: The shared shell scripts receive identical arguments from both the Claude Code and Codex adapters.
- **SC-005**: Setup correctly merges spex hooks into an existing `.codex/hooks.json` containing other hooks.
- **SC-006**: On a system where `python3` is not on PATH but `python` or `py` is, hooks execute successfully.

## Smoke Test

1. Run setup with `integration=codex` on a fresh test repo, start Codex, and verify no hooks.json parse errors appear.
2. Type `/spex:help` in the Codex session and verify the model responds with spex help content (context injection working).
3. Inspect hook debug output to confirm shared shell scripts were called with correct arguments.

## Dependencies

- **Codex CLI v0.144+**: Hook contract with `UserPromptSubmit` and `PreToolUse` events.
- **Shared shell scripts**: `context-hook.sh`, `skill-gate.sh`, `stage-gate.sh`, `verify-gate.sh` in `spex/scripts/hooks/shared/`.
- **python-resolve.sh**: Cross-platform Python interpreter resolver in `spex/scripts/`.
- **setup.yml / spex-init.sh**: Setup pipeline that generates `.codex/hooks.json`.

## Risks

- **`turn_id` scope uncertainty**: If Codex's `turn_id` is per-turn rather than per-session, marker-based gating (skill gate, stage gate) will fail across turns. Mitigation: verify empirically during implementation; if per-turn, extract a stable session identifier from `transcript_path` or another field.

## Out of Scope

- Adding tool `matcher` support to hooks.json entries.
- Adding `commandWindows` entries for Windows-specific hook commands.
- Modifying the shared POSIX shell enforcement scripts.
- Supporting Codex hook events beyond `UserPromptSubmit` and `PreToolUse`.
- Changing the AGENTS.md template content.

## Clarifications

### Session 2026-07-13

- Q: Does `turn_id` persist across turns within a Codex session (like Claude Code's `session_id`), or does it change per turn? → A: Treat as session-scoped. If `turn_id` changes per turn, marker files would not persist across turns, breaking the skill gate. Use `turn_id` as the session identifier and verify empirically. If `turn_id` is per-turn, a future fix would need to extract a stable session identifier from a different field or the `transcript_path`.

## Assumptions

- The Codex v0.144+ hook contract as documented at learn.chatgpt.com/docs/hooks is accurate and stable.
- The `turn_id` field serves the same purpose as Claude Code's `session_id` for session-scoped marker files. If it is per-turn rather than per-session, marker-based gating will need a different identifier (tracked as a risk).
- Empty stdout from a hook is treated as "allow" by Codex.
- Exit code 0 with valid JSON stdout is the primary response mechanism.
- The existing shared shell scripts' argument interfaces are stable.
