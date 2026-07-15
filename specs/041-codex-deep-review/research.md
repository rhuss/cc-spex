# Research: Codex Integration for Deep Review

**Date**: 2026-07-14
**Feature**: 041-codex-deep-review

## Codex CLI Review Interface

**Decision**: Use `codex review` CLI directly (not the codex-companion plugin).

**Rationale**: The `codex review` subcommand is a first-class Rust binary with proper flags (`--base <branch>`, `--uncommitted`, `--commit <sha>`). It handles auth, sandbox, and RPC internally. The codex-companion plugin (`codex-companion.mjs`) is a Claude Code-specific Node.js wrapper that adds session management, background jobs, and broker multiplexing, none of which are needed for our synchronous, fire-and-forget use case.

**Alternatives considered**:
- codex-companion.mjs review: Adds Node.js dependency, requires `CLAUDE_PLUGIN_ROOT`, only works when the Claude Code codex plugin is installed
- Direct codex app-server RPC: Overkill, requires managing JSON-RPC protocol, spawning app-server process

## Codex Review Output Format

**Decision**: Parse free-text output using pattern matching for file paths, line numbers, and severity indicators.

**Rationale**: `codex review` produces markdown-formatted review text. The output includes file references, line numbers, and categorized observations. The exact format varies by review content but follows consistent patterns that can be extracted via regex matching on common markers (file paths with line numbers, severity keywords like "critical", "important", "minor").

**Alternatives considered**:
- Structured output schema: Not available for `codex review` (only for `codex exec` with `--output-schema`)
- Custom prompt via `codex exec`: Would give structured output but loses the built-in review intelligence

## Recursion Guard Mechanism

**Decision**: Use harness marker blocks (`{harness:codex-review-tool}...{/harness:codex-review-tool}`) stripped at adapt time.

**Rationale**: The existing adapter system already handles conditional content inclusion per harness. The Codex adapter's `command-map.json` simply omits the `codex-review-tool` token, so the entire Codex detection and dispatch block is removed when adapting for Codex. This is a compile-time guard (adapt-time), not a runtime check, which is more reliable.

**Alternatives considered**:
- Runtime env var check (e.g., `CODEX_SESSION_ID`): Fragile, depends on Codex's internal env vars which may change
- Plugin detection (check `CLAUDE_PLUGIN_ROOT`): Wrong abstraction, the codex plugin may be installed even when running inside Codex
- `codex --version` output parsing: Unreliable, would need to know Codex's self-identification

## External Tool Config Pattern

**Decision**: Add `codex: true` to `external_tools:` in `deep-review-config.yml`, following the exact CodeRabbit pattern.

**Rationale**: CodeRabbit is enabled by default (`coderabbit: true`), detected at runtime, and skipped silently when not installed. This is the established pattern for optional external tools. Codex follows the same contract: enabled by default, detected via `which`, skipped gracefully.

**Alternatives considered**:
- Disabled by default: Would reduce adoption; users who install Codex likely want it active
- Separate config section: Unnecessary complexity; the `external_tools` flat dict is sufficient
