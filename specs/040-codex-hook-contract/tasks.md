# Tasks: Codex Hook Contract Migration

**Feature**: 040-codex-hook-contract
**Generated**: 2026-07-13
**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Phase 1: Setup

- [x] T001 Read current Codex adapter scripts and Claude Code adapter scripts to verify shared script argument parity: `spex/scripts/adapters/codex/context-hook.py`, `spex/scripts/adapters/codex/pretool-gate.py`, `spex/scripts/hooks/context-hook.py`, `spex/scripts/hooks/pretool-gate.py`

## Phase 2: US1 - Update context-hook.py stdin/stdout contract

Goal: Context injection works on Codex v0.144+ (FR-001, FR-002, FR-006, FR-008, FR-012)

- [x] T002 [US1] Update module docstring in `spex/scripts/adapters/codex/context-hook.py` to document the v0.144+ stdin contract (`prompt`, `turn_id`, `cwd`, `permission_mode`, `transcript_path`) and stdout contract (`{"systemMessage": "..."}`)
- [x] T003 [US1] Replace `session_id` stdin field with `turn_id` in `main()` of `spex/scripts/adapters/codex/context-hook.py`, falling back to `"unknown"` if absent
- [x] T004 [US1] Replace all `{"action": "context", "message": ...}` stdout calls with `{"systemMessage": ...}` in `spex/scripts/adapters/codex/context-hook.py`
- [x] T005 [US1] Verify shared script call arguments in `run_shared('context-hook.sh', [...])` match Claude Code adapter: `[prompt, session_id, cwd, plugin_root]`

## Phase 3: US2 - Update pretool-gate.py stdin/stdout contract

Goal: Tool gating works on Codex v0.144+ (FR-003, FR-004, FR-005, FR-006, FR-008, FR-012)

- [x] T006 [US2] Update module docstring in `spex/scripts/adapters/codex/pretool-gate.py` to document the v0.144+ stdin contract and stdout formats
- [x] T007 [US2] Replace `session_id` stdin field with `turn_id` in `main()` of `spex/scripts/adapters/codex/pretool-gate.py`, falling back to `"unknown"` if absent
- [x] T008 [US2] Replace `codex_deny()` output format from `{"action": "deny", "message": reason}` to `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}` in `spex/scripts/adapters/codex/pretool-gate.py`
- [x] T009 [US2] Replace `codex_context()` output format from `{"action": "context", "message": text}` to `{"systemMessage": text}` in `spex/scripts/adapters/codex/pretool-gate.py`
- [x] T010 [US2] Verify all shared script call arguments (`skill-gate.sh`, `stage-gate.sh`, `verify-gate.sh`, `teams-gate.sh`) match Claude Code adapter arguments in `spex/scripts/adapters/codex/pretool-gate.py`

## Phase 4: US3 - Verify hooks.json generation (already implemented)

Goal: Confirm setup generates valid hooks.json (FR-009, FR-010, FR-011)

- [x] T011 [US3] Verify `spex/setup.yml` codex-hooks step generates event-grouped hooks.json with `python-resolve.sh` wrapper (read and confirm, no code changes expected)
- [x] T012 [US3] Verify `spex/scripts/spex-init.sh` codex section generates identical event-grouped format with merge support (read and confirm, no code changes expected)

## Phase 5: Polish

- [x] T013 Run `make release` to validate plugin structure and verify no regressions
- [x] T014 Test hooks.json generation by running setup with `integration=codex` on the smoke test repo at `/tmp/spex-smoke-codex`

## Dependencies

```
T001 → T002, T003, T004, T005 (read existing code first)
T002, T003, T004 → T005 (verify after changes)
T006, T007, T008, T009 → T010 (verify after changes)
T011, T012: independent (verification only)
T013: after T005, T010 (all code changes done)
T014: after T013 (validation passes first)
```

## Implementation Strategy

**MVP**: Phase 2 (US1: context injection) + Phase 3 (US2: tool gating). These are both P1 and must ship together since they're the two halves of hook enforcement.

**Parallel opportunities**: T002-T004 can run in parallel (different sections of same file). T006-T009 can run in parallel. T011 and T012 are independent of all code changes.

**Total**: 14 tasks across 5 phases
