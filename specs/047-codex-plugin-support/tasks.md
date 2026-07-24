# Tasks: First-Class Codex Plugin Support

**Input**: Design documents from `specs/047-codex-plugin-support/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Included because the specification defines automated acceptance, compatibility, fault-injection, and 100-run lifecycle criteria.

**Organization**: Tasks are grouped by user story so each story can be implemented and validated as an independent increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it uses different files and has no dependency on an incomplete task.
- **[Story]**: Maps work to a user story from `spec.md`.
- Every task names an exact file or directory.

## Shared Interfaces

Tasks that produce or consume shared behavior use these stable interfaces:

- `spex-materialize-plugin.sh --harness <claude|codex|opencode> --output <absolute-dir>` emits a staged distribution inventory and digest as JSON on stdout.
- `spex-validate-materialized.sh --harness <id> --input <absolute-dir>` returns 0 only when schema, inventory, identity, marker, path, and foreign-reference checks pass.
- `spex-init-profile.py load|propose|validate|persist --root <absolute-dir>` reads or emits an InitializationProfile JSON document; `persist` uses expected `config_revision` and atomic replacement.
- `spex-ship-state.sh create|validate|resolve|transfer|resume|recovery-start|recovery-record|recovery-complete` emits WorkflowState or WorktreeIdentity JSON on stdout and refuses invalid mutation with a nonzero exit.
- Progress adapters consume one JSON object conforming to `contracts/progress-event.schema.json` per transition and may change presentation only.
- Teams dispatch consumes one JSON object conforming to `contracts/subagent-assignment.schema.json`; writer assignments set `isolated_worktree=true` and return reviewed evidence before dependents proceed.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish directories, fixtures, and shared validation entry points used by all stories.

- [ ] T001 Create thin distribution descriptor directories and placeholder inventories in `plugins/claude/README.md` and `plugins/codex/README.md`
- [ ] T002 [P] Create unit and integration test directory conventions in `tests/unit/README.md` and `tests/integration/README.md`
- [ ] T003 [P] Add representative OpenCode adapter fixture metadata in `tests/fixtures/adapters/opencode-minimal/adapter.json`
- [ ] T004 Add JSON Schema validation target and dependencies to `Makefile`
- [ ] T005 Add shared shell test helpers for disposable homes, repositories, and worktrees in `tests/lib/test_helpers.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement shared contracts, adapter discovery, and deterministic materialization that every story consumes.

**⚠️ CRITICAL**: No user-story implementation begins until this phase passes.

- [ ] T006 [P] Add valid and invalid HarnessAdapter fixtures in `tests/fixtures/contracts/harness-adapter/`
- [ ] T007 [P] Add valid and invalid InitializationProfile, WorkflowState, WorktreeIdentity, ProgressEvent, and SubagentAssignment fixtures in `tests/fixtures/contracts/`
- [ ] T008 Implement contract validation runner for all schemas and fixtures in `tests/unit/test_contracts.sh`
- [ ] T009 Define Claude, Codex, and OpenCode adapter declarations conforming to the adapter contract in `spex/scripts/adapters/claude/adapter.json`, `spex/scripts/adapters/codex/adapter.json`, and `spex/scripts/adapters/opencode/adapter.json`
- [ ] T010 Implement deterministic staged plugin materialization with atomic output and no canonical-source mutation in `spex/scripts/spex-materialize-plugin.sh`
- [ ] T011 Implement fail-closed unresolved-marker, foreign-tool, absolute-path, identity-collision, and output-inventory validation in `spex/scripts/spex-validate-materialized.sh`
- [ ] T012 Add materialization idempotence, malformed adapter, missing map, and leakage tests in `tests/unit/test_materialize_plugins.sh`
- [ ] T013 Wire `materialize`, `validate-materialized`, and `test-unit` targets into `Makefile`

**Checkpoint**: Contracts validate and both harness distributions can be reproducibly staged without modifying shared sources.

