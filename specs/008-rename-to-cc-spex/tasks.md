# Tasks: Rename Plugin to cc-spex

**Input**: Design documents from `/specs/008-rename-to-cc-spex/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Tests**: No automated test suite exists for this plugin. Verification is manual (`make reinstall` + Claude Code session testing).

**Organization**: Tasks are grouped by user story to enable incremental rename and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Directory and File Renames)

**Purpose**: Structural renames that must happen before any content changes

- [x] T001 Rename plugin root directory: `git mv sdd/ spex/`
- [x] T002 Rename init script: `git mv spex/scripts/sdd-init.sh spex/scripts/spex-init.sh`
- [x] T003 Rename traits script: `git mv spex/scripts/sdd-traits.sh spex/scripts/spex-traits.sh`

**Checkpoint**: Directory structure is in place. All subsequent tasks reference `spex/` paths.

---

## Phase 2: Foundational (Plugin Metadata)

**Purpose**: Update plugin identity files that define how Claude Code loads the plugin

**CRITICAL**: Plugin will not load correctly until these are updated to match directory structure.

- [x] T004 Update plugin name and keywords in `spex/.claude-plugin/plugin.json`: change `"name": "sdd"` to `"spex"`, keyword `"sdd"` to `"spex"`
- [x] T005 [P] Update hooks.json path references in `spex/.claude-plugin/` if any reference `sdd/` (no-op: uses ${CLAUDE_PLUGIN_ROOT})
- [x] T006 [P] Update `spex/.superpowers-sync` metadata references from `sdd` to `spex`

**Checkpoint**: Plugin metadata points to correct names and paths.

---

## Phase 3: User Story 1 - Plugin Internal Rename (Priority: P1) MVP

**Goal**: All commands, skills, overlays, hooks, and scripts use `spex:` prefix internally.

**Independent Test**: `make reinstall` then run `/spex:help`, `/spex:init`, `/spex:traits` in Claude Code. All commands load, hooks fire correctly, skills cross-reference each other.

### Command Files (10 files)

- [x] T007 [P] [US1] Update frontmatter `name: sdd:brainstorm` to `spex:brainstorm` and all internal `sdd:` refs in `spex/commands/brainstorm.md`
- [x] T008 [P] [US1] Update frontmatter `name: sdd:evolve` to `spex:evolve` and all internal `sdd:` refs in `spex/commands/evolve.md`
- [x] T009 [P] [US1] Update frontmatter `name: sdd:help` to `spex:help` and all internal `sdd:` refs in `spex/commands/help.md`
- [x] T010 [P] [US1] Update frontmatter `name: sdd:init` to `spex:init` and all internal `sdd:` refs in `spex/commands/init.md`
- [x] T011 [P] [US1] Update frontmatter `name: sdd:review-code` to `spex:review-code` and all internal `sdd:` refs in `spex/commands/review-code.md`
- [x] T012 [P] [US1] Update frontmatter `name: sdd:review-plan` to `spex:review-plan` and all internal `sdd:` refs in `spex/commands/review-plan.md`
- [x] T013 [P] [US1] Update frontmatter `name: sdd:review-spec` to `spex:review-spec` and all internal `sdd:` refs in `spex/commands/review-spec.md`
- [x] T014 [P] [US1] Update frontmatter `name: sdd:traits` to `spex:traits` and all internal `sdd:` refs in `spex/commands/traits.md`
- [x] T015 [P] [US1] Update frontmatter `name: sdd:verify` to `spex:verify` and all internal `sdd:` refs in `spex/commands/verify.md`
- [x] T016 [P] [US1] Update frontmatter `name: sdd:worktree` to `spex:worktree` and all internal `sdd:` refs in `spex/commands/worktree.md`

### Skill Files (14 files with references)

- [x] T017 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/brainstorm/SKILL.md`
- [x] T018 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/evolve/SKILL.md`
- [x] T019 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/help/SKILL.md`
- [x] T020 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/init/SKILL.md`
- [x] T021 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/review-code/SKILL.md`
- [x] T022 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/review-plan/SKILL.md`
- [x] T023 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/review-spec/SKILL.md`
- [x] T024 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/spec-kit/SKILL.md`
- [x] T025 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/spec-refactoring/SKILL.md`
- [x] T026 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/teams-orchestrate/SKILL.md`
- [x] T027 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/teams-spec-guardian/SKILL.md`
- [x] T028 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/using-superpowers/SKILL.md`
- [x] T029 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/verification-before-completion/SKILL.md`
- [x] T030 [P] [US1] Replace `{Skill: sdd:*}` with `{Skill: spex:*}` and `/sdd:` with `/spex:` in `spex/skills/worktree/SKILL.md`

