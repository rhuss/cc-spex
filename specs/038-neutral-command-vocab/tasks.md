# Tasks: Neutral Command Vocabulary with Per-Harness Adaptation

**Input**: Design documents from `/specs/038-neutral-command-vocab/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create pre-rewrite snapshot and adapter directory structure

- [X] T001 Create pre-rewrite snapshot of all extension command files by copying `spex/extensions/` to `specs/038-neutral-command-vocab/pre-rewrite-snapshot/` for regression comparison
- [X] T002 [P] Create Claude Code adapter directory at `spex/scripts/adapters/claude/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the adaptation engine and Claude Code mapping table before any command files are rewritten

**CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Create `spex/scripts/spex-adapt-commands.sh` implementing the adaptation script per plan design: parse `--dry-run` flag and positional args (harness, commands-dir, adapters-dir), load `command-map.json` via `jq`, apply inline substitutions to all `.md` files in `*/commands/` subdirectories, find and replace capability marker blocks (`<!-- harness:X -->...<!-- /harness:X -->`) with section content or fallback note, use temp directory for atomic writes, output unified diff in dry-run mode, exit 0 on missing mapping table (neutral passthrough per FR-007)
- [X] T004 Create Claude Code mapping table at `spex/scripts/adapters/claude/command-map.json` with: harness identifier, version field, inline substitutions array (neutral-to-CC text pairs for all 6 capability types), sections object mapping each capability marker name to its CC-specific replacement content, and fallback_note template. Content must restore all tool references present in the pre-rewrite snapshot (FR-006). Populate section replacements from the pre-rewrite snapshot by extracting the exact CC-specific instruction blocks that currently exist in each command file.

**Checkpoint**: Adaptation engine ready. Command file rewriting can now begin.

---

## Phase 3: User Story 1 - Author writes commands in neutral vocabulary (Priority: P1) MVP

**Goal**: Rewrite all 8 command files with CC-specific references to use harness-neutral vocabulary and capability markers. Source files must contain zero CC tool names after rewrite.

**Independent Test**: Run `rg 'AskUserQuestion|Agent tool|subagent_type|Agent Teams|CLAUDE_CODE_EXPERIMENTAL|EnterWorktree|ExitWorktree|settings\.json|settings\.local\.json' spex/extensions/*/commands/*.md` and verify 0 matches. Verify commands are syntactically valid markdown with balanced capability markers.

### Implementation for User Story 1

- [X] T005 [P] [US1] Rewrite `spex/extensions/spex/commands/speckit.spex.ship.md`: replace AskUserQuestion references (2) with neutral interactive-choice language and capability markers, replace Agent tool dispatch blocks (4) with neutral subagent-dispatch capability markers containing behavioral descriptions, replace subagent_type reference (1) with neutral parameter description, replace Agent Teams reference (1) with neutral agent-teams capability marker. Preserve all behavioral intent and prompt content.
- [X] T006 [P] [US1] Rewrite `spex/extensions/spex-teams/commands/speckit.spex-teams.orchestrate.md`: replace settings.json (1) and settings.local.json (4) references with neutral harness-settings capability markers, replace Agent Teams (4) and CLAUDE_CODE_EXPERIMENTAL (2) references with neutral agent-teams capability markers, replace team_name (1) with neutral parameter description, replace isolation: "worktree" (1) with neutral worktree-isolation capability marker. Preserve all behavioral intent.
- [X] T007 [P] [US1] Rewrite `spex/extensions/spex-teams/commands/speckit.spex-teams.research.md`: replace settings.json (1) and settings.local.json (4) references with neutral harness-settings capability markers, replace Agent Teams (4) and CLAUDE_CODE_EXPERIMENTAL (2) references with neutral agent-teams capability markers, replace team_name (1) with neutral parameter description. Preserve all behavioral intent.
- [X] T008 [P] [US1] Rewrite `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md`: replace EnterWorktree (1) and ExitWorktree (1) tool references with neutral worktree-isolation capability markers, replace isolation: "worktree" (2) parameters with neutral descriptions of workspace isolation behavior. Preserve all behavioral intent.
- [X] T009 [P] [US1] Rewrite `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: replace Agent tool (2) references with neutral subagent-dispatch and parallel-dispatch capability markers, replace subagent_type (1) with neutral parameter description, convert existing harness-conditional blocks (Claude Code vs Codex) to capability markers with neutral default text. Preserve all behavioral intent.
- [X] T010 [P] [US1] Rewrite `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: replace AskUserQuestion (2) references with neutral interactive-choice language (one inline replacement for "do NOT use AskUserQuestion" negative reference, one capability marker for the structured selection block). Preserve all behavioral intent.
- [X] T011 [P] [US1] Rewrite `spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md`: replace Agent Teams (1) and CLAUDE_CODE_EXPERIMENTAL (1) references with neutral agent-teams capability marker. Preserve all behavioral intent.
- [X] T012 [P] [US1] Rewrite `spex/extensions/spex-gates/commands/speckit.spex-gates.stamp.md`: replace AskUserQuestion (1) reference with neutral interactive-choice inline replacement (negative reference: "do NOT present interactive prompts"). Preserve all behavioral intent.

