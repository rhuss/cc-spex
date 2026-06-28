# Research: Focused Interactive Smoke Test

## Summary

All technical decisions were resolved from the brainstorm and existing codebase analysis. No external research required.

## Findings

### 1. Existing Smoke Test Architecture

The current v2 smoke test (`speckit.spex.smoke-test.md`) uses a two-phase subagent architecture:
- Phase 1: Fresh-context subagent executes scenarios and collects evidence
- Phase 2: Main session presents evidence interactively for human judgment

The command parses Given/When/Then acceptance scenarios from the User Scenarios section of the spec. It categorizes scenarios as auto-verified (deterministic) or judgment (human-needed).

**Impact on this feature**: The entire command is rewritten. The subagent architecture, acceptance scenario parsing, and auto-verify categorization are all removed.

### 2. Ship Pipeline Integration Points

The ship pipeline (`speckit.spex.ship.md`) references the smoke test at Stage 8:
- Checks for scenarios via `grep -c '\*\*Given\*\*'` on the spec
- Spawns a fresh-context subagent for the smoke test
- Records results via `spex-ship-state.sh smoke-test-record`

**Impact on this feature**: Stage 8 detection changes from Given/When/Then grep to `## Smoke Test` heading detection. Subagent spawn logic simplifies but can remain for context isolation in pipeline mode.

### 3. Spec Template Structure

The spec template (`.specify/templates/spec-template.md`) currently has no `## Smoke Test` section. The template ends with the Assumptions section at line 128.

**Impact on this feature**: Add an optional `## Smoke Test` section between Success Criteria and Assumptions, with guidance comments.

### 4. Extension Hook Registration

The smoke test is registered as an optional `before_finish` hook in `.specify/extensions.yml`:
```yaml
before_finish:
- extension: spex
  command: speckit.spex.smoke-test
  enabled: true
  optional: true
```

**Impact on this feature**: No change to hook registration. The hook still fires before finish. The command itself changes behavior.

### 5. Playwright MCP Availability

Playwright MCP is available as `mcp__playwright__*` tools in the Claude Code environment. Availability can be checked by attempting to use the tools — there is no explicit availability check API.

**Impact on this feature**: The smoke test should attempt Playwright for browser scenarios and fall back to manual instructions if tools fail or are unavailable.
