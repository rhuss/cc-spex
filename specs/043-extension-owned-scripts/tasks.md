# Tasks: Extension-Owned Scripts

**Input**: Design documents from `specs/043-extension-owned-scripts/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Remove Stale and Canonical Scripts

**Purpose**: Delete detach scripts from wrong locations

- [x] T001 [P] [US2] Delete stale `spex/extensions/spex/scripts/spex-detach.py` (stale copy from before extension refactor)
- [x] T002 [P] [US2] Delete stale `spex/extensions/spex/scripts/spex-detach.sh` (stale copy, no longer referenced after PR #38 path fix)
- [x] T003 [P] [US1] Delete canonical `spex/scripts/spex-detach.py` (now extension-owned at `spex/extensions/spex-detach/scripts/`)
- [x] T004 [P] [US1] Delete canonical `spex/scripts/spex-detach.sh` (now extension-owned at `spex/extensions/spex-detach/scripts/`)

**Checkpoint**: Only `spex/extensions/spex-detach/scripts/` contains detach scripts

---

## Phase 2: Update Makefile

**Purpose**: Update SCRIPTS variables so sync only handles shared scripts

- [x] T005 [US1] Remove `spex-detach.sh` from `SCRIPTS_spex` in Makefile (FR-006)
- [x] T006 [US1] Remove `spex-detach` from `EXTENSIONS` list, delete `SCRIPTS_spex_detach` variable, and delete `_print-scripts-spex-detach` helper target in Makefile (FR-003, FR-004, FR-007). Clearing the variable to empty would break sync-scripts which guards against empty script lists with `exit 1`.

**Checkpoint**: `make sync-scripts && make sync-scripts-check` passes

---

## Phase 3: Fix Harness Marker

**Purpose**: Fix bash syntax error from harness marker inside fenced block

- [x] T007 [US4] Split bash block around first `{harness:codex-review-tool}` marker in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: close bash fence before marker, place marker outside, open new bash fence after (FR-008)

**Checkpoint**: Harness markers are outside all fenced bash blocks

---

## Phase 4: Validate

**Purpose**: Verify build passes after all changes

- [x] T008 Run `make sync-scripts` and verify no errors
- [x] T009 Run `make sync-scripts-check` and verify clean pass

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1**: No dependencies, all deletions are independent
- **Phase 2**: Depends on Phase 1 (Makefile changes reference scripts that should be deleted first)
- **Phase 3**: Independent of Phases 1-2 (different file entirely)
- **Phase 4**: Depends on Phases 1-3 (validates final state)

### Parallel Opportunities

- T001-T004 are all file deletions on different files, fully parallel
- T005-T006 modify the same file (Makefile) but different lines
- T007 is independent of all other tasks (different file)
- Phase 1 and Phase 3 can run in parallel

---

## Implementation Strategy

### MVP First

1. Delete stale copies (T001-T002) - immediate safety improvement
2. Delete canonical copies (T003-T004) + update Makefile (T005-T006) - completes the ownership migration
3. Fix harness marker (T007) - separate bug fix
4. Validate (T008-T009) - confirm nothing broken

---

## Notes

- This is a deletion-heavy feature. Most tasks are `rm` operations.
- The authoritative copies at `spex/extensions/spex-detach/scripts/` are NOT modified.
- `spex-flow-state.sh` remains canonical and shared (no changes).
