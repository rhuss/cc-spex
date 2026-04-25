# Tasks: Leverage Spec-Kit 0.7.x Workflows and Integrations

**Input**: Design documents from `/specs/017-workflow-integration-upgrade/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: No new project initialization needed. This feature modifies an existing plugin.

- [ ] T001 Verify spec-kit 0.7.4 is installed: `specify --version` must show >=0.7.4

---

## Phase 2: Version Bump and Legacy Cleanup (US-5)

**Purpose**: Clean starting point. Bump all manifests, remove legacy code, delete obsolete scripts.

- [ ] T002 [P] [US5] Update `speckit_version` from `">=0.5.2"` to `">=0.7.4"` in `spex/extensions/spex/extension.yml`
- [ ] T003 [P] [US5] Update `speckit_version` to `">=0.7.4"` in `spex/extensions/spex-gates/extension.yml`
- [ ] T004 [P] [US5] Update `speckit_version` to `">=0.7.4"` in `spex/extensions/spex-teams/extension.yml`
- [ ] T005 [P] [US5] Update `speckit_version` to `">=0.7.4"` in `spex/extensions/spex-worktrees/extension.yml`
- [ ] T006 [P] [US5] Update `speckit_version` to `">=0.7.4"` in `spex/extensions/spex-deep-review/extension.yml`
- [ ] T007 [US5] Remove all legacy migration functions from `spex/scripts/spex-init.sh`: `migrate_traits_config`, `migrate_phase_marker`, `migrate_old_commands`, `migrate_from_beads`, `do_beads_migration`, `fix_constitution`, `detect_old_traits`
- [ ] T008 [US5] Update version check in `spex/scripts/spex-init.sh` `check_version()` to require `>=0.7.4`
- [ ] T009 [US5] Remove `spex/scripts/spex-ship-state.sh` (251 lines, replaced by workflow engine)
- [ ] T010 [US5] Remove references to `spex-ship-state.sh` from any other files that source or call it

**Checkpoint**: All manifests show `>=0.7.4`. `rg "migrate_|fix_constitution|do_beads" spex/scripts/spex-init.sh` returns nothing. `spex-ship-state.sh` is deleted.

---

## Phase 3: Init Simplification (US-2)

**Purpose**: Rewrite `spex-init.sh` to a thin wrapper using native `specify integration install/upgrade`.

- [ ] T011 [US2] Replace `specify init --here --ai claude --force` with `specify init --here --force` in `do_init()` in `spex/scripts/spex-init.sh`
- [ ] T012 [US2] Add `specify integration install claude` call after `specify init` in `do_init()` in `spex/scripts/spex-init.sh` (use `specify integration upgrade claude` if integration already installed)
- [ ] T013 [US2] Add stale workflow marker cleanup to `do_init()`: check `.specify/.spex-workflow-active`, verify PID liveness with `kill -0`, remove if stale
- [ ] T014 [US2] Update `do_refresh()` to use `specify integration upgrade claude` instead of `specify init --here --ai claude --force` in `spex/scripts/spex-init.sh`
- [ ] T015 [US2] Update `do_update()` to use `specify integration upgrade claude` in `spex/scripts/spex-init.sh`
- [ ] T016 [US2] Remove `had_skills` tracking and `RESTART_REQUIRED` logic from `do_init()` (integration command handles skill installation natively)
- [ ] T017 [US2] Verify `wc -l spex/scripts/spex-init.sh` is under 120 lines

**Checkpoint**: Init script is under 120 lines. `/spex:init` on a fresh project installs integration and extensions. `--refresh` and `--update` flags work.

---

## Phase 4: Plugin Ecosystem Detection (US-3)

**Purpose**: Add configurable companion plugin detection.

- [ ] T018 [US3] Create `spex/plugin-integrations.yml` with prose and copyedit plugin entries (detect paths, marker files, skills, injection targets)
- [ ] T019 [US3] Add `detect_plugins()` function to `spex/scripts/spex-init.sh` that reads `plugin-integrations.yml` from `$PLUGIN_ROOT`, checks paths for `plugin.json` or `.claude-plugin/plugin.json`, writes results to `.specify/spex-plugins.json`
- [ ] T020 [US3] Call `detect_plugins()` from `do_init()`, `do_refresh()`, and `do_update()` in `spex/scripts/spex-init.sh`
- [ ] T021 [P] [US3] Add "Plugin Integration" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md` that reads `.specify/spex-plugins.json` and appends injection instructions
- [ ] T022 [P] [US3] Add "Plugin Integration" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md`
- [ ] T023 [P] [US3] Add "Plugin Integration" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`

**Checkpoint**: With prose plugin installed, `.specify/spex-plugins.json` shows prose as available after init. Review-spec includes prose:check instruction. Without prose, review-spec does not include the instruction.

---

## Phase 5: Ship Workflow YAML (US-1)

**Purpose**: Replace 788-line procedural ship command with declarative workflow.

- [ ] T024 [US1] Create `spex/extensions/spex/workflows/` directory
- [ ] T025 [US1] Create `spex/extensions/spex/workflows/spex-ship.yml` workflow definition with inputs (spec, ask), pre_run/post_run hooks for marker file, and steps (specify, review-spec, plan, review-plan, tasks, implement, review-code, verify)
- [ ] T026 [US1] Add `ask` input passthrough to review-spec, review-plan, and review-code steps in `spex-ship.yml`
- [ ] T027 [US1] Add `pre_run` hook to write `.specify/.spex-workflow-active` JSON with PID and timestamp in `spex-ship.yml`
- [ ] T028 [US1] Add `post_run` hook to remove `.specify/.spex-workflow-active` in `spex-ship.yml`
- [ ] T029 [US1] Rewrite `spex/extensions/spex/commands/speckit.spex.ship.md` as thin wrapper (~50 lines): parse `--ask`, `--create-pr`, brainstorm file args, invoke `specify workflow run spex-ship`, handle PR creation after workflow completes
- [ ] T030 [US1] Add workflow installation to `install_extensions()` in `spex/scripts/spex-init.sh`: `specify workflow add <path>` for spex-ship.yml if workflow not already installed
- [ ] T031 [US1] Update `spex/extensions/spex/extension.yml` to reference the workflow file
- [ ] T032 [US1] Verify `specify workflow info spex-ship` shows all steps after installation
- [ ] T033 [US1] Update `spex/scripts/spex-ship-statusline.sh` to use `specify workflow status` instead of reading `.spex-state` directly

