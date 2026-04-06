# Tasks: Post-Specify Worktree Creation

**Input**: Design documents from `/specs/015-worktree-post-specify/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

---

## Phase 1: US1 - Automatic Worktree After Specify (Priority: P1)

**Goal**: After `speckit.specify` completes with the worktrees trait enabled, commit all changes, restore main, create a colon-named worktree, and print switch instructions.

**Independent Test**: Run `speckit.specify` with the worktrees trait enabled. Verify: (1) worktree exists at `<parent>/<repo-name>:<branch-name>`, (2) original repo is on `main`, (3) all modified tracked files are committed, (4) switch instructions are printed.

- [ ] T001 [US1] Update `spex/skills/worktree/SKILL.md` Step 4 (path computation) to use colon naming convention: derive `REPO_NAME` via `basename $(git rev-parse --show-toplevel)`, compute `WORKTREE_PATH` as `<resolved-base>/<repo-name>:<branch-name>`
- [ ] T002 [US1] Update `spex/skills/worktree/SKILL.md` Step 5 (commit scope) to use `git add -A` instead of `git add "$SPEC_DIR"`, with a `git diff --cached --quiet` guard to skip empty commits
- [ ] T003 [P] [US1] Update `spex/skills/worktree/SKILL.md` Step 8 (switch instructions) to show the colon-format path in the `cd` command
- [ ] T004 [P] [US1] Update FR references throughout `spex/skills/worktree/SKILL.md` to match the new spec numbering (FR-001 through FR-012)
- [ ] T005 [P] [US1] Verify `spex/overlays/worktrees/skills/speckit-specify/SKILL.append.md` correctly delegates to `{Skill: spex:worktree}` and stays under 30 lines (constitution II)

**Checkpoint**: Core worktree creation flow uses colon naming and commits all tracked files

---

## Phase 2: US2 - Worktree Session Bootstrap (Priority: P2)

**Goal**: A new Claude session in a worktree auto-triggers `spex:init` and has all spec files available.

**Independent Test**: Create a worktree, start Claude session, verify `spex:init` triggers and all speckit commands are available.

- [ ] T006 [US2] Verify the existing `spex-initialized: false` sentinel detection in `context-hook.py` works correctly when the session starts in a worktree directory (`.git` is a file, not a directory)
- [ ] T007 [P] [US2] Verify `.claude/skills/` is in `.gitignore` so it gets regenerated per session, not carried from the feature branch

**Checkpoint**: Worktree sessions self-bootstrap without manual intervention

---

## Phase 3: US3 - Worktree Listing (Priority: P3)

**Goal**: `/spex:worktree list` shows all active feature worktrees with colon-format paths.

**Independent Test**: Create two worktrees, run list, verify both appear with correct colon-format paths.

- [ ] T008 [US3] Update `spex/skills/worktree/SKILL.md` List action output to display colon-format paths (e.g., `cc-spex:004-user-auth` instead of `../004-user-auth`)

**Checkpoint**: Listing shows correct colon-format paths

---

## Phase 4: US4 - Worktree Cleanup (Priority: P4)

**Goal**: `/spex:worktree cleanup` detects merged worktrees and offers removal with confirmation.

**Independent Test**: Merge a feature branch, run cleanup, verify worktree directory and git reference are removed.

- [ ] T009 [US4] Review `spex/skills/worktree/SKILL.md` Cleanup action for compatibility with colon-format paths in `git worktree remove` command

**Checkpoint**: Cleanup works with colon-named worktree directories

---

## Phase 5: Verification

- [ ] T010 Run `make release` to validate plugin schema and integration test
- [ ] T011 Manual end-to-end test: enable worktrees trait, run `/speckit-specify`, verify full flow (commit, checkout main, worktree add with colon naming, switch instructions)
