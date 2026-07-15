# Brainstorm: Codex Integration for Deep Review

**Date:** 2026-07-14
**Status:** active

## Problem Framing

The deep-review extension dispatches 5 specialized Claude agents (correctness, architecture, security, production readiness, test quality) and optionally invokes external CLI tools (CodeRabbit, Copilot) for additional perspectives. Codex (OpenAI's coding agent) has a built-in `codex review` CLI subcommand that provides an independent, model-diverse review. Integrating it as an external tool would give deep-review a third-party perspective from a different model family, increasing the chance of catching issues that Claude-based agents miss.

The constraint: when spex itself is running inside Codex (via the Codex harness adapter), invoking `codex review` would be recursive and wasteful. The integration must detect this and skip.

## Approaches Considered

### A: External tool via codex-companion plugin

Use the codex-companion plugin's `codex-companion.mjs review` wrapper, which handles auth, target resolution, and JSON-RPC communication with the Codex app-server.

- Pros: Handles complexity internally, structured output
- Cons: Depends on the Claude Code codex plugin being installed (`CLAUDE_PLUGIN_ROOT`), adds a Node.js dependency, the plugin is a Claude Code-specific integration layer not needed for our simple use case

### B: Direct `codex review` CLI call

Call the `codex review` CLI binary directly, following the exact same pattern as CodeRabbit.

- Pros: Simple, stable (Rust binary), no plugin dependency, same detection/invocation pattern as CodeRabbit, works anywhere `codex` is installed
- Cons: Free-text output requires parsing, no structured output schema

### C: Plugin-aware with direct fallback

Try the codex-companion plugin first, fall back to direct CLI.

- Pros: Most robust
- Cons: Two code paths to maintain, unnecessary complexity

## Decision

**Approach B: Direct `codex review` CLI call.** The `codex review` subcommand is a first-class CLI feature with proper flags (`--base`, `--uncommitted`). It requires no plugin wrapper and follows the exact same external tool pattern already used for CodeRabbit. The recursion guard is handled cleanly by the existing harness adapter system.

## Key Requirements

1. **Config**: Add `codex: true` to `external_tools:` in `deep-review-config.yml` (enabled by default, like CodeRabbit)
2. **Detection**: `which codex >/dev/null 2>&1` at runtime, respecting the config toggle
3. **Recursion guard**: Wrap Codex detection and dispatch in a harness marker block (e.g., `{harness:codex-review-tool}...{/harness:codex-review-tool}`) that is present for Claude/OpenCode adapters but omitted by the Codex adapter's command-map
4. **Invocation**: `codex review --base $MAIN_BRANCH` for initial review, `codex review --uncommitted` for fix-loop re-review rounds
5. **Output parsing**: Parse Codex's free-text review output, extract file/line/severity/description, normalize to the common finding schema with `source_agent = "codex"`, `confidence = 75`
6. **Fix loop integration**: Codex findings with Critical/Important severity enter the fix loop identically to CodeRabbit findings
7. **Reporting**: Add "Codex (external)" row to the agent summary table in Step 9
8. **Adapter update**: Add the harness marker token to Claude and OpenCode command-maps (include the block), and ensure it is absent from the Codex command-map (skip the block)

## Open Questions

- What is the exact output format of `codex review`? Need to test with a real diff to determine the parsing strategy. May need structured output flags if available.
- Should Codex review run in parallel with the 5 internal agents (alongside CodeRabbit), or sequentially in Step 4? Following the CodeRabbit pattern suggests Step 4 (after internal agents).
- How should auth failures be handled? If `codex review` fails because the user isn't logged in, log the failure and skip (same as CodeRabbit error handling).
