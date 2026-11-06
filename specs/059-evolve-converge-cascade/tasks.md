# Tasks: Evolve as Flow-Back via speckit-converge

**Feature**: `059-evolve-converge-cascade` | **Input**: [spec.md](./spec.md), [plan.md](./plan.md), [data-model.md](./data-model.md), [contracts/markers-and-converge-handoff.md](./contracts/markers-and-converge-handoff.md), [quickstart.md](./quickstart.md)

This feature changes agent instructions, not executable code. "Implementation" means editing spex extension command/doc files and the constitution; "validation" means running the `quickstart.md` scenario for each story plus `rg` structural checks. No unit-test tasks are generated (the spec requests scenario-based Independent Tests, not TDD).

**Primary file** (most tasks edit it): `spex/extensions/spex/commands/speckit.spex.evolve.md`. Tasks editing the same file run sequentially (no `[P]`).

## Phase 1: Setup

- [x] T001 Confirm the edit surface: run `rg -n 'speckit-analyze' spex` and compare `spex/docs/help.md` with `spex/extensions/spex/docs/help.md` to determine whether the two help files are synced copies or independent (this fixes the fan-out for T021, T025). Record the finding as a one-line note under the R7 section of `specs/059-evolve-converge-cascade/research.md`.

## Phase 2: Foundational (blocking prerequisites for all user stories)

- [x] T002 In `spex/extensions/spex/commands/speckit.spex.evolve.md`, replace the directive at lines ~85-90 ("After modifying the spec, regenerate dependent artifacts... **CRITICAL: Never manually edit plan.md or tasks.md. Always regenerate via /speckit-* commands**") with the flow-back framing: evolve MUST NOT invoke `/speckit-plan` or `/speckit-tasks` for a feature whose `tasks.md` has ≥1 completed task (FR-001), and MUST NOT edit `tasks.md` — post-implementation tasks are added only by `/speckit-converge` (FR-003). Covers SC-007.
- [x] T003 In the same file, add (near the resolution section) the definitions of **completed task** (`- [x]`/`- [X]`), **open task** (`- [ ]`), and **spec item**, and the FR-002 resolution→cascade table (Update/clarify spec → spec edits, plan edits if affected, then converge; Fix code Minor/Major/Critical → converge only; Fix code Trivial → direct fix, no artifact change). (FR-002)

## Phase 3: User Story 1 — Spec catches up to finished code, task history intact (P1) 🎯 MVP

**Goal**: An accepted "update spec" resolution records the change with supersede/retire markers and revision notes, then converge confirms consistency with `tasks.md` byte-identical.

**Independent test**: quickstart.md Scenario 1 (SC-001, SC-002, SC-005).

- [x] T004 [US1] In `speckit.spex.evolve.md` (Execute Resolution section, replacing the old regenerate block ~263-279), add the spec-edit rules: append ` **SUPERSEDED by <new-ID>**` to a replaced live item and add a new item with the next unused ID; use ` **SUPERSEDED**` for ID-less items (acceptance scenarios, edge cases) with the replacement directly after; never reuse/renumber/delete IDs; never edit or revive an already-marked item; a meaning-preserving wording clarification may be edited in place without a marker (FR-005, FR-006, FR-007). Use the exact strings from `contracts/markers-and-converge-handoff.md` §1.
- [x] T005 [US1] In the same file, add the spec.md `## Revision Notes` behavior: one entry per session under a `### YYYY-MM-DD: <title>` subheading listing superseded/retired/added/clarified IDs grouped by kind with a one-line rationale; create the section if missing (FR-008; contract §2).
- [x] T006 [US1] In the same file, add the plan-edit rules: edit affected plan passages in place so plan.md states only current intent (FR-009); append one structured `## Revision Notes` entry per session that edits the plan (`### YYYY-MM-DD: <title>` + **Change**/**Rationale**/**Requirements**, optional **Tasks**) (FR-010; contract §3); leave plan.md and research/data-model/quickstart/contracts unchanged where unaffected (FR-011).
- [x] T007 [US1] In the same file, add the converge hand-off: invoke `/speckit-converge` once after all session edits, only when spec.md, plan.md, and tasks.md all exist, ≥1 task complete, no open task, and ≥1 resolution routes to converge; otherwise (open tasks remain) do not invoke converge and instead list open tasks related to superseded/retired items and report converge runs after they are done (FR-004). Pass the FR-012 guidance string from contract §4 as converge `$ARGUMENTS`. On converged, report spec/plan/code agree and do NOT start implementation (FR-013).
- [x] T008 [US1] In the same file, reconcile the old "verify artifacts in sync via /speckit-analyze" step (line ~273) with the converge hand-off so it no longer implies regeneration; retain analyze usage only with the FR-025 note (added in T021). Ensure the "Verify Reconciliation" section describes a converged result, not regeneration.
- [x] T009 [US1] Validate US1: run quickstart Scenario 1 against a throwaway completed feature; run `rg -n 'regenerat' speckit.spex.evolve.md` (expect no "regenerate tasks.md for completed work" directive — SC-007) and `rg -n 'speckit-converge' speckit.spex.evolve.md` (expect present).