### Overlay Files (9 files with references)

- [x] T031 [P] [US1] Replace `{Skill: sdd:*}` and `/sdd:` refs in `spex/overlays/superpowers/commands/speckit.specify.append.md`
- [x] T032 [P] [US1] Replace `{Skill: sdd:*}` and `/sdd:` refs in `spex/overlays/superpowers/commands/speckit.plan.append.md`
- [x] T033 [P] [US1] Replace `{Skill: sdd:*}` and `/sdd:` refs in `spex/overlays/superpowers/commands/speckit.implement.append.md`
- [x] T034 [P] [US1] Replace `{Skill: sdd:*}` refs in `spex/overlays/teams/commands/speckit.implement.append.md`
- [x] T035 [P] [US1] Replace `{Skill: sdd:*}` refs in `spex/overlays/teams/commands/speckit.plan.append.md`
- [x] T036 [P] [US1] Replace `{Skill: sdd:*}` refs in `spex/overlays/teams-spec/commands/speckit.implement.append.md`
- [x] T037 [P] [US1] Replace `{Skill: sdd:*}` refs in `spex/overlays/teams-vanilla/commands/speckit.implement.append.md`
- [x] T038 [P] [US1] Replace `{Skill: sdd:*}` refs in `spex/overlays/teams-vanilla/commands/speckit.plan.append.md`
- [x] T039 [P] [US1] Replace `{Skill: sdd:*}` refs in `spex/overlays/worktrees/commands/speckit.specify.append.md`

### Hook Scripts (4 Python files)

- [x] T040 [US1] Update `spex/scripts/hooks/context-hook.py`: change `/sdd:` prefix matching to `/spex:`, XML tags `<sdd-*>` to `<spex-*>`, marker file `.claude-sdd-*` to `.claude-spex-*`, script paths `sdd-init.sh`/`sdd-traits.sh` to `spex-*`, config path `sdd-traits.json` to `spex-traits.json`, known commands list
- [x] T041 [P] [US1] Update `spex/scripts/hooks/skill-gate-hook.py`: change marker file `.claude-sdd-skill-pending-*` to `.claude-spex-skill-pending-*`, `/sdd:` refs to `/spex:`
- [x] T042 [P] [US1] Update `spex/scripts/hooks/verification-gate-hook.py`: change marker `.claude-sdd-verified-*` to `.claude-spex-verified-*`, `/sdd:verify` to `/spex:verify`
- [x] T043 [P] [US1] Update `spex/scripts/hooks/teams-enforce-hook.py`: change `{Skill: sdd:teams-orchestrate}` to `{Skill: spex:teams-orchestrate}`

### Shell Scripts (internal references)

