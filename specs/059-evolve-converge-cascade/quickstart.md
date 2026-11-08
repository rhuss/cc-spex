# Quickstart: Validating Evolve Flow-Back

Phase 1 output. These scenarios prove the feature end-to-end. Each maps to a user story's Independent Test and the success criteria it covers. Because the feature changes agent instructions rather than executable code, validation is scenario-driven plus structural (`rg`) checks.

## Prerequisites

- A spex project with `/speckit-converge` available (spec-kit version spex requires). On older versions, the FR-018 fallback path is what gets validated.
- The edited evolve, review-code, verify, docs, and constitution files installed (reinstall the plugin after editing sources under `spex/`).
- A throwaway test feature with `spec.md`, `plan.md`, and a `tasks.md` whose tasks are all `- [x]` complete.

## Structural checks (fast, run first)

```bash
# SC-007: no remaining directive to regenerate tasks.md for completed features
rg -n 'regenerat' spex/extensions/spex/commands/speckit.spex.evolve.md
#   expect: only pre-implementation / living-spec-no-tasks contexts, never "regenerate tasks.md" for completed work

# Converge hand-off is wired into evolve
rg -n 'speckit-converge' spex/extensions/spex/commands/speckit.spex.evolve.md
#   expect: present (was absent before this feature)

# Marker vocabulary documented for readers (FR-027)
rg -n 'SUPERSEDED by|RETIRED|Persistence model' README.md spex/docs/help.md

# Constitution declares the model (FR-028)
rg -n 'Persistence model: flow-back' .specify/memory/constitution.md

# Plugin still validates end-to-end (no command/hook/skill regressions)
make validate        # schema validation
make test-install    # installs from local marketplace, checks extensions/commands/hooks/skills, self-cleaning
# (do NOT use `make release` for validation — it versions, commits, tags, pushes, and creates a GitHub release)
```

## Scenario 1 — Spec catches up to finished code (US1 → SC-001, SC-002, SC-005)

1. In the completed test feature, introduce a mismatch where the **code is right** and `FR-004` states a different threshold.
2. Run `/speckit-spex-evolve` and choose "update spec".
3. **Expect**: `FR-004` keeps its text plus a trailing `**SUPERSEDED by FR-0NN**`; a new `FR-0NN` states the accepted value. `plan.md` states only the new value and both files gain a dated `### 2026-...:` revision note. `tasks.md` is byte-identical. Evolve reports converged and does not start implementation. Neither `/speckit-plan` nor `/speckit-tasks` ran.

## Scenario 2 — Evolved spec requires new behavior (US2 → SC-003)

1. In the completed test feature, evolve the spec to add a requirement the code does not satisfy.
2. **Expect**: converge appends a `## Phase N: Convergence` section with tasks traced to the new ID; every pre-existing `tasks.md` line is unchanged. Evolve proceeds to `/speckit-implement` (or offers it interactively). After implementation, a single confirming converge reports converged or lists remaining gaps. No further looping.

## Scenario 3 — Code fix traced as a task (US3)

1. Introduce a code deviation of severity Minor against a correct requirement; run evolve and choose "fix code".
2. **Expect**: `spec.md` and `plan.md` unchanged; converge appends a task traced to the requirement tagged `contradicts`; implementation fixes it.
3. Repeat with a **Trivial** deviation. **Expect**: fixed directly, converge does not run, and `spec.md`/`plan.md`/`tasks.md` are unchanged.

## Scenario 4 — Persistence model respected (US4 → SC-006)

1. Add `Persistence model: flow-forward` to a test constitution; run evolve on a delivered feature.
2. **Expect**: no file in that feature directory changes; a new feature directory is recommended.
3. Replace with a naturally spaced `- Persistence model: living spec` bullet and a feature with at least one completed task; **expect** flow-back cascade (the lenient matcher recognizes the spaced, bulleted form — FR-019).
4. Remove the line entirely; **expect** flow-back behavior and a one-time note that a model can be declared.

## Scenario 5 — Reviewers judge against live intent only (US5 → SC-004)

1. After a Scenario 1 evolve, run `/speckit-spex-gates-review-code` and `/speckit-spex-gates-verify`.
2. **Expect**: neither raises a finding whose only evidence is a superseded/retired item or a completed task's old wording. A genuinely unmet **live** requirement is still reported.

## Edge cases to spot-check

- Evolve before any task is complete → may regenerate (today's behavior).
- No `plan.md`/`tasks.md` → spec edit only, no converge.
- Some tasks open → spec+plan edits applied, converge deferred; open tasks related to superseded/retired items are listed.
- Converge appends `unrequested` tasks → presented to the user; pauses a ship run at every oversight level.
- `/speckit-converge` missing → spec/plan edits kept, missing-command reported with upgrade hint, `tasks.md` untouched.