---

## Phase 3: User Story 1 — Install and Initialize Spex in Codex (Priority: P1) 🎯 MVP

**Goal**: A Codex user installs the native plugin and completes repeatable interactive initialization with selected extensions and an enforced project security profile.

**Independent Test**: Install the Codex distribution in a clean personal marketplace, run `spex:init` in an unconfigured trusted repository with recommended extensions and Safe security, refresh it, and invoke a Spex command without manual file repair.

### Tests for User Story 1

- [ ] T014 [P] [US1] Add Codex manifest, marketplace inventory, plugin-root hook, and collision assertions in `tests/unit/test_codex_plugin_manifest.sh`
- [ ] T015 [P] [US1] Add initialization-profile transition, safer-fallback confirmation, refusal, and atomic-write tests in `tests/unit/test_initialization_profile.sh`
- [ ] T016 [P] [US1] Add recommended extension, dependency closure, explicit Teams opt-in, and refresh-preservation fixtures in `tests/unit/test_setup_profiles.sh`
- [ ] T017 [P] [US1] Add clean install, init, refresh, and first-command integration scenarios in `tests/integration/test_install_codex.sh`

### Implementation for User Story 1

- [ ] T018 [P] [US1] Create the native Codex plugin manifest and bundled hook declaration in `plugins/codex/.codex-plugin/plugin.json` and `plugins/codex/hooks/hooks.json`
- [ ] T019 [P] [US1] Add the Codex plugin to the repository personal marketplace with a collision-free identity in `.codex-plugin/marketplace.json`
- [ ] T020 [US1] Refactor extension selection to recommend gates, deep review, and worktrees while requiring explicit Teams, collaboration, and detach selection in `spex/setup.yml`
- [ ] T021 [US1] Implement InitializationProfile load, dependency validation, revisioning, and atomic persistence in `spex/scripts/spex-init-profile.py`
- [ ] T022 [US1] Implement Codex capability probing and Safe/Autonomous/YOLO mapping to trusted project configuration in `spex/scripts/adapters/codex/configure-project.py`
- [ ] T023 [US1] Make `spex:init` preserve existing selections, require confirmation for safer fallback, and leave configuration unchanged on refusal/failure in `spex/skills/init/SKILL.md` and `spex/setup.yml`
- [ ] T024 [US1] Reduce the legacy bootstrap to harness-aware setup delegation and remove generic Claude-only readiness/status-line behavior in `spex/scripts/spex-init.sh`
- [ ] T025 [US1] Merge sentinel-owned Codex guidance without replacing unrelated repository instructions in `spex/templates/agents-md/codex.md` and `spex/scripts/adapters/codex/configure-project.py`
- [ ] T026 [US1] Add Codex plugin materialization and local install targets to `Makefile`

**Checkpoint**: User Story 1 is independently installable, refreshable, and acceptance-tested as the MVP.

---

## Phase 4: User Story 2 — Run Reliable Codex Workflows in a Feature Worktree (Priority: P1)

**Goal**: Workflow state, artifact discovery, hooks, and delegated stages remain bound to the validated feature worktree across interruption and CWD resets.

**Independent Test**: Create a feature worktree from main, run two later stages including delegated review, interrupt/resume from both checkouts, and observe zero mutations or state advances in the wrong checkout.

### Tests for User Story 2

- [ ] T027 [P] [US2] Add WorkflowState identity, optimistic revision, atomic write, and schema migration tests in `tests/unit/test_ship_state.py`
- [ ] T028 [P] [US2] Add worktree identity and two-phase transfer fault injection at every transition in `tests/unit/test_worktree_transfer.py`
- [ ] T029 [P] [US2] Add competing-state, moved/deleted worktree, invalid spec, and deterministic refusal tests in `tests/unit/test_state_resolver.py`
- [ ] T030 [P] [US2] Add delegated CWD reset and 100-run wrong-checkout lifecycle scenarios in `tests/integration/test_worktree_lifecycle.sh`