- [x] T044 [US1] Update `spex/scripts/spex-init.sh`: change `sdd-traits.sh` refs to `spex-traits.sh`, `sdd-traits.json` refs to `spex-traits.json`, any `sdd/` path refs to `spex/`
- [x] T045 [US1] Update `spex/scripts/spex-traits.sh` in sub-steps (400+ occurrences, highest-risk task):
  1. Change `TRAITS_CONFIG` constant from `.specify/sdd-traits.json` to `.specify/spex-traits.json`
  2. Change `SDD_PATTERN_INIT` value to reference `spex-init.sh`
  3. Change `SDD_PATTERN_TRAITS` value to reference `spex-traits.sh`
  4. Replace all `sdd-init.sh` / `sdd-traits.sh` path references with `spex-*` equivalents
  5. Replace `.sdd-phase` with `.spex-phase`
  6. Keep `<!-- SDD-TRAIT:* -->` sentinel format unchanged (methodology name)
  7. Verify with `rg 'sdd' spex/scripts/spex-traits.sh` that only `SDD-TRAIT` sentinels and "SDD" prose remain
- [x] T046 [P] [US1] Update `spex/scripts/check-upstream-changes.sh`: change any `sdd` path references to `spex`

### Plugin Docs (6 files)

- [x] T047 [P] [US1] Update `sdd:` command refs to `spex:` in `spex/docs/help.md`
- [x] T048 [P] [US1] Update `sdd:` command refs to `spex:` in `spex/docs/tutorial-full.md`
- [x] T049 [P] [US1] Update `sdd:` command refs to `spex:` in `spex/docs/tutorial-quickstart.md`
- [x] T050 [P] [US1] Update `sdd:` command refs to `spex:` in `spex/docs/tutorial-team.md`
- [x] T051 [P] [US1] Update `sdd` refs in `spex/docs/sync-reports/sync-2026-03-20.md`
- [x] T052 [P] [US1] Update `sdd` refs in `spex/docs/sync-reports/sync-2026-02-13.md`

### Dev Command

- [x] T053 [US1] Update `cc-sdd` verification checks in `spex/.claude/commands/update-superpowers.md`

**Checkpoint**: Plugin internal rename complete. `make reinstall` should load all `/spex:*` commands. Run `/spex:help` to verify.

---

## Phase 4: User Story 2 - Backwards-Compatible Migration (Priority: P2)

**Goal**: Existing projects with `sdd-traits.json` seamlessly migrate to `spex-traits.json` on `/spex:init`.

**Independent Test**: Create a test project with `.specify/sdd-traits.json`. Run `/spex:init`. Verify `spex-traits.json` is created with identical content.

- [ ] T054 [US2] Add migration logic to `spex/scripts/spex-init.sh`: detect `.specify/sdd-traits.json`, copy to `.specify/spex-traits.json` if new file doesn't exist, print migration message
- [ ] T055 [US2] Update `spex/scripts/spex-traits.sh` to check `spex-traits.json` first, fall back to `sdd-traits.json` for read-only access during transition
- [ ] T056 [US2] Add `.spex-phase` / `.sdd-phase` transition awareness to `spex/scripts/spex-init.sh`: recognize old phase marker, write new one

**Checkpoint**: Migration works end-to-end. Old projects upgrade smoothly.

---

## Phase 5: User Story 3 - Repo-Root Documentation (Priority: P3)

**Goal**: All repo-root files reflect `spex` naming. Only "SDD" methodology prose remains.

**Independent Test**: `rg 'sdd:' --glob '!specs/**' --glob '!brainstorm/**' --glob '!CHANGELOG.md' .` returns zero command-prefix matches.

### Speckit Command Files

- [ ] T057 [P] [US3] Update `{Skill: sdd:*}` to `{Skill: spex:*}` in `.claude/commands/speckit.implement.md`
- [ ] T058 [P] [US3] Update `{Skill: sdd:*}` to `{Skill: spex:*}` in `.claude/commands/speckit.specify.md`
- [ ] T059 [P] [US3] Update `{Skill: sdd:*}` to `{Skill: spex:*}` in `.claude/commands/speckit.plan.md`

### Build and Config Files

