# Brainstorm: Smoke Test Integration via before_finish Hook

**Date:** 2026-06-19
**Status:** active

## Problem Framing

The smoke test command (`/speckit-spex-smoke-test`, brainstorm #18, spec 025) exists as a standalone tool but has no integration point in the finish workflow. Users must remember to run it manually before `/speckit-spex-finish`. This means:

1. Users who skip straight to finish miss the smoke test entirely
2. The ship pipeline has no natural pause point for smoke testing before the verify+merge gate
3. The review-code and deep-review "next steps" text only mentions `/clear` then `/speckit-spex-finish`, with no mention of the smoke test

A secondary issue surfaced during investigation: the existing `after_finish` hook (flow-state cleanup) is dead config. The finish skill lacks the hook-reading boilerplate that core spec-kit commands use, so no hooks (before or after) fire on finish today.

## Context: How Hooks Work

Hooks in spec-kit are **AI-instruction-driven**, not framework-executed. Each command's markdown file contains instructions telling Claude to:
1. Read `.specify/extensions.yml`
2. Find hooks under `hooks.before_{command}` or `hooks.after_{command}`
3. For optional hooks, prompt the user; for mandatory hooks, auto-execute

The core commands (implement, specify, plan, tasks, etc.) all have this boilerplate. The finish skill does not, making it a gap.

The spec-kit CLI (`specify`) manages hook registration (YAML config) but does not execute hooks itself. Any hook name is accepted (no allowlist), so `before_finish` works as a hook event name without CLI changes.

## Approaches Considered

### A: Update Next-Steps Text Only

Add smoke test mention to the hardcoded "next steps" blocks in review-code and deep-review skills.

- Pros: Two-line change in two files. No hook machinery.
- Cons: Only catches users who follow the suggested next steps from a review gate. Misses direct `/speckit-spex-finish` invocations and the ship pipeline path.

### B: before_finish Hook + Next-Steps Update (Chosen)

Register `speckit-spex-smoke-test` as an optional `before_finish` hook. Also update next-steps text as belt-and-suspenders.

- Pros: Catches all paths to finish (manual flow, ship pipeline, direct invocation). Uses existing, well-tested hook pattern. Optional means users can skip. Also fixes a structural gap (finish skill not supporting hooks at all).
- Cons: Slightly more work than Option A (need to add hook-reading boilerplate to finish skill). But this is a copy-paste of ~30 lines from implement.md.

### C: Custom Logic in Finish Skill

Hard-code a smoke test check directly in the finish skill, outside the hook system.

- Pros: Self-contained, no dependency on extensions.yml.
- Cons: Breaks the extension model. Not reusable for future before_finish needs. Maintenance burden.

## Decision

**Approach B: before_finish hook in extensions.yml + hook-reading boilerplate in finish skill + next-steps text update.**

Three deliverables:

1. **Add hook-reading boilerplate to `speckit.spex.finish.md`**: Copy the pattern from core spec-kit's `implement.md` (Pre-Execution Checks section) into the finish skill before Phase 1. This enables both `before_finish` and `after_finish` hooks. The `after_finish` hook for flow-state cleanup, which is currently dead config, will start working too.

2. **Register smoke test as `before_finish` hook in extensions.yml**:
   ```yaml
   before_finish:
   - extension: spex
     command: speckit.spex.smoke-test
     enabled: true
     optional: true
     prompt: Run interactive smoke test before finishing?
     description: Walk through spec acceptance scenarios interactively
     condition: null
   ```
   `optional: true` means the user is prompted, not forced. The smoke test skill already handles "no scenarios found" gracefully.

3. **Update next-steps text in review-code and deep-review skills**:
   ```
   Review complete. To close out this feature:
     1. /speckit-spex-smoke-test    (walk through acceptance scenarios)
     2. /clear                      (free context for final gate)
     3. /speckit-spex-finish         (verify + merge/PR, all-in-one)
   ```

## Key Requirements

- The hook-reading boilerplate must match the pattern used by core spec-kit commands (implement.md is the reference)
- The before_finish hook fires before Phase 1 (verification), giving the user a chance to validate before the gate runs
- The smoke test hook must be optional (`optional: true`) so users can skip it
- The after_finish hook for flow-state cleanup should also start working as a side effect
- Next-steps text changes go in both `speckit.spex-gates.review-code.md` and `speckit.spex-deep-review.run.md`

## Open Questions

- Should the finish skill also gain `after_finish` hook-reading boilerplate (for the existing flow-state cleanup hook), or is before_finish sufficient for now?
- Should the hook-reading boilerplate be extracted into a shared include/partial that multiple extension commands can reference, to avoid copy-pasting the pattern?
