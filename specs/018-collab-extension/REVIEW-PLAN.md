# Review Guide: spex-collab Extension

**Spec:** [spec.md](spec.md) | **Plan:** [plan.md](plan.md) | **Tasks:** [tasks.md](tasks.md)
**Generated:** 2026-04-26

---

## What This Spec Does

When a team uses the spec-driven development workflow, the spec, plan, and implementation together can produce thousands of lines of structured artifacts and code. A single PR containing all of that is difficult to review meaningfully. This extension generates `REVIEWERS.md`, a human-readable guide that helps reviewers complete their review within 30 minutes, and splits implementation into phase-based PRs with pause points between phases.

**In scope:** REVIEWERS.md generation for spec and code PRs, task-based phase splitting, PR creation via `gh`, cross-session phase state persistence.

**Out of scope:** Reviewer assignment, automated merging, CI/CD integration, comment/feedback tracking. The extension creates PRs but never merges them and never monitors external systems.

## Bigger Picture

This extension is the implementation of the collaborative SDD workflow described in the README's Workflow section. It consolidates what were previously three separate review files (REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md) into a single `REVIEWERS.md` artifact. The spex-gates validation logic still runs, but outputs findings to console only when spex-collab is enabled. Without this extension, the two-phase PR workflow described in the README is a manual process.

The extension depends on spex-gates but modifies its output behavior: when spex-collab is enabled, spex-gates suppresses file output (FR-014). If spex-collab is disabled, vanilla spec-kit behavior is preserved, including the original separate review files. This is the first extension that both manages cross-session state (via `.spex-state`) and alters another extension's output, which sets precedents for inter-extension coordination.

---

## Spec Review Guide (30 minutes)

> This guide helps you focus your 30 minutes on the parts of the spec and plan
> that need human judgment most.

### Understanding the approach (8 min)

Read [User Story 1](spec.md#user-story-1---spec-pr-with-reviewersmd-priority-p1) and [User Story 2](spec.md#user-story-2---phase-based-implementation-prs-priority-p1) for the two core capabilities. As you read, consider:

- Are both stories truly P1? Story 2 (phase splitting) is substantially more complex than Story 1 (REVIEWERS.md generation). Would delivering Story 1 first as MVP and Story 2 as a follow-up be more pragmatic?
- The [Extension Integration](spec.md#extension-integration) section acknowledges that spec-kit lacks a phase boundary hook. Does the phase-manager approach (user invokes a command after each phase) feel natural enough, or is the friction too high?
- The spec assumes task phases map to user story headings in tasks.md. Is this assumption reliable across different project types, or could tasks.md structure vary enough to break phase detection?

### Key decisions that need your eyes (12 min)

**Phase boundary via user-invokable command** ([Research: Phase Boundary](research.md))

Since spec-kit has no `after_implement_phase` hook, the plan uses a user-invokable `phase-manager` command instead of wrapping `/speckit-implement`. This preserves transparency (FR-009) but means the user must remember to invoke the command after each phase.
- Does this trade-off feel right? The alternative (wrapping implement) was rejected for violating skill autonomy, but it would be more seamless.

**State namespacing under `collab` key** ([Data Model: Phase Plan](data-model.md#phase-plan-in-spex-state))

The extension stores all its state under a `collab` namespace in `.spex-state` rather than at the top level. This is a new pattern, as existing state fields (`implemented`, `clarified`) sit at the top level.
- Should this set the precedent for all extensions, or should spex-collab follow the existing flat pattern for consistency?

**PR target branch is always `main`** ([Clarifications](spec.md#clarifications))

Each phase PR targets `main` with sequential deltas. This is simple but means each phase PR must wait for the previous one to merge before opening.
- Does this create a bottleneck for teams with slow review cycles? Would stacked PRs (each targeting the previous) be more practical?

**REVIEWERS.md regeneration on re-run** ([Clarifications](spec.md#clarifications))

Spec sections are overwritten on re-run, but code phase sections are preserved. This means the spec REVIEWERS.md always reflects current state, but older code phase guidance persists even if the spec changed.
- Is there a scenario where stale code phase sections would mislead reviewers after a spec update?

### Areas where I'm less certain (5 min)

- [FR-014](spec.md#functional-requirements): This is the first time one extension modifies another extension's behavior. The spec says spex-gates should suppress file output when spex-collab is enabled. Does this create a coupling that violates constitution principle III (Extension Composability)? The manifest `requires` declaration makes the dependency explicit, but the behavioral change is implicit.

- [Edge case: change split mid-implementation](spec.md#edge-cases): The spec says users can "re-group remaining phases but not already-completed ones." The data-model.md now clarifies this: completed phases are immutable, remaining phases can be re-grouped. Is this distinction clear enough for the implementation?

- The [Assumptions](spec.md#assumptions) section mentions that `review_brief.md` from the brainstorm command is "superseded" by REVIEWERS.md. T028 tracks this as a follow-up issue, but until it ships, two competing review guides could coexist and confuse reviewers.

### Risks and open questions (5 min)

- If a user forgets to invoke `phase-manager` after a phase completes (since there is no automatic hook), does the workflow break silently? Should the `before_implement` hook on subsequent runs detect that a phase completed without phase-manager and prompt the user?

- The extension requires `spex-gates >= 1.0.0`. What happens if a user has spex-gates disabled but spex-collab enabled? The manifest declares the dependency, but does spec-kit enforce it at enable time?

- SC-001 ("review within 30 minutes") is the primary success criterion but is inherently subjective. Is there a way to validate this before shipping, such as timing a review of this very feature's spec using the generated REVIEWERS.md?

---
*Full context in linked [spec](spec.md) and [plan](plan.md).*
