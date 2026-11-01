# Brainstorm: Evolve cascade via speckit-converge

**Date:** 2026-11-01
**Status:** active

## Problem Framing

`speckit-spex-evolve` changes spec.md after implementation has started or finished, either to catch the spec up to the code or to require new behavior. The command then says: "Never manually edit plan.md or tasks.md. Always regenerate via `/speckit-plan` and `/speckit-tasks`." For a feature whose tasks are already done, that instruction is destructive. Regenerating tasks.md wipes the `[X]` completion state, which spec-kit keeps inside the task list itself. Agents notice the conflict and skip the cascade ("Rerunning /speckit-plan and /speckit-tasks would overwrite the completed task list"). That leaves the spec, plan and tasks inconsistent, with no defined rule for which one wins.

Upstream spec-kit now ships `/speckit-converge`, and it is already installed in spex projects. It reads spec.md, plan.md and tasks.md as the source of intent, checks the code against them, and **only appends** a `## Phase N: Convergence` section of traced tasks (`- [ ] T042 ... per FR-003 (missing)`). It never rewrites, renumbers or deletes existing tasks. When nothing is missing, tasks.md stays byte-for-byte unchanged. This is the speckit-native way to bring tasks up to date after intent changes.

## Approaches Considered

### A: Evolve hands off to `/speckit-converge` (chosen)
Evolve decides the direction, edits spec.md, appends a dated amendment to plan.md when plan decisions change, then invokes `/speckit-converge`.
- Pros: reuses upstream task logic, so spex adds no task format of its own. Works the same way in ship and in step-by-step mode. Spec-catches-up-to-code leaves tasks.md unchanged automatically.
- Cons: `/speckit-analyze` and review gates may flag finished tasks that still carry the old targets. They need guidance to treat superseded `[X]` tasks as history.

### B: Evolve writes its own `Phase N: Evolution` section
- Pros: every evolve leaves a visible entry in tasks.md.
- Cons: duplicates converge's logic and adds a spex task format next to upstream's. Pre-checked "spec caught up" tasks record work that never happened.

### C: Separate `evolution.md` changelog per feature
- Pros: fully decoupled, so plan and tasks are never touched.
- Cons: converge, analyze and implement never read it, so evolved intent is invisible to the pipeline. That is the opposite of speckit-compatible.

## Decision

Approach A. Decisions made along the way:

1. **tasks.md is an execution log (append-only).** Finished tasks stay as written. Old targets in completed tasks are planning history, not drift.
2. **plan.md gets dated amendments, not regeneration.** When an evolve changes something plan.md describes (a target, a threshold, a design choice), append a `## Amendments` entry: date, what changed, why, and the affected FR/SC IDs. The original plan text stays. Converge reads the amendment as current intent. Regenerating via `/speckit-plan` is dropped because it churns plan.md and its design docs (research.md, data-model.md, contracts/) beyond the actual change.
3. **Fix-code resolutions go through converge, except trivial ones.** Major and critical "spec is right, code is wrong" fixes become traced `contradicts` tasks via converge, then `/speckit-implement`. Trivial fixes (naming, formatting) stay direct.

Resulting evolve cascade:

| Evolve resolution | spec.md | plan.md | tasks.md |
|---|---|---|---|
| Update/clarify spec (code already right) | edit, mark evolved FRs | amendment if a plan decision changed | converge reports converged, so no change |
| Update spec (new behavior required) | edit, mark evolved FRs | amendment if a plan decision changed | converge appends Convergence phase, then implement |
| Fix code (major/critical) | unchanged | unchanged | converge appends `contradicts` task, then implement |
| Fix code (trivial) | unchanged | unchanged | unchanged, direct fix |

## Key Requirements

- Replace the "never manually edit, always regenerate" instruction in `speckit.spex.evolve.md` with the cascade above.
- Mark evolved requirements in spec.md in a recognizable way (for example a trailing `*(evolved YYYY-MM-DD)*`) so reviewers and converge can see what changed.
- Define the plan.md `## Amendments` entry format (date, change, rationale, affected FR/SC IDs), appended at the end of plan.md.
- After the spec and plan edits, evolve invokes `/speckit-converge`. On `tasks_appended`, it proceeds to (or recommends) `/speckit-implement`. On `converged`, it reports that and stops.
- Guide downstream consumers (review-code, verify, `/speckit-analyze` usage in spex) to treat completed tasks that are superseded by later amendments as history, not inconsistency.
- Keep `.specify/` upstream files untouched. All changes live in spex extension commands.
- Update README.md and spex/docs/help.md to describe the evolve cascade.

## Open Questions

- How should evolve run inside ship (auto-triggered from review-code)? Does a converge + implement loop need flow-state support or a cap on iterations?
- Should spex-collab `revise` move to the same append-only model, or keep regenerate + `reconcile` because pre-merge spec PRs work differently from post-implementation evolution?
- How does `/speckit-analyze` behave in practice with superseded `[X]` tasks? Is skill guidance enough, or do amendments need an explicit "supersedes T0xx" reference?
- Is the "trivial vs. major" boundary for fix-code taken from evolve's existing severity classification, or does it need a separate rule?
- Relation to the `openspec-style-proposal-short-run` inbox idea: amendments plus converge already form a small delta model for existing specs.