### Implementation for User Story 2

- [ ] T031 [US2] Upgrade WorkflowState serialization, validation, revisions, FeatureContext, diagnostics, and machine-readable commands in `spex/scripts/spex-ship-state.py`
- [ ] T032 [US2] Expose `create`, `validate`, `resolve`, `transfer`, and `resume` state operations through `spex/scripts/spex-ship-state.sh`
- [ ] T033 [US2] Return and validate machine-readable WorktreeIdentity during creation and implement two-phase state transfer in `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md`
- [ ] T034 [US2] Replace environment/CWD authority with resolver output while retaining it only as a convenience optimization in `spex/scripts/spex-worktree-cwd.sh`
- [ ] T035 [US2] Require ship resume, spec discovery, stage advancement, and post-delegation continuation to consume validated FeatureContext in `spex/extensions/spex/commands/speckit.spex.ship.md`
- [ ] T036 [US2] Resolve Codex hook state and project paths from validated workflow context and Git root in `spex/scripts/adapters/codex/context-hook.py` and `spex/scripts/adapters/codex/pretool-gate.py`
- [ ] T037 [US2] Sync canonical state/worktree scripts into owning extensions and update the inventory in `Makefile`

**Checkpoint**: User Story 2 passes all transfer, conflict, resume, and 100-run isolation scenarios independently.

---

## Phase 5: User Story 3 — Ship Continuously Through Recoverable Blockers (Priority: P1)

**Goal**: Ship performs bounded in-scope recovery, cascades accepted revisions, and stops only at a real authority boundary or evidenced terminal state.

**Independent Test**: Inject a resolvable feasibility finding after normal retries and verify autonomous research, artifact revision, affected-gate rerun, continued execution, bounded budgets, and a precise terminal report when convergence is impossible.

### Tests for User Story 3

- [ ] T038 [P] [US3] Add RecoveryEpisode attempt/deadline transition and restart persistence tests in `tests/unit/test_ship_recovery.py`
- [ ] T039 [P] [US3] Add repeated-finding, equivalent-remedy, artifact-hash, and A→B→A oscillation tests in `tests/unit/test_recovery_convergence.py`
- [ ] T040 [P] [US3] Add downstream invalidation, earliest-stage rewind, authority pause, and terminal resume-report fixtures in `tests/integration/test_ship_recovery.sh`

### Implementation for User Story 3

- [ ] T041 [US3] Implement RecoveryEpisode lifecycle, three-attempt/1,800-second defaults, UTC deadlines, attempt evidence, and terminal states in `spex/scripts/spex-ship-state.py`
- [ ] T042 [US3] Implement normalized finding, remedy, artifact-input, and result fingerprints with repeat/oscillation refusal in `spex/scripts/spex-ship-state.py`
- [ ] T043 [US3] Replace retry-exhaustion pauses with bounded research, feasibility, revision, alternative, or decomposition recovery routing in `spex/extensions/spex/commands/speckit.spex.ship.md`
- [ ] T044 [US3] Implement affected-artifact/gate invalidation and earliest-stage rewind after accepted recovery in `spex/extensions/spex/commands/speckit.spex.ship.md`
- [ ] T045 [US3] Add focused authority-boundary pauses and terminal evidence/residual-risk/resume reporting in `spex/extensions/spex/commands/speckit.spex.ship.md`
- [ ] T046 [US3] Prevent stage completion, subagent return, context compression, and recoverable findings from ending ship in `spex/scripts/hooks/shared/stage-gate.sh` and `spex/extensions/spex/commands/speckit.spex.ship.md`

**Checkpoint**: User Story 3 independently demonstrates continuous bounded recovery and deterministic terminal behavior.

---

## Phase 6: User Story 4 — Understand Progress and Recover State in Codex (Priority: P2)

**Goal**: Codex presents normal, delegated, recovery, pause, and completion transitions natively while durable state remains authoritative.

