# Tasks: Replace Traits with Spec-Kit Extensions

**Input**: Design documents from `/specs/016-traits-to-extensions/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

---

## US1: Initialize Project with Extensions (P1)

### T01 [X] [US1] Create spex core extension bundle

Create `spex/extensions/spex/` with:
- `extension.yml` manifest (id: spex, version: 1.0.0, speckit_version >= 0.5.2)
- Migrate commands from `spex/commands/`: brainstorm.md, ship.md, help.md, init.md, evolve.md
- Rename command files to `speckit.spex.{name}.md` format
- Move skill content from `spex/skills/brainstorm/SKILL.md`, `spex/skills/ship/SKILL.md`, `spex/skills/help/SKILL.md`, `spex/skills/evolve/SKILL.md`, `spex/skills/spec-refactoring/SKILL.md`, `spex/skills/using-superpowers/SKILL.md`, `spex/skills/spec-kit/SKILL.md` into extension commands
- Integrate `_ship-guard` overlay content: each command that participates in ship pipeline must check `.spex-state` and suppress prompts in autonomous mode (no overlay injection needed)
- Add `speckit.spex.extensions` command (replaces `spex/commands/traits.md`) for managing extension enable/disable
- Register provides.commands in manifest for all commands
- No hooks (core extension uses direct command invocation)

**Files**: `spex/extensions/spex/extension.yml`, `spex/extensions/spex/commands/speckit.spex.*.md`
**Verify**: `extension.yml` validates against contract schema, all commands have frontmatter

### T02 [X] [P] [US1] Create spex-gates extension bundle

Create `spex/extensions/spex-gates/` with:
- `extension.yml` manifest (id: spex-gates, version: 1.0.0)
- Migrate skill content from `spex/skills/review-spec/SKILL.md` -> `commands/speckit.spex-gates.review-spec.md`
- Migrate skill content from `spex/skills/review-plan/SKILL.md` -> `commands/speckit.spex-gates.review-plan.md`
- Migrate skill content from `spex/skills/review-code/SKILL.md` -> `commands/speckit.spex-gates.review-code.md`
- Migrate skill content from `spex/skills/verification-before-completion/SKILL.md` -> `commands/speckit.spex-gates.verify.md`
- Migrate `spex/commands/stamp.md` -> `commands/speckit.spex-gates.stamp.md`
- Register hooks in manifest:
  - `after_specify`: review-spec (mandatory)
  - `after_plan`: review-plan (mandatory)
  - `after_implement`: review-code (mandatory), verify (mandatory)
- Include `_ship-guard` autonomous mode check in each command

**Files**: `spex/extensions/spex-gates/extension.yml`, `spex/extensions/spex-gates/commands/speckit.spex-gates.*.md`
**Verify**: `extension.yml` has correct hook events, commands reference valid spec-kit lifecycle events

### T03 [X] [P] [US1] Create spex-worktrees extension bundle

Create `spex/extensions/spex-worktrees/` with:
- `extension.yml` manifest (id: spex-worktrees, version: 1.0.0)
- Migrate skill content from `spex/skills/worktree/SKILL.md` -> `commands/speckit.spex-worktrees.worktree.md`
- Register hooks in manifest:
  - `after_specify`: worktree (optional, prompt: "Create a worktree for this feature?")
- Worktree context notes (currently in `worktrees/speckit-plan` and `worktrees/speckit-implement` overlays) are informational only; inline them in the worktree command docs

**Files**: `spex/extensions/spex-worktrees/extension.yml`, `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.worktree.md`
**Verify**: Hook is marked `optional: true`, command handles create/list/cleanup subcommands

### T04 [X] [P] [US1] Create spex-teams extension bundle

Create `spex/extensions/spex-teams/` with:
- `extension.yml` manifest (id: spex-teams, version: 1.0.0)
- `requires.extensions`: `[{id: "spex-gates", version: ">=1.0.0"}]`
- Migrate skill content from `spex/skills/teams-orchestrate/SKILL.md` -> `commands/speckit.spex-teams.orchestrate.md`
- Migrate skill content from `spex/skills/teams-research/SKILL.md` -> `commands/speckit.spex-teams.research.md`
- Create new `commands/speckit.spex-teams.implement.md` (standalone teams implement, per clarification Q1): reads `tasks.md`, checks for 2+ independent tasks, spawns parallel agents
- Register hooks in manifest:
  - `before_plan`: research (optional, prompt: "Run parallel codebase research?")
- Config: `spex-teams-config.yml` with `agent_teams_env: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`

**Files**: `spex/extensions/spex-teams/extension.yml`, `spex/extensions/spex-teams/commands/speckit.spex-teams.*.md`, `spex/extensions/spex-teams/config-template.yml`
**Verify**: Dependency on spex-gates declared, implement command is standalone (no hook pre-emption)

### T05 [X] [P] [US1] Create spex-deep-review extension bundle

Create `spex/extensions/spex-deep-review/` with:
- `extension.yml` manifest (id: spex-deep-review, version: 1.0.0)
- `requires.extensions`: `[{id: "spex-gates", version: ">=1.0.0"}]`
- Migrate skill content from `spex/skills/deep-review/SKILL.md` -> `commands/speckit.spex-deep-review.review.md`
- Register hooks in manifest:
  - `after_implement`: review (optional, prompt: "Run deep multi-perspective review?")
- Config: `spex-deep-review-config.yml` with `external_tools` settings (CodeRabbit, Copilot)

**Files**: `spex/extensions/spex-deep-review/extension.yml`, `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.review.md`, `spex/extensions/spex-deep-review/config-template.yml`
**Verify**: Dependency on spex-gates declared, external_tools config migrated from spex-traits.json

### T06 [X] [US1] Refactor spex-init.sh for extension installation

Modify `spex/scripts/bash/spex-init.sh`:
- Replace `apply_traits()` with `install_extensions()` that loops over `spex/extensions/*/` and runs `specify extension add "$ext_path" --dev` for each
- Add old traits detection: if `.specify/spex-traits.json` exists, print warning "Traits have been replaced by extensions. Run /spex:init to migrate."
- Keep: CLI version check, `specify init`, gitignore setup, status line config, existing migrations
- Remove: `spex-traits.sh` sourcing and invocation
- Handle partial failures: if one extension fails to install, report error and continue with remaining

**Files**: `spex/scripts/bash/spex-init.sh`
**Verify**: `spex-init.sh` runs without errors on a fresh project, installs all 5 extensions, prints migration warning when old config detected

---

## US2: Quality Gates via Hooks (P1)

### T07 [X] [US2] Wire spex-gates hooks into spec-kit lifecycle

This task validates the hook wiring after T02 (spex-gates creation) and T06 (init refactoring):
- Run `/spex:init` to install all extensions
- Verify `.specify/extensions.yml` contains the correct hooks:
  - `after_specify`: `speckit.spex-gates.review-spec` (mandatory)
  - `after_plan`: `speckit.spex-gates.review-plan` (mandatory)
  - `after_implement`: `speckit.spex-gates.review-code` (mandatory), `speckit.spex-gates.verify` (mandatory)
- Verify `.specify/extensions/.registry` shows spex-gates as enabled with correct registered_commands
- Test: Run a speckit command and confirm hooks are listed correctly

**Depends on**: T02, T06
**Files**: No new files (validation task)
**Verify**: `extensions.yml` hook entries match spex-gates manifest exactly

---

## US3: Enable and Disable Extensions (P2)

### T08 [X] [US3] Update hook scripts for extension-based config

Modify Python hook scripts to read from extensions config instead of traits config:

1. `spex/scripts/python/context-hook.py`:
   - Change config detection from `.specify/spex-traits.json` to `.specify/extensions/.registry`
   - Update `<spex-configured>` check
   - Remove `<spex-traits-command>` context element (replace with extension info if needed)

2. `spex/scripts/python/pretool-gate.py`:
   - Update `check_teams_enforce()` to read from `.specify/extensions/.registry`: check `extensions["spex-teams"]["enabled"]` instead of `traits.teams`
   - Remove references to `teams-vanilla` and `teams-spec` trait names

**Depends on**: T06
**Files**: `spex/scripts/python/context-hook.py`, `spex/scripts/python/pretool-gate.py`
**Verify**: Both scripts parse the new config format correctly, teams gate still blocks unauthorized background agents when spex-teams is enabled

### T09 [X] [US3] Verify enable/disable removes/restores commands

Validate that `specify extension disable/enable` works correctly:
- Disable spex-teams: verify `speckit.spex-teams.*` commands are removed from `.claude/commands/`, hooks are disabled in `extensions.yml`
- Re-enable spex-teams: verify commands return, hooks re-enabled
- Disable spex-gates: verify all review commands removed, review hooks disabled
- Test that disabled extension hooks do not fire during pipeline

**Depends on**: T06, T07
**Files**: No new files (validation task)
**Verify**: Commands appear/disappear from agent directory, hooks toggle `enabled` flag

---

## US4: Ship Pipeline with Extensions (P2)

### T10 [X] [US4] Update ship command for extension-based pipeline

Modify the ship command (now `speckit.spex.ship` in T01) to:
- Read prerequisite state from `.specify/extensions/.registry` instead of `.specify/spex-traits.json`:
  - Check `spex-gates` is enabled (required for quality gates)
  - Check `spex-deep-review` is enabled (recommended but not required)
- Remove overlay-based prerequisite check for `superpowers` and `deep-review` traits
- Add teams routing: when `spex-teams` is enabled and `tasks.md` has 2+ independent tasks, route to `speckit.spex-teams.implement` instead of standard implement
- Ship-guard behavior: set `.spex-state` before each pipeline step; hooks and commands check this file themselves (no overlay injection)
- External tools config: read from `spex-deep-review` extension config instead of `spex-traits.json`

**Depends on**: T01, T02, T05
**Files**: `spex/extensions/spex/commands/speckit.spex.ship.md`
**Verify**: Ship pipeline reads from registry, routes to teams implement when appropriate, sets `.spex-state` correctly

---

## US5: Teams as Standalone Command (P3)

### T11 [X] [US5] Implement teams standalone implement command

Finalize `speckit.spex-teams.implement` (created in T04) with:
- Read `tasks.md` and parse task list
- Count independent tasks (marked with `[P]`)
- If 2+ independent tasks: spawn parallel agents via Agent Teams
- If <2 independent tasks: fall back to standard implement behavior
- Check `.spex-state` for autonomous mode; suppress prompts if running in ship pipeline
- Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var if not already set

**Depends on**: T04
**Files**: `spex/extensions/spex-teams/commands/speckit.spex-teams.implement.md`
**Verify**: Command correctly parses tasks.md, spawns parallel agents for independent tasks, falls back for sequential tasks

---

## US6: Worktree Creation via Hook (P3)

### T12 [X] [US6] Verify worktree hook fires after specify

Validate worktree hook integration (created in T03):
- Run `/speckit.specify` with spex-worktrees enabled
- Verify `after_specify` hook fires with optional prompt "Create a worktree for this feature?"
- Verify hook fires after spex-gates review-spec hook (ordering in extensions.yml)
- Verify no worktree prompt when spex-worktrees is disabled

**Depends on**: T03, T07
**Files**: No new files (validation task)
**Verify**: Optional hook prompts user, worktree creation works, disabled state suppresses hook

---

## Cleanup & Constitution

### T13 [X] Remove old overlay system

Remove all old trait/overlay infrastructure:
- Delete `spex/overlays/` directory entirely (all subdirectories: `_ship-guard`, `superpowers`, `deep-review`, `teams`, `teams-vanilla`, `teams-spec`, `worktrees`)
- Delete `spex/skills/` directory entirely (all 18 skill directories)
- Delete `spex/commands/` directory entirely (all 14 command files)
- Delete `spex/scripts/bash/spex-traits.sh`
- Remove `spex/skills/traits/` and `spex/skills/teams-spec-guardian/` (deprecated)
- Update `spex/.claude-plugin/plugin.json`: remove skill and command references, update version
- Move permissions management from `spex-traits.sh` to `spex-init.sh` (or `spex/extensions/spex/commands/speckit.spex.extensions.md`)

**Depends on**: T01-T06 (all extensions created), T08 (scripts updated)
**Files**: Multiple deletions, `spex/.claude-plugin/plugin.json` update
**Verify**: `spex/overlays/`, `spex/skills/`, `spex/commands/` do not exist. `spex/extensions/` contains all 5 extensions. `plugin.json` is valid.

### T14 [X] [P] Update constitution

Update `.specify/memory/constitution.md` per FR-012:
- Rewrite Section II "Overlay Delegation" to "Extension Architecture": extensions provide commands and hooks, no content injection
- Rewrite Section III "Trait Composability" to "Extension Composability": extensions managed via `specify extension enable/disable`, independent and combinable
- Update "Plugin Architecture Constraints": new file organization (`spex/extensions/` instead of `spex/commands/`, `spex/skills/`, `spex/overlays/`)
- Remove all references to: `spex-traits.sh`, overlay application, sentinel markers, `spex-traits.json`, trait enablement
- Update "Development Workflow" if any references to traits exist
- Bump version to 2.0.0

**Files**: `.specify/memory/constitution.md`
**Verify**: No references to "overlay", "trait", "sentinel", "spex-traits" remain in constitution

### T15 [X] Integration test validation

Run `make release` to validate the complete extension-based architecture:
- Schema validation passes
- All 5 extensions install correctly
- All extension commands are registered in agent directory
- All hooks are registered in `extensions.yml`
- Enable/disable toggles work
- No references to old overlay system remain in active files

**Depends on**: T13, T14
**Files**: Possibly update `Makefile` if test scripts reference old paths
**Verify**: `make release` passes cleanly

---

## Task Dependency Graph

```
T01 ──┐
T02 ──┤
T03 ──┤──> T06 ──> T07 ──> T09
T04 ──┤                      │
T05 ──┘                      ├──> T13 ──> T15
                              │
T08 ─────────────────────────┘
T10 (depends on T01, T02, T05)
T11 (depends on T04)
T12 (depends on T03, T07)
T14 [P] (independent, can run with T13)
```

## Parallel Execution Analysis

**Wave 1** (independent, all [P]): T01, T02, T03, T04, T05
**Wave 2**: T06 (depends on Wave 1 extensions existing)
**Wave 3** (independent): T07, T08, T10, T11
**Wave 4**: T09, T12 (validation)
**Wave 5** (independent): T13, T14
**Wave 6**: T15 (final validation)
