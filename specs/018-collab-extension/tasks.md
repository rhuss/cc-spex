# Tasks: spex-collab Extension

**Input**: Design documents from `/specs/018-collab-extension/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Extension Scaffold)

**Purpose**: Create the extension directory structure, manifest, and configuration template

- [ ] T001 Create extension manifest in spex/extensions/spex-collab/extension.yml with schema_version 1.0, extension metadata, requires (spex-gates >= 1.0.0), provides (3 commands, 1 config), hooks (after_tasks, before_implement), and tags
- [ ] T002 [P] Create configuration template in spex/extensions/spex-collab/config-template.yml with pr_base_branch (default: main) and auto_generate_reviewers (default: true)
- [ ] T003 [P] Create REVIEWERS.md skeleton template in spex/extensions/spex-collab/templates/reviewers-template.md with spec PR sections (Feature Overview, Scope Boundaries, Key Decisions, Areas Needing Attention, Open Questions, Review Checklist) and code phase section template

**Checkpoint**: Extension directory exists with manifest, config template, and reviewers template. `specify extension add spex/extensions/spex-collab --dev` succeeds.

---

## Phase 2: US1 - Spec PR with REVIEWERS.md (Priority: P1)

**Goal**: Generate a human-readable REVIEWERS.md for spec PRs after the planning phase completes, helping reviewers finish their review within 30 minutes.

**Independent Test**: After running `/speckit-tasks` with spex-collab enabled, `REVIEWERS.md` exists in the spec directory with Feature Overview, Scope Boundaries, Key Decisions, Areas Needing Attention, Open Questions, and Review Checklist sections.

### Implementation for US1

- [ ] T004 [US1] Create the reviewers command in spex/extensions/spex-collab/commands/speckit.spex-collab.reviewers.md with YAML frontmatter (name, description, argument-hint) and step-by-step instructions
- [ ] T005 [US1] Implement ship mode guard in reviewers command: check .specify/.spex-state for mode "ship", return immediately if detected (FR-006)
- [ ] T006 [US1] Implement spec directory resolution in reviewers command: use check-prerequisites.sh --json --paths-only to locate FEATURE_DIR, FEATURE_SPEC, and related artifacts
- [ ] T007 [US1] Implement spec PR REVIEWERS.md generation logic: read spec.md (overview, scope, requirements), plan.md (technical approach, key decisions), and tasks.md (coverage). Compose REVIEWERS.md using the template from spex/extensions/spex-collab/templates/reviewers-template.md. Write to FEATURE_DIR/REVIEWERS.md (FR-001, FR-003, FR-004). REVIEWERS.md is the single reviewer artifact, replacing REVIEW-SPEC.md and REVIEW-PLAN.md
- [ ] T008 [US1] Implement re-run behavior: when REVIEWERS.md already exists, regenerate spec sections (everything above the first `## Phase` heading) while preserving any existing code phase sections below that boundary (FR-002 clarification)
- [ ] T009 [US1] Implement disabled extension guard: check if spex-collab extension is enabled via specify extension list or config check. If disabled, return without generating REVIEWERS.md (FR-007)

**Checkpoint**: `REVIEWERS.md` is generated in spec directory after `after_tasks` hook fires. Ship mode produces no output. Disabled extension produces no output. Re-runs preserve code phase sections.

---

## Phase 3: US2 - Phase-Based Implementation PRs (Priority: P1)

**Goal**: Split implementation into phase-based PRs with pause points between phases, so reviewers get focused, coherent changes instead of one massive PR.

**Independent Test**: When `/speckit-implement` runs with spex-collab enabled (not ship mode), the user sees the phase split proposal and can confirm or adjust before implementation begins. After each phase, the user is offered PR creation.

### Implementation for US2

