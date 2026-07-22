# Brainstorm: Smoke Test Rethink — Interactive-Only with Maximum Automation

**Date:** 2026-06-28
**Status:** active
**Supersedes:** #18 (guided-smoke-test), #22 (smoke-test-v2)

## Problem Framing

The smoke test v2 (brainstorm #22, spec 028) improved on v1 by adding fresh-context execution, auto-verification, and structured evidence. But real usage revealed a deeper problem: **most scenarios don't need a human at all, and the ones that do get buried in noise.**

Running 17+ acceptance scenarios interactively is unsustainable. Deterministic checks (file existence, exit codes, output matching) duplicate what tests and deep review already cover. The human clicks through 15 auto-verified passes to reach the 2 scenarios that actually need eyes. For cc-spex itself — which is mostly skill files processed by Claude — the smoke test has no runnable artifact to exercise, making the entire walkthrough theater.

Three problems from v1/v2 that remain valid:
1. **Self-testing bias** (v2 solved with subagent, but irrelevant if human judges anyway)
2. **Simulated tests** (v2 added hard gate, remains as a principle)
3. **Insufficient explainability** (v2 solved with structured evidence, carry forward)

The new problem: **the smoke test tries to be both an automated test runner and a manual validation tool, and does neither well.**

## Prior Art

- **Brainstorm #18** (guided-smoke-test): Introduced the concept, pipeline integration, differentiated ordering. Status: spec-created (025).
- **Brainstorm #22** (smoke-test-v2): Two-phase subagent architecture, auto-verify, mandatory report. Status: active (028).
- **Key lessons carried forward**: No simulated tests (hard gate). Persistent SMOKE-TEST.md report. Evidence-based verdicts.

## Approaches Considered

### A: Focused Manual Smoke Test (Chosen)

Radically simplify: the smoke test is ONLY for features with runnable artifacts AND only walks through 3-5 hand-picked scenarios from a dedicated `## Smoke Test` section in the spec.

- **Spec template change**: Optional `## Smoke Test` section. If absent, no smoke test. Each scenario is a short human-readable instruction.
- **No auto-verified scenarios**. Everything in the smoke test section is interactive by definition.
- **Library/skill features**: Skip automatically (no runnable artifact, no `## Smoke Test` section).
- **Maximum automation support**: Claude handles all setup, execution, and teardown. Start servers, open browsers (Playwright), navigate URLs, fill forms, take screenshots, run commands, hit APIs, set up test data. Human only does the judgment call.
- **Single-session**: No subagent. With 3-5 curated scenarios and human judgment, fresh context adds overhead without value.
- **Report**: Compact SMOKE-TEST.md with just the curated scenarios and verdicts.

Pros: Eliminates busywork. Human time spent only on genuine judgment. 3-5 focused scenarios instead of 17+.
Cons: Requires spec authors to curate scenarios (but that's the point).

### B: Smart Filter on Existing Scenarios

Keep current architecture, add aggressive filter to only present interactive scenarios.

Pros: No spec changes.
Cons: Still parses all scenarios, filter logic is fragile, doesn't solve library-code case.

### C: Eliminate Smoke Test, Enhance /verify

Remove smoke test entirely, add optional "try it yourself?" prompt to verify gate.

Pros: One fewer command.
Cons: Loses structured walkthrough, evidence, and persistent report.

## Decision

**Approach A: Focused Manual Smoke Test with maximum automation support.**

The smoke test becomes a lean, high-value tool: Claude does all the boring setup and execution, the human only provides judgment on 3-5 curated scenarios. Features without runnable artifacts skip the smoke test entirely.

Retire brainstorms #18 and #22. Their lessons (no simulation, evidence-based, persistent report) are carried forward.

## Key Requirements

### What the smoke test IS
- An interactive validation of 3-5 hand-picked scenarios for features with runnable artifacts (CLI, server, UI)
- Claude-driven setup and execution: start servers, open browsers, navigate, fill forms, take screenshots, run commands, hit APIs, prepare test data, tear down
- Human provides only the judgment: "does this look right?" / "does this work as expected?"
- Persistent SMOKE-TEST.md report with evidence and verdicts

### What the smoke test IS NOT
- Not a test runner for deterministic checks (that's tests + deep review)
- Not applicable to library/skill features (auto-skip when no runnable artifact)
- Not a subagent architecture (single session, no fresh-context overhead)
- Not a walkthrough of ALL acceptance scenarios (only the curated `## Smoke Test` section)

### Spec template change
- Add optional `## Smoke Test` section to the spec template
- Contains 3-5 short scenario descriptions focused on interactive validation
- If the section is absent, the smoke test stage is skipped in the pipeline

### Automation support
- Detect project type and start the app (delegate to `/run` if available)
- Use Playwright MCP for browser-based scenarios (navigate, click, screenshot)
- Use `curl`/`gh api`/CLI tools for API and command-line scenarios
- Prepare test data (seed databases, create fixtures, set up state)
- Take screenshots and capture output as evidence for the report
- Clean up after (stop servers, remove test data)

### Pipeline integration
- Ship pipeline: if no `## Smoke Test` section exists, skip smoke test stage
- If section exists, pause for interactive walkthrough (always interactive, never autonomous)
- No auto-merge after smoke test; user decides next step via `/speckit-spex-finish`

### No-simulation hard gate (carried from v2)
- Every scenario must exercise the real system
- If a scenario cannot be tested, skip honestly with manual instructions
- Never fake output or edit files to simulate expected results

## Open Questions

- Should the `## Smoke Test` section be generated by the specify step (with human curation), or always written by hand?
- Should there be a maximum scenario count enforced (e.g., reject specs with >5 smoke test scenarios)?
- How should the smoke test interact with Playwright MCP availability? Graceful degradation to CLI-only, or require it for browser scenarios?
