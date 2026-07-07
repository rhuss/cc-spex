# Tasks: Extension-Local Scripts

**Input**: Design documents from `/specs/036-extension-local-scripts/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Build Infrastructure)

**Purpose**: Create the script sync mechanism and CI check before touching any commands

- [x] T001 Create extension script directories: `mkdir -p spex/extensions/{spex,spex-gates,spex-collab,spex-deep-review,spex-detach}/scripts`
- [x] T002 Add `sync-scripts` target to Makefile with script inventory mapping per data-model.md
- [x] T003 Add `sync-scripts-check` target to Makefile that uses `diff` to compare canonical scripts against extension copies
- [x] T004 Add `sync-scripts-check` as prerequisite of the `release` target in Makefile
- [x] T005 Run `make sync-scripts` to populate all extension script directories from `spex/scripts/`

**Checkpoint**: `make sync-scripts && make sync-scripts-check` both pass. All extension `scripts/` directories contain correct copies.

---

## Phase 2: User Story 1 & 4 - Migrate Command Templates (Priority: P1)

**Goal**: Replace all `$PLUGIN_ROOT/scripts/<script>` references in command files with `.specify/extensions/<ext-id>/scripts/<script>` and remove "Step 0: Resolve Plugin Root" preambles.

**Independent Test**: `rg 'PLUGIN_ROOT' spex/extensions/` returns zero matches.

### Implementation

- [x] T006 [P] [US1] Update `spex/extensions/spex/commands/speckit.spex.ship.md`: replace `$PLUGIN_ROOT/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, replace `$PLUGIN_ROOT/scripts/spex-worktree-cwd.sh` with `.specify/extensions/spex/scripts/spex-worktree-cwd.sh`, remove Step 0 preamble
- [x] T007 [P] [US1] Update `spex/extensions/spex/commands/speckit.spex.finish.md`: replace `$PLUGIN_ROOT/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, replace `$PLUGIN_ROOT/scripts/spex-finish-context.sh` with `.specify/extensions/spex/scripts/spex-finish-context.sh`, remove Step 0 preamble
- [x] T008 [P] [US1] Update `spex/extensions/spex/commands/speckit.spex.submit.md`: replace `$PLUGIN_ROOT/scripts/spex-detach.sh` with `.specify/extensions/spex/scripts/spex-detach.sh`, replace `$PLUGIN_ROOT/scripts/spex-finish-context.sh` with `.specify/extensions/spex/scripts/spex-finish-context.sh`, replace `$PLUGIN_ROOT/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, remove Step 0 preamble
- [x] T009 [P] [US1] Update `spex/extensions/spex/commands/speckit.spex.brainstorm.md`: replace `$PLUGIN_ROOT/scripts/spex-detach.sh` with `.specify/extensions/spex/scripts/spex-detach.sh`, remove Step 0 preamble
- [x] T010 [P] [US1] Update `spex/extensions/spex/commands/speckit.spex.flow-state.md`: replace `$PLUGIN_ROOT/scripts/spex-flow-state.sh` with `.specify/extensions/spex/scripts/spex-flow-state.sh`, remove Step 0 preamble
- [x] T011 [P] [US1] Update `spex/extensions/spex/commands/speckit.spex.smoke-test.md`: replace `$PLUGIN_ROOT/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, remove Step 0 preamble
- [x] T012 [P] [US1] Update `spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md`: replace `$PLUGIN_ROOT/scripts/spex-flow-state.sh` with `.specify/extensions/spex-gates/scripts/spex-flow-state.sh`, remove Step 0 preamble
- [x] T013 [P] [US1] Update `spex/extensions/spex-gates/commands/speckit.spex-gates.review-plan.md`: replace `$PLUGIN_ROOT/scripts/spex-flow-state.sh` with `.specify/extensions/spex-gates/scripts/spex-flow-state.sh`, remove Step 0 preamble
- [x] T014 [P] [US1] Update `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md`: replace `$PLUGIN_ROOT/scripts/spex-flow-state.sh` with `.specify/extensions/spex-gates/scripts/spex-flow-state.sh`, remove Step 0 preamble
- [x] T015 [P] [US1] Update `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: replace `$PLUGIN_ROOT/scripts/spex-closeout-gate.sh` with `.specify/extensions/spex-gates/scripts/spex-closeout-gate.sh`
- [x] T016 [P] [US1] Update `spex/extensions/spex-collab/commands/speckit.spex-collab.triage.md`: replace `$PLUGIN_ROOT/scripts/spex-triage-state.sh` with `.specify/extensions/spex-collab/scripts/spex-triage-state.sh`, replace `$PLUGIN_ROOT/scripts/sanitize-gh-json.py` with `.specify/extensions/spex-collab/scripts/sanitize-gh-json.py`, remove Step 0 preamble
- [x] T017 [P] [US1] Update `spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md`: replace `$PLUGIN_ROOT/scripts/spex-flow-state.sh` with `.specify/extensions/spex-collab/scripts/spex-flow-state.sh`, remove Step 0 preamble
- [x] T018 [P] [US1] Update `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: replace `$PLUGIN_ROOT/scripts/spex-flow-state.sh` with `.specify/extensions/spex-deep-review/scripts/spex-flow-state.sh`, remove Step 0 preamble
- [x] T019 [P] [US1] Update `spex/extensions/spex-detach/commands/speckit.spex-detach.detach.md`: replace `$PLUGIN_ROOT/scripts/spex-detach.sh` with `.specify/extensions/spex-detach/scripts/spex-detach.sh`, remove Step 0 preamble

**Checkpoint**: `rg 'PLUGIN_ROOT' spex/extensions/` returns zero matches (excluding extension.yml and historical docs). All command files reference `.specify/extensions/<ext-id>/scripts/`.

---

## Phase 3: User Story 1 & 4 - Migrate Skill Files (Priority: P1)

**Goal**: Replace all `<PLUGIN_ROOT>/scripts/<script>` references in skill files with `.specify/extensions/<ext-id>/scripts/<script>` and remove "Replace `<PLUGIN_ROOT>`" instructions.

**Independent Test**: `rg 'PLUGIN_ROOT' .claude/skills/` returns zero matches.

### Implementation

- [x] T020 [P] [US1] Update `.claude/skills/speckit-spex-ship/SKILL.md`: replace all `<PLUGIN_ROOT>/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, replace `<PLUGIN_ROOT>/scripts/spex-worktree-cwd.sh` with `.specify/extensions/spex/scripts/spex-worktree-cwd.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions and "Step 0: Resolve Plugin Root" section
- [x] T021 [P] [US1] Update `.claude/skills/speckit-spex-brainstorm/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-detach.sh` with `.specify/extensions/spex/scripts/spex-detach.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T022 [P] [US1] Update `.claude/skills/speckit-spex-submit/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-detach.sh` with `.specify/extensions/spex/scripts/spex-detach.sh`, replace `<PLUGIN_ROOT>/scripts/spex-finish-context.sh` with `.specify/extensions/spex/scripts/spex-finish-context.sh`, replace `<PLUGIN_ROOT>/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`
- [x] T023 [P] [US1] Update `.claude/skills/speckit-spex-smoke-test/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T024 [P] [US1] Update `.claude/skills/speckit-spex-flow-state/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` with `.specify/extensions/spex/scripts/spex-flow-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T025 [P] [US1] Update `.claude/skills/speckit-spex-gates-review-spec/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` with `.specify/extensions/spex-gates/scripts/spex-flow-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T026 [P] [US1] Update `.claude/skills/speckit-spex-gates-review-plan/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` with `.specify/extensions/spex-gates/scripts/spex-flow-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T027 [P] [US1] Update `.claude/skills/speckit-spex-gates-review-code/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` with `.specify/extensions/spex-gates/scripts/spex-flow-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T028 [P] [US1] Update `.claude/skills/speckit-spex-collab-triage/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-triage-state.sh` with `.specify/extensions/spex-collab/scripts/spex-triage-state.sh`, replace `<PLUGIN_ROOT>/scripts/sanitize-gh-json.py` with `.specify/extensions/spex-collab/scripts/sanitize-gh-json.py`, remove "Replace `<PLUGIN_ROOT>`" instructions
- [x] T029 [P] [US1] Update `.claude/skills/speckit-spex-finish/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-ship-state.sh` with `.specify/extensions/spex/scripts/spex-ship-state.sh`, replace `<PLUGIN_ROOT>/scripts/spex-finish-context.sh` with `.specify/extensions/spex/scripts/spex-finish-context.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions and "Step 0: Resolve Plugin Root" section
- [x] T042 [P] [US1] Update `.claude/skills/speckit-spex-collab-phase-manager/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` with `.specify/extensions/spex-collab/scripts/spex-flow-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions and "Step 0: Resolve Plugin Root" section
- [x] T043 [P] [US1] Update `.claude/skills/speckit-spex-deep-review-run/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-flow-state.sh` with `.specify/extensions/spex-deep-review/scripts/spex-flow-state.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions and "Step 0: Resolve Plugin Root" section
- [x] T044 [P] [US1] Update `.claude/skills/speckit-spex-detach-detach/SKILL.md`: replace `<PLUGIN_ROOT>/scripts/spex-detach.sh` with `.specify/extensions/spex-detach/scripts/spex-detach.sh`, remove "Replace `<PLUGIN_ROOT>`" instructions and "Step 0: Resolve Plugin Root" section