- [ ] T060 [US3] Update `Makefile`: change `MARKETPLACE := sdd-plugin-development` to `spex-plugin-development`, `PLUGIN` variable, test command paths, `sdd/` directory refs to `spex/`
- [ ] T061 [P] [US3] Update `.claude-plugin/marketplace.json`: change name `"sdd"` to `"spex"`, source `"./sdd"` to `"./spex"`, update URLs to `rhuss/cc-spex`
- [ ] T062 [P] [US3] Update `.gitignore`: change `sdd/` path patterns to `spex/`, `.sdd-phase` to `.spex-phase`

### Project Documentation

- [ ] T063 [US3] Update `CLAUDE.md`: project structure `sdd/` to `spex/`, command references, trait refs. Keep "SDD" methodology prose.
- [ ] T064 [P] [US3] Update `README.md`: project name, command examples from `sdd:` to `spex:`
- [ ] T065 [P] [US3] Update `TESTING.md`: test instructions from `sdd:` to `spex:`

### Constitution and Memory

- [ ] T066 [US3] Update `.specify/memory/constitution.md`: all `sdd:` prefix refs to `spex:`, `sdd/` path refs to `spex/`, `sdd-*.sh` to `spex-*.sh`, `sdd-traits.json` to `spex-traits.json`. Keep "SDD" as methodology name in titles and prose.
- [ ] T067 [US3] Update memory files in `.claude/projects/.../memory/MEMORY.md` and individual memory files: tooling references from `sdd` to `spex`

### Other Docs

- [ ] T068 [P] [US3] Update `docs/smoke-test.md`: `sdd:` command refs to `spex:`
- [ ] T069 [P] [US3] Update `docs/design.md`: `sdd` architecture refs to `spex`
- [ ] T070 [P] [US3] Update `docs/plugin-schema.md`: `sdd` schema examples to `spex`
- [ ] T071 [P] [US3] Update `docs/upstream-sync-strategy.md`: `sdd` sync refs to `spex`
- [ ] T072 [P] [US3] Update `examples/todo-app/WALKTHROUGH.md`: `sdd:` command refs to `spex:`
- [ ] T073 [P] [US3] Update `examples/todo-app/README.md`: `sdd:` command refs to `spex:`

**Checkpoint**: `rg 'sdd:' --glob '!specs/**' --glob '!brainstorm/**' --glob '!CHANGELOG.md' .` returns zero command-prefix matches. Only "SDD" methodology prose remains.

---

## Phase 6: User Story 4 - GitHub Repo and Directory Rename (Priority: P4)

**Goal**: Repository and parent directory reflect new name.

**Independent Test**: Old GitHub URL redirects. `make reinstall` works from new directory.

- [ ] T074 [US4] Update all `rhuss/cc-sdd` URLs to `rhuss/cc-spex` in `spex/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`, and any other files with hardcoded repo URLs. Note: T004 and T061 update name/source fields in these same files; T074 specifically targets repository/homepage URL fields that should only change when the GitHub rename is imminent.
- [ ] T075 [US4] Rename GitHub repository via Settings: `rhuss/cc-sdd` to `rhuss/cc-spex` (manual action)
- [ ] T076 [US4] Rename parent directory: `cc-superpowers-sdd` to `cc-superpowers-spex` (manual action)
- [ ] T077 [US4] Update git remote URL if needed after repo rename

**Checkpoint**: GitHub redirect works. Plugin installs from new path.

---

## Phase 7: User Story 5 - Consumer Projects (Priority: P5, separate effort)

**Goal**: Consumer projects reference new plugin name. Documented for completeness, not executed in this feature.

- [ ] T078 [US5] Update cc-deck `.claude/commands/speckit.*.md`: `{Skill: sdd:*}` to `{Skill: spex:*}`
- [ ] T079 [US5] Update cc-deck `.claude/settings.local.json`: script path permissions
- [ ] T080 [US5] Update cc-deck `.specify/sdd-traits.json` to `spex-traits.json`
- [ ] T081 [US5] Update cc-deck build manifests and Antora docs

