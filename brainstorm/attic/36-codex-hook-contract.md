# Brainstorm: Codex Hook Contract Migration

**Date:** 2026-07-13
**Status:** active

## Problem Framing

The Codex CLI hook contract changed significantly between when the spex adapters were written and the current v0.144.1. The adapter scripts (`context-hook.py`, `pretool-gate.py`) parse the wrong stdin format and produce output Codex ignores. Three things are broken:

1. **hooks.json structure**: Was `{"hooks": [{type, event, command}]}`, now event-grouped `{"hooks": {"PreToolUse": [{hooks: [{command, type}]}]}}`. Fixed in `ddace4e`.
2. **stdin contract**: Old format used `session_id`, `cwd`, `tool_name`, `tool_input`. New format uses `turn_id`, `prompt`, `permission_mode`, `transcript_path` for UserPromptSubmit, and different field shapes for PreToolUse.
3. **stdout contract**: Old format used `{"action": "deny/context/allow", "message": "..."}`. New format uses `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}` for denials, `{"systemMessage": "..."}` for context injection, and exit code 2 as an alternative deny mechanism.

The harness marker system (command adaptation via `spex-adapt-commands.sh`) works independently and is unaffected. But without working hooks, there's no mechanical enforcement of workflow order on Codex.

## Approaches Considered

### A: Update Python adapters in-place (Chosen)
Update `context-hook.py` and `pretool-gate.py` I/O layers to match the v0.144+ contract. Continue delegating to shared POSIX shell scripts for enforcement logic.

- Pros: Minimal change footprint, shared enforcement logic stays, clear diff
- Cons: Two serialization layers (Codex JSON -> Python -> shell -> Python -> Codex JSON)

### B: Thin shell wrappers
Replace Python adapters with shell+jq scripts that call shared scripts directly.

- Pros: Eliminates Python dependency
- Cons: `jq` not guaranteed on all systems, complex JSON in shell is fragile

### C: Abstract adapter layer
Single generic Python dispatcher with config map for both events.

- Pros: DRY, single entry point
- Cons: Over-engineered for two hooks, config indirection

## Decision

Approach A: Update Python adapters in-place. The existing scripts have good structure and error handling. Only the I/O layer (stdin parsing, stdout formatting) needs to change. Shared shell scripts remain untouched.

## Key Requirements

- Both hooks parse Codex v0.144+ stdin format correctly
- Both hooks produce valid v0.144+ stdout format (systemMessage for context, hookSpecificOutput for deny, or exit code 2)
- Shared shell scripts (skill-gate.sh, stage-gate.sh, verify-gate.sh, teams-gate.sh) called with same arguments as today
- No tool matchers (gate everything, decide internally)
- No `commandWindows` entries (python-resolve.sh handles cross-platform)
- Error handling: malformed stdin exits 0 silently (no crash)
- hooks.json uses event-grouped format (already fixed)

## Open Questions

- Should we verify the Codex stdin contract against the actual v0.144.1 binary by inspecting hook invocations, or trust the docs?
- The `transcript_path` field in UserPromptSubmit could be useful for richer context injection. Worth exploring after the core fix.
- Exit code 2 vs JSON deny response: which is more reliable across Codex versions? Start with JSON, fall back to exit code if needed.
