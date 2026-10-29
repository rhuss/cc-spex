# Changelog

All notable changes to the **spex** plugin (repository: [cc-spex](https://github.com/rhuss/cc-spex)) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [6.2.0] - 2026-10-29

### Added

- **Ship progress in Codex.** Codex has no spex status line, so a `$speckit-spex-ship` run now shows where it stands in the conversation: after the start, every stage change, pause, failure, resume and completion it prints a one-line banner (for example `🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠`, with `⏸ paused` or `✗ failed` when it stops) and refreshes an eight-stage checklist through `update_plan`. Both come from the new `spex-ship-state.sh progress` command, which renders the banner through a color-free `--banner` mode of the status line script, so icons and the progress bar have one source. OpenCode shows the banner only. `$cc-spex-init` asks once per project whether to add Codex's built-in "task progress" item to the footer and terminal title; on yes it appends `task-progress` to `[tui].status_line` and `[tui].terminal_title` in the Codex config (comments and formatting kept, result verified with `tomllib`), on no it records `"codex_progress": "declined"` in `.specify/spex.json` and prints how to add it by hand with `/statusline` and `/title`. Claude Code is unchanged: the adapted Claude commands and the status line output are byte-identical.

- **Bundled Codex plugin.** The `spex/` directory is now also the Codex plugin `cc-spex` (`spex/.codex-plugin/plugin.json`, marketplace `.agents/plugins/marketplace.json`). It bundles the complete spex source, so `$cc-spex-init` runs the setup workflow from the installed plugin: no clone, no download, no temporary checkout, and the installed extensions always match the plugin version. The source is `SPEX_SOURCE` when set, `./spex` inside the cc-spex repository, and the bundled tree otherwise. The plugin keeps the `cc-spex` identity, so updating the marketplace replaces the earlier thin plugin; the README lists manual steps for installs from a local path or the `050-cc-spex-plugin` branch.

- **Ship oversight control.** When a brainstorm hands off to ship, it asks which oversight level (`smart`, `always`, `never`) to use and passes it as `--ask`. `/speckit-spex-ship --resume --ask <level>` (or replying "continue with never" to a pause) changes the level of a paused pipeline through the new `spex-ship-state.sh resume [--ask <level>]` command.
- **Walkthrough step counts.** Every walkthrough step is named "Step n of M", and the status line walkthrough indicator shows done/total in every state.

### Changed

- Synced with Superpowers 7.0.1 (@2ce8aa1): adapted the rebuilt brainstorming skill into `brainstorm`. It now reads what you pointed at before asking anything and never asks what the project already answers, opens with an echo of a detailed request (or one open question with its reason), asks open questions first and offers a menu only when you are stuck, builds each question on your last answer or on something it found, plays back its understanding in 200-300 word chunks as it forms, finds out which platform/language/library choices you want to own and says its own defaults out loud, lays out the 2-3 surviving approaches in a message of their own before writing anything, and carries a Red Flags table. Problem Framing records success criteria and non-goals; Key Requirements marks proposals as the agent's call. Sizing, the builder check, spikes and the visual companion were not adopted (see `docs/sync-reports/sync-2026-10-23.md`).
- **Extension selections are exact in every mode.** After setup the enabled optional extensions equal the resolved selection for `recommended`, `all`, an explicit list and the interactive choice; everything else is disabled, and extensions spex does not ship (such as `git`) are never touched. `all` (and the interactive reply "all") no longer includes `spex-detach`, which is enabled only when named. Selecting `spex-worktrees` enables the `git` extension. Setup names every extension whose state it changed, and a declaration from an earlier `all` run that lists a disabled `spex-detach` is migrated once (spex-detach is dropped from it and the change is reported).
- **`.specify/spex.json` is the single source of truth.** A refresh without inputs re-applies the stored selection through both init paths (`/spex:init --refresh` and `--update` included), resetting manual `specify extension` toggles. Interactive `/spex:init` now writes the declaration. Projects without a declaration keep the earlier registry-preserving refresh.
- **New git extension guidance.** When `spex-worktrees` is selected without the `git` extension, setup and `/spex:init` now suggest adding the git extension or re-running setup with a selection that leaves out `spex-worktrees`, instead of disabling it by hand.
- **Finish runs verify first; `stamp` removed.** `finish` is the single close-out command: it runs verification before any hook, walkthrough, squash or merge, and stops when a gate fails (fix and rerun, `/speckit-spex-evolve`, or `--no-verify` to skip on purpose). A passing verify is recorded against a content fingerprint (excluding `specs/` and `brainstorm/`) by the new `spex-verify-record.sh`, so finish skips re-verification on unchanged code. The redundant `stamp` command is removed.

### Fixed

- **Setup from a temporary source works again** ([#58](https://github.com/rhuss/cc-spex/issues/58)). The setup workflow installed extensions without `--dev` when its source lived under `/tmp` or `$TMPDIR` (for example the macOS `/var/folders/.../T/`), which the current `specify` CLI treats as a catalog name, so setup stopped at its first extension. Extensions are now always installed with `--dev`, which copies them into the project, so the source can be deleted afterwards.
- **`recommended` and `all` left unselected extensions enabled** ([#58](https://github.com/rhuss/cc-spex/issues/58)). Only the interactive mode and explicit lists disabled anything, so `recommended` kept `spex-teams` and `spex-collab` on while the declaration listed only the recommended set. One script (`spex-apply-extensions.sh`) now enforces the selection for every mode and init path.
- **The ship status line no longer stays on "paused".** A paused pipeline was only marked running again by the next stage change or an explicit `resume`, so after you answered a pause the status line kept showing `⏸ paused` for the rest of the stage (and for good if the project's installed state script predated `resume`). The spex prompt hook (Claude Code and Codex) now sets a paused ship pipeline back to `running` whenever you reply, using the plugin's own state script. A reply like "stop here" also flips it to running; `/speckit-spex-ship --resume` or `/speckit-spex-clear` set it right again.

- **Specify no longer switches the main checkout to the feature branch** ([#57](https://github.com/rhuss/cc-spex/issues/57)). With `spex-worktrees` enabled, `/speckit-specify` now creates the worktree first (a new `before_specify` hook at priority 1 runs `spex-worktree.sh prepare`), and the unchanged `git` extension hook creates the branch inside it. The spec, `feature.json` and the flow or ship state are written only in the worktree, and the session stays there. Other agent sessions in the main checkout keep committing to the default branch. Ship and the brainstorm handoff prepare the worktree themselves before invoking specify, so they do not depend on hook order. The spex methodology skill tells agents to dispatch hooks by `priority`. If an agent still runs them in file order, `prepare` detects the switched main checkout (late mode), restores it before any spec content is written and prints a `NOTICE`. The `after_specify` hook now runs `finalize`, which only confirms branch, directory, `feature.json` and state. Existing projects must run `/spex:init --refresh` once to register the new hook.
- **Worktree preparation no longer runs the `git` extension's internal branch script.** `prepare` used to call `create-new-feature.sh --dry-run` only to name the worktree directory, and broke when spec-kit renamed that script to `create-new-feature-branch.sh`. Now the worktree starts under a provisional name, `.claude/worktrees/.pending-<short-name>-<random>`, and the `after_specify` finalize step renames it after the branch that the `git` extension created inside it. The `WORKTREE_PREPARED` status line has no `branch=` field then (it keeps it when `--branch` or `GIT_BRANCH_NAME` names the branch, and the directory is named after it right away). Finalize in a prepared worktree that never got its branch now reports `WORKTREE_SKIPPED reason=branch-not-created` and changes nothing. `/speckit-spex-worktrees-manage list` shows pending worktrees, and `cleanup` offers to remove those an interrupted run left behind.
- **The legacy worktree move no longer sweeps unrelated changes.** Moving an already checked-out feature branch into a worktree (`adopt`, formerly `create`, also used by `ensure`) commits only the feature's spec directory. It no longer runs `git add -u` or stages `brainstorm/`, so another session's uncommitted work stays where it is.
- **`/spex:init` refuses `spex-worktrees` without the `git` extension.** Init (and the setup workflow) now exits with an error naming both fixes instead of printing an easy-to-miss warning. Ship checks the same prerequisite and never creates a branch by hand.
- **Parallel ship pipelines no longer show each other's status.** The status line now reads the full context JSON from stdin and resolves the state file only from the root of the session's own checkout, so the context percentage renders again and a finished session no longer shows another pipeline's progress.
- **Status line icons no longer run into their labels.** The map, gear and eye glyphs are rendered with emoji presentation.
- **`$cc-spex-init` in Codex no longer accepts `--refresh`/`--update`.** Every run already refreshes from the bundled source, and the Codex bootstrap does not support these Claude Code flags.

## [6.1.0] - 2026-10-12

### Changed

- **Reworked the walkthrough as a runbook.** `speckit-spex-smoke-test` was renamed to `speckit-spex-walkthrough` (flag `--no-smoke-test` became `--no-walkthrough`) and rebuilt around trying the feature. It first judges testability (one line and no files when nothing can be tried by hand, `--force` to override), then writes a tutorial-style `RUNBOOK.md` where every step states why it matters, the exact command, and what you should see before you run it. It then runs a co-pilot session: for each step you either run the command yourself (it lands on the clipboard) or let the agent run it with the exact command, the real output, and an expected-versus-actual comparison. Light mode sets up quick fixtures (background processes, podman containers, podman compose) with one approval; full mode adds a review pause and tiered consent for slow and remote fixtures. `ship` drafts a runbook at the end of the pipeline so the feature can be tried later from the merged branch, and `finish`, `verify`, and the status line now read the runbook status. The report artifact is `RUNBOOK.md` (replacing the short-lived `WALKTHROUGH.md` and the earlier `SMOKE-TEST.md`). Deterministic work moved into `spex-runbook-status`, `spex-runbook-check`, `spex-runbook-fixture`, `spex-runbook-clip`, and `spex-finish-preserve-specs`; the `spex-walkthrough-workspace`, `spex-walkthrough-coverage`, and `spex-walkthrough-lint` helpers were removed. Cross-references in `finish`, `ship`, `verify`, `review-code`, `deep-review`, the help docs, and the README were updated.

### Fixed

- **Walkthrough completion was never recorded**, so `finish` and `verify` kept prompting to run it again. Status is now derived from the runbook by a script and recorded on every step, with a squash-proof code fingerprint for freshness.
- **Detach (stealth) mode lost spec artifacts when the worktree was removed.** The spec dir is git-excluded and exists only in the worktree; `finish` now copies it back to the main checkout (`spex-finish-preserve-specs.sh`) before removing the worktree.

## [6.0.0] - 2026-10-09

Version 6 makes spex agent-harness-agnostic. Setup moves from Claude Code plugin initialization to spec-kit's workflow system, so the same spec-driven workflow runs on Claude Code, Codex, and OpenCode. See [Migrating from v5.x to v6.x](README.md#migrating-from-v5x-to-v6x) for upgrade guidance.

### Breaking

- **Workflow-based setup replaces plugin-based initialization.** `/spex:init` now drives spec-kit's workflow engine instead of Claude Code plugin init. Extension command files are authored in harness-neutral vocabulary and adapted per harness at setup time. Projects initialized under v5.x should re-run `/spex:init`; a leftover `.specify/spex-traits.json` is detected and reported (the old config is no longer used).
- **Extensions now carry their own scripts.** Scripts live inside each extension bundle rather than in a shared location, so extensions are self-contained.

### Added

- **Multi-harness support.** Neutral command vocabulary with per-harness adaptation (`spex-adapt-commands.sh` + `command-map.json` per harness), a Codex hook contract, and native Codex project configuration. spex now works on Claude Code, Codex, and OpenCode.
- **spex-detach extension.** Stealth mode that hides spec artifacts (`.specify/`, `specs/`, `brainstorm/`) from git via `.git/info/exclude` for contributing to repos that don't use SDD, with a `disable` subcommand, registry-aware `is-enabled`, and sibling-repo archiving at finish time.
- **Guided-demo smoke test.** The smoke test is rewritten to synthesize user-observable flows from spec FRs, triage infrastructure, and present evidence for human review.
- **Smart phase splitting** in spex-collab, driven by file-count thresholds.
- **`context_boundary` hook property** for post-implement review gates.
- Goal-alignment agent, early Codecov detection, and `finish --auto`.
- Spec-declared constants drift check in `review-code`.
- Status line shown from specify start in step-by-step mode.
- Review and PR-comment triage can be delegated to the standalone [cc-review](https://github.com/rhuss/cc-review) plugin.

### Changed

- Rewrote `spex-ship-state` and `spex-detach` scripts in Python for reliability.
- Init writes ignore rules to `.git/info/exclude` (local to the clone, shared across worktrees) instead of the tracked `.gitignore`. An existing spex block in `.gitignore` is reported with removal instructions; init never edits a tracked file itself.
- Synced with Superpowers 6.4.2 (@8ca22db): adapted the "leaner plans" philosophy into the `review-plan` gate (flags over-specification alongside placeholders; adds **Review Focus** and **Proportion** checks), and absorbed "Establish Shared Understanding" into `brainstorm` (write back understanding, separating stated facts from assumptions, before exploring approaches).
- Synced with Superpowers 6.3.0 (@b36e082): `Spec:` field validation in the `review-plan` gate; removed persuasion sections from `verification-before-completion`.

### Fixed

- Resolved multiple open bugs (#14, #19, #21, #22, #23, #24).
- Worktrees: read the spec directory from `feature.json` instead of the branch name; auto-enable the git extension when worktrees is selected; copy symlinked config targets so linked skills survive worktree creation; route bare `after_specify` / `before_implement` hook calls to `create` / `ensure`; remove stale `.spex-state` from the main repo after worktree creation.
- Robust agent detection when multiple agent directories coexist.
- Generate missing extension command skills during init.
- `spex-detach is-enabled` and the `finish` archive step read the `enabled` flag in `.specify/extensions/.registry` rather than mere directory presence.
- Root `hooks.json` uses `python-resolve.sh` with correct interpreter ordering (#17).

## [5.8.0] - 2026-06-25

### Added
- Guided smoke test skill (`speckit-spex-smoke-test`) for interactive spec-driven acceptance walkthrough
- Before/after finish hook support for extensible feature completion pipeline
- Mid-implementation review checkpoints in ship pipeline
- Backpressure loops for autonomous pipeline control
- No-simulated-tests hard gate in smoke test skill

### Changed
- Synced with superpowers@896224c (Superpowers 6.0.3, 2026-06-18)
  - `writing-plans`: 3 new patterns adapted into `review-plan` quality gate (task right-sizing, Global Constraints validation, per-task Interfaces)
  - `brainstorming`: no-op (visual companion just-in-time change, skipped by spex)
  - Companion skills updated upstream: trivial fixes in `test-driven-development`, `systematic-debugging`
  - All spex spec-compliance enhancements preserved

### Fixed
- Exclude brainstorm files from PR branches
- Clean up state file in main repo after worktree merge
- Prevent silent file loss on worktree removal in finish
- Run smoke test in fresh-context subagent for ship mode
- `specify extension enable` takes one arg at a time
- Extract finish context detection into script

## [5.0.0] - 2026-04-25

### Changed (BREAKING)
- **Traits replaced by spec-kit native extensions.** The overlay system (sentinel markers, `spex-traits.sh`, `spex-traits.json`) is removed entirely. All capabilities now use spec-kit's extension mechanism with `extension.yml` manifests, lifecycle hooks, and `specify extension enable/disable`.
- **Command names changed.** `/spex:*` commands are now registered by spec-kit as `/speckit-spex-*` (e.g., `/speckit-spex-brainstorm`, `/speckit-spex-ship`). Only `/spex:init` remains as a plugin-level bootstrap skill.
- **Quality gates fire automatically via hooks.** Review commands no longer need manual invocation. `spex-gates` registers `after_specify`, `after_tasks`, and `after_implement` hooks that run reviews automatically.
- **Config location changed.** Extension state is tracked in `.specify/extensions/.registry` (JSON), replacing `.specify/spex-traits.json`.

### Added
- **Five bundled extensions:** spex (core), spex-gates (quality gates), spex-worktrees (git worktrees), spex-teams (parallel agents), spex-deep-review (multi-agent review)
- **Flow state tracking.** The `after_specify` hook from the spex core extension creates `.specify/.spex-state` with `"mode": "flow"` to power the status line during step-by-step workflow.
- **CodeRabbit enabled by default** in deep-review extension config (when CLI is available).
- **Worktree config copy.** Worktree creation now copies `.claude/` and `.specify/` directories, so no `/spex:init` is needed in the worktree.
- **Teams routing in ship.** Ship pipeline checks for spex-teams extension and routes to parallel implementation when 2+ independent tasks exist.

### Removed
- `spex/overlays/` directory (all overlay files)
- `spex/skills/` directory (all skills except `init/`)
- `spex/commands/` directory (all command files)
- `spex/scripts/bash/spex-traits.sh`
- `/spex:traits` command (replaced by `specify extension enable/disable`)

### Migration from 4.x

1. Run `make install` to update the plugin
2. In each project, run `/spex:init` to install extensions (old `spex-traits.json` is detected and a warning is printed)
3. Update command references: `/spex:brainstorm` -> `/speckit-spex-brainstorm`, `/spex:ship` -> `/speckit-spex-ship`, etc.
4. Extension management: `specify extension enable/disable <name>` replaces `/spex:traits enable/disable`

## [3.0.2] - 2026-04-05

**Last release supporting `speckit.*.md` command format.** Future versions will migrate to Agent Skills format (`speckit-*/SKILL.md`). A `release/3.x` maintenance branch is available for bugfixes on this format.

### Changed
- Synced with superpowers@eafe962 (2026-03-25)
  - `writing-plans`: Evaluated, 3 patterns adapted into `spex:review-plan` (expanded red flag patterns, type/name consistency check, no-placeholder enforcement)
  - `brainstorming`: Adapted inline self-review as pre-check before `spex:review-spec` dispatch
  - `verification-before-completion`: No upstream changes
  - `review-code`: No upstream equivalent (spex-only)
  - All spex spec-compliance enhancements preserved

## [3.0.0] - 2026-03-28

### Changed (BREAKING)
- **Plugin renamed from `sdd` to `spex`** with all commands, skills, and configuration updated
  - Command prefix: `/sdd:*` changed to `/spex:*`
  - Config file: `.specify/sdd-traits.json` changed to `.specify/spex-traits.json`
  - Phase file: `.specify/.sdd-phase` changed to `.specify/.spex-phase`
  - Script names: `sdd-init.sh`, `sdd-traits.sh` changed to `spex-init.sh`, `spex-traits.sh`
  - Marketplace: `sdd-plugin-development` changed to `spex-plugin-development`
- **Repository renamed from `cc-sdd` to `cc-spex`** (GitHub auto-redirects old URLs)
- All documentation updated to use spex terminology

### Added
- **Automatic migration from sdd** in `make install` (removes old marketplace and plugin)
- **Backward-compatible config migration** in `spex-init.sh` (renames old config files on init)

### Migration from 2.x

1. Run `make install` in the cc-spex repository (automatically removes old sdd plugin)
2. In each project using spex, run `/spex:init` to migrate config files
3. Update any scripts or aliases referencing `/sdd:*` commands to `/spex:*`

Old `.specify/sdd-traits.json` files are automatically renamed to `spex-traits.json` on first `/spex:init`.

## [2.0.0] - 2026-03-16

### Added
- **Automatic spec-kit initialization** - Plugin automatically initializes projects on first SDD command
  - Checks if spec-kit CLI is installed
  - Automatically runs `specify init` if project not initialized
  - Reminds user to restart if new `.claude/commands/` were installed
  - No manual setup required for users
- **Restart detection** - Plugin detects when spec-kit installs local commands and prompts restart
- **Clear error messages** - If spec-kit not installed, provides installation instructions
- **Canonical two-skill architecture** - Clear separation of concerns:
  - `spec-kit` - Technical integration layer (auto-init, layout validation, CLI wrappers)
  - `using-superpowers` - Methodology layer (workflow routing, process discipline)
  - All workflow skills call `spec-kit` for automatic setup
- **Traits infrastructure** - Hook-based plugin root injection, `superpowers` and `teams` traits with sentinel-guarded overlays
- **Brainstorm document persistence** - Sessions produce numbered brainstorm documents with overview index, revisit detection, and status tracking
- **REVIEWERS.md** - Anti-self-review guardrails with structural validation (5+ required headings)
- **Constitution path standardized** - Canonical location at `.specify/memory/constitution.md`

### Changed (BREAKING)
- **spec-kit is now a required dependency** - Plugin no longer bundles templates, scripts, or spec-kit commands
- Templates, scripts, and commands now live in local project (`.specify/` and `.claude/commands/`) via `specify init`
- Single source of truth: spec-kit repository maintains all templates, scripts, and commands
- Cleaner separation of concerns: plugin focuses on Claude Code integration, spec-kit provides tooling
- **Consolidated teams traits** - `teams-vanilla` and `teams-spec` merged into single `teams` trait (migration on init)
- **Task tracking simplified** - Direct `tasks.md` checkbox tracking replaces external state management

### Removed
- **`constitution` skill** - Redundant wrapper; use `/speckit-constitution` directly
- **`beads` trait** - Removed entirely; task state tracked in `tasks.md` checkboxes
- **`teams-vanilla` and `teams-spec` traits** - Consolidated into `teams` trait
- **Bundled templates** - Removed `templates/` directory (use `specify init` instead)
- **Bundled scripts** - Removed `scripts/` directory (use `specify init` instead)
- **Bundled spec-kit commands** - Removed `commands/speckit-*` files (installed to `.claude/commands/` via `specify init`)

### Migration Guide
1. Ensure spec-kit CLI is installed and in your PATH
2. ~~Run `specify init` in each project~~ - Now happens automatically on first SDD command!
3. Restart Claude Code when prompted (if new commands were installed to `.claude/commands/`)
4. Update any custom references from plugin templates to `.specify/templates/`
5. Update any custom references from plugin scripts to `.specify/scripts/`
6. `/speckit-*` commands now come from `specify init`, not the plugin

## [1.0.0] - 2025-11-11

### Added

#### Core Skills
- **using-superpowers**: Entry skill establishing mandatory SDD workflows
- **brainstorm**: Refine rough ideas into executable specifications through collaborative dialogue
- **spec**: Create formal specifications directly from clear requirements
- **implement**: Implement features from validated specifications using TDD with spec compliance checking
- **evolve**: Reconcile spec/code mismatches with AI-guided evolution and user control

#### Modified Superpowers Skills
- **writing-plans**: Generate implementation plans FROM specifications with full requirement coverage
- **review-code**: Review code against spec compliance with scoring and deviation detection
- **verification-before-completion**: Extended verification including tests AND spec compliance validation

#### SDD-Specific Skills
- **review-spec**: Review specifications for soundness, completeness, and implementability
- **spec-refactoring**: Consolidate and improve evolved specs while maintaining feature coverage
- **spec-kit**: Wrapper for spec-kit CLI operations with workflow discipline
- **constitution**: Create and manage project constitution defining project-wide principles

#### Slash Commands
- `/sdd:brainstorm`: Interactive specification refinement
- `/sdd:spec`: Direct specification creation
- `/sdd:implement`: Feature implementation from specs
- `/sdd:evolve`: Spec/code reconciliation
- `/sdd:review-spec`: Specification review
- `/sdd:constitution`: Project constitution management

#### Bundled Resources
- **Templates**: 5 spec-kit templates (spec, plan, tasks, checklist, agent-file)
- **Scripts**: 5 bash scripts for feature management and automation
- **Reference Commands**: 8 spec-kit command implementations for reference

#### Configuration Schema
- Auto-update spec settings with configurable thresholds
- Spec-kit CLI integration settings
- Constitution path and requirement settings
- Specs directory configuration

#### Documentation
- Comprehensive README with workflow examples
- TESTING.md with integration testing guide
- Example todo-app project with walkthrough
- Plugin schema documentation

### Infrastructure
- Plugin structure following Claude Code standards
- Proper .claude-plugin/plugin.json manifest
- .gitignore for clean repository
- Local development marketplace setup
- MIT license
- GitHub repository and issue tracking

### Acknowledgements
- Built on [superpowers](https://github.com/obra/superpowers) by Jesse Vincent for process discipline foundation
- Integrates [spec-kit](https://github.com/github/spec-kit) by GitHub for specification workflows

---

For detailed commit history, see [GitHub Commits](https://github.com/rhuss/cc-spex/commits/main)