**Independent Test**: Observe a multi-stage Codex workflow, interrupt after a transition, and verify the resumed stage matches durable state; stale visible progress is reported and corrected without installing Claude status-line support.

### Tests for User Story 4

- [ ] T047 [P] [US4] Add ordered ProgressEvent schema, sequence, transition-kind, and fallback tests in `tests/unit/test_progress_events.py`
- [ ] T048 [P] [US4] Add Codex transcript/native presentation and no-Claude-statusline initialization scenarios in `tests/integration/test_codex_progress.sh`

### Implementation for User Story 4

- [ ] T049 [US4] Emit ProgressEvent records from every workflow and recovery state transition in `spex/scripts/spex-ship-state.py` and `spex/scripts/spex-flow-state.sh`
- [ ] T050 [US4] Implement Codex native task-progress presentation with concise transcript fallback in `spex/scripts/adapters/codex/progress.py`
- [ ] T051 [US4] Report and reconcile visible-progress/state disagreement during resume in `spex/extensions/spex/commands/speckit.spex.ship.md`
- [ ] T052 [US4] Preserve Claude status-line behavior as an adapter specialization and exclude it from Codex materialization in `spex/scripts/adapters/claude/adapter.json` and `spex/scripts/adapters/codex/adapter.json`

**Checkpoint**: User Story 4 independently exposes accurate Codex progress and state-authoritative resume.

---

## Phase 7: User Story 5 — Use Optional Codex Parallel Teams Safely (Priority: P2)

**Goal**: Explicitly enabled Codex Teams parallelizes independent work with bounded context, isolated writer worktrees, reconciliation, and sequential fallback.

**Independent Test**: Run two independent writer groups plus one dependent task, verify distinct worktrees and review before dependency release, then disable subagents and complete the same work sequentially.

### Tests for User Story 5

- [ ] T053 [P] [US5] Add assignment validation, dependency/file-conflict analysis, and minimum-context tests in `tests/unit/test_subagent_assignments.py`
- [ ] T054 [P] [US5] Add isolated writer-worktree lifecycle, partial failure, reconciliation, and cleanup tests in `tests/integration/test_codex_teams.sh`
- [ ] T055 [P] [US5] Add unavailable/unsafe/not-beneficial sequential fallback scenarios in `tests/integration/test_codex_teams_fallback.sh`

### Implementation for User Story 5

- [ ] T056 [US5] Generate bounded SubagentAssignment records with explicit workdirs, effective security, dependencies, allowed files, and evidence in `spex/extensions/spex-teams/commands/speckit.spex-teams.orchestrate.md`
- [ ] T057 [US5] Implement dependency and file/contract conflict analysis before Codex dispatch in `spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md`
- [ ] T058 [US5] Allow shared read views for research and create isolated Git worktrees for concurrent writers in `spex/extensions/spex-teams/commands/speckit.spex-teams.research.md` and `spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md`
- [ ] T059 [US5] Require orchestrator wait, specification review, reconciliation, dependent release, and partial-work preservation in `spex/extensions/spex-teams/commands/speckit.spex-teams.orchestrate.md`
- [ ] T060 [US5] Implement sequential fallback as a successful execution mode when capability or safety checks fail in `spex/scripts/adapters/codex/command-map.json`

**Checkpoint**: User Story 5 independently proves safe parallel writers and lossless sequential fallback.

---

## Phase 8: User Story 6 — Maintain Multiple Harness Plugins Together (Priority: P3)

**Goal**: Maintainers build, validate, install, and evolve Claude and Codex distributions from one core while retaining an OpenCode adapter path.

**Independent Test**: Materialize and install Claude-only, Codex-only, and combined distributions; verify disjoint identities and zero leaked harness artifacts; validate an OpenCode fixture without copying shared workflows.

### Tests for User Story 6