**Checkpoint**: All 8 command files now use neutral vocabulary. Zero CC-specific tool references remain in source. Capability markers identify all sections needing harness-specific adaptation.

---

## Phase 4: User Story 2 - Setup workflow adapts commands for detected harness (Priority: P1)

**Goal**: Add an `adapt-commands` step to setup.yml that runs the adaptation script after extension installation, transforming neutral commands to harness-optimized versions.

**Independent Test**: Run `specify workflow run setup.yml --integration claude` on a clean project and grep installed command files for CC tool references. Run again with `--integration codex` and verify no CC references present.

**Depends on**: Phase 2 (script exists), Phase 3 (files are neutral)

### Implementation for User Story 2

- [X] T013 [US2] Add `adapt-commands` step to `spex/setup.yml` between the `select-extensions` and `adapt-harness` steps. The step should: locate the adapters directory from the source path, run `spex-adapt-commands.sh` with the detected harness, the installed extensions directory (`.specify/extensions/`), and the adapters directory. Handle all harness values (claude, codex, opencode, generic). Exit cleanly if no mapping table exists for the harness.
- [X] T014 [US2] Verify idempotency (FR-005): run the setup workflow twice with `--integration claude` and confirm the adapted command files are byte-identical after both runs. Document the verification in a test script or inline comment.

**Checkpoint**: Setup workflow transforms neutral commands to harness-specific versions. Idempotent on re-run.

---

## Phase 5: User Story 4 - Zero regression for Claude Code users (Priority: P1)

**Goal**: Verify that after neutral rewrite + Claude Code adaptation, the end result is functionally identical to the pre-rewrite commands.

**Independent Test**: Diff the adapted Claude Code commands against the pre-rewrite snapshot. All CC-specific tool references must be present. Run `spex-adapt-commands.sh --dry-run claude` to preview transformations.

**Depends on**: Phase 3 (neutral files), Phase 4 (setup.yml integration)

### Implementation for User Story 4

- [X] T015 [US4] Run `./spex/scripts/spex-adapt-commands.sh --dry-run claude .specify/extensions spex/scripts/adapters` and verify every CC-specific tool reference from the pre-rewrite snapshot appears in the dry-run diff output. Compare against `specs/038-neutral-command-vocab/pre-rewrite-snapshot/`. Adjust the Claude Code mapping table (`spex/scripts/adapters/claude/command-map.json`) until all references are restored.
- [X] T016 [US4] Verify functional equivalence by comparing the adapted output of each of the 8 command files against their pre-rewrite versions. For each file: confirm the same tool names, parameters, and instruction blocks are present. Document any intentional differences (e.g., improved wording) vs regressions. Fix any regressions by updating the mapping table or neutral source text.

**Checkpoint**: Claude Code users experience zero behavioral change. All tool references restored after adaptation.

---

## Phase 6: User Story 3 - Mapping tables for maintainability (Priority: P2)

**Goal**: Demonstrate that adding a new harness requires only a mapping table file and a setup.yml case entry, with zero changes to the adaptation script.

**Independent Test**: Create a Codex mapping table and run `spex-adapt-commands.sh --dry-run codex` to verify transformations apply without script changes.

**Depends on**: Phase 2 (script exists)

### Implementation for User Story 3

- [X] T017 [P] [US3] Create Codex mapping table at `spex/scripts/adapters/codex/command-map.json` as a proof-of-concept. Define inline substitutions and section replacements appropriate for Codex (e.g., interactive-choice sections replaced with plain-text prompts, agent-teams sections replaced with fallback notes since Codex has different team mechanics). Verify with `spex-adapt-commands.sh --dry-run codex`.
- [X] T018 [P] [US3] Create OpenCode mapping table stub at `spex/scripts/adapters/opencode/command-map.json` with harness identifier and version, empty inline array, empty sections object, and a fallback_note template. This demonstrates the data-driven extensibility without requiring full OpenCode content.