**Checkpoint**: US1 is the MVP — flow-back for the common "spec catches up" case works end to end.

## Phase 4: User Story 2 — Evolved spec requires new behavior (P2)

**Goal**: A new/superseding requirement the code lacks produces appended converge tasks, then implementation, then a single confirming converge.

**Independent test**: quickstart.md Scenario 2 (SC-003).

- [x] T010 [US2] In `speckit.spex.evolve.md`, add the FR-014 flow: when converge appends tasks, proceed to `/speckit-implement` inside an autonomous pipeline or offer it interactively; after implementation run converge once more with the same guidance; report converged or the remaining gaps; do not loop further on its own.
- [x] T011 [US2] In the same file, add FR-015 `unrequested`-task handling (present to the user before implementation; inside an autonomous ship run, pause at every oversight level) and FR-017 pipeline containment (the converge→implement→confirming-converge sequence runs within the review-code stage, counts against its retry limit, adds no stage; the invoked `/speckit-implement` runs in pipeline mode and skips its `after_implement` hooks). Use contract §5-§6.
- [x] T012 [US2] In the same file, add FR-016 precedence (when evolve is triggered by verify or finish and converge appends tasks: verify MUST NOT pass, finish MUST stop before squash/merge, evolve MUST NOT start implementation; tell the user to implement and re-run) and FR-018 fallback (converge unavailable/errors: keep spec+plan edits, report missing command with `/spex:init --update` hint or the error, do not regenerate or edit tasks.md).
- [x] T013 [US2] Validate US2: run quickstart Scenario 2 (appended Convergence phase traced to the new ID, pre-existing tasks.md lines unchanged, implementation runs/offered, confirming converge reports converged/gaps).

## Phase 5: User Story 3 — Code fix traced as a task (P2)

**Goal**: Non-trivial fix-code resolutions append a traced `contradicts` task via converge; trivial ones are fixed directly.

**Independent test**: quickstart.md Scenario 3.

- [x] T014 [US3] In `speckit.spex.evolve.md`, add fix-code routing by severity using evolve's existing Critical/Major/Minor/Trivial scale: Minor/Major/Critical → converge only, spec.md and plan.md unchanged, converge appends a task traced to the affected requirement; Trivial → direct code fix, converge does not run, no artifact change (FR-002 rows 2-3).
- [x] T015 [US3] Validate US3: run quickstart Scenario 3 (Minor → traced `contradicts` task, spec/plan unchanged; Trivial → direct fix, no artifact change).

## Phase 6: User Story 4 — Persistence model respected (P3)

**Goal**: Evolve honors the constitution's declared persistence model; undeclared defaults to flow-back.

**Independent test**: quickstart.md Scenario 4 (SC-006).

- [x] T016 [US4] In `speckit.spex.evolve.md`, add persistence-model detection: read the constitution for `Persistence model: <value>` with the lenient matcher (case-insensitive label/value, hyphen ≡ space in value, leading list marker/whitespace tolerated, anywhere, first match wins); recognized values flow-back/flow-forward/living-spec; absent or unrecognized → flow-back, stated once that a model can be declared (FR-019; contract §7).
- [x] T017 [US4] In the same file, add the model branches: flow-forward → on a delivered feature (all tasks complete) change no file in that feature directory and recommend a new feature directory, but apply flow-back before delivery (FR-020); living-spec → regenerate plan.md/tasks.md only when no task is complete, otherwise flow-back cascade (FR-021).
- [x] T018 [US4] Validate US4: run quickstart Scenario 4, including the spaced/bulleted `- Persistence model: living spec` form (must match) and the undeclared→flow-back path. Also exercise the matcher boundaries: an unrecognized value (e.g. `Persistence model: hybrid`) falls through to flow-back; label/value case-insensitivity (e.g. `persistence model: FLOW-FORWARD`); and "first match wins" when two matching lines are present.

