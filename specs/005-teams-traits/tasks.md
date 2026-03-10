# Tasks: Agent Teams Integration for SDD

**Input**: Design documents from `/specs/005-teams-traits/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Prepare overlay and skill directory structure

- [ ] T001 (cc-superpowers-sdd-yaa.1) Create overlay directory structure: `sdd/overlays/teams-vanilla/commands/` and `sdd/overlays/teams-spec/commands/`
- [ ] T002 (cc-superpowers-sdd-yaa.2) [P] Create skill directory structure: `sdd/skills/teams-orchestrate/` and `sdd/skills/teams-spec-guardian/`

---

## Phase 2: Foundational - Trait Dependency Infrastructure (User Story 2 - P1)

**Purpose**: Extend `sdd-traits.sh` with dependency checking. MUST complete before trait overlays can be tested.

**Goal**: Users can enable/disable traits with dependency validation. `teams-spec` cannot be enabled without its dependencies.

**Independent Test**: Run `sdd-traits.sh enable teams-spec` without deps (should error). Enable all deps, then enable `teams-spec` (should succeed). Try disabling `teams-vanilla` while `teams-spec` is enabled (should error).

- [ ] T003 (cc-superpowers-sdd-9nj.1) [US2] Extend `VALID_TRAITS` to include `teams-vanilla` and `teams-spec` in `sdd/scripts/sdd-traits.sh`
- [ ] T004 (cc-superpowers-sdd-9nj.2) [US2] Add `get_trait_deps()` function using case statement (bash 3.2 compatible) in `sdd/scripts/sdd-traits.sh` that returns dependency list for each trait
- [ ] T005 (cc-superpowers-sdd-9nj.3) [US2] Add `check_deps_for_enable()` function in `sdd/scripts/sdd-traits.sh` that checks all dependencies of a given trait are enabled, returns missing list
- [ ] T006 (cc-superpowers-sdd-9nj.4) [US2] Add `check_dependents_for_disable()` function in `sdd/scripts/sdd-traits.sh` that checks no enabled trait depends on the one being disabled, returns dependent list
- [ ] T007 (cc-superpowers-sdd-9nj.5) [US2] Modify `do_enable()` in `sdd/scripts/sdd-traits.sh` to call `check_deps_for_enable()` before enabling and report missing deps with exit 1
- [ ] T008 (cc-superpowers-sdd-9nj.6) [US2] Modify `do_disable()` in `sdd/scripts/sdd-traits.sh` to call `check_dependents_for_disable()` before disabling and report dependents with exit 1
- [ ] T009 (cc-superpowers-sdd-9nj.7) [US2] Modify `do_init()` in `sdd/scripts/sdd-traits.sh` to auto-include `teams-vanilla` when `teams-spec` is in the enable list (with warning), and error if `superpowers` or `beads` are missing when `teams-spec` is requested
- [ ] T010 (cc-superpowers-sdd-9nj.8) [US2] Update `ensure_config()` in `sdd/scripts/sdd-traits.sh` to include `teams-vanilla` and `teams-spec` keys (both false) in default config JSON

**Checkpoint**: Dependency infrastructure complete. `sdd-traits.sh enable/disable/init` correctly validates trait dependencies.

---

## Phase 3: User Story 1 - teams-vanilla Trait (Priority: P1) MVP

**Goal**: Enable parallel task implementation via CC Teams with basic lead coordination.

**Independent Test**: Enable `teams-vanilla`, run `/speckit.implement` on a project with 5+ independent tasks. Verify teammates are spawned and tasks complete in parallel.

### Implementation for User Story 1

- [ ] T011 (cc-superpowers-sdd-p08.1) [P] [US1] Create teams-vanilla overlay at `sdd/overlays/teams-vanilla/commands/speckit.implement.append.md` with sentinel marker `<!-- SDD-TRAIT:teams-vanilla -->`, CC Teams feature flag check, and delegation to `{Skill: sdd:teams-orchestrate}`
- [ ] T012 (cc-superpowers-sdd-p08.2) [US1] Create teams-orchestrate skill at `sdd/skills/teams-orchestrate/SKILL.md` with frontmatter, CC Teams prerequisite check, feature flag auto-enablement logic in `.claude/settings.local.json`, task graph analysis instructions, teammate spawning instructions (max 5, spawn prompt template with spec.md context), completion waiting protocol, and sequential fallback for single-task or linear-dependency cases

**Checkpoint**: `teams-vanilla` trait can be enabled and `/speckit.implement` orchestrates parallel teammates.

---

## Phase 4: User Story 3 - teams-spec Trait (Priority: P2)

**Goal**: Spec guardian lead with worktree isolation, review-code integration, and beads bridge.

**Independent Test**: Enable `teams-spec` (and all deps), run `/speckit.implement`. Verify lead does not implement, teammates use worktrees, review-code runs on completed work, beads state is synced.

**Dependencies**: Requires Phase 2 (dependency infrastructure) and Phase 3 (teams-vanilla) to be complete.

### Implementation for User Story 3

- [ ] T013 (cc-superpowers-sdd-rhg.1) [P] [US3] Create teams-spec overlay at `sdd/overlays/teams-spec/commands/speckit.implement.append.md` with sentinel marker `<!-- SDD-TRAIT:teams-spec -->`, spec guardian role declaration (lead MUST NOT implement), precedence note over teams-vanilla, and delegation to `{Skill: sdd:teams-spec-guardian}`
- [ ] T014 (cc-superpowers-sdd-rhg.2) [US3] Create teams-spec-guardian skill at `sdd/skills/teams-spec-guardian/SKILL.md` with frontmatter, beads bootstrap (run `sdd-beads-sync.py` if issues not synced), worktree teammate spawning instructions, spec guardian review loop (run `sdd:review-code` on completed work, send feedback on failures, merge on pass), final beads sync protocol (`bd sync` + reverse sync to update tasks.md), and failure handling (teammate crash, merge conflicts)

**Checkpoint**: `teams-spec` trait can be enabled. Lead acts as spec guardian, teammates work in worktrees, beads state persists.

---

## Phase 5: User Story 4 - Beads Bridge (Priority: P2)

**Goal**: Beads issues bootstrapped from tasks.md before team spawn, synced back on completion.

**Independent Test**: Run `/speckit.implement` with `teams-spec`. Verify `bd list` shows issues before teammates start and all issues closed after completion.

**Note**: The beads bridge logic is embedded in the `teams-spec-guardian` skill (T014). This phase validates that the beads integration works end-to-end, not separate implementation.

- [ ] T015 (cc-superpowers-sdd-22c.1) [US4] Validate beads bridge in `sdd/skills/teams-spec-guardian/SKILL.md`: ensure pre-flight bootstrap section calls `sdd-beads-sync.py`, ensure skip logic when issues already exist, ensure final sync section runs `bd sync` and reverse sync

**Checkpoint**: Beads issues correctly bootstrapped and synced during teams-spec implementation.

---

## Phase 6: User Story 5 - Init Command Update (Priority: P3)

**Goal**: New traits visible in `/sdd:init` trait selection prompt with dependency descriptions.

**Independent Test**: Run `/sdd:init` on a fresh project. Verify 4 traits appear with correct descriptions.

- [ ] T016 (cc-superpowers-sdd-c92.1) [US5] Update trait selection in `sdd/commands/init.md` to add `teams-vanilla` option with description "Parallel implementation via Claude Code Agent Teams (experimental)" and `teams-spec` option with description "Spec guardian + worktree isolation (requires: teams-vanilla, superpowers, beads)"

**Checkpoint**: `/sdd:init` surfaces all 4 traits with dependency information.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [ ] T017 (cc-superpowers-sdd-a8z.1) Verify overlay files are under 30 lines each: `sdd/overlays/teams-vanilla/commands/speckit.implement.append.md` and `sdd/overlays/teams-spec/commands/speckit.implement.append.md`
- [ ] T018 (cc-superpowers-sdd-a8z.2) [P] Run `sdd-traits.sh apply` and verify idempotent overlay application (sentinels prevent duplicates)
- [ ] T019 (cc-superpowers-sdd-a8z.3) Run `make reinstall` and manually test full flow: enable `teams-vanilla`, run `/speckit.implement`, verify teammates spawn

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (directory structure exists)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (traits infrastructure ready)
- **User Story 3 (Phase 4)**: Depends on Phase 2 + Phase 3 (teams-vanilla must work first)
- **User Story 4 (Phase 5)**: Depends on Phase 4 (beads bridge is part of teams-spec-guardian skill)
- **User Story 5 (Phase 6)**: Depends on Phase 2 (traits must be in VALID_TRAITS)
- **Polish (Phase 7)**: Depends on all prior phases

### User Story Dependencies

- **US1 (teams-vanilla)**: Depends on foundational phase only. Independently testable.
- **US2 (dependency infrastructure)**: No user story dependencies. Foundational work.
- **US3 (teams-spec)**: Depends on US1 (teams-vanilla must exist) and US2 (dependency checking)
- **US4 (beads bridge)**: Depends on US3 (embedded in teams-spec-guardian skill)
- **US5 (init update)**: Depends on US2 (traits must be registered in VALID_TRAITS)

### Within Each User Story

- Directory structure before file creation
- Functions before callers (deps check before enable/disable modification)
- Overlay before skill (overlay references the skill)

### Parallel Opportunities

- T001 and T002 can run in parallel (different directories)
- T011 and T013 can run in parallel (different overlay files)
- T017 and T018 can run in parallel (different validation concerns)
- US1 (Phase 3) and US5 (Phase 6) can run in parallel after Phase 2

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Sequential within Phase 2 (functions build on each other):
T003 → T004 → T005, T006 (parallel, independent functions) → T007, T008 (parallel, each uses one function) → T009 → T010
```