**Checkpoint**: `specify workflow info spex-ship` shows all steps. Ship wrapper command invokes workflow. SC-001 met: workflow YAML + wrapper under 160 lines combined.

---

## Phase 6: Hook/Workflow Coordination (US-4)

**Purpose**: Prevent double-reviewing by suppressing hooks when workflow is active.

- [ ] T034 [P] [US4] Add "Workflow Coordination" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md`: check `.spex-workflow-active`, verify PID, exit early or clean stale marker
- [ ] T035 [P] [US4] Add "Workflow Coordination" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md`
- [ ] T036 [P] [US4] Add "Workflow Coordination" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`
- [ ] T037 [P] [US4] Add "Workflow Coordination" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`
- [ ] T038 [P] [US4] Add "Workflow Coordination" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.stamp.md`
- [ ] T039 [US4] Remove or simplify existing "Ship Pipeline Guard" sections in all 5 review commands (old `.spex-state` check replaced by workflow marker)
- [ ] T040 [US4] Add "Workflow Isolation" section to the speckit-implement skill: when `.spex-workflow-active` exists, spawn subagent for implementation with only file paths (spec.md, plan.md, tasks.md), including teams auto-detection logic
- [ ] T041 [US4] Add "Workflow Isolation" section to `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`: when `.spex-workflow-active` exists, spawn subagent for review with no implementation context

**Checkpoint**: Ad-hoc `/speckit.specify` fires review-spec hook. Inside workflow, review-spec hook is suppressed. Implement and review-code spawn subagents during workflow runs.

---

## Phase 7: Constitution Amendment and Polish

**Purpose**: Documentation updates and cross-cutting cleanup.

- [ ] T042 Add workflow naming convention to section V (Naming Discipline) in `.specify/memory/constitution.md`: workflow IDs use `spex-*` prefix
- [ ] T043 Bump constitution version from 2.0.0 to 2.1.0 in `.specify/memory/constitution.md`
- [ ] T044 Update `spex/extensions/spex/commands/speckit.spex.help.md` with new ship invocation pattern (`specify workflow run spex-ship` or `/spex:ship`)
- [ ] T045 [P] Update `.gitignore` patterns in `configure_gitignore()` to include `.specify/.spex-workflow-active`
- [ ] T046 Run `make release` to validate plugin installation, extension registration, and command availability

**Checkpoint**: Constitution shows v2.1.0 with workflow naming. Help command reflects new ship pattern. `make release` passes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies
- **Phase 2 (Version Bump)**: Depends on Phase 1 (verify version)
- **Phase 3 (Init Simplification)**: Depends on Phase 2 (legacy code removed first)
- **Phase 4 (Plugin Detection)**: Depends on Phase 3 (init script simplified first)
- **Phase 5 (Ship Workflow)**: Depends on Phase 2 (manifests bumped). Can run in parallel with Phases 3-4.
- **Phase 6 (Coordination)**: Depends on Phase 5 (workflow marker must exist)
- **Phase 7 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **US-5 (Version Bump)**: No dependencies on other stories. Start first.
- **US-2 (Init)**: Depends on US-5 (legacy code removed before rewriting init)
- **US-3 (Plugins)**: Depends on US-2 (init simplified before adding plugin detection)
- **US-1 (Ship Workflow)**: Depends on US-5 (manifests bumped). Independent of US-2 and US-3.
- **US-4 (Coordination)**: Depends on US-1 (workflow YAML must exist for marker creation)

### Parallel Opportunities

- T002-T006: All manifest bumps run in parallel
- T021-T023: All plugin integration sections run in parallel
- T034-T038: All workflow coordination sections run in parallel
- Phase 5 (Ship Workflow) can run in parallel with Phase 3 (Init) and Phase 4 (Plugins)

---

## Parallel Example: Phase 2 (Version Bump)

```text
# All manifest bumps in parallel:
Task: "Update speckit_version in spex/extensions/spex/extension.yml"
Task: "Update speckit_version in spex/extensions/spex-gates/extension.yml"
Task: "Update speckit_version in spex/extensions/spex-teams/extension.yml"
Task: "Update speckit_version in spex/extensions/spex-worktrees/extension.yml"
Task: "Update speckit_version in spex/extensions/spex-deep-review/extension.yml"
```

---

## Implementation Strategy

### MVP First (US-5 + US-1)

1. Complete Phase 2: Version bump and legacy cleanup
2. Complete Phase 5: Ship workflow YAML
3. **STOP and VALIDATE**: Verify `specify workflow info spex-ship` works
4. This gives you the core value: declarative ship pipeline with resume

### Incremental Delivery

1. US-5 (Version Bump) -> Clean foundation
2. US-1 (Ship Workflow) -> Core pipeline replacement
3. US-2 (Init Simplification) -> Reduced maintenance
4. US-3 (Plugin Detection) -> Ecosystem composability
5. US-4 (Coordination) -> Hook/workflow harmony
6. Constitution + Polish -> Documentation alignment