## Phase 7: User Story 5 — Reviewers judge code against live intent only (P3)

**Goal**: review-code, verify, and analyze guidance assess live spec items only, so append-only history is not reported as drift. These edit different files from evolve and can run in parallel with Phases 3-6.

**Independent test**: quickstart.md Scenario 5 (SC-004).

- [x] T019 [P] [US5] In `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`, require compliance to be assessed against live spec items only: items marked `SUPERSEDED by`/`RETIRED` MUST NOT count as unmet (FR-022); no finding may rest solely on a completed task's wording (FR-023); live items the code does not satisfy are still reported (FR-024).
- [x] T020 [P] [US5] In `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`, add the same live-items-only rules (FR-022, FR-023, FR-024) and the FR-016 behavior (when evolve/converge appended tasks, verify MUST NOT pass).
- [x] T021 [US5] Add the `/speckit-analyze` guidance note (findings about superseded/retired items, or completed tasks for them, are expected and not actionable) wherever spex tells the agent to run analyze: `speckit.spex-gates.review-spec.md`, `speckit.spex.spec-kit.md`, `speckit.spex.evolve.md`, and `spex/docs/help.md` (+ the extension help copy if T001 found it independent) (FR-025). Not `[P]` — touches evolve.md and help.md shared with other tasks.
- [x] T022 [US5] Validate US5: run quickstart Scenario 5 (no finding whose only evidence is a superseded/retired item or a completed task's wording; a genuinely unmet live requirement is still reported).

## Phase 8: Polish & Cross-Cutting Concerns

- [x] T023 Update `.specify/memory/constitution.md`: add the line `Persistence model: flow-back`; clarify that "plan and tasks SHOULD be generated by `/speckit-plan` and `/speckit-tasks`" applies before implementation and that after implementation, flow-back edits and converge-appended tasks are expected; correct the dotted `/speckit.plan` / `/speckit.tasks` references to the hyphen form (FR-028). Bump the constitution version and Sync Impact Report header.
- [x] T024 [P] Update `README.md` to describe evolve's flow-back cascade: supersede/retire markers, revision notes, the converge hand-off, append-only `tasks.md`, and persistence-model handling (FR-027).
- [x] T025 [P] Update `spex/docs/help.md` (and `spex/extensions/spex/docs/help.md` if T001 found it independent) with the same flow-back description (FR-027) and the analyze note (FR-025 overlap).
- [x] T026 Scope-boundary + regression check: confirm no file under `.specify/` except `constitution.md` was modified (FR-026) via `git status`; run `make validate` (schema) and `make test-install` (install/integration, self-cleaning) to confirm no command/hook/skill regressions. Do NOT run `make release` (it versions, commits, tags, pushes, and creates a GitHub release).
- [x] T027 Final cross-reference sweep: `rg` across all edited files for stale "regenerate tasks" directives and broken `/speckit-*` references; confirm each of SC-001 through SC-007 has a documented validating scenario in quickstart.md.

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002-T003)** must complete before any user story.
- **US1 (T004-T009)** depends on Foundational. It is the MVP; complete and validate it first.
- **US2 (T010-T013)** and **US3 (T014-T015)** extend the US1 cascade in the same file → run after US1, sequentially (same file).
- **US4 (T016-T018)** depends on Foundational; edits evolve's entry decision → after US1 to avoid conflicting edits in the same file.
- **US5 (T019-T022)** edits different files (gates) and is independent of US1-US4; T019 and T020 are `[P]` with each other and may proceed in parallel with the evolve phases. T021 touches evolve.md/help.md so it is sequenced after the evolve edits and before/with docs.
- **Polish (T023-T027)**: T024 and T025 are `[P]`; T023 (constitution) independent; T026/T027 run last.

## Parallel Execution Examples

- Early parallel track: `T019` (review-code) and `T020` (verify) can run together, and alongside the US1-US4 evolve edits, since they touch separate files.
- Docs parallel: `T024` (README.md) and `T025` (help.md) can run together once behavior is settled.

## Implementation Strategy

- **MVP** = Phase 1-3 (Setup, Foundational, US1). This delivers flow-back for the most common evolve outcome and is independently testable via quickstart Scenario 1.
- Then layer US2, US3 (same file, sequential), US4, and the independent US5 gate edits.
- Finish with constitution, docs, and the scope-boundary/regression sweep.
- Keep all edits inside spex extension files and the constitution (FR-026); never touch upstream `.specify/` templates, scripts, or generated commands.
