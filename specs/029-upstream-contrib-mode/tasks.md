# Tasks: spex-detach Extension

**Input**: Design documents from `specs/029-upstream-contrib-mode/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/spex-detach-sh.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1-US5)
- Exact file paths included in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the spex-detach extension bundle structure

- [ ] T001 Create extension directory structure at spex/extensions/spex-detach/
- [ ] T002 [P] Create extension manifest at spex/extensions/spex-detach/extension.yml per contract in specs/029-upstream-contrib-mode/contracts/spex-detach-sh.md
- [ ] T003 [P] Create config template at spex/extensions/spex-detach/config-template.yml with archive.path, archive.auto_commit, upstream.default_branch, detach.strip_paths fields per data-model.md
- [ ] T004 Add spex-detach to install_order array in spex/scripts/spex-init.sh after spex-worktrees, before spex-deep-review

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shell script skeleton with shared helpers that all subcommands depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Create spex-detach.sh at spex/scripts/bash/spex-detach.sh with subcommand routing (detach, archive, is-enabled, clean-branch-name), argument parsing, and helper functions: get_project_name() (upstream > origin > dirname fallback), detect_upstream_default() (auto-detect from remote HEAD), read_config() (parse spex-detach-config.yml via yq with defaults)

**Checkpoint**: Extension bundle installable via `specify extension add`, script skeleton callable

---

## Phase 3: User Story 1 - Enable the spex-detach extension (Priority: P1) MVP

**Goal**: Contributors can enable spex-detach during init and verify it is active

**Independent Test**: Run `specify init`, enable spex-detach when prompted, verify the extension directory exists at `.specify/extensions/spex-detach/` and `spex-detach.sh is-enabled` exits 0

### Implementation for User Story 1

- [ ] T006 [P] [US1] Implement `is-enabled` subcommand in spex/scripts/bash/spex-detach.sh: check for `.specify/extensions/spex-detach` directory, exit 0 if present, exit 1 otherwise
- [ ] T007 [P] [US1] Implement `clean-branch-name` subcommand in spex/scripts/bash/spex-detach.sh: accept --branch flag (default: current branch), output `pr/<branch-name>` to stdout

**Checkpoint**: Extension installs via init, `is-enabled` and `clean-branch-name` work. All spec-kit commands function normally.

---

## Phase 4: User Story 2 - Create clean PR branch at finish time (Priority: P1)

**Goal**: `spex-finish` creates a clean `pr/<branch>` branch with only code changes via squash-onto-base

**Independent Test**: Initialize with spex-detach, commit spec + code changes, run `/speckit-spex-finish`, verify `pr/<branch>` exists with no `.specify/`, `specs/`, or `brainstorm/` directories and original feature branch is unchanged

### Implementation for User Story 2

- [ ] T008 [US2] Implement `detach` subcommand in spex/scripts/bash/spex-detach.sh: compute merge-base, generate filtered diff with --binary and pathspec exclusions (:!.specify :!specs :!brainstorm), create pr/<branch> from merge-base, apply diff as single squashed commit, handle empty-diff edge case (exit 2), output JSON result per contract
- [ ] T009 [US2] Add detach detection block after Phase 2 in spex/extensions/spex/commands/speckit.spex.finish.md: detect `.specify/extensions/spex-detach` directory, locate spex-detach.sh via find, call `spex-detach.sh detach` to create clean PR branch, report result
- [ ] T010 [US2] Modify Phase 4 action selection in spex/extensions/spex/commands/speckit.spex.finish.md: when detach is active, replace "Push and create PR" with "Push clean PR branch to upstream" option targeting `pr/<branch>`, keep "Merge to default branch" and "Keep branch as-is" unchanged
- [ ] T011 [US2] Implement "Push clean PR branch" action in Phase 5 of spex/extensions/spex/commands/speckit.spex.finish.md: push `pr/<branch>` to remote, create PR from clean branch via `gh pr create`, include note that spec artifacts are preserved on the feature branch
- [ ] T012 [US2] Add clean branch verification (FR-008) in spex/extensions/spex/commands/speckit.spex.finish.md: after detach, check that no `.specify/`, `specs/`, or `brainstorm/` directories exist on `pr/<branch>`, abort with error if verification fails

**Checkpoint**: Full detach flow works end-to-end. Clean PR branch contains only code. Feature branch preserved.

---

## Phase 5: User Story 3 - Archive specs to project-specs repo (Priority: P2)

**Goal**: At finish time, spec artifacts (`.specify/` + `specs/<feature>/`) are copied to the configured project-specs repo

**Independent Test**: Configure archive path in spex-detach-config.yml, finish a feature, verify specs appear at `<archive-path>/<project-name>/<feature-name>/`

### Implementation for User Story 3

- [ ] T013 [US3] Implement `archive` subcommand in spex/scripts/bash/spex-detach.sh: accept --target, --project, --feature, --auto-commit flags, copy `.specify/` and `specs/<feature>/` to target path organized by project/feature, create directory structure if missing, optionally auto-commit to target repo, handle unreachable path gracefully (warn and continue), output JSON result per contract
- [ ] T014 [US3] Create command skill at spex/extensions/spex-detach/commands/speckit.spex-detach.detach.md: accept "archive" or "detach" argument, locate and call spex-detach.sh with appropriate subcommand, read config from `.specify/extensions/spex-detach/spex-detach-config.yml`, support manual invocation outside finish flow

**Checkpoint**: Archive works as `before_finish` hook and via manual `/speckit-spex-detach-detach archive` invocation.

---

## Phase 6: User Story 4 - Brainstorm documents in project-specs repo (Priority: P2)

**Goal**: When spex-detach is enabled, brainstorm documents are written to the project-specs repo instead of the code worktree

**Independent Test**: With spex-detach enabled and archive path configured, run brainstorming, verify document is saved to project-specs repo's `brainstorm/` directory, not the code worktree

### Implementation for User Story 4

- [ ] T015 [US4] Add spex-detach awareness to spex/extensions/spex/commands/speckit.spex.brainstorm.md: at the start of brainstorm execution, check if spex-detach is enabled (via `spex-detach.sh is-enabled`), if enabled read `archive.path` from spex-detach-config.yml, redirect brainstorm document output to `<archive.path>/brainstorm/` instead of local `brainstorm/` directory
- [ ] T016 [US4] Add brainstorm context passing to `/speckit-specify`: when spex-detach is enabled and a brainstorm document path in the project-specs repo is provided as argument, read the document as context input for specification generation

**Checkpoint**: Brainstorm documents created in project-specs repo. Brainstorm content available as context for `/speckit-specify`.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, verification, edge cases

- [ ] T017 [P] Update README.md with spex-detach extension: add to Bundled Extensions section, add detach commands to Commands Reference table, update workflow descriptions
- [ ] T018 [P] Update spex/docs/help.md with spex-detach commands and workflow section
- [ ] T019 [P] Add edge case handling across spex-detach.sh: no spec artifacts in worktree (skip detach), spec-only changes (warn empty PR branch), re-run idempotency (regenerate pr/ branch)
- [ ] T020 Verify parallel worktree independence (US5): create two worktrees with spex-detach enabled, run spec-kit commands in both, confirm independent `.specify/.spex-state` tracking and no cross-worktree interference
- [ ] T021 Run quickstart.md validation: walk through the full workflow from init to finish to verify documented steps match actual behavior

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (extension structure must exist)
- **US1 (Phase 3)**: Depends on Phase 2 (script skeleton needed)
- **US2 (Phase 4)**: Depends on Phase 3 (is-enabled, clean-branch-name used by finish modifications)
- **US3 (Phase 5)**: Depends on Phase 2 (script skeleton). Can run in parallel with US2.
- **US4 (Phase 6)**: Depends on Phase 5 (uses archive path config)
- **US5 (Phase 7)**: No code, verification only. Depends on US1 + US2.
- **Polish (Phase 7)**: Depends on all stories being complete

### User Story Dependencies

- **US1 (P1)**: Extension enablement, no story dependencies
- **US2 (P1)**: Depends on US1 (needs is-enabled detection). Core value proposition.
- **US3 (P2)**: Independent of US2. Only needs foundational script.
- **US4 (P2)**: Depends on US3 (uses same archive.path config concept)
- **US5 (P1)**: No code, inherent in worktree model. Verification only.

### Within Each User Story

- Script subcommands before finish command modifications
- Finish detection before action selection modifications
- Action selection before push implementation

### Parallel Opportunities

- T002 + T003 (extension manifest + config template)
- T006 + T007 (is-enabled + clean-branch-name subcommands)
- T013 can start after Phase 2, in parallel with T009-T012
- T017 + T018 + T019 (documentation + edge cases)

---

## Parallel Example: User Story 2

```bash
# After T008 (detach subcommand) is complete, these can overlap:
# But T009 must complete before T010, T010 before T011

Task: "T009 - Add detach detection block in finish.md"
Task: "T010 - Modify Phase 4 action selection in finish.md" (after T009)
Task: "T011 - Implement Push clean PR branch action in finish.md" (after T010)
Task: "T012 - Add clean branch verification in finish.md" (after T009)
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 2 Only)

1. Complete Phase 1: Setup (extension bundle)
2. Complete Phase 2: Foundational (script skeleton)
3. Complete Phase 3: US1 (extension enablement)
4. Complete Phase 4: US2 (clean PR branch creation)
5. **STOP and VALIDATE**: Manually test: init with spex-detach, create spec + code changes, run finish, verify clean PR branch
6. This delivers the core value proposition without archiving

### Incremental Delivery

1. Setup + Foundational → Extension installable
2. Add US1 → Extension detectable
3. Add US2 → Clean PR branch works (MVP!)
4. Add US3 → Archiving works
5. Add US4 → Brainstorm redirection works
6. Polish → Documentation, edge cases, US5 verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- US5 has no implementation tasks (worktree independence is inherent in git)
- spex-detach.sh must use JSON output for machine-readability (consumed by finish command)
- Config reads use yq with fallback defaults for robustness
- All finish command modifications are additive (no existing behavior changes when spex-detach is not installed)