**Note**: These tasks are in a separate repository and will be executed after the plugin rename is complete and tested.

---

## Phase 8: Polish & Verification

**Purpose**: Final validation across all user stories

- [ ] T082 Run automated verification: `rg 'sdd:' spex/` expects zero matches for command prefixes
- [ ] T083 Run automated verification: `rg '<sdd-' spex/scripts/` expects zero matches for XML tags
- [ ] T084 Run `make reinstall` and verify plugin loads with `/spex:*` commands
- [ ] T085 Test `/spex:init` with old `sdd-traits.json` migration scenario
- [ ] T086 Test `/spex:traits list` shows correct trait state
- [ ] T087 Run a mini SDD workflow: `/spex:brainstorm`, verify skill delegation works

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately. `git mv` operations.
- **Foundational (Phase 2)**: Depends on Phase 1 (directory must exist at new path).
- **US1 (Phase 3)**: Depends on Phase 1 and 2 (files at new paths with correct metadata).
- **US2 (Phase 4)**: Depends on T044, T045 from US1 (init/traits scripts must be updated first).
- **US3 (Phase 5)**: Can start after Phase 1 for non-plugin files, but ideally after US1 for consistency.
- **US4 (Phase 6)**: Depends on all previous phases (everything must be renamed before repo rename).
- **US5 (Phase 7)**: Depends on US4 (repo must be renamed first). Separate effort.
- **Polish (Phase 8)**: Depends on US1-US4 completion.

### User Story Dependencies

- **US1 (P1)**: Standalone after Setup. Core rename.
- **US2 (P2)**: Depends on US1 (migration logic goes in scripts that US1 renames).
- **US3 (P3)**: Loosely depends on US1 (documentation should match plugin state).
- **US4 (P4)**: Depends on US1 + US3 (everything must be renamed before GitHub rename).
- **US5 (P5)**: Separate repo, depends on US4.

### Within User Story 1

- Command files (T007-T016): all [P], can run in parallel
- Skill files (T017-T030): all [P], can run in parallel
- Overlay files (T031-T039): all [P], can run in parallel
- Hook scripts (T040-T043): T040 is complex (not [P]), T041-T043 are [P]
- Shell scripts (T044-T046): T044 and T045 are sequential (cross-reference), T046 is [P]
- Docs (T047-T053): all [P] except T053

### Parallel Opportunities

```text
# All command files at once:
T007, T008, T009, T010, T011, T012, T013, T014, T015, T016

# All skill files at once:
T017-T030

# All overlay files at once:
T031-T039

# Hook scripts (3 of 4 in parallel):
T041, T042, T043

# Plugin docs at once:
T047-T052

# Repo-root docs at once:
T064, T065, T068-T073
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: `git mv` operations (T001-T003)
2. Complete Phase 2: Plugin metadata (T004-T006)
3. Complete Phase 3: US1 internal rename (T007-T053)
4. **STOP and VALIDATE**: `make reinstall` + test `/spex:help`, `/spex:init`, `/spex:traits`
5. If working: proceed to US2-US4

### Incremental Delivery

1. Setup + Foundational + US1 = working plugin under new name
2. Add US2 = migration support for existing projects
3. Add US3 = consistent documentation
4. Add US4 = GitHub repo and directory rename
5. US5 = consumer projects (separate effort)

---

## Notes

- [P] tasks = different files, no dependencies
- Keep `<!-- SDD-TRAIT:name -->` sentinel markers unchanged (methodology name, not plugin prefix)
- Keep "SDD" in prose where it refers to Spec-Driven Development methodology
- Historical files (specs/, brainstorm/, CHANGELOG.md) are explicitly excluded from all tasks
- Total: 87 tasks across 8 phases
- US1 is heavily parallelizable (46 of 47 tasks are [P])