## Parallel Example: After Phase 2

```bash
# Phase 3 and Phase 6 can run in parallel:
Task: "Create teams-vanilla overlay" (T011)
Task: "Update init command" (T016)

# Within Phase 3, overlay and skill are sequential:
T011 → T012
```

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Setup (directory structure)
2. Complete Phase 2: Foundational (dependency infrastructure in sdd-traits.sh)
3. Complete Phase 3: User Story 1 (teams-vanilla overlay + orchestration skill)
4. **STOP and VALIDATE**: Enable `teams-vanilla`, run `/speckit.implement`, verify parallel teammates
5. This delivers the core value proposition: parallel implementation

### Incremental Delivery

1. Setup + Foundational + US1 -> MVP: parallel implementation works
2. Add US3 (teams-spec) -> Spec guardian with worktrees and review-code
3. Add US4 (beads bridge) -> Cross-session persistence
4. Add US5 (init update) -> Discoverability
5. Polish -> Validation, documentation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Overlay files MUST be under 30 lines (constitution Principle II)
- Use bash 3.2 compatible syntax (case statements, not associative arrays) per research.md
- Skills follow existing SKILL.md pattern with frontmatter
- Manual verification via `make reinstall` + Claude Code session testing


<!-- SDD-TRAIT:beads -->
## Beads Task Management

This project uses beads (`bd`) for persistent task tracking across sessions:
- Run `/sdd:beads-task-sync` to create bd issues from this file
- `bd ready --json` returns unblocked tasks (dependencies resolved)
- `bd close <id>` marks a task complete (use `-r "reason"` for close reason, NOT `--comment`)
- `bd comments add <id> "text"` adds a detailed comment to an issue
- `bd backup` persists state to git
- `bd create "DISCOVERED: [short title]" --labels discovered` tracks new work
  - Keep titles crisp (under 80 chars); add details via `bd comments add <id> "details"`
- Run `/sdd:beads-task-sync --reverse` to update checkboxes from bd state
- **Always use `jq` to parse bd JSON output, NEVER inline Python one-liners**
