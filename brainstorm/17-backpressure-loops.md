# Brainstorm: Backpressure Loops for Implementation and Post-PR

**Date:** 2026-06-11
**Status:** active

## Problem Framing

Spex runs quality gates at phase boundaries (review-spec after specify, review-plan after plan, review-code after implement, verify/stamp before finish). This catches issues at transitions but leaves two gaps:

1. **During implementation:** If task 3 breaks what task 2 built, the failure compounds silently until verify/stamp at the end. No automated checks run between tasks in `tasks.md`.

2. **After PR creation:** Once `/speckit-spex-finish` opens a PR, spex cleans up state and exits. Nobody watches CI results or responds to review comments. The collab extension's triage command handles review comment processing, but it's collab-only and requires manual invocation.

These gaps were identified after reading Lucas F Costa's "Backpressure is all you need" article, which found that per-iteration automated checks and post-PR monitoring were the two most effective mechanisms for keeping autonomous coding agents on track.

**Key insight from the article:** "Any system that relies on a human to catch the machine's mistakes will be limited by the human, not the machine." The solution is layered automated backpressure, not tighter human supervision.

## Context: What Spex Already Has

- **Phase-level gates:** review-spec, review-plan, review-code, verify/stamp (spex-gates extension)
- **Deep review:** 5 specialized review agents with fix loop (spex-deep-review extension)
- **PR comment triage:** Bot/human comment processing with auto-fix (spex-collab extension)
- **Brainstorm #12:** Post-mortem on deep review gaps, added fix-loop test execution, spec-anchored test validation, framework gotchas injection

What's missing is the connective tissue: checks *within* implementation, and a feedback loop *after* PR creation that doesn't require the collab extension.

## Approaches Considered

### A: Per-Task Test Checkpoints During Implementation (Recommended)

Add a test/lint checkpoint between tasks during `/speckit-implement`. After each task in `tasks.md` is completed, run the project's test suite before moving to the next task. If tests fail, the agent must fix them before proceeding.

- Pros: Catches compounding failures early. Low overhead (test suite already exists). Natural checkpoint boundary (tasks are meaningful units of work). Prevents "house of cards" implementations where late tasks build on broken early ones.
- Cons: Adds implementation time (test suite runs between every task). May be excessive for projects with slow test suites. Per-patch (as in the article) would be too fine-grained for spex's task-based model.

### B: Post-PR Watch Mode

Instead of cleaning up state immediately after PR creation in `/speckit-spex-finish`, offer a "watch" mode that keeps state alive and monitors the PR. Split into two concerns:

1. **CI monitoring (universal, no extension needed):** After pushing/creating a PR, watch CI status. If CI fails, read the failure, fix, and push again. This is purely mechanical.

2. **Review comment triage (generalized from collab):** Extract the core triage logic from the collab extension so it can be invoked from a post-finish monitoring loop. The collab extension keeps its interactive workflow and bot profiles, but the basic "check for new comments, assess, fix" loop becomes available to the regular flow too.

- Pros: Closes a real gap where PRs sit unattended after creation. CI monitoring is simple and high-value. Reuses existing triage infrastructure. Doesn't require the collab extension for basic CI watching.
- Cons: "Watch mode" needs a mechanism to persist across sessions (state file, `/loop`, or cron). Generalizing triage requires careful extraction to avoid breaking collab's richer workflow.

### C: Full Backpressure Extension

Create a new `spex-backpressure` extension that bundles per-task checks, post-PR monitoring, and configurable check layers (lint, test, benchmark, visual). Projects configure which checks run via a `BACKPRESSURE.md` or config file.

- Pros: Clean separation. Fully configurable. Mirrors the article's packaged approach.
- Cons: Over-engineered for what we actually need. Most of the article's layers (benchmarking, visual design review) are too domain-specific for a general framework. Creates yet another extension when the logic belongs in existing commands.

## Decision

**Approach A + B combined, without a new extension.** Keep changes within existing commands and extensions:

1. **Per-task test checkpoints:** Enhance `/speckit-implement` to run the test suite after each task completion. Gate the next task on green tests. This is a modification to the implement command, not a new extension.

2. **Post-PR CI monitoring:** Add a "watch" option to `/speckit-spex-finish` that, after creating/pushing a PR, enters a monitoring loop for CI status. On failure, attempt fix and re-push. Universal (no collab extension needed).

3. **Generalize triage for post-PR use:** Restructure the collab triage command so its core assessment/fix logic can be invoked from the post-finish monitoring loop. The collab extension keeps its bot profiles, interactive human review, and state management. The regular flow gets a lighter version focused on CI failures and basic comment response.

Approach C (new extension) is rejected as over-engineering. The backpressure concept is a property of existing commands doing more, not a separate concern.

## Key Requirements

- Per-task test runs during implementation must be opt-out (on by default), since slow test suites may make this impractical for some projects
- Post-PR watch mode must work without the collab extension installed
- When collab IS enabled, the watch mode should integrate with triage (not duplicate it)
- State file management needs to support the "finish created a PR but we're still watching" lifecycle
- The watch loop should have a configurable timeout (not watch forever)

## Open Questions

- What mechanism should the post-PR watch use? Options: keep the session alive with `/loop`, use a cron job, or rely on manual re-invocation with `/speckit-spex-finish --watch`
- Should per-task test checkpoints also run linting, or just the test suite?
- How should the state file lifecycle change? Currently finish cleans it up. Watch mode needs it to survive past PR creation but still eventually get cleaned up
- Should the watch mode handle merge conflicts (rebase against target branch)?
- How does this interact with the ship pipeline's autonomous mode? Should ship automatically enter watch mode after finish?

## References

- [Backpressure is all you need](https://www.lucasfcosta.com/blog/backpressure-is-all-you-need) by Lucas F Costa
- Brainstorm #12: Hardening the Spec-Driven Review Process (related: deep review fix loop gaps)
- Brainstorm #14: Collab Triage Lifecycle (triage command design)
- spex-collab triage command (existing PR comment processing)
- spex-gates verify command (existing end-of-pipeline verification)
