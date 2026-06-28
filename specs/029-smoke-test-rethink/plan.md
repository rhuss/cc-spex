# Implementation Plan: Focused Interactive Smoke Test

**Branch**: `029-smoke-test-rethink` | **Date**: 2026-06-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/029-smoke-test-rethink/spec.md`

## Summary

Replace the v2 two-phase subagent smoke test with a focused, single-session interactive smoke test. The new command reads scenarios from an optional `## Smoke Test` section in the spec (not from acceptance scenarios), Claude automates all setup/execution/teardown, and the human only provides pass/fail judgment. Features without the section skip automatically. The spec template and ship pipeline are updated to match.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown  
**Primary Dependencies**: `jq`, `yq`, `specify` CLI, Playwright MCP (optional)  
**Storage**: File-based (SMOKE-TEST.md report, .spex-state)  
**Testing**: Manual verification via `make release` integration test  
**Target Platform**: macOS/Linux (Claude Code CLI)  
**Project Type**: CLI plugin (spec-kit extension)  
**Performance Goals**: Smoke test walkthrough under 5 minutes for 3 scenarios  
**Constraints**: Single-session execution, no subagent spawning  
**Scale/Scope**: 3-5 curated scenarios per spec

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Modifying existing extension command, following manifest patterns |
| III. Extension Composability | PASS | Smoke test remains independent, no cross-extension dependencies |
| IV. Quality Gates | PASS | Smoke test is a quality gate in the ship pipeline |
| V. Naming Discipline | PASS | Command stays `speckit.spex.smoke-test`, no naming changes |
| VI. Skill Autonomy | PASS | Smoke test command is self-contained with clear single purpose |
| VII. State as Scripts | PASS | State operations use existing `spex-ship-state.sh` script |

No violations. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/029-smoke-test-rethink/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── tasks.md             # Phase 2 output (via /speckit-tasks)
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   └── spex/
│       └── commands/
│           └── speckit.spex.smoke-test.md    # MODIFY: Rewrite smoke test command
│           └── speckit.spex.ship.md          # MODIFY: Update Stage 8
.specify/
├── templates/
│   └── spec-template.md                      # MODIFY: Add ## Smoke Test section
```

**Structure Decision**: This feature modifies 3 existing files. No new files or directories are created (aside from SMOKE-TEST.md reports generated at runtime). The changes are:
1. Rewrite the smoke test command skill
2. Update the ship pipeline's Stage 8 to use the new detection mechanism
3. Add optional `## Smoke Test` section to the spec template

## Phase 0: Research

### Decision 1: Scenario Format in `## Smoke Test` Section

**Decision**: Numbered list of short imperative instructions. Each item describes what to set up and what the human should verify. No Given/When/Then structure.

**Rationale**: The brainstorm explicitly rejected the structured Given/When/Then format used in acceptance scenarios. Prose instructions are faster to write and more natural for hand-picked validation scenarios. The smoke test command parses numbered list items.

**Alternatives considered**: 
- Given/When/Then triples (rejected — too formal for curated manual scenarios)
- YAML/frontmatter per scenario (rejected — overkill for 3-5 items)

### Decision 2: Single-Session vs Subagent

**Decision**: Single-session execution. The current session reads scenarios and executes them directly. No subagent spawning.

**Rationale**: With only 3-5 curated scenarios (all requiring human judgment), the fresh-context benefit of a subagent is negligible. The subagent overhead (spawn, context transfer, parsing structured return) exceeds the value. The human is present for every scenario, providing natural bias-correction.

**Alternatives considered**: 
- Keep subagent architecture (rejected — overhead without value for 3-5 human-judged scenarios)
- Hybrid: subagent for setup, main session for judgment (rejected — unnecessary complexity)

### Decision 3: Detection Mechanism for Skip

**Decision**: Check for the literal heading `## Smoke Test` in the spec file. If absent, skip. Simple `grep` check.

**Rationale**: Heading-based detection is robust, simple, and doesn't require parsing the full spec structure. The heading is unique enough that false positives are unlikely.

**Alternatives considered**:
- Parse spec AST (rejected — overkill for heading detection)
- Config flag in extension config (rejected — the spec is the source of truth)

### Decision 4: Playwright MCP Graceful Degradation

**Decision**: Check for Playwright MCP availability at runtime. If available, use it for browser scenarios. If unavailable, fall back to step-by-step manual instructions with URLs, actions, and what to look for.

**Rationale**: Playwright MCP is powerful but not universally available. Manual instructions ensure browser scenarios are never blocked, just less automated.

**Alternatives considered**:
- Require Playwright MCP (rejected — would block smoke tests for users without it)
- Skip browser scenarios entirely (rejected — loses validation value)

### Decision 5: Ship Pipeline Stage 8 Changes

**Decision**: The ship pipeline's Stage 8 checks for `## Smoke Test` heading instead of parsing acceptance scenarios with Given/When/Then. The `HAS_SCENARIOS` check changes from `grep -c '\*\*Given\*\*'` to `grep -c '## Smoke Test'`. The subagent spawn is removed — the smoke test runs in the main session (or a fresh subagent for context isolation in ship pipeline mode, but that subagent uses the new single-session logic internally).

**Rationale**: Aligns the pipeline with the new detection mechanism and simplified architecture.

## Phase 1: Design

### Data Model

**Smoke Test Scenario** (parsed from spec at runtime):
- `number`: Integer — position in the numbered list (1-based)
- `instruction`: String — the prose description of what to set up and verify
- `verdict`: Enum — `pass` | `fail` | `skip` (set by human during review)
- `notes`: String — optional reviewer notes
- `retry_result`: Optional — if scenario failed and was retried after fix

**SMOKE-TEST.md Report** (written to spec directory):
- Header: feature name, date, spec path, summary counts
- Per scenario: number, instruction, evidence collected, verdict, notes
- Retry documentation when applicable

### Interface Contract: `## Smoke Test` Section Format

```markdown
## Smoke Test

<!--
  Optional section. Include when the feature has a runnable artifact
  (CLI, server, UI) that benefits from interactive human validation.
  Omit for libraries, internal modules, or features without a user-facing
  runtime component.

  Write 3-5 short imperative instructions. Each describes what Claude
  should set up and what you (the human) should verify. Claude handles
  all automation; you only provide judgment.
-->

1. Start the server and verify the dashboard loads with sample data
2. Create a new item via the form and verify it appears in the list
3. Delete an item and verify the confirmation dialog works correctly
```

### Interface Contract: SMOKE-TEST.md Report Format

```markdown
# Smoke Test Report

**Feature**: <feature name>
**Date**: YYYY-MM-DD
**Spec**: <relative path to spec.md>
**Result**: N passed, M skipped, K failed (out of TOTAL)

---

## Scenario 1: <instruction text>

### Evidence

**Setup**: <what Claude did to prepare>
**Execution**: <commands run, URLs navigated, screenshots taken>
**Output**:
```
<captured output or screenshot description>
```

### Verdict: PASS | FAIL | SKIP

<reviewer notes>

---
```

### Quickstart

After implementation, the smoke test workflow is:

1. Write a spec with a `## Smoke Test` section containing 3-5 scenarios
2. Run `/speckit-spex-smoke-test` (or let the ship pipeline reach Stage 8)
3. Claude automates setup and execution for each scenario
4. Provide pass/fail judgment when prompted
5. Review SMOKE-TEST.md report in the spec directory

### Agent Context Update

The CLAUDE.md plan reference should point to this plan file during implementation.