- [ ] T061 [P] [US6] Refactor existing Claude marketplace coverage into a harness-specific suite in `tests/integration/test_install_claude.sh`
- [ ] T062 [P] [US6] Add combined manifest, cache, hook, generated-artifact, and project-config collision tests in `tests/integration/test_install_combined.sh`
- [ ] T063 [P] [US6] Add OpenCode minimal-adapter reuse and explicit degradation tests in `tests/unit/test_opencode_adapter_fixture.sh`
- [ ] T064 [P] [US6] Add released-artifact unresolved-marker and reciprocal foreign-reference scans in `tests/unit/test_harness_leakage.sh`

### Implementation for User Story 6

- [ ] T065 [P] [US6] Create the thin Claude distribution descriptor while preserving current marketplace compatibility in `plugins/claude/adapter.json`
- [ ] T066 [P] [US6] Publish capability and degradation summaries for Claude, Codex, and OpenCode in `spex/scripts/adapters/claude/capabilities.json`, `spex/scripts/adapters/codex/capabilities.json`, and `spex/scripts/adapters/opencode/capabilities.json`
- [ ] T067 [US6] Make unresolved markers, unavailable commands, foreign paths, and identity collisions fatal during release in `spex/scripts/spex-validate-materialized.sh`
- [ ] T068 [US6] Extend version synchronization and package inventories across both distributions in `Makefile`, `VERSION`, `spex/VERSION`, `spex/setup.yml`, and `spex/bundle.yml`
- [ ] T069 [US6] Add `test-install-claude`, `test-install-codex`, `test-install-combined`, aggregate `test`, and pre-tag cross-harness gates to `Makefile`
- [ ] T070 [US6] Update marketplace installation, adapter architecture, capability degradation, and coexistence documentation in `README.md`, `spex/docs/help.md`, `docs/design.md`, and `TESTING.md`

**Checkpoint**: User Story 6 independently proves shared-core maintenance, coexistence, and future-adapter extensibility.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Complete release-quality checks spanning all delivered stories.

- [ ] T071 [P] Update cross-references for specialized Codex ship and init surfaces in `spex/extensions/spex/commands/speckit.spex.ship.md`, `spex/skills/init/SKILL.md`, and `README.md`
- [ ] T072 [P] Add migration guidance from legacy Claude-only setup and old `standard|yolo|none` inputs in `docs/codex-plugin-migration.md`
- [ ] T073 Run all scenarios from `specs/047-codex-plugin-support/quickstart.md` and record evidence in `specs/047-codex-plugin-support/validation.md`
- [ ] T074 Run `make sync-scripts`, verify `make sync-scripts-check`, and inspect the resulting canonical-to-extension diff in `spex/extensions/`
- [ ] T075 Run the aggregate unit, lifecycle, recovery, materialization, and three installation suites through `make test` and document any intentional platform skips in `TESTING.md`
- [ ] T076 Run the full pre-release validation path without tagging through the release-check target in `Makefile`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: Starts immediately.
- **Phase 2 Foundational**: Depends on Phase 1 and blocks all stories.
- **US1 (Phase 3)**: Depends only on Phase 2; recommended MVP.
- **US2 (Phase 4)**: Depends only on Phase 2, though US1 is needed for the complete installed Codex demonstration.
- **US3 (Phase 5)**: Depends on US2's versioned state and resolver tasks T031–T035.
- **US4 (Phase 6)**: Depends on US2 state transitions and US3 recovery transitions.
- **US5 (Phase 7)**: Depends on US1 effective security profiles and US2 explicit worktree context.
- **US6 (Phase 8)**: Depends on US1 distribution output; it can begin in parallel with US2–US5 after the US1 manifest/materializer integration is stable.
- **Polish (Phase 9)**: Depends on every story included in the release scope.

### User Story Completion Graph

```text
Setup → Foundation → US1 ───────────────┐
                   └→ US2 → US3 → US4  ├→ US6 → Polish
                         └──────→ US5 ──┘
```

### Within Each User Story

