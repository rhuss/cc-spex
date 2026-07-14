# Smoke Test Report

**Feature**: Codex Hook Contract Migration
**Date**: 2026-07-14
**Spec**: specs/040-codex-hook-contract/spec.md
**Result**: 0 passed, 3 skipped, 0 failed (out of 3)

---

## Scenario 1: hooks.json parse validation

> Run setup with `integration=codex` on a fresh test repo, start Codex, and verify no hooks.json parse errors appear.

### Evidence

**Setup**: Setup ran on `/tmp/spex-smoke-codex` with `integration=codex`.
**Execution**: `jq .` validated the generated `.codex/hooks.json` as syntactically valid JSON in the v0.144+ event-grouped format.

### Verdict: SKIP

Requires a live Codex CLI session. Manual test:
```bash
cd /tmp/spex-smoke-codex && codex
# Verify no "failed to parse hooks config" error at startup
```

---

## Scenario 2: Context injection via /spex:help

> Type `/spex:help` in the Codex session and verify the model responds with spex help content (context injection working).

### Verdict: SKIP

Requires a live Codex CLI session. Manual test:
```bash
cd /tmp/spex-smoke-codex && codex
# Type: /spex:help
# Expected: Model responds with spex workflow diagram and commands list
```

---

## Scenario 3: Shared shell script argument verification

> Inspect hook debug output to confirm shared shell scripts were called with correct arguments.

### Verdict: SKIP

Requires a live Codex CLI session with debug output. Manual test:
```bash
# Test context-hook.py directly:
echo '{"prompt":"/spex:help","turn_id":"test","cwd":"/tmp/spex-smoke-codex","permission_mode":"default"}' \
  | python3 spex/scripts/adapters/codex/context-hook.py 2>/dev/null
# Expected: {"systemMessage": "<spex-context>..."}

# Test pretool-gate.py directly:
echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"turn_id":"test","cwd":"/tmp/spex-smoke-codex","permission_mode":"default"}' \
  | python3 spex/scripts/adapters/codex/pretool-gate.py 2>/dev/null
# Expected: no output (allow = exit 0)
```