**Checkpoint**: `rg 'PLUGIN_ROOT' .claude/skills/` returns zero matches. All skill files reference `.specify/extensions/<ext-id>/scripts/`.

---

## Phase 4: User Story 4 - Update Context Hook and Constitution (Priority: P1)

**Goal**: Remove `<plugin-root>` tag from system prompt injection and update constitution to reflect new architecture.

**Independent Test**: Run `echo '{"prompt":"/spex:ship","session_id":"test","cwd":"/tmp","hook_event_name":"UserPromptSubmit"}' | python3 spex/scripts/hooks/context-hook.py` and verify output does not contain `<plugin-root>`.

### Implementation

- [x] T030 [P] [US4] Update `spex/scripts/hooks/context-hook.py`: remove the `<plugin-root>{plugin_root}</plugin-root>` line from the `ctx` f-string template (around line 145). Keep the `plugin_root` variable for internal use.
- [x] T031 [P] [US4] Update `.specify/memory/constitution.md`: replace the "Plugin root detection" constraint (lines 136-138) to describe extension-local scripts pattern instead of `$PLUGIN_ROOT`. Update the "File organization" constraint to note scripts live in both `spex/scripts/` (canonical) and `spex/extensions/<id>/scripts/` (copies).

**Checkpoint**: Context hook output no longer includes `<plugin-root>` tag. Constitution reflects new architecture.

