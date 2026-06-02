# Tasks: Collab Triage Lifecycle

**Input**: Design documents from `specs/022-collab-triage-lifecycle/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Config Template)

**Purpose**: Add triage configuration to the collab extension config template

- [x] T001 Add `triage.split_threshold` (default 100) and `triage.loop_interval` (default "5m") to `spex/extensions/spex-collab/config-template.yml`

---

## Phase 2: Foundational (Flow State Script)

**Purpose**: Extend the flow state script with triage gate support. Must complete before US1/US2 can use the gates.

- [x] T002 Add `triage-spec` and `triage-impl` cases to the `do_gate()` function in `spex/scripts/spex-flow-state.sh`, mapping to `triage_spec_passed` and `triage_impl_passed` fields respectively
- [x] T003 Update the `do_create()` function in `spex/scripts/spex-flow-state.sh` to include `triage_spec_passed: false` and `triage_impl_passed: false` in the initial state JSON (only when spex-collab is enabled, checked via `.specify/extensions/.registry`)

---

## Phase 3: US1 - Triage Spec PR (P1)

**Goal**: After spec PR creation, transition to `triage-spec` flow state and display suggest-with-delay message. After triage completes, gate check in phase-manager recommends same-PR or split.

**Independent Test**: Create a spec PR with collab enabled, verify triage suggestion appears, mark triage gate, invoke phase-manager, verify gate check logic.

- [x] T004 [US1] Add suggest-with-delay message output to the spec PR creation step in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md`: read `triage.loop_interval` from collab-config.yml (default "5m"), display delay notice and `/loop {interval} /speckit-spex-collab-triage` command, set flow state running phase to `triage-spec` via `spex-flow-state.sh running triage-spec`
- [x] T005 [US1] Add gate check logic to `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md`: after `triage_spec_passed` is true, read `.specify/.pr-triage-state.json`, count total entries for the current PR, compare against `triage.split_threshold` from collab-config.yml (default 100). Below threshold: offer to update PR title to "[Spec + Impl]" and update labels. Above threshold: recommend merging spec PR as-is and creating separate impl PR(s). Present as user choice via AskUserQuestion.
- [x] T006 [US1] Add the PR title update and label change logic to `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md`: when user chooses same-PR, use `gh pr edit` to update title and labels. When user chooses split, use `gh pr merge` for spec PR and document that impl PR(s) will be created during implementation phases.

---

## Phase 4: US2 - Triage Impl PR (P1)

**Goal**: After implementation push to PR, transition to `triage-impl` flow state with suggest-with-delay. Include deep review suggestion when deep-review extension is enabled.

**Independent Test**: Push impl commits to PR, verify triage-impl suggestion appears, verify deep review suggestion when deep-review extension is enabled.

- [x] T007 [US2] Add suggest-with-delay message output after implementation push in `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md`: check if deep-review extension is enabled (from `.specify/extensions/.registry`), if yes show deep review suggestion first, then show triage-impl suggestion with `/loop {interval} /speckit-spex-collab-triage` command, set flow state running phase to `triage-impl` via `spex-flow-state.sh running triage-impl`

---

## Phase 5: US3 - Status Line T Badge (P2)

**Goal**: Display a `T` badge in the status line for triage state, only when spex-collab is enabled.

**Independent Test**: Set flow state with triage fields, run statusline script, verify T badge appears with correct indicator.

- [x] T008 [P] [US3] Add collab extension detection to the `render_flow()` function in `spex/scripts/spex-ship-statusline.sh`: read `.specify/extensions/.registry` to check if `spex-collab` is enabled. Only render the T badge when enabled.
- [x] T009 [P] [US3] Add `T` badge rendering to `render_flow()` in `spex/scripts/spex-ship-statusline.sh`: extract `triage_spec_passed` and `triage_impl_passed` from state JSON (add to the existing `IFS='|' read` line), render `T` badge using the same pattern as C/S/P/R badges (active `▶` when running is `triage-spec` or `triage-impl`, checkmark `✓` when either triage passed field is true, circle `○` when pending). Place the T badge after the R badge in the gate section.

---

## Phase 6: US4 - Configurable Thresholds (P3)

**Goal**: Ensure triage config values are read from collab-config.yml with proper defaults.

**Independent Test**: Set custom values in collab-config.yml, verify gate check uses custom threshold and suggestion shows custom interval.

- [x] T010 [US4] Verify that T004, T005, and T007 correctly read from `collab-config.yml` with shell-level fallback defaults (`${VAR:-default}` pattern). No separate task needed if the reading logic in T004/T005/T007 already uses the fallback pattern. This is a validation-only task: read the phase-manager command, confirm the config reads include fallback defaults, fix if missing.

---

## Phase 7: Polish & Documentation

**Purpose**: Update documentation to reflect the new triage lifecycle

- [x] T011 [P] Update `spex/docs/help.md` to document the triage lifecycle flow, the T badge, and the configurable thresholds
- [x] T012 [P] Update `README.md` to mention triage lifecycle in the spex-collab extension description and workflow section

---

## Dependencies

```text
T001 (config) ─────────────────────────────────────────┐
T002 (gate actions) ──┬── T004 (suggest-spec) ──┬── T005 (gate check) ── T006 (PR actions)
T003 (create fields) ─┘   T007 (suggest-impl)   │
                          T008 (collab detect) ──┤
                          T009 (T badge render) ──┘
                          T010 (validate config reads)
                          T011 (docs help)
                          T012 (docs readme)
```

## Parallel Execution

- **T008 + T009**: Both modify `spex-ship-statusline.sh` but different sections (collab detection vs badge rendering). Can be done sequentially in one pass.
- **T011 + T012**: Independent documentation files.
- **T001, T002, T003**: Can all run in parallel (different files).

## Implementation Strategy

**MVP**: T001-T006 (config + flow state + spec triage lifecycle with gate check)
**Increment 2**: T007 (impl triage lifecycle)
**Increment 3**: T008-T009 (status line badge)
**Increment 4**: T010-T012 (validation + docs)
