# Tasks: Update Check on Init

**Input**: Design documents from `specs/035-update-check/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: Create the VERSION file as the canonical version source

- [x] T001 Create VERSION file at repository root with content `5.9.1-dev` in `VERSION`

---

## Phase 2: User Story 2 - VERSION file as version source of truth (P1)

**Story goal**: VERSION file exists at repo root, marketplace.json version is derived from it during release.

**Independent test**: Read VERSION file and verify it contains a valid semver string. After a release, verify marketplace.json matches.

- [x] T002 [US2] Rewrite `make release` target in `Makefile`: read version from `VERSION`, guard against `-dev` suffix (exit with "Cannot release a dev version. Remove -dev suffix from VERSION first."), preserve existing `validate` and `test-install` prerequisites, update `.claude-plugin/marketplace.json` version field using `jq`, commit, create git tag `v$VERSION`, push commit and tag, then bump `VERSION` to `{patch+1}-dev`, commit, and push

---

## Phase 3: User Story 1 - Update notification on init (P1)

**Story goal**: Users running an outdated version see a warning during init.

**Independent test**: Set VERSION to an older version, run init, verify warning appears. Disconnect network, run init, verify silent completion.

- [x] T005 [US1] Add `check_update()` function to `spex/scripts/spex-init.sh` that reads VERSION from `$script_dir/../../VERSION`, curls GitHub releases API with `--connect-timeout 3 --max-time 5 -sf`, extracts `tag_name` and `body` using `jq`, and compares versions
- [x] T006 [US1] Implement semver comparison logic in `check_update()` in `spex/scripts/spex-init.sh`: if local version has `-dev` suffix, skip check entirely (per FR-008); otherwise split version on `.`, compare major/minor/patch numerically; if local >= latest, silent; if local < latest, print warning
- [x] T007 [US1] Add breaking change extraction in `check_update()` in `spex/scripts/spex-init.sh`: grep release body for lines starting with `BREAKING:` and display them below the version warning
- [x] T008 [US1] Call `check_update` from normal init path and `--refresh` path in `spex/scripts/spex-init.sh` (not from `--clear` or `--update`)

---

## Phase 4: Polish & Documentation

**Purpose**: Update documentation to reflect the new feature

- [x] T009 Update `README.md` with update check behavior description and VERSION file documentation
- [x] T010 Update `spex/docs/help.md` with update check mention in the init command reference
- [x] T011 Update constitution release process description in `.specify/memory/constitution.md` to reference VERSION file instead of manual marketplace.json version bump

---

## Dependencies

```
T001 (VERSION file) ──┬── T002 (make release)
                      └── T005, T006, T007, T008 (update check)

T002 ── independent of ── T005, T006, T007, T008
(US2 and US1 can run in parallel after T001)

T005 ── T006 ── T007 ── T008 (sequential within US1)

T009, T010, T011 ── after all implementation tasks
```

## Parallel Execution

- **US2 task** (T002) and **US1 tasks** (T005-T008) can run in parallel after T001
- **Documentation tasks** (T009-T011) are all parallelizable with each other

## Implementation Strategy

**MVP**: T001 + T005-T008 (VERSION file + update check). This delivers the core user-facing feature.

**Full scope**: All 11 tasks. US2 (make release) and documentation are important but not blocking for the update check itself.

**Incremental delivery**: Implement US1 (update check) first for immediate user value, then US2 (make release automation), then documentation.