- Write the story's tests first and confirm they fail for the intended missing behavior.
- Implement data/state contracts before orchestration that consumes them.
- Implement shared/canonical behavior before adapter presentation.
- Run the independent test and checkpoint before releasing dependent stories.

## Parallel Opportunities

- T002 and T003 can run beside T001; T006 and T007 can run together.
- US1 test tasks T014–T017 are independent; manifest tasks T018–T019 can run together.
- US2 test tasks T027–T030 are independent before state implementation begins.
- US3 tests T038–T040 can run in parallel; T041–T042 share a file and must be sequential.
- US4 tests T047–T048 can run in parallel.
- US5 tests T053–T055 can run in parallel.
- US6 tests T061–T064 and adapter declarations T065–T066 can run in parallel.
- Once US1 is stable, US2 and the early US6 coexistence work can proceed concurrently; US3/US4 and US5 follow the graph above.

## Parallel Execution Examples

### User Story 1

```text
T014: Validate Codex manifest and hook packaging in tests/unit/test_codex_plugin_manifest.sh
T015: Validate profile transitions in tests/unit/test_initialization_profile.sh
T016: Validate extension choices in tests/unit/test_setup_profiles.sh
T017: Build Codex installation journey in tests/integration/test_install_codex.sh
```

### User Story 2

```text
T027: Exercise WorkflowState in tests/unit/test_ship_state.py
T028: Fault-inject state transfer in tests/unit/test_worktree_transfer.py
T029: Exercise resolver conflicts in tests/unit/test_state_resolver.py
T030: Build 100-run lifecycle suite in tests/integration/test_worktree_lifecycle.sh
```

### User Story 3

```text
T038: Test recovery budgets in tests/unit/test_ship_recovery.py
T039: Test convergence fingerprints in tests/unit/test_recovery_convergence.py
T040: Test recovery integration in tests/integration/test_ship_recovery.sh
```

### User Story 4

```text
T047: Test semantic progress events in tests/unit/test_progress_events.py
T048: Test Codex presentation in tests/integration/test_codex_progress.sh
```

### User Story 5

```text
T053: Test assignments and conflicts in tests/unit/test_subagent_assignments.py
T054: Test isolated writers in tests/integration/test_codex_teams.sh
T055: Test fallback in tests/integration/test_codex_teams_fallback.sh
```

### User Story 6

```text
T061: Build Claude install regression suite in tests/integration/test_install_claude.sh
T062: Build combined install suite in tests/integration/test_install_combined.sh
T063: Validate OpenCode proof adapter in tests/unit/test_opencode_adapter_fixture.sh
T064: Scan harness leakage in tests/unit/test_harness_leakage.sh
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases.
2. Complete User Story 1 through T026.
3. Stop and run the US1 independent clean-install/init/refresh test.
4. Demonstrate the native Codex plugin and project profile before starting state/recovery work.

### Incremental Delivery

1. **MVP**: US1 provides native install and initialization.
2. **Reliability core**: US2 binds workflows to the correct worktree.
3. **Autonomous ship**: US3 adds bounded recovery.
4. **Codex experience**: US4 adds native progress and accurate resume.
5. **Experimental parallelism**: US5 adds safe Teams with fallback.
6. **Maintainer release**: US6 hardens shared-core multi-harness delivery.

### Parallel Team Strategy

After Foundation, one group can finish US1 while another prepares US2 tests. Once US1 and US2 are stable, separate groups can implement US3/US4, US5, and US6 files according to the dependency graph. Concurrent writers must use isolated worktrees and reconcile through the US5 contract.

## Notes

- `[P]` denotes genuinely independent files/work; tasks sharing a file are intentionally sequential.
- User-story labels provide traceability to `spec.md` acceptance scenarios and requirements.
- The exact contracts live in `specs/047-codex-plugin-support/contracts/`.
- Commit after each task or coherent task group, and run the story checkpoint before dependent work.
