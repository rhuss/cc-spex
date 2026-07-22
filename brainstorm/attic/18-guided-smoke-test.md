# Brainstorm: Guided Smoke Test and Ship Pipeline Safety

**Date:** 2026-06-11
**Status:** abandoned (superseded by #24-smoke-test-rethink)

## Problem Framing

Two related problems surfaced from the backpressure loops discussion and brainstorm #12's post-mortem:

**1. Runtime bugs slip through code review.** The deep review runs 5 specialized agents against the code, but all analysis is static. Brainstorm #12 documented a case where the deep review passed, all unit tests passed, but a real bug (controller-runtime's `r.Patch()` wiping in-memory state) was only caught by manual testing on a live cluster. No amount of code review can catch bugs that only manifest at runtime.

**2. Ship mode auto-merges without human validation.** The current ship pipeline finishes by auto-merging to main (when collab is not enabled) or auto-creating a PR. For a fully autonomous pipeline, this is risky: the code was generated, reviewed, and merged without a human ever running it. The smoke test creates a natural pause point, but even without the smoke test, auto-merging should be reconsidered.

## Context: Existing Skills

The system already has `/run` and `/verify` skills that can launch apps and check behavior. The smoke test concept builds on these but adds structure (spec-driven scenarios) and interactivity (step-by-step guided experience).

Brainstorm #12 proposed a "Live Smoke Test Gate" (Proposal 4) but dismissed it as too heavyweight. This brainstorm takes a different angle: not a heavyweight gate, but an interactive guided experience that Claude facilitates step by step.

## Approaches Considered

### A: Guided Smoke Test with Differentiated Ordering (Chosen)

A standalone `/speckit-spex-smoke-test` command that parses acceptance scenarios from spec.md and walks the user through each one interactively. Two different pipeline orderings depending on the mode:

**Regular flow:** implement → smoke test (interactive) → deep review → verify/stamp
- The user is present, so smoke test first catches runtime bugs early
- Deep review then reviews code that actually works, and any smoke test fixes get reviewed too
- This is the ideal ordering from brainstorm #12's lessons: fixes get reviewed

**Ship mode:** implement → deep review (autonomous) → smoke test (interactive pause) → STOP
- Deep review runs first because it's autonomous and the user isn't present yet
- Smoke test is always interactive (some things can't be automated: checking a browser, verifying external integrations, observing behavior that requires human judgment)
- Ship mode stops after smoke test. No auto-merge, no auto-PR creation. The user manually decides the next step after validating the app works.

- Pros: Catches the exact class of bug that brainstorm #12 documented. Interactive experience matches how developers actually validate. Different ordering per mode makes each pipeline optimal. Ship stopping before merge is a safety net.
- Cons: Ship mode now always requires human interaction at the end (by design, but changes the "fully autonomous" promise). Two orderings to document and maintain.

### B: Standalone Command Only, No Pipeline Integration

Just the interactive command, no ship pipeline changes. Users invoke it when they want.

- Pros: Simplest. No pipeline changes.
- Cons: Doesn't address the ship pipeline safety issue. Relies on user discipline to run it. Misses the brainstorm #12 lesson about ordering.

### C: Fully Automated Smoke Test in Both Modes

Non-interactive smoke test everywhere, including ship mode.

- Pros: Fully autonomous pipeline preserved.
- Cons: Can't automate everything (browser checks, external integrations, visual verification). False confidence: a passing automated smoke test doesn't mean a human validated the behavior. Doesn't address the auto-merge safety concern.

## Decision

**Approach A: Guided smoke test with differentiated ordering, plus ship pipeline always stops before merge/PR.**

Two deliverables in one feature:

1. **`/speckit-spex-smoke-test` command** (new, standalone):
   - Parses Given/When/Then acceptance scenarios from spec.md
   - Detects project type and how to start the app
   - Walks through each scenario step by step: explains what it will do, executes the step (start app, run curl, check output), shows the result, waits for user confirmation
   - Records results in the state file so verify/stamp knows it was run
   - On failure, helps debug interactively before moving to the next scenario
   - Verify/stamp reminds the user if acceptance scenarios exist but no smoke test was recorded

2. **Ship pipeline behavioral changes**:
   - Reorder: deep review runs before smoke test in ship mode
   - Smoke test is always interactive in ship mode (the pipeline pauses)
   - Ship mode never auto-merges or auto-creates PRs regardless of `ask` level. After the smoke test (or after review-code if smoke test is skipped), the pipeline stops and the user manually runs `/speckit-spex-finish`
   - This changes the current behavior where ship with `ask: never` can merge autonomously

## Key Requirements

- The smoke test derives its test scenarios from spec.md acceptance scenarios (Given/When/Then), not from a separate test definition file
- Each scenario step is executed by Claude (not just described), with the user confirming results
- The command detects project type (go, node, python, etc.) and figures out how to start the app using the same detection logic as verify
- Results are recorded in the state file so verify/stamp can check whether a smoke test was run
- Ship mode always stops before merge/PR, requiring manual `/speckit-spex-finish`
- Regular flow ordering: smoke test before deep review (fixes get reviewed)
- Ship mode ordering: deep review before smoke test (deep review is autonomous, smoke test is the pause point)

## Open Questions

- How should the smoke test handle projects that can't be started locally (e.g., projects that need a cloud environment, a database, or external services)?
- Should the smoke test record its results in a persistent file (like REVIEW-CODE.md) or only in the state file?
- For the ship pipeline stop behavior: should it print explicit next-step instructions ("Run /speckit-spex-finish to merge or create a PR"), or just stop silently?
- How does the smoke test interact with the `/run` skill that already exists? Should it delegate app startup to `/run`, or handle it independently?
- Should there be a way to mark specific acceptance scenarios as "manual only" (can't be automated even partially) vs. "automatable" in the spec?