---

## Phase 5: User Story 2 & 3 - Build Sync and CI Check (Priority: P2)

**Goal**: Ensure `make sync-scripts` works correctly and CI catches stale copies.

**Independent Test**: Modify a canonical script, verify `make sync-scripts-check` fails with actionable error, then run `make sync-scripts` and verify the check passes.

### Implementation

- [x] T032 [US2] Verify `make sync-scripts` correctly copies all scripts per inventory (run the target and compare outputs with `diff`)
- [x] T033 [US3] Verify `make sync-scripts-check` detects stale copies: temporarily modify one canonical script, run the check, confirm it fails with script name, affected extensions, and remediation command

**Checkpoint**: Both `sync-scripts` and `sync-scripts-check` work as specified. Release target fails if scripts are out of sync.

---

## Phase 6: User Story 5 - Simplify spex-init.sh (Priority: P3)

**Goal**: Verify init script works with self-contained extensions and remove any residual manual script-copy logic.

**Independent Test**: Run `spex-init.sh` on a test project and verify extensions install with scripts present.

### Implementation

- [x] T034 [US5] Review `spex/scripts/spex-init.sh` for any manual script-copy logic outside of `install_extensions`. Remove if found. The `install_extensions` function calls `specify extension add` which copies the entire extension directory including `scripts/`.
- [x] T035 [US5] Verify `configure_statusline` in `spex/scripts/spex-init.sh` can find `spex-ship-statusline.sh` at both `$script_dir/spex-ship-statusline.sh` (canonical, during init) and `.specify/extensions/spex/scripts/spex-ship-statusline.sh` (extension-local, at runtime)

**Checkpoint**: `spex-init.sh` is simplified. All extensions install with their scripts via `specify extension add`.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and documentation

- [x] T036 Run `rg 'PLUGIN_ROOT' spex/extensions/ .claude/skills/` to verify zero matches (exclude brainstorm/, specs/, docs/)
- [x] T037 Run `rg '<plugin-root>' spex/scripts/hooks/context-hook.py` to verify tag removed
- [x] T038 Run `make sync-scripts-check` to verify all extension scripts match canonical sources
- [x] T039 Run `make test-install` to verify the plugin installs correctly with extension scripts
- [x] T040 Update `README.md` if it references `$PLUGIN_ROOT` or the plugin-root mechanism
- [x] T041 Update `spex/docs/help.md` if it references `$PLUGIN_ROOT` or the plugin-root mechanism

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies, start immediately
- **Phase 2 (Commands)**: Depends on Phase 1 (extensions must have scripts directories populated)
- **Phase 3 (Skills)**: Can run in parallel with Phase 2 (different files)
- **Phase 4 (Hook/Constitution)**: Can run in parallel with Phases 2 and 3 (different files)
- **Phase 5 (Sync verification)**: Depends on Phase 1 (sync targets must exist)
- **Phase 6 (Init simplification)**: Can start after Phase 1
- **Phase 7 (Polish)**: Depends on all prior phases

### Parallel Opportunities

- T006-T019 (command files) are all parallelizable (different files)
- T020-T028 (skill files) are all parallelizable (different files)
- T030-T031 (hook/constitution) are parallelizable with each other and with Phases 2-3
- Phases 2, 3, and 4 can all run in parallel after Phase 1 completes

---

## Implementation Strategy

### MVP First (User Stories 1 & 4)

1. Complete Phase 1: Build sync infrastructure
2. Complete Phases 2-4 in parallel: Migrate all PLUGIN_ROOT references
3. **STOP and VALIDATE**: `rg PLUGIN_ROOT` returns zero matches in commands/skills/hook
4. This delivers harness-agnostic operation

### Incremental Delivery

1. Phase 1 (Setup) -> Sync infrastructure ready
2. Phases 2+3+4 (Migration) -> All PLUGIN_ROOT eliminated, harness-agnostic
3. Phase 5 (CI) -> Sync enforcement verified
4. Phase 6 (Init) -> Simplified init script
5. Phase 7 (Polish) -> Documentation and final verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Total tasks: 45
- Tasks per story: US1 (28), US2 (1), US3 (1), US4 (2), US5 (2), Cross-cutting (6), Setup (5)
- Parallel opportunities: Phases 2, 3, and 4 are fully parallelizable (32 tasks)
- MVP scope: Phases 1-4 (US1 + US4) delivers the core value
