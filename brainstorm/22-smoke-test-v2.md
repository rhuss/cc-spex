# Brainstorm: Smoke Test V2 - Fresh Context + Human Judgement

**Date:** 2026-06-22
**Status:** abandoned (superseded by #24-smoke-test-rethink)

## Problem Framing

The smoke test (spec 025, implemented) has three problems surfaced through real usage:

**1. Self-testing bias.** The smoke test runs in the same context as the implementation. The AI "knows" what it built and can unconsciously confirm its own work rather than genuinely testing it. A smoke test should validate from a fresh perspective, like a human tester who didn't write the code.

**2. Simulated tests.** When the smoke test encounters a scenario it can't exercise (e.g., requires a separate run, external infrastructure), it was observed to manually edit files to fake the expected output rather than honestly skipping. A hard gate was added (commit 27d6112) but the root cause is that execution and judgement are tangled in the same context.

**3. Insufficient explainability.** The current smoke test just shows pass/fail/skip counts. It doesn't explain why each scenario matters, what risk it catches, or present evidence in a way that enables a qualified human judgement. The report is ephemeral (console only + state file counts).

## Approaches Considered

### A: Two-Phase Smoke Test (Chosen)

Split into execution (subagent, fresh context) and review (main session, human judgement).

**Phase 1 - Execute (subagent):**
- Spawned via Agent tool, has no memory of the implementation
- Reads spec scenarios from scratch
- For each automatable scenario: runs the actual command, captures full output
- For each human-action scenario: prepares step-by-step instructions with exact commands and expected observations
- Scenarios it cannot exercise: marked as "manual" with precise instructions (no simulation)
- Returns a structured payload with all evidence

**Phase 2 - Review (main session, interactive):**
- Presents each scenario one at a time with full context
- For each scenario: Given/When/Then, why this scenario matters (what risk it catches), the evidence collected (command output, file diffs, etc.)
- For automated scenarios: shows the command and output, asks human to confirm pass/fail/skip
- For human-action scenarios: shows instructions, waits for human to perform and report back
- On fail: asks what went wrong, attempts to understand and fix, offers retry
- At the end: writes SMOKE-TEST.md to the spec directory

**Ship pipeline integration:**
- After Stage 7 (review-code), the pipeline announces: "Technically done. Here's what I've prepared for the smoke test." Lists the scenarios found and how many are automated vs. manual.
- Asks the user: "Ready to walk through the verification?" User opts in or defers.
- In standalone mode: same two-phase pattern, same report output.

- Pros: Fresh context eliminates self-testing bias. Human stays in control of judgement. Evidence is persistent. The no-simulated-tests problem is solved structurally (subagent can't simulate because it doesn't have implementation memory to draw on). Works for both ship and standalone mode.
- Cons: Two-phase adds implementation complexity. Subagent has a token cost. Scenarios requiring mid-execution human input must be handled via instruction handoff rather than real-time interaction.

### B: Mandatory /clear + Enhanced Reporting

Keep single-session model but make /clear mandatory and add full reporting.

- Pros: Simpler. No subagent coordination.
- Cons: /clear doesn't truly give fresh context (compressed history remains). AI still "knows" what it implemented. Doesn't address self-testing structurally.

### C: External Bash Runner

Parse scenarios, run commands, produce report entirely in bash.

- Pros: Truly independent, deterministic.
- Cons: Can't handle complex scenarios needing AI reasoning. Limited to simple command-and-check patterns.

## Decision

**Approach A: Two-Phase Smoke Test.** The subagent gives genuine context isolation, and the interactive review phase preserves human judgement. This solves all three problems (bias, simulation, explainability) structurally rather than through rules.

## Key Requirements

- The execution subagent MUST NOT have access to the implementation conversation context
- The execution subagent MUST read the spec and only the spec to understand what to test
- Every scenario in the report MUST include: Given/When/Then, why it matters, evidence, and a verdict prompt
- Human-action scenarios MUST have precise step-by-step instructions (exact commands, what to look for, expected vs. actual)
- The report MUST be persisted as SMOKE-TEST.md in the spec directory (alongside REVIEW-CODE.md)
- On fail: the review phase MUST ask what went wrong, attempt to understand the root cause, and offer to fix and retry
- The no-simulated-tests hard gate MUST remain: scenarios that cannot be exercised are skipped with manual instructions, never faked
- Ship pipeline: after review-code, announce readiness and ask user to opt in to the smoke test walk-through

## Open Questions

- Should the subagent also start/stop the application, or should app lifecycle be handled in the main session (where the user can intervene if startup fails)?
- Should SMOKE-TEST.md include timing information (how long each scenario took to execute)?
- How should the structured payload from Phase 1 to Phase 2 be passed: as a file (e.g., .specify/.smoke-test-evidence.json) or as the subagent's return text?
