# Smoke Test Report

**Feature**: Unified Harness Marker Syntax
**Date**: 2026-07-12
**Spec**: specs/039-robust-harness-markers/spec.md
**Result**: 3 passed, 0 skipped, 0 failed (out of 3)

---

## Scenario 1: Claude dry-run adaptation

> Run `spex-adapt-commands.sh --dry-run claude .specify/extensions spex/scripts/adapters` and verify the diff shows all `{harness:key}` tokens being replaced with Claude-specific content, with no leftover markers.

### Evidence

**Setup**: Copied source files from `spex/extensions/` to a temp directory (installed `.specify/extensions/` files predate marker migration).
**Execution**: `spex-adapt-commands.sh --dry-run claude <temp-dir> spex/scripts/adapters`
**Output**: 8 of 30 files modified. All `{harness:key}` inline tokens replaced with Claude-specific text (e.g., `{harness:subagent-mechanism}` -> `the Agent tool`). All `{harness:key}...{/harness:key}` blocks replaced with Claude-specific sections. No WARNING lines from Phase 3 leftover validation.

### Verdict: PASS

---

## Scenario 2: Codex dry-run adaptation

> Run `spex-adapt-commands.sh --dry-run codex .specify/extensions spex/scripts/adapters` and verify the diff shows Codex-appropriate replacements and fallback notes for unsupported capabilities.

### Evidence

**Setup**: Copied `spex/extensions/` to temp dir.
**Execution**: `spex-adapt-commands.sh --dry-run codex <temp-dir> spex/scripts/adapters`
**Output**: 8 of 30 files modified. All markers replaced with Codex-appropriate content (generic "subagents" instead of Claude-specific "Agent tool", text prompts instead of `AskUserQuestion`). All 19 Codex tokens have mapping entries, so no fallback notes were generated. No script warnings.

### Verdict: PASS

---

## Scenario 3: Debug mode trace lines

> Run `spex-adapt-commands.sh --debug claude .specify/extensions spex/scripts/adapters 2>debug.log` and verify `debug.log` contains trace lines for each processed marker.

### Evidence

**Setup**: Copied `spex/extensions/` to temp dir.
**Execution**: `spex-adapt-commands.sh --debug claude <temp-dir> spex/scripts/adapters 2>/tmp/spex-debug.log`
**Output**: 19 DEBUG trace lines covering all 16 unique marker keys across 8 files. Each line shows: file name, marker type (block/inline), marker key, and action (replaced). Debug output cleanly separated on stderr from adaptation summary.

### Verdict: PASS
