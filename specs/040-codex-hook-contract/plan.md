# Implementation Plan: Codex Hook Contract Migration

**Branch**: `040-codex-hook-contract` | **Date**: 2026-07-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/040-codex-hook-contract/spec.md`

## Summary

Update the two Codex adapter Python scripts (`context-hook.py` and `pretool-gate.py`) to match the Codex CLI v0.144+ hook contract. The scripts' stdin parsing and stdout formatting layers change; their delegation to shared POSIX shell scripts remains identical. The hooks.json generation in `setup.yml` and `spex-init.sh` has already been fixed (event-grouped format, python-resolve.sh wrapper).

## Technical Context

**Language/Version**: Python 3 (hooks), POSIX shell (shared scripts), JSON (hooks.json)
**Primary Dependencies**: `jq`, `yq`, `specify` CLI, shared shell scripts in `spex/scripts/hooks/shared/`
**Storage**: Marker files in `$TMPDIR` (session-scoped), `.specify/.spex-state` (pipeline state)
**Testing**: Manual smoke test (Codex session), `make release` for schema validation
**Target Platform**: macOS, Linux, Windows (via python-resolve.sh)
**Project Type**: Plugin (hook scripts for Codex CLI agent)
**Constraints**: No changes to shared shell scripts; hooks.json format already fixed

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Following full SDD workflow |
| II. Extension Architecture | Pass | Hook scripts live in `spex/scripts/adapters/codex/` |
| III. Extension Composability | Pass | Codex adapter is independent of other extensions |
| IV. Quality Gates | Pass | Ship pipeline runs all gates |
| V. Naming Discipline | Pass | Branch `040-codex-hook-contract` follows pattern |
| VI. Skill Autonomy | N/A | No skills are modified |
| VII. State as Scripts | Pass | Marker file operations stay in Python; state management delegates to shell scripts |

## Project Structure

### Documentation (this feature)

```text
specs/040-codex-hook-contract/
├── spec.md
├── plan.md              # This file
├── research.md          # Codex hook contract reference
├── data-model.md        # stdin/stdout JSON schemas
└── checklists/
    └── requirements.md
```

### Source Code (files to modify)

```text
spex/scripts/adapters/codex/
├── context-hook.py      # UPDATE: stdin/stdout contract (FR-001, FR-002)
└── pretool-gate.py      # UPDATE: stdin/stdout contract (FR-003, FR-004, FR-005)
```

Already fixed (not in scope):
```text
spex/setup.yml           # DONE: hooks.json event-grouped format (FR-009, FR-010, FR-011)
spex/scripts/spex-init.sh # DONE: hooks.json event-grouped format (FR-009, FR-010, FR-011)
```

## Implementation Approach

### Phase 1: Update context-hook.py (FR-001, FR-002, FR-006, FR-007, FR-008, FR-012)

**What changes:**
1. **Stdin parsing** (line 62-69): Replace `session_id` with `turn_id`. Add `permission_mode`, `transcript_path` to parsed fields (ignored but documented). Keep `prompt` and `cwd` (same field names).
2. **Session ID resolution**: Use `turn_id` from stdin as the session identifier for marker file naming. Fall back to `"unknown"` if absent.
3. **Stdout formatting** (lines 91-94, 140-150): Replace `{"action": "context", "message": "<text>"}` with `{"systemMessage": "<text>"}`.
4. **Docstring update**: Update the documented contract in the module docstring.

**What stays the same:**
- `run_shared()` function and all shared script calls (identical arguments)
- `get_marker_path()`, `clear_marker()` functions
- `/spex:` command detection logic
- Plugin root resolution
- Enforcement block construction
- All shared script arguments: `[prompt, session_id, cwd, plugin_root]`

### Phase 2: Update pretool-gate.py (FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-012)

**What changes:**
1. **Stdin parsing** (lines 96-104): Replace `session_id` with `turn_id`. Add `permission_mode` to parsed fields (ignored). Keep `tool_name`, `tool_input`, `cwd` (same field names).
2. **Session ID resolution**: Use `turn_id` for marker file naming. Fall back to `"unknown"`.
3. **Deny output** (lines 68-71): Replace `{"action": "deny", "message": reason}` with `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}`.
4. **Context output** (lines 74-77): Replace `{"action": "context", "message": text}` with `{"systemMessage": text}`.
5. **Docstring update**: Update the documented contract.

**What stays the same:**
- `run_shared()` function and all shared script calls (identical arguments)
- `tmpdir()`, `marker_path()`, `parse_result()` functions
- `side_effects()` function
- Gate execution order (skill-gate, teams-gate, stage-gate, verify-gate)
- All shared script arguments (verified against Claude Code adapter)

### Phase 3: Verification

1. Run `make release` to validate plugin structure
2. Test hooks.json generation: run setup with `integration=codex` on a test repo
3. Manual smoke test: start Codex, type `/spex:help`, verify context injection

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `turn_id` is per-turn, not per-session | Medium | High (markers won't persist) | Verified assumption in spec; if wrong, swap to stable identifier from `transcript_path` |
| Codex contract changes again in future version | Low | Medium | Hook scripts are thin wrappers; only I/O layer needs updating |
| Shared scripts get different arguments | Low | High | Explicit argument verification against Claude Code adapter |

## Complexity Assessment

This is a **low-complexity** change:
- 2 files modified (Python scripts)
- Only I/O layer changes (stdin parsing, stdout formatting)
- Internal logic and shared script delegation unchanged
- No new dependencies
- No architectural changes
