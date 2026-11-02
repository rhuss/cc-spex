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

---

## Revisit: 2026-11-02

### Updated Problem Framing

A first ship run (aborted at review-spec) exposed two weak spots in the original decision, and research into upstream spec-kit (v1.2.5) changed the framing:

- **Upstream separates delivery from persistence.** The delivery loop is fixed: specify, plan, tasks, implement, converge, and repeat implement/converge until done. What happens to artifacts after delivery is a team-chosen *persistence model*: flow-forward (completed feature dirs are immutable, changes get a new feature dir), living spec (spec.md is the contract, plan/tasks are regenerated), or flow-back (accepted discoveries are reconciled into any artifact). None is the default. Upstream recommends recording the choice in the constitution. Sources: `docs/concepts/spec-persistence.md`, `docs/guides/evolving-specs.md`.
- **Core deliberately has no amend/reconcile command.** [github/spec-kit#4940](https://github.com/github/spec-kit/issues/4940) (core flow-back amend step) was closed as not planned: accepting a discovery is a human decision that must be written into the intended contract *before* converge, and converge must never accept code as a substitute for documented intent. `/speckit.revise` ([#4156](https://github.com/github/spec-kit/issues/4156), PR [#4158](https://github.com/github/spec-kit/pull/4158)) was redirected to a community extension. [#4944](https://github.com/github/spec-kit/issues/4944) (open) explores opt-in persistence extensions. Extensions are the sanctioned place for this, which is what evolve is.
- **Community conventions exist.** The [reconcile extension](https://github.com/stn1slv/spec-kit-reconcile) (community catalog, v1.3.1) amends affected spec.md/plan.md sections in place with dated revision notes, appends remediation tasks, never edits `[X]` tasks, is re-run safe, writes nothing under a flow-forward constitution, and routes back to converge. Both reconcile and the revise proposal mark dead requirements as `SUPERSEDED by <ID>`, `RETIRED`, or `CANCELLED` instead of rewriting them, and give replacements new IDs.
- **Converge is not idempotent** ([#4269](https://github.com/github/spec-kit/issues/4269), open): running it while tasks are still open appends duplicates.

Weak spots in the original decision:

1. **The appended `## Amendments` section leaves stale intent in plan.md.** Converge reads the whole plan as intent, so the original (now wrong) plan text could produce false `contradicts` tasks after a spec-catches-up evolve.
2. **The `*(evolved YYYY-MM-DD)*` marker edits a requirement's meaning in place.** Completed tasks are usually tagged by user story, not FR ID, so reviewers cannot tell which completed tasks a change superseded.

### New Approaches Considered

#### D: Depend on the reconcile extension
- Pros: maintained, battle-tested conventions, already re-run safe.
- Cons: external dependency outside spex's extension set; every run is interactive (approval prompt), which conflicts with ship's autonomous mode; it takes a free-form gap report while evolve already produces structured findings.

#### E: Evolve as spex's flow-back implementation, adopting community conventions (chosen)
Keep Approach A's core (artifacts first, then converge confirms), but replace the two weak spots with the conventions upstream and the community already use, and make the persistence model explicit.

### Updated Decision

Approach E. Changes to the original decision:

1. **Requirement changes use supersede markers, not in-place rewording.** Replacing a live requirement: mark the old line `SUPERSEDED by FR-0NN` and add the replacement under a new ID. Dropping one: mark it `RETIRED`. Pure wording clarifications that do not change meaning may be edited in place. Existing IDs are never reused or renumbered. A completed task that implements a superseded or retired requirement is history by definition.
2. **plan.md is edited in place, with a dated revision note.** The affected plan section is updated so plan.md states only current intent. A `## Revision Notes` entry at the end (date, what changed, rationale, affected IDs) records the change. The original wording survives in git and in the revision note, not as live text that converge would read. research.md, data-model.md, contracts/ are only touched when the change reaches them.
3. **Persistence model is declared.** spex projects declare flow-back as the model evolve implements (constitution template / project constitution). Under a declared flow-forward model, evolve writes nothing to the completed feature and recommends a new feature directory instead. Living-spec projects may regenerate plan/tasks only when no task is complete.
4. **Unchanged from the original decision:** tasks.md is append-only and only converge appends to it; converge runs after all spec/plan edits, only when no task is still open (avoids #4269); fix-code at Minor or higher goes through converge as a traced `contradicts` task, Trivial fixes stay direct; when converge appends tasks from a verify/finish trigger, verify does not pass and finish stops.
5. **Converge is told how to read the artifacts.** Evolve passes guidance in converge's arguments: `SUPERSEDED`/`RETIRED` lines are not intent, completed tasks for them are history, revision notes explain plan changes. Upstream converge stays untouched.

### Key Requirements (updated)

- Replace evolve's "never manually edit, always regenerate" instruction with the flow-back cascade above.
- Supersede/retire marker convention compatible with the reconcile extension and the revise proposal (`SUPERSEDED by <ID>`, `RETIRED`), with no ID reuse or renumbering.
- In-place plan.md edits plus a `## Revision Notes` entry format (date, change, rationale, affected IDs).
- Evolve invokes `/speckit-converge` with interpretation guidance after spec/plan edits; on appended tasks, proceed to (or offer) `/speckit-implement`, then re-run converge once to confirm.
- Evolve respects the declared persistence model (flow-forward: no edits, recommend new feature dir).
- Review-code and verify treat completed tasks for superseded/retired requirements as history.
- No changes under `.specify/` (upstream files); all changes in spex extension files.
- Update README.md, spex/docs/help.md, and the constitution (persistence model, Principle I wording on generated plan/tasks).

### Open Threads

- Should `unrequested` converge findings pause an autonomous ship run at every oversight level (removing code is a judgment call)?
- Should spex-collab `revise` adopt the same markers, given upstream's revise proposal uses them?
- Should evolve interoperate with an installed reconcile extension (detect it and defer), or stay independent?
- Contribute to [github/spec-kit#4944](https://github.com/github/spec-kit/issues/4944) with spex's flow-back experience?
