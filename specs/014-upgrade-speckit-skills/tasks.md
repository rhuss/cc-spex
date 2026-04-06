# Tasks: Upgrade speckit commands to Agent Skills format

**Input**: Design documents from `/specs/014-upgrade-speckit-skills/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Release v3.0.2 and maintenance branch)

**Purpose**: Tag the last old-format release and create the maintenance branch before any migration work begins.

- [x] T001 Bump version to 3.0.2 in `.claude-plugin/marketplace.json` and `spex/.claude-plugin/plugin.json`
- [x] T002 Add v3.0.2 entry in `CHANGELOG.md` noting this is the last release supporting `speckit.*.md` commands
- [x] T003 Run `make release` to validate current state
- [x] T004 Tag v3.0.2 and create GitHub release via `gh release create v3.0.2 --generate-notes`
- [x] T005 Create `release/3.x` branch from v3.0.2 tag

**Checkpoint**: v3.0.2 released, `release/3.x` branch exists for bugfix maintenance

---

## Phase 2: Foundational (Core script updates)

**Purpose**: Update spex-init.sh and spex-traits.sh to support the new skills format. These MUST be complete before overlay migration or reference updates.

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Add `check_version()` function to `spex/scripts/spex-init.sh` that parses `specify version` output, extracts semver, and requires >= 0.5.0
- [x] T007 Update `check_ready()` in `spex/scripts/spex-init.sh` to look for `.claude/skills/speckit-specify/SKILL.md` (and other core skills) instead of `.claude/commands/speckit.${cmd}.md`
- [x] T008 Add `migrate_old_commands()` function to `spex/scripts/spex-init.sh` that detects and removes old `.claude/commands/speckit.*.md` files
- [x] T009 Update `configure_gitignore()` in `spex/scripts/spex-init.sh` to use `.claude/skills/speckit-*` pattern instead of `.claude/commands/speckit.*`
- [x] T010 Update `do_init()` in `spex/scripts/spex-init.sh` to call version check before `specify init`, invoke migration, and update command detection from `ls .claude/commands/speckit.*` to `ls .claude/skills/speckit-*/SKILL.md`
- [x] T011 Update `apply_internal_overlays()` in `spex/scripts/spex-traits.sh` to scan for `skills/*/SKILL.append.md` instead of `commands/*.append.md`, mapping to `.claude/skills/*/SKILL.md` targets
- [x] T012 Update `do_apply()` in `spex/scripts/spex-traits.sh` to handle new overlay directory structure: `skills/<name>/SKILL.{append,prepend}.md` → `.claude/skills/<name>/SKILL.md`
- [x] T013 Add prepend support in `spex/scripts/spex-traits.sh`: detect `SKILL.prepend.md` files, insert content after YAML frontmatter (between `---` markers) but before main content, use `<!-- SPEX-PREPEND:<trait> -->` sentinel
- [x] T014 Update sentinel cleanup logic in `spex/scripts/spex-traits.sh` to scan `.claude/skills/` instead of `.claude/commands/`

**Checkpoint**: Both core scripts support the new skills format. Init can detect version, migrate old files, and validate new format. Traits can apply overlays to skills with both append and prepend.

---

## Phase 3: User Story 1 - Fresh project initialization (Priority: P1) MVP

**Goal**: New users can run `/spex:init` and get working speckit skills with trait overlays applied.

**Independent Test**: Run `spex-init.sh` in a clean directory with specify >= 0.5.0. Verify `.claude/skills/speckit-*/SKILL.md` files exist, traits apply, gitignore is correct.

### Implementation for User Story 1

- [x] T015 [P] [US1] Migrate ship-guard overlays: create `spex/overlays/_ship-guard/skills/speckit-clarify/SKILL.append.md` (move from `commands/speckit.clarify.append.md`), repeat for implement, plan, specify, tasks (5 files total)
- [x] T016 [P] [US1] Migrate superpowers overlays: create `spex/overlays/superpowers/skills/speckit-implement/SKILL.append.md`, `speckit-plan/SKILL.append.md`, `speckit-specify/SKILL.append.md` (3 files)
- [x] T017 [P] [US1] Migrate deep-review overlay: create `spex/overlays/deep-review/skills/speckit-implement/SKILL.append.md` (1 file)
- [x] T018 [P] [US1] Migrate teams overlays: create `spex/overlays/teams/skills/speckit-implement/SKILL.append.md`, `speckit-plan/SKILL.append.md` (2 files)
- [x] T019 [P] [US1] Migrate worktrees overlays: create `spex/overlays/worktrees/skills/speckit-implement/SKILL.append.md`, `speckit-plan/SKILL.append.md`, `speckit-specify/SKILL.append.md` (3 files)
- [x] T020 [P] [US1] Migrate deprecated overlays: create `spex/overlays/teams-spec/skills/speckit-implement/SKILL.append.md`, `spex/overlays/teams-vanilla/skills/speckit-implement/SKILL.append.md`, `spex/overlays/teams-vanilla/skills/speckit-plan/SKILL.append.md` (3 files)
- [x] T021 [US1] Remove old `commands/` subdirectories from all overlay trait directories after migration
- [x] T022 [US1] Update speckit references inside overlay files: change `/speckit.tasks` → `/speckit-tasks` and `/speckit.clarify` → `/speckit-clarify` in `spex/overlays/superpowers/skills/speckit-plan/SKILL.append.md`

**Checkpoint**: All 17 overlay files migrated to skills structure. Fresh init with traits produces correct results.

---

## Phase 4: User Story 2 - Existing user upgrade (Priority: P1)

**Goal**: Users with old speckit.*.md files get a clear upgrade path with version gate and migration.

**Independent Test**: Set up project with old files, run init with old CLI (verify error), upgrade CLI, re-run init (verify migration).

### Implementation for User Story 2

- [x] T023 [US2] Update `spex/scripts/hooks/pretool-gate.py`: change command name mapping from `"speckit.specify"` → `"speckit-specify"` etc. (5 mappings)
- [x] T024 [US2] Update `spex/scripts/hooks/context-hook.py`: change command URL mappings from `'/speckit.specify'` → `'/speckit-specify'` etc. (4 mappings + context string)

**Checkpoint**: Version gate blocks old CLI with clear message, migration cleans up old files, hooks route correctly.

---

## Phase 5: User Story 3 - Trait overlay with prepend (Priority: P2)

**Goal**: Trait system works with new skills format including prepend support.

**Independent Test**: Enable superpowers trait, verify SKILL.md files contain appended content. Create a test SKILL.prepend.md, verify it inserts before content but after frontmatter.

### Implementation for User Story 3

- [x] T025 [US3] Verify idempotent overlay application: run `spex-traits.sh apply` twice, confirm no duplicate sentinels in `.claude/skills/speckit-*/SKILL.md`
- [x] T026 [US3] Test prepend with a YAML-frontmatter SKILL.md: create test case, verify prepend inserts after `---` frontmatter block

**Checkpoint**: Trait system fully functional with new overlay structure, including prepend.

---

## Phase 6: User Story 4 - Skill and command reference updates (Priority: P2)

**Goal**: All active spex files use the new hyphen notation for speckit commands.

**Independent Test**: `rg 'speckit\.' spex/skills/ spex/commands/ spex/scripts/` returns zero matches.

### Implementation for User Story 4

- [x] T027 [P] [US4] Update speckit references in `spex/skills/ship/SKILL.md` (25+ references: `/speckit.specify` → `/speckit-specify`, etc.)
- [x] T028 [P] [US4] Update speckit references in `spex/skills/brainstorm/SKILL.md` (20+ references)
- [x] T029 [P] [US4] Update speckit references in `spex/skills/spec-kit/SKILL.md` (20+ references, also update `.claude/commands/speckit.` path refs to `.claude/skills/speckit-`)
- [x] T030 [P] [US4] Update speckit references in `spex/skills/using-superpowers/SKILL.md` (15+ references)
- [x] T031 [P] [US4] Update speckit references in `spex/skills/review-spec/SKILL.md` (8+ references)
- [x] T032 [P] [US4] Update speckit references in `spex/skills/evolve/SKILL.md` (8+ references)
- [x] T033 [P] [US4] Update speckit references in `spex/skills/worktree/SKILL.md` (6+ references)
- [x] T034 [P] [US4] Update speckit references in `spex/skills/review-code/SKILL.md` (2+ references)
- [x] T035 [P] [US4] Update speckit references in `spex/skills/deep-review/SKILL.md` (2+ references)
- [x] T036 [P] [US4] Update speckit references in `spex/skills/verification-before-completion/SKILL.md` (2+ references)
- [x] T037 [P] [US4] Update speckit references in `spex/skills/review-plan/SKILL.md` (3+ references)
- [x] T038 [US4] Update speckit reference in `spex/commands/init.md` (1 reference)
- [x] T039 [US4] Verify zero dot-notation references remain: run `rg 'speckit\.' spex/skills/ spex/commands/ spex/scripts/` and confirm empty output

**Checkpoint**: All active spex files use hyphen notation. Zero dot-notation references in skills, commands, or scripts.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, constitution, version bump, and final validation.

- [x] T040 [P] Update `README.md`: replace all `/speckit.X` references with `/speckit-X`, update workflow diagrams, command tables, overlay path descriptions
- [x] T041 [P] Update `CHANGELOG.md`: add v4.0.0 section with breaking change description and migration instructions
- [x] T042 [P] Update `docs/smoke-test.md`: replace speckit references and `.claude/commands/speckit` path references
- [x] T043 [P] Update `docs/plugin-schema.md`: replace speckit reference and path description
- [x] T044 [P] Update `spex/docs/help.md`: replace all speckit command references (15+ occurrences)
- [x] T045 [P] Update `spex/docs/tutorial-full.md`: replace speckit references (3 occurrences)
- [x] T046 [P] Update `spex/docs/tutorial-team.md`: replace speckit references (2 occurrences)
- [x] T047 Update `.specify/memory/constitution.md`: update Section V (naming, `/speckit.*` → `/speckit-*`) and Plugin Architecture Constraints (overlay paths `{commands,templates}/` → `skills/<name>/`)
- [x] T048 Update `.gitignore`: replace `.claude/commands/speckit.*` with `.claude/skills/speckit-*`
- [ ] T049 Bump version to 4.0.0 in `.claude-plugin/marketplace.json` and `spex/.claude-plugin/plugin.json`
- [ ] T050 Run `make release` to validate entire plugin with new format
- [x] T051 Verify SC-005: `rg 'speckit\.' spex/ README.md docs/ .gitignore` shows zero matches in active files (historical specs excluded)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup/Release)**: No dependencies, start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 (must be on main after release)
- **Phase 3 (US1 - Fresh init)**: Depends on Phase 2 (scripts must support new format)
- **Phase 4 (US2 - Upgrade path)**: Depends on Phase 2 (version gate must exist)
- **Phase 5 (US3 - Prepend)**: Depends on Phase 2 (prepend logic in spex-traits.sh)
- **Phase 6 (US4 - References)**: Independent of Phases 3-5, only requires Phase 2
- **Phase 7 (Polish)**: Depends on Phases 3-6 completion

### User Story Dependencies

- **US1 (Fresh init)**: Depends on Foundational only. Requires overlay files to be migrated.
- **US2 (Upgrade)**: Depends on Foundational only. Can run in parallel with US1.
- **US3 (Prepend)**: Depends on Foundational (prepend support in traits script). Can run in parallel with US1/US2.
- **US4 (References)**: Independent of US1-3. Can start as soon as Phase 2 is done.

### Within Each User Story

- Overlay migrations (T015-T020) are all parallelizable
- Reference updates (T027-T037) are all parallelizable (different files)
- Documentation updates (T040-T046) are all parallelizable

### Parallel Opportunities

```text
After Phase 2 completes:
  ├── US1 (T015-T022) - overlay migration
  ├── US2 (T023-T024) - hook updates         } all in parallel
  ├── US3 (T025-T026) - prepend verification
  └── US4 (T027-T039) - reference updates

Within US1: T015, T016, T017, T018, T019, T020 all parallel
Within US4: T027-T037 all parallel
Within Phase 7: T040-T046 all parallel
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2)

1. Complete Phase 1: Release v3.0.2, create release/3.x
2. Complete Phase 2: Core script updates (spex-init.sh, spex-traits.sh)
3. Complete Phase 3: Overlay migration (US1)
4. Complete Phase 4: Hook updates (US2)
5. **STOP and VALIDATE**: Test fresh init and upgrade path
6. Continue with US3, US4, and Polish

### Incremental Delivery

1. Phase 1 + 2 → Foundation ready (scripts work with new format)
2. Phase 3 (US1) → Fresh init works → Can test end-to-end
3. Phase 4 (US2) → Upgrade path works → Existing users can migrate
4. Phase 5 (US3) → Prepend verified → Advanced trait features confirmed
5. Phase 6 (US4) → References clean → No stale dot-notation
6. Phase 7 → Documentation, version bump, final validation → Release v4.0.0

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Historical artifacts (brainstorm/, old specs/) are excluded from reference updates per FR-006
- Deprecated overlays (teams-spec, teams-vanilla) are migrated alongside active ones
- Commit after each phase or logical group
- Stop at any checkpoint to validate independently
