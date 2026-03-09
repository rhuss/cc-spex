# Tasks: Teams Trait Consolidation

**Input**: Design documents from `/specs/006-teams-trait-consolidation/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md

**Tests**: No automated tests requested. Verification is manual via `make reinstall` + Claude Code session testing.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create consolidated trait directory structure and prepare for migration

- [ ] T001 (cc-superpowers-sdd-dk2.1) Create consolidated trait overlay directory at sdd/overlays/teams/commands/
- [ ] T002 (cc-superpowers-sdd-dk2.2) [P] Read and document current content of sdd/overlays/teams-vanilla/commands/speckit.implement.append.md for reference
- [ ] T003 (cc-superpowers-sdd-dk2.3) [P] Read and document current content of sdd/overlays/teams-spec/commands/speckit.implement.append.md for reference
- [ ] T004 (cc-superpowers-sdd-dk2.4) [P] Read and document current content of sdd/overlays/teams-vanilla/commands/speckit.plan.append.md for reference

**Checkpoint**: Directory structure ready, existing overlay content documented for consolidation

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Update trait infrastructure to support the new `teams` trait name with alias resolution

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 (cc-superpowers-sdd-9e7.1) Add `resolve_trait_name()` alias function to sdd/scripts/sdd-traits.sh that maps `teams-vanilla` and `teams-spec` to `teams`
- [ ] T006 (cc-superpowers-sdd-9e7.2) Update VALID_TRAITS in sdd/scripts/sdd-traits.sh to include `teams` alongside old names (line 31)
- [ ] T007 (cc-superpowers-sdd-9e7.3) Update `get_trait_deps()` in sdd/scripts/sdd-traits.sh to set `teams` dependencies to `superpowers beads` and remove old `teams-spec` dependency entry
- [ ] T008 (cc-superpowers-sdd-9e7.4) Update `ensure_agent_teams_env()` in sdd/scripts/sdd-traits.sh to handle `teams` trait name in addition to old names
- [ ] T009 (cc-superpowers-sdd-9e7.5) Add config normalization to `ensure_config()` in sdd/scripts/sdd-traits.sh that converts old trait names (`teams-vanilla`, `teams-spec`) to `teams` in .specify/sdd-traits.json
- [ ] T010 (cc-superpowers-sdd-9e7.6) Add deprecation notice output in `do_enable` and `do_disable` functions in sdd/scripts/sdd-traits.sh when old trait names are used

**Checkpoint**: `sdd-traits.sh enable teams` works, `sdd-traits.sh enable teams-vanilla` resolves to `teams` with deprecation notice

---

## Phase 3: User Story 1 - Single Teams Trait Activation (Priority: P1) MVP

**Goal**: Enable a single `teams` trait that provides the full spec guardian workflow

**Independent Test**: Enable `teams` trait on a project, run `sdd-traits.sh apply`, verify the implement skill contains the consolidated decision gate

### Implementation for User Story 1

- [ ] T011 (cc-superpowers-sdd-13s.1) [US1] Create consolidated implement overlay at sdd/overlays/teams/commands/speckit.implement.append.md with decision gate at top, sentinel `<!-- SDD-TRAIT:teams -->`, and delegation to `{Skill: sdd:teams-orchestrate}`
- [ ] T012 (cc-superpowers-sdd-13s.2) [US1] Create plan overlay at sdd/overlays/teams/commands/speckit.plan.append.md with sentinel `<!-- SDD-TRAIT:teams -->` and delegation to `{Skill: sdd:teams-research}` (content from teams-vanilla plan overlay)
- [ ] T013 (cc-superpowers-sdd-13s.3) [US1] Merge spec guardian behavior into sdd/skills/teams-orchestrate/SKILL.md: add worktree isolation (`isolation: "worktree"`), per-task spec compliance review via `{Skill: sdd:review-code}`, merge-only-if-compliant protocol, and beads bridge (`bd close`, `bd backup`)
- [ ] T014 (cc-superpowers-sdd-13s.4) [US1] Add overlay cleanup logic to `do_apply()` in sdd/scripts/sdd-traits.sh: before appending new overlays, strip blocks from disabled or aliased traits (remove content from old sentinel to next sentinel or EOF)
- [ ] T015 (cc-superpowers-sdd-13s.5) [US1] Verify `sdd-traits.sh apply` with `teams` enabled correctly appends consolidated overlay to .claude/commands/speckit.implement.md and .claude/commands/speckit.plan.md

**Checkpoint**: Enabling `teams` trait produces correct consolidated overlay injection with decision gate

---

## Phase 4: User Story 2 - Decision Gate Enforcement (Priority: P1)

**Goal**: Enforce Agent Teams usage when multiple independent tasks exist via PreToolUse hook

**Independent Test**: With `teams` trait active, attempt to use `Agent` tool with `run_in_background` and verify it is blocked

### Implementation for User Story 2

- [ ] T016 (cc-superpowers-sdd-8zo.1) [US2] Create PreToolUse hook script at sdd/scripts/hooks/teams-enforce-hook.py that blocks `Agent` tool calls with `run_in_background` when `teams` trait is enabled (reads .specify/sdd-traits.json)
- [ ] T017 (cc-superpowers-sdd-8zo.2) [US2] Register teams-enforce-hook.py in sdd/hooks.json under PreToolUse events, filtered to `Agent` tool name
- [ ] T018 (cc-superpowers-sdd-8zo.3) [US2] Update the consolidated implement overlay at sdd/overlays/teams/commands/speckit.implement.append.md to include anti-pattern list (never use Agent with run_in_background, never implement directly when 2+ independent tasks exist)

**Checkpoint**: PreToolUse hook blocks incorrect Agent usage during teams-enabled sessions

---

## Phase 5: User Story 3 - Backward-Compatible Migration (Priority: P2)

**Goal**: Old trait names (`teams-vanilla`, `teams-spec`) resolve to `teams` without breaking existing projects

**Independent Test**: Configure a project with `teams-vanilla` and `teams-spec` in .specify/sdd-traits.json, run `sdd-traits.sh apply`, verify single `teams` overlay applied

### Implementation for User Story 3

- [ ] T019 (cc-superpowers-sdd-rje.1) [US3] Add deduplication logic to `do_enable` in sdd/scripts/sdd-traits.sh: when enabling `teams-vanilla` or `teams-spec`, resolve to `teams` and skip if already enabled
- [ ] T020 (cc-superpowers-sdd-rje.2) [US3] Add deduplication in `do_apply()` in sdd/scripts/sdd-traits.sh: when collecting enabled traits, resolve aliases and deduplicate so `teams` overlay is only applied once even if both old names are in config
- [ ] T021 (cc-superpowers-sdd-rje.3) [US3] Update `do_status` in sdd/scripts/sdd-traits.sh to show canonical trait name with alias note (e.g., "teams: enabled (aliases: teams-vanilla, teams-spec)")

**Checkpoint**: Existing projects with old trait names migrate seamlessly on next `sdd-traits.sh apply`

---

## Phase 6: User Story 4 - Anti-Pattern Detection (Priority: P3)

**Goal**: Detect and block regular background agent usage during multi-task implementation

**Independent Test**: Verify the hook correctly distinguishes Agent Teams from regular Agent with run_in_background

### Implementation for User Story 4

- [ ] T022 (cc-superpowers-sdd-prx.1) [US4] Refine teams-enforce-hook.py at sdd/scripts/hooks/teams-enforce-hook.py to distinguish legitimate Agent tool usage (subagent_type parameter present, no run_in_background) from anti-pattern usage (run_in_background without team context)
- [ ] T023 (cc-superpowers-sdd-prx.2) [US4] Add clear error message in hook response directing model to use `{Skill: sdd:teams-orchestrate}` instead of direct Agent calls

**Checkpoint**: Hook blocks anti-pattern usage while allowing legitimate Agent tool calls

---

## Phase 7: Polish and Cross-Cutting Concerns

**Purpose**: Cleanup, deprecation markers, documentation

- [ ] T024 (cc-superpowers-sdd-96s.1) [P] Add deprecation comment header to sdd/overlays/teams-vanilla/commands/speckit.implement.append.md noting replacement by sdd/overlays/teams/
- [ ] T025 (cc-superpowers-sdd-96s.2) [P] Add deprecation comment header to sdd/overlays/teams-spec/commands/speckit.implement.append.md noting replacement by sdd/overlays/teams/
- [ ] T026 (cc-superpowers-sdd-96s.3) [P] Add deprecation comment header to sdd/overlays/teams-vanilla/commands/speckit.plan.append.md noting replacement by sdd/overlays/teams/
- [ ] T027 (cc-superpowers-sdd-96s.4) [P] Add deprecation notice to sdd/skills/teams-spec-guardian/SKILL.md frontmatter noting merge into sdd:teams-orchestrate
- [ ] T028 (cc-superpowers-sdd-96s.5) Run `make reinstall` and validate full workflow: enable teams trait, apply overlays, invoke implement skill, verify decision gate and consolidated orchestration

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (directory structure needed)
- **US1 (Phase 3)**: Depends on Phase 2 (alias resolution needed for trait to work)
- **US2 (Phase 4)**: Depends on Phase 3 T011 (needs consolidated overlay to exist)
- **US3 (Phase 5)**: Depends on Phase 2 (alias resolution is the core mechanism)
- **US4 (Phase 6)**: Depends on Phase 4 T016 (refines the hook created in US2)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 completion. Core consolidation, no dependencies on other stories.
- **US2 (P1)**: Can start after US1 T011 (needs overlay to exist). Hook enforcement is independent otherwise.
- **US3 (P2)**: Can start after Phase 2 completion. Alias/dedup logic is independent of US1 overlay content.
- **US4 (P3)**: Depends on US2 T016 (refines the hook). Cannot start until hook exists.

### Within Each User Story

- Overlays before skills (overlay references skill by name)
- Script changes before overlay application
- Core implementation before refinement

### Parallel Opportunities

- T002, T003, T004 can run in parallel (reading existing files)
- US1 and US3 can run in parallel after Phase 2 (independent concerns)
- T024, T025, T026, T027 can all run in parallel (deprecation markers in different files)

---

## Parallel Example: User Story 1

```bash
# After Phase 2 completes, these can be launched together:
Task: "Create consolidated implement overlay at sdd/overlays/teams/commands/speckit.implement.append.md"
Task: "Create plan overlay at sdd/overlays/teams/commands/speckit.plan.append.md"

# Then sequentially:
Task: "Merge spec guardian behavior into sdd/skills/teams-orchestrate/SKILL.md"
Task: "Add overlay cleanup logic to do_apply() in sdd/scripts/sdd-traits.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (create directories)
2. Complete Phase 2: Foundational (alias support in sdd-traits.sh)
3. Complete Phase 3: US1 (consolidated overlay + merged skill)
4. **STOP and VALIDATE**: Enable `teams` trait, apply, verify decision gate appears in implement command
5. Manual test with a multi-task implementation session

### Incremental Delivery

1. Setup + Foundational -> Alias resolution works
2. Add US1 -> Single trait with spec guardian overlay -> Test independently (MVP)
3. Add US2 -> Hook enforcement -> Test independently
4. Add US3 -> Backward compatibility -> Test with old trait configs
5. Add US4 -> Anti-pattern refinement -> Test hook precision
6. Polish -> Deprecation markers and full validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- This is a Markdown/Bash plugin: verification is manual via `make reinstall` + Claude Code session testing


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
