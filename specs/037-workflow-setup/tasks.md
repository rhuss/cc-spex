# Tasks: Workflow-Based Setup

**Input**: Design documents from `/specs/037-workflow-setup/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Validate spec-kit workflow engine capabilities before writing the full workflow

- [x] T001 Validate that `specify workflow run` accepts a local YAML file by creating a minimal test workflow at `/tmp/test-workflow.yml` with a single `shell` step (`echo hello`), running it, and confirming output
- [x] T002 Validate that `specify workflow run` supports `switch` steps by creating a test workflow with `inputs.integration` and a `switch` on it, running with `--set integration=claude`, and confirming the correct branch executes
- [x] T003 Validate that `specify workflow run` supports `prompt` steps by creating a test workflow with a `prompt` step, running it, and observing whether the agent receives and responds to the prompt

**Checkpoint**: All 3 step types (`shell`, `switch`, `prompt`) work as expected. If any fail, document the limitation and adjust the plan before proceeding.

---

## Phase 2: User Story 1 & 4 - Core Setup Workflow + Distribution (Priority: P1)

**Goal**: Create the setup workflow that installs extensions and auto-detects the harness. Make it distributable from a GitHub URL.

**Independent Test**: Run `specify workflow run spex/setup.yml` on a clean project. All extensions installed, commands available.

### Implementation

- [x] T004 [US1] Create `spex/setup.yml` with workflow metadata (name, description, version) and `inputs` block defining `integration` (default: "auto"), `extensions` (default: "all"), and `permissions` (default: "standard") per plan.md
- [x] T005 [US1] Add `check-version` step: `shell` step that runs `specify version` and verifies the output shows >= 0.7.4, exits with error message if too old
- [x] T006 [US1] Add `init-project` step: `init` step that runs `specify init --here --integration {{ inputs.integration }} --script sh --force`
- [x] T007 [US1] Add `detect-agent` step: `shell` step that runs `spex/scripts/hooks/shared/detect-agent.sh` when `inputs.integration` is "auto". The step's stdout (e.g., "claude") is captured as `steps.detect-agent.output` and referenced in subsequent `switch` steps via `{{ steps.detect-agent.output }}`
- [x] T008 [US1] Add `migrate-commands` step: `shell` step that removes pre-skills-format `.claude/commands/speckit.*.md` files if they exist
- [x] T009 [US1] Add 7 sequential `install-ext-*` steps: each a `shell` step running `specify extension add spex/extensions/<ext> --dev` in dependency order (spex, spex-gates, spex-worktrees, spex-deep-review, spex-teams, spex-collab, spex-detach). Each step checks if already installed and skips if so.
- [x] T010 [US1] Add `adapt-harness` step: `switch` on detected integration with 4 branches:
  - `claude`: run `spex/scripts/hooks/shared/configure-statusline.sh` equivalent (configure `.claude/settings.local.json` statusline), install Claude Code hooks
  - `codex`: copy Codex adapter scripts to `.codex/hooks.json`, copy `spex/templates/agents-md/codex.md` to `AGENTS.md`
  - `opencode`: copy OpenCode plugin to `.opencode/plugins/`, copy `spex/templates/agents-md/opencode.md` to `AGENTS.md`
  - `default`: echo "No agent-specific configuration applied. Extensions installed with neutral defaults."
- [x] T011 [US1] Add `configure-gitignore` step: `shell` step that adds spex patterns to `.gitignore` (reuse logic from `configure_gitignore` in `spex-init.sh`)
- [x] T012 [US1] Add `fix-constitution` step: `shell` step that handles legacy constitution path migration (reuse logic from `fix_constitution` in `spex-init.sh`)
- [x] T013 [US1] Add `check-update` step: `shell` step that checks GitHub API for newer spex versions (non-blocking, warn-only)
- [x] T014 [US4] Create `spex/bundle.yml` declaring all 7 extensions and the setup workflow in `provides.extensions` and `provides.workflows` per data-model.md
- [x] T015 [US4] Add `setup.yml` to GitHub release assets in the `release` target of `Makefile` (add `cp spex/setup.yml` to the release asset packaging)
- [x] T016 [US1] Test: run `specify workflow run spex/setup.yml` on a clean `/tmp/test-037` project and verify all extensions are installed with scripts, commands are available. Time the run and verify it completes in under 60 seconds (SC-001)

**Checkpoint**: `specify workflow run spex/setup.yml` produces a fully initialized project identical to current `spex-init.sh` output on Claude Code.

---

## Phase 3: User Story 2 - Interactive Extension Selection (Priority: P2)

**Goal**: Add extension selection via `prompt` step with `--set extensions=<list>` override and fallback to "all".

**Independent Test**: Run with `--set extensions=spex-gates,spex-worktrees` and verify only those (plus core) are enabled.

### Implementation

- [x] T017 [US2] Add `select-extensions` step to `spex/setup.yml`: `if` step that checks `inputs.extensions`:
  - If "all": no action (all extensions already installed and enabled)
  - If "interactive": `prompt` step asking the agent to present extension choices, parse response, then `shell` step to `specify extension disable` unselected extensions
  - If comma-separated list: `shell` step to disable extensions not in the list
- [x] T018 [US2] Add fallback logic for `prompt` step failure: if the prompt step produces no parseable response, log "Extension selection unavailable on this harness. All extensions enabled. Use 'specify extension disable <name>' to customize." and continue with all enabled
- [x] T019 [US2] Add dependency enforcement: if user deselects `spex-gates` but selected `spex-teams`, `spex-deep-review`, or `spex-collab`, auto-enable `spex-gates` with a warning message (all three depend on spex-gates per the dependency graph)
- [x] T020 [US2] Test: run with `--set extensions=spex-gates,spex-worktrees` on a clean project, verify only spex + spex-gates + spex-worktrees are enabled after setup

**Checkpoint**: Extension selection works via `--set` flag. Interactive prompt works on Claude Code (or gracefully degrades).

---

## Phase 4: User Story 3 - Per-Agent Permission Configuration (Priority: P2)

**Goal**: Configure harness-specific permissions during setup workflow.

**Independent Test**: After setup, run a spex command on each harness without getting permission prompts.

### Implementation

- [x] T021 [P] [US3] Add `configure-permissions` nested step inside the `claude` case of `adapt-harness` in `spex/setup.yml`: `switch` on `inputs.permissions`:
  - `standard`: write `.claude/settings.json` with `{"permissions": {"allow": ["Skill", "Bash(specify *)", "Bash(*spex-init.sh*)", "Bash(*spex-ship-statusline.sh*)"]}}` (merge with existing)
  - `yolo`: write `.claude/settings.json` with `{"permissions": {"defaultMode": "bypassPermissions", "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)", "WebFetch", "WebSearch", "Skill", ...]}}` (merge with existing)
  - `none`: skip permission configuration
- [x] T022 [P] [US3] Add permission configuration for `codex` case: write Codex-appropriate hook permissions to `.codex/hooks.json`
- [x] T023 [P] [US3] Add permission configuration for `opencode` case: write OpenCode-appropriate plugin permissions
- [x] T024 [US3] Test: run setup workflow with `--set permissions=standard` on Claude Code, verify `.claude/settings.json` has correct allowlists. Re-run and verify existing entries are preserved (merge, not overwrite)

**Checkpoint**: Permission configuration works for all 3 harnesses at both standard and yolo levels. Re-run preserves existing settings.

---

## Phase 5: User Story 5 - Claude Code Plugin Compatibility Shim (Priority: P3)

**Goal**: Update `spex-init.sh` to delegate to the setup workflow when possible.

**Independent Test**: Run `/spex:init` via the Claude Code plugin and verify it produces the same result as `specify workflow run setup.yml`.

### Implementation

- [x] T025 [US5] Add delegation logic to `do_init()` in `spex/scripts/spex-init.sh`: check if `specify` CLI is available and `setup.yml` exists relative to the script directory. If both true, run `specify workflow run "$SETUP_WORKFLOW"` and exit with its return code. If either is missing, fall through to legacy init.
- [x] T026 [US5] Add delegation logic to `do_refresh()` in `spex/scripts/spex-init.sh`: same check, delegate to `specify workflow run "$SETUP_WORKFLOW"` with appropriate flags for refresh mode
- [x] T027 [US5] Test: run `spex-init.sh` directly, verify it delegates to the workflow. Run with `specify` not in PATH, verify it falls back to legacy init.

**Checkpoint**: `spex-init.sh` delegates to workflow when possible, falls back cleanly when not.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, verification, and cleanup

- [x] T028 Update `README.md`: add `specify workflow run <url>` as the primary install command, document both local and remote install paths
- [x] T029 Update `spex/docs/help.md`: add workflow-based setup to quick reference
- [x] T030 Run full verification: `specify workflow run spex/setup.yml` on clean project for Claude Code, Codex (`--set integration=codex`), and OpenCode (`--set integration=opencode`)
- [x] T031 Verify idempotency: run `specify workflow run spex/setup.yml` twice on the same project, confirm no duplicates and no overwritten user settings

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies, start immediately. BLOCKS all other phases (validates workflow engine capabilities).
- **Phase 2 (US1+US4)**: Depends on Phase 1 validation passing.
- **Phase 3 (US2)**: Depends on Phase 2 (workflow must exist before adding extension selection).
- **Phase 4 (US3)**: Can run in parallel with Phase 3 (different steps in the same workflow file, but independent logic).
- **Phase 5 (US5)**: Depends on Phase 2 (workflow must exist before init can delegate to it).
- **Phase 6 (Polish)**: Depends on all prior phases.

### Parallel Opportunities

- T021, T022, T023 (permission configs for 3 harnesses) are parallelizable
- T028, T029 (documentation updates) are parallelizable
- Phases 3 and 4 can proceed in parallel after Phase 2 completes

---

## Implementation Strategy

### MVP First (User Stories 1 & 4)

1. Complete Phase 1: Validate workflow engine capabilities
2. Complete Phase 2: Core setup workflow + bundle manifest
3. **STOP and VALIDATE**: `specify workflow run spex/setup.yml` works on Claude Code
4. This delivers the harness-agnostic install mechanism

### Incremental Delivery

1. Phase 1 (Validation) -> Workflow engine capabilities confirmed
2. Phase 2 (Core) -> Single-command install works for all harnesses
3. Phase 3 (Extension selection) -> Interactive/CLI customization
4. Phase 4 (Permissions) -> Zero-prompt operation
5. Phase 5 (CC shim) -> Backward compatibility
6. Phase 6 (Polish) -> Documentation and final verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Total tasks: 31
- Tasks per story: US1 (13), US2 (4), US3 (4), US4 (2), US5 (3), Cross-cutting (4), Validation (3)
- Parallel opportunities: T021-T023 (permission configs), T028-T029 (docs)
- MVP scope: Phases 1-2 (US1 + US4) delivers the core value
- Phase 1 is a validation gate: if workflow engine capabilities are insufficient, the plan needs revision before proceeding
