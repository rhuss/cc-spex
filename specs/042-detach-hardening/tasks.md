# Tasks: Harden spex-detach

**Input**: Design documents from `specs/042-detach-hardening/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Foundational Bug Fix

**Purpose**: Fix the script path bug that blocks brainstorm-detach integration

- [x] T001 [US3] Fix detach script path in brainstorm skill: change `.specify/extensions/spex/scripts/spex-detach.sh` to `.specify/extensions/spex-detach/scripts/spex-detach.sh` at line 282 in spex/extensions/spex/commands/speckit.spex.brainstorm.md

**Checkpoint**: Brainstorm skill's detach-awareness check no longer silently fails

---

## Phase 2: Detach Script Enhancements (spex-detach.py)

**Purpose**: Add verification, move semantics, brainstorm archiving, and .gitignore check to the Python script

- [x] T002 [P] [US2] Add `cmd_verify` subcommand to spex/extensions/spex-detach/scripts/spex-detach.py: accept `--branch` and `--base` args, run `git diff --name-only <base>..<branch>`, check file paths against SpecKit fingerprint patterns from `strip_paths` config, output JSON `{"clean": bool, "leaked_files": [...], "patterns_checked": [...]}`, exit 0 if clean, exit 1 if leaked. Register `verify` in the COMMANDS dict in the same change
- [x] T003 [US2] Integrate verification into `cmd_detach` in spex/extensions/spex-detach/scripts/spex-detach.py: after creating PR branch and committing, call verify logic on the new `pr/<branch>` against merge base. If verification fails, delete PR branch and report error with leaked file list. **Depends on T002** (requires `cmd_verify` to exist)
- [x] T004 [P] [US4] Add `--move` flag to `cmd_archive` in spex/extensions/spex-detach/scripts/spex-detach.py: after successful copy+commit to sibling repo, delete source `specs/<feature>/` and `brainstorm/` directories (defer `.specify/` deletion). Handle deletion failures with warning, not error
- [x] T005 [P] [US4] Add brainstorm archiving to `cmd_archive` in spex/extensions/spex-detach/scripts/spex-detach.py: copy `brainstorm/` directory to sibling repo alongside existing `.specify/` and `specs/<feature>/` archiving. Add `--include-brainstorm` flag
- [x] T006 [P] [US5] Add `.gitignore` check to `cmd_detach` in spex/extensions/spex-detach/scripts/spex-detach.py: check if `upstream` remote exists, if yes read `.gitignore` for `.specify`, `specs`, `brainstorm` entries, emit warning to stderr for missing entries. Non-blocking (does not affect exit code)
**Checkpoint**: `spex-detach.py verify`, `archive --move --include-brainstorm`, and `.gitignore` check all work standalone

**Interfaces (consumed by Phase 3)**:

- `spex-detach.sh verify --branch <branch> --base <base>` -> exits 0 if clean, 1 if leaked; stdout JSON `{"clean": bool, "leaked_files": [str], "patterns_checked": [str]}`
- `spex-detach.sh archive --move --include-brainstorm` -> copies .specify/, specs/<feature>/, brainstorm/ to sibling repo, commits, deletes sources; exits 0 on success, non-zero on failure
- `spex-detach.sh detach` -> creates `pr/<branch>` clean branch, runs verify internally; exits 0 if clean, 1 if leaked, 2 if empty (no code changes)

---

## Phase 3: User Story 1 - Finish Integration (Priority: P1)

**Goal**: Wire detach into spex-finish so it runs automatically after squash

**Independent Test**: Run `spex-finish` with `spex-detach` enabled, verify `pr/<branch>` is created and offered as push target

**Depends on**: Phase 2 complete (verify and archive --move must exist in spex-detach.py)

### Implementation for User Story 1

- [x] T008 [US1] Add `--skip-archive` flag to Argument Parsing section in spex/extensions/spex/commands/speckit.spex.finish.md alongside existing `--no-smoke-test`
- [x] T009 [US1] Add detach step between Phase 3 Step 1 (Commit outstanding changes) and Phase 3 Step 2 (Compute merge base) in spex/extensions/spex/commands/speckit.spex.finish.md: detect `.specify/extensions/spex-detach`, run archive with `--move --include-brainstorm` (unless `--skip-archive` or no `archive.path`), run `.gitignore` check, run detach to create `pr/<branch>`, set `DETACH_PR_BRANCH` variable. **Must run before squash** per FR-001/FR-004 so source deletions from archive --move are included in the squash commit
- [x] T010 [US1] Update Phase 4 (Select Action) in spex/extensions/spex/commands/speckit.spex.finish.md: when `DETACH_PR_BRANCH` is set, add "Push clean PR branch" option that runs `git push <remote> <pr-branch>`

**Checkpoint**: `spex-finish` with detach enabled creates clean PR branch and offers push option

---

## Phase 4: Brainstorm Enhancements (Priority: P3)

**Goal**: Add sibling repo discovery and init auto-detection to brainstorm skill

**Independent Test**: Run brainstorm in a project with `archive.path` set and sibling brainstorm docs, verify they appear in revisit detection

- [x] T011 [P] [US6] Add sibling specs repo scanning to revisit detection (step 4 of checklist) in spex/extensions/spex/commands/speckit.spex.brainstorm.md: read `archive.path` from spex-detach-config.yml, scan `<archive.path>/brainstorm/` for `NN-*.md` files, include matches alongside local brainstorm matches. Support updating sibling brainstorm with revisit section
- [x] T012 [P] [US7] Add init auto-detection advisory in spex/extensions/spex/commands/speckit.spex.brainstorm.md: when detach is enabled and `archive.path` is empty, scan `../` for `*-specs` directories, suggest first match as advisory message. Note: FR-010 targets `specify init` (upstream spec-kit), but init cannot be modified here; brainstorm is the practical integration point

**Checkpoint**: Brainstorm skill discovers sibling repo documents and suggests archive.path

---

## Phase 5: Polish & Documentation

**Purpose**: Update documentation to reflect new detach capabilities

- [x] T013 [P] Update spex/docs/help.md: add detach workflow section explaining finish integration, archive, verify, and .gitignore check
- [x] T014 [P] Update README.md: update spex-detach extension description to reflect archive+verify+finish integration capabilities

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Bug Fix)**: No dependencies, can start immediately
- **Phase 2 (Script Enhancements)**: No dependency on Phase 1 (different file). Can run in parallel with Phase 1
- **Phase 3 (Finish Integration)**: Depends on Phase 2 completion (finish.md calls verify and archive --move from spex-detach.py)
- **Phase 4 (Brainstorm Enhancements)**: Depends on Phase 1 (same file, path fix should be done first)
- **Phase 5 (Documentation)**: Depends on Phase 3 and Phase 4 (documents final behavior)

### User Story Dependencies

- **US3 (P2)**: Independent, fix first (one-liner)
- **US2 (P1)**: Independent, modifies spex-detach.py (verify)
- **US4 (P2)**: Independent, modifies spex-detach.py (archive), can run in parallel with US2
- **US5 (P3)**: Independent, modifies spex-detach.py (.gitignore check), can run in parallel with US2/US4
- **US1 (P1)**: Depends on US2 + US4 (finish needs verify and archive --move to exist)
- **US6 (P3)**: Depends on US3 (same file, path fix should be done first)
- **US7 (P3)**: Depends on US3 (same file, path fix should be done first)

### Parallel Opportunities

- Phase 1 and Phase 2 can run in parallel (different files)
- Within Phase 2: T002-T006 all modify spex-detach.py but different functions, marked [P] (except T003 which depends on T002)
- Phase 4: T011 and T012 modify brainstorm skill but different sections, marked [P]
- Phase 5: T013 and T014 are different files, marked [P]

---

## Implementation Strategy

### MVP First (US2 + US1)

1. Fix path bug (T001) - quick win
2. Add verify to spex-detach.py (T002, T003) - core safety
3. Wire detach into finish (T008, T009, T010) - core gap
4. **STOP and VALIDATE**: Test finish with detach enabled

### Incremental Delivery

1. Phase 1 + Phase 2 → Script enhancements ready
2. Phase 3 → Finish integration working → Core value delivered
3. Phase 4 → Brainstorm enhancements → Nice-to-have
4. Phase 5 → Documentation → Complete feature

---

## Notes

- All changes are modifications to existing files, no new files created
- spex-detach.py is the most heavily modified file (T002-T006)
- speckit.spex.finish.md is the most critical change (T008-T010)
- speckit.spex.brainstorm.md has both a bug fix (T001) and enhancements (T011, T012)
- Commit after each task or logical group