- [ ] T010 [US2] Create the phase-split command in spex/extensions/spex-collab/commands/speckit.spex-collab.phase-split.md with YAML frontmatter and step-by-step instructions
- [ ] T011 [US2] Implement ship mode guard in phase-split command: check .specify/.spex-state for mode "ship", return immediately without prompting (FR-006)
- [ ] T012 [US2] Implement task phase detection: parse tasks.md for heading-based groupings (## US1:, ## Phase 1:, etc.), collect task IDs under each heading. If no phase markers found, treat all tasks as a single phase (FR-012)
- [ ] T013 [US2] Implement phase split proposal display: present parsed phases as a table (phase number, name, task count, task IDs). Ask user to confirm or adjust groupings using AskUserQuestion. Allow merging or splitting phases for remaining unstarted work (FR-008)
- [ ] T014 [US2] Implement phase plan persistence: store confirmed plan in .specify/.spex-state under collab namespace using jq (collab.phase_plan array with phase number, name, tasks). Initialize collab.completed_phases as empty array, collab.current_phase as null, collab.pr_base_branch from config (FR-013)
- [ ] T015 [US2] Create the phase-manager command in spex/extensions/spex-collab/commands/speckit.spex-collab.phase-manager.md with YAML frontmatter and step-by-step instructions
- [ ] T016 [US2] Implement phase state reading in phase-manager: read .specify/.spex-state collab namespace, determine current phase from completed_phases array, skip already-completed phases on session resume (FR-013)
- [ ] T017 [US2] Implement PR creation flow in phase-manager: check gh CLI availability, construct PR title and body from REVIEWERS.md content, offer PR creation via gh pr create --base main targeting the base branch from collab.pr_base_branch. If user confirms: create PR, mark phase complete, pause. If user declines: mark phase complete, continue to next phase (FR-010, FR-011)
- [ ] T018 [US2] Implement phase completion and pause: after PR creation, update .spex-state with completed phase number in collab.completed_phases array, set collab.current_phase to null, output message instructing user to invoke phase-manager again after PR is merged to continue (FR-011)
- [ ] T019 [US2] Implement gh CLI fallback: if gh is not installed, warn user and print manual PR creation instructions (branch name, target, suggested title/body). Skip PR creation but still mark phase complete

**Checkpoint**: `before_implement` hook shows phase split proposal. User can confirm or adjust. Phase-manager tracks completed phases in .spex-state. PR creation works via gh or falls back gracefully.

---

## Phase 4: US3 - Code PR with Updated REVIEWERS.md (Priority: P2)

**Goal**: After each implementation phase completes, update REVIEWERS.md with code-specific review guidance so code PR reviewers get focused guidance.

**Independent Test**: After an implementation phase completes and review gates pass, REVIEWERS.md contains a new phase section with "What Changed", "Spec Compliance", "Focus Areas", and "AI Assumptions" subsections.

### Implementation for US3

- [ ] T020 [US3] Implement code phase REVIEWERS.md update in phase-manager command: after phase completion, read REVIEW-CODE.md for compliance findings and focus areas, read git diff --stat for changed files summary, compose a new phase section using the code phase template from reviewers-template.md (FR-002, FR-005)
- [ ] T021 [US3] Implement phase section append logic: append new "## Phase N: [Name] (YYYY-MM-DD)" section to REVIEWERS.md with subsections for What Changed, Spec Compliance, Focus Areas for Review, and AI Assumptions. Never overwrite existing phase sections (FR-002 clarification)
- [ ] T022 [US3] Implement code review gate invocation in phase-manager: before updating REVIEWERS.md, check if REVIEW-CODE.md exists for this phase. If not, invoke speckit.spex-gates.review-code to generate it. Use the review findings to populate the Spec Compliance and Focus Areas subsections

**Checkpoint**: After phase 1 implementation + phase-manager invocation, REVIEWERS.md has a Phase 1 section with code-specific guidance. After phase 2, a Phase 2 section is appended without overwriting Phase 1.

---

## Phase 5: Polish & Integration

**Purpose**: Wire spex-collab into the init script, register hooks, update documentation

- [ ] T023 [P] Update spex/scripts/spex-init.sh to include spex-collab in the extension installation loop (specify extension add spex/extensions/spex-collab --dev)
- [ ] T024 [P] Register spex-collab hooks in .specify/extensions.yml: add after_tasks hook for speckit.spex-collab.reviewers (optional: false) and before_implement hook for speckit.spex-collab.phase-split (optional: true, prompt: "Review PR split for implementation phases?")
- [ ] T025 [P] Modify spex-gates review-spec and review-plan commands: when spex-collab is enabled (check specify extension list or extension registry), suppress file output (no REVIEW-SPEC.md, no REVIEW-PLAN.md) and output validation findings to console only (FR-014)
- [ ] T026 [P] Update README.md: add spex-collab to Bundled Extensions section (description, commands, hooks), add entry to Commands Reference table, document the phase-manager workflow. Note that REVIEWERS.md replaces REVIEW-SPEC.md and REVIEW-PLAN.md
- [ ] T027 Run make release to validate schema and integration test passes with spex-collab present
- [ ] T028 [P] Create follow-up issue to update brainstorm skill: remove review_brief.md generation (superseded by spex-collab REVIEWERS.md per spec Assumptions)

**Checkpoint**: `/spex:init` installs spex-collab. Extension appears in `specify extension list`. `make release` passes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, can start immediately
- **US1 (Phase 2)**: Depends on Phase 1 (extension scaffold must exist)
- **US2 (Phase 3)**: Depends on Phase 1 (extension scaffold must exist). Independent of US1
- **US3 (Phase 4)**: Depends on Phase 3 (phase-manager command must exist, US3 extends it)
- **Polish (Phase 5)**: Depends on Phases 1-4 completion

### User Story Dependencies

- **US1 (P1)**: Can start after Setup. No dependencies on other stories
- **US2 (P1)**: Can start after Setup. Independent of US1
- **US3 (P2)**: Depends on US2 (extends the phase-manager command created in US2)

### Within Each User Story

- Ship mode guard before core logic
- Spec directory resolution before artifact reading
- Core generation before re-run/overwrite logic

### Parallel Opportunities

- T002 and T003 can run in parallel (config template and reviewers template)
- T023, T024, T025 can run in parallel (different files: init script, extensions.yml, README)
- US1 and US2 can be implemented in parallel (different commands, no shared state)

---

## Parallel Example: Setup Phase

```bash
# Launch parallel tasks after T001:
Task: "Create config template in spex/extensions/spex-collab/config-template.yml"
Task: "Create reviewers template in spex/extensions/spex-collab/templates/reviewers-template.md"
```

## Parallel Example: Polish Phase

```bash
# Launch all integration tasks together:
Task: "Update spex/scripts/spex-init.sh"
Task: "Register hooks in .specify/extensions.yml"
Task: "Update README.md"
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (extension scaffold)
2. Complete Phase 2: US1 (REVIEWERS.md generation)
3. **STOP and VALIDATE**: Run `/speckit-tasks` with spex-collab enabled, verify REVIEWERS.md is generated
4. This alone delivers value: spec PRs get review guides

### Incremental Delivery

1. Setup + US1 -> Spec PRs have REVIEWERS.md (MVP)
2. Add US2 -> Implementation splits into phase-based PRs
3. Add US3 -> Code PRs get phase-specific review guidance
4. Polish -> Full integration with init script and documentation

---

## Notes

- All commands are Markdown files (no compiled artifacts per constitution)
- Ship mode guard pattern: check `.spex-state` for `mode: "ship"`, return immediately
- State updates use `jq` for atomic JSON mutation of `.spex-state`
- REVIEWERS.md phase sections identified by `## Phase N:` headings
- Extension requires spex-gates >= 1.0.0 (uses review-code output)
