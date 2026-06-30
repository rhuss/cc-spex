# Tasks: Worktree CWD Persistence

**Input**: Design documents from `specs/032-worktree-cwd-persistence/`
**Prerequisites**: plan.md, spec.md

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: User Story 1+2 - Worktrees Inside Project with Simplified Paths (Priority: P1) MVP

**Goal**: Change default worktree location to `.claude/worktrees/<branch>` and simplify path format.

**Independent Test**: Create a worktree via the extension. Verify it lands in `.claude/worktrees/<branch>` (not `../repo@branch`).

### Implementation

- [ ] T001 [US1] Change default base_path from `".."` to `".claude/worktrees"` in Step 1 of `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md` (the `yq` fallback value and the `echo` fallback)
- [ ] T002 [US1] Add inside-project detection in Step 4 of `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md` -- detect if `BASE_PATH` starts with `.claude/worktrees` and set `INSIDE_PROJECT=true`. When inside project: `mkdir -p` the base dir and use `$REPO_ROOT/$BASE_PATH/$BRANCH_NAME` as the worktree path. When outside project: keep existing `${RESOLVED_BASE}/${REPO_NAME}@${BRANCH_NAME}` format.
- [ ] T003 [US1] Modify the inside-repo guard in Step 4 of `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md` -- allow `$REPO_ROOT/.claude/worktrees/*` paths while still rejecting other inside-project paths (e.g., `base_path: "."`)
- [ ] T004 [US2] Update the Step 9 output message in `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md` -- for inside-project worktrees, show the relative path `.claude/worktrees/<branch>` instead of the full absolute path

**Checkpoint**: Worktrees are created at `.claude/worktrees/<branch>` by default, CWD persists.

---

## Phase 2: User Story 3 - CWD Recovery Script (Priority: P2)

**Goal**: Update the recovery script to note that inside-project worktrees should rarely need recovery.

- [ ] T005 [US3] Update comments in `spex/scripts/spex-worktree-cwd.sh` to note that inside-project worktrees (`.claude/worktrees/`) should not trigger CWD resets, making this script a safety net rather than a primary mechanism

**Checkpoint**: Recovery script handles both inside and outside worktrees.

---

## Phase 3: User Story 4 - Documentation (Priority: P2)

**Goal**: Update docs to describe `.claude/worktrees/` as the default.

- [ ] T006 [P] [US4] Update the spex-worktrees extension description in `README.md` -- mention `.claude/worktrees/` as the default worktree location, note that this keeps CWD stable in Claude Code
- [ ] T007 [P] [US4] Update the spex-worktrees entry in `spex/docs/help.md` -- reference `.claude/worktrees/` as the default location

**Checkpoint**: Documentation accurately describes the new default.

---

## Phase 4: Polish

- [ ] T008 Verify cross-references are consistent across modified files
- [ ] T009 Commit all changes

---

## Dependencies & Execution Order

- **Phase 1** (manage command): No dependencies, start immediately
- **Phase 2** (recovery script): Independent of Phase 1
- **Phase 3** (docs): Independent, T006 and T007 can run in parallel
- **Phase 4** (polish): After all phases

### Parallel Opportunities

- T006 and T007 can run in parallel (different files)
- Phases 1, 2, 3 modify different files and can run in parallel

## Implementation Strategy

### MVP (Phase 1 only)

1. Modify manage command default and path format
2. Test: create a worktree, verify `.claude/worktrees/<branch>` path
3. Verify CWD persists after subagent returns