**Checkpoint**: New harness support proven achievable with only a mapping table file. No spex-adapt-commands.sh changes required (SC-003).

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates, validation, and cleanup

- [X] T019 [P] Update `README.md` to document the neutral command vocabulary approach, the adapt-commands step in the setup workflow, and how to create mapping tables for new harnesses
- [X] T020 [P] Update `spex/docs/help.md` to document the spex-adapt-commands.sh script usage, capability marker syntax, and mapping table format
- [X] T021 Verify SC-004 performance target: time the adapt-commands step by running `time ./spex/scripts/spex-adapt-commands.sh claude .specify/extensions spex/scripts/adapters` and confirm it completes in under 5 seconds for the full set of extension commands
- [X] T022 Run `make release` validation (schema validation + integration test) to verify all extensions, commands, hooks, and skills are still properly registered after the rewrite
- [X] T023 Archive the pre-rewrite snapshot: keep `specs/038-neutral-command-vocab/pre-rewrite-snapshot/` as a durable regression baseline (do NOT delete, it is the ground truth for T015/T016 verification). Add the directory to `.gitignore` if it should not be committed.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (snapshot needed for mapping table content)
- **US1 (Phase 3)**: Depends on Phase 2 (mapping table defines what neutral text maps to, guides the rewrite)
- **US2 (Phase 4)**: Depends on Phase 2 (script) + Phase 3 (neutral files)
- **US4 (Phase 5)**: Depends on Phase 3 + Phase 4 (end-to-end pipeline must work)
- **US3 (Phase 6)**: Depends on Phase 2 only (script exists, can test with neutral files from Phase 3)
- **Polish (Phase 7)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational (Phase 2)
- **US2 (P1)**: Depends on US1 completion (needs neutral files to adapt)
- **US4 (P1)**: Depends on US1 + US2 (needs full pipeline working)
- **US3 (P2)**: Can start after Foundational, but best tested after US1 provides neutral files

### Within Each User Story

- All 8 rewrite tasks in US1 (T005-T012) can run in parallel (different files)
- US2 tasks are sequential (T013 before T014)
- US4 tasks are sequential (T015 before T016)
- US3 tasks can run in parallel (T017, T018 are different files)

### Parallel Opportunities

- T001 and T002 can run in parallel (setup)
- T003 and T004 can run in parallel once T001 completes (foundational)
- T005-T012 can ALL run in parallel (8 independent file rewrites)
- T017 and T018 can run in parallel (different mapping tables)
- T019 and T020 can run in parallel (different doc files)

---

## Parallel Example: User Story 1

```bash
# All 8 file rewrites can run simultaneously (different files, no dependencies):
Task: "Rewrite speckit.spex.ship.md to neutral vocabulary"
Task: "Rewrite speckit.spex-teams.orchestrate.md to neutral vocabulary"
Task: "Rewrite speckit.spex-teams.research.md to neutral vocabulary"
Task: "Rewrite speckit.spex-worktrees.manage.md to neutral vocabulary"
Task: "Rewrite speckit.spex-deep-review.run.md to neutral vocabulary"
Task: "Rewrite speckit.spex-gates.verify.md to neutral vocabulary"
Task: "Rewrite speckit.spex-teams.implement.md to neutral vocabulary"
Task: "Rewrite speckit.spex-gates.stamp.md to neutral vocabulary"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 + 4)

1. Complete Phase 1: Setup (snapshot + directory)
2. Complete Phase 2: Foundational (spex-adapt-commands.sh + Claude mapping table)
3. Complete Phase 3: US1 (rewrite all 8 files to neutral vocabulary)
4. Complete Phase 4: US2 (setup.yml integration)
5. Complete Phase 5: US4 (zero regression verification)
6. **STOP and VALIDATE**: Run smoke test with `--integration claude`, verify functional equivalence

### Incremental Delivery

1. Setup + Foundational -> Adaptation engine ready
2. Add US1 (neutral rewrite) -> Verify zero CC refs in source (SC-001)
3. Add US2 (setup.yml) -> Verify end-to-end adaptation works
4. Add US4 (regression check) -> Verify Claude Code parity (SC-002, SC-005)
5. Add US3 (Codex/OpenCode tables) -> Verify extensibility (SC-003)
6. Polish -> Docs + validation (make release)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US1 is the largest phase (8 parallel file rewrites), but each rewrite is self-contained
- US4 is a verification phase, not new code. It validates the mapping table completeness.
- The pre-rewrite snapshot (T001) is critical: it provides the ground truth for regression testing (US4) and the source content for the Claude mapping table (T004)
- Commit after each phase to create clean rollback points
