# Implementation Plan: Smoke Test V2 - Two-Phase Fresh Context

**Branch**: `028-smoke-test-v2` | **Date**: 2026-06-23 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/028-smoke-test-v2/spec.md`

## Summary

Rewrite the smoke test skill to use a two-phase architecture: Phase 1 spawns a subagent (fresh context, no implementation memory) to execute scenarios and collect evidence; Phase 2 presents evidence interactively in the main session for human judgement. Persist results as SMOKE-TEST.md. Update the ship pipeline's Stage 8 to use this pattern.

## Technical Context

**Language/Version**: Markdown (skill files), Bash (POSIX-compatible)
**Primary Dependencies**: Claude Code Agent tool (subagent spawning), `jq` for JSON parsing
**Storage**: N/A (file-based: SMOKE-TEST.md report, state file for pipeline integration)
**Testing**: Manual verification via smoke test invocation on a project with acceptance scenarios
**Target Platform**: Claude Code CLI (macOS/Linux)
**Project Type**: AI agent plugin (Markdown skills)
**Performance Goals**: N/A
**Constraints**: No compiled artifacts; Markdown and Bash only (constitution constraint)
**Scale/Scope**: 2 files modified (smoke test skill, ship skill), 1 file created (SMOKE-TEST.md template behavior)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Modifying existing extension command |
| III. Extension Composability | PASS | No cross-extension dependencies added |
| IV. Quality Gates | PASS | Smoke test is itself a quality gate enhancement |
| V. Naming Discipline | PASS | Same command name, `/speckit-spex-smoke-test` |
| VI. Skill Autonomy | PASS | Smoke test delegates execution to subagent, review stays in main skill |
| VII. State as Scripts | PASS | State recording continues to use `spex-ship-state.sh` |

No violations.

## Project Structure

### Documentation (this feature)

```text
specs/028-smoke-test-v2/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── tasks.md             # Phase 2 output (via /speckit-tasks)
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (files to modify)

```text
spex/extensions/spex/commands/
└── speckit.spex.smoke-test.md     # Rewrite: two-phase architecture

spex/extensions/spex/commands/
└── speckit.spex.ship.md           # Update Stage 8: announce + opt-in flow
```

**Structure Decision**: No new files created. Two existing skill files modified. The SMOKE-TEST.md report is generated at runtime by the skill (not a template file).

## Implementation Approach

### Deliverable 1: Rewrite Smoke Test Skill (FR-001 through FR-009, FR-011 through FR-013)

The existing `speckit.spex.smoke-test.md` is rewritten with the two-phase architecture. The skill retains its current name, command registration, and no-simulated-tests hard gate.

**New structure of the skill:**

1. **Preamble**: Same frontmatter, same hard gate, same ship pipeline guard
2. **Prerequisites**: Same spec resolution via check-prerequisites.sh
3. **Step 1: Parse Acceptance Scenarios**: Same scenario parsing logic (extract Given/When/Then from spec)
4. **Step 2: App Lifecycle (Main Session)**: If scenarios need a running app, detect project type and start the app. This happens in the main session before the subagent is spawned. Track the process for cleanup later.
5. **Step 3: Execute via Subagent (Phase 1)**: Spawn a subagent via the Agent tool. The prompt tells the subagent:
   - The spec file path (to read scenarios from)
   - The project root path
   - Whether the app is assumed to be running
   - Categorize each scenario: automatable, manual, or skip
   - For automatable: run the command, capture full output
   - For manual: prepare step-by-step instructions
   - For skip: explain why and provide manual instructions
   - Return structured text payload with evidence per scenario
   - MUST NOT read plan.md or tasks.md
   - MUST NOT simulate expected output
6. **Step 4: Interactive Review (Phase 2)**: Parse the subagent's return text. For each scenario:
   - Present: scenario number, user story, Given/When/Then, why it matters, evidence
   - For automated: show command + output, ask pass/fail/skip
   - For manual: show instructions, wait for human to perform and report
   - For skip: show reason + instructions, let human confirm or attempt
   - On fail: interactive debugging loop (suggest causes, offer fix, retry)
7. **Step 5: Write SMOKE-TEST.md**: Generate the report from collected verdicts
8. **Step 6: Record Results**: Same state recording via spex-ship-state.sh
9. **Step 7: Cleanup**: Stop app if main session started it

**Evidence return format** (structured text from subagent):

```
## Scenario 1 of N (User Story: <title>)
**Type**: automated | manual | skip
**Given** <precondition>
**When** <action>
**Then** <expected outcome>
**Why it matters**: <one sentence on what risk this catches>

### Evidence
**Command**: <exact command run>
**Output**:
\`\`\`
<full command output>
\`\`\`
**Observation**: <subagent's factual observation about the output>

---
```

For manual scenarios, the Evidence section contains Instructions instead of Command/Output.
For skip scenarios, the Evidence section contains Skip Reason and Manual Test Instructions.

### Deliverable 2: Update Ship Pipeline Stage 8 (FR-010)

Modify `speckit.spex.ship.md` Stage 8 to:
1. Read the spec and count scenarios (same as current)
2. Announce: "Pipeline is technically done. N scenarios found (M automated, K manual)."
3. Ask: "Ready to walk through the verification?"
4. On opt-in: invoke `/speckit-spex-smoke-test` (which runs the two-phase flow)
5. On decline: record skipped, announce completion, user runs finish manually

### Deliverable 3: Documentation Updates

Update README.md and help.md to describe the two-phase smoke test behavior.

## SMOKE-TEST.md Report Format

```markdown
# Smoke Test Report

**Feature**: <feature name>
**Date**: YYYY-MM-DD
**Spec**: <relative path to spec.md>
**Result**: N passed, M skipped, K failed (out of TOTAL)

## Scenario 1 of TOTAL (User Story: <title>)

**Given** <precondition>
**When** <action>
**Then** <expected outcome>

**Why it matters**: <explanation of what risk this scenario catches>

### Evidence

**Command**: `<exact command>`
**Output**:
\`\`\`
<full output>
\`\`\`

### Verdict: PASS | FAIL | SKIP

<any notes from the reviewer>

---
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Subagent can't execute commands in project context | Low | High | Subagent inherits CWD and file access from parent session |
| Evidence payload too large for return text | Low | Medium | Truncate long command outputs with head/tail markers |
| App started by main session dies during subagent execution | Medium | Medium | Subagent checks app health before each scenario, reports failure |
